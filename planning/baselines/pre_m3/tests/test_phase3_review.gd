extends SceneTree
## Narrow regression probes for recovery UI context; no disk IO or personal save.

class FaultStore:
 extends RefCounted
 var generation=0
 var root_path="res://tests/in_memory_review"
 var fail=false
 var committed: Array=[]
 func configure(path: String,_validator: Callable=Callable()): root_path=path
 func commit_snapshot(_candidate: Dictionary,_generation: int) -> Dictionary:
  if fail: return {"ok":false,"reason":"injected_before_write"}
  committed.append(_candidate.duplicate(true))
  generation+=1
  return {"ok":true,"generation":generation}

class InitialFaultStore:
 extends FaultStore
 func load_profile(): return {"ok":true,"needs_initialization":true}
 func read_legacy(_path: String): return {"ok":true,"exists":false}

var checks=0
var failures=0

func _initialize(): call_deferred("run")

func check(condition: bool,label: String):
 checks+=1
 if not condition:
  failures+=1
  push_error("RECOVERY REVIEW: "+label)

func make_game():
 var game=load("res://main.tscn").instantiate()
 game.test_mode=true
 root.add_child(game)
 game.set_physics_process(false); game.set_process(false)
 game.profiles.saves=FaultStore.new()
 game.profiles.memory_only=false
 return game

func run():
 create_timer(20).timeout.connect(func(): push_error("Recovery review timeout"); quit(1))
 var profile=load("res://scripts/raid/profile_service.gd").new()
 profile.saves=InitialFaultStore.new(); profile.saves.fail=true
 var initialized=profile.initialize(false,"memory-review")
 check(not initialized.ok and profile.profile.is_empty() and profile.blocked,"failed first save enters protected startup state instead of exposing an empty camp profile")
 var game=make_game()
 check(not is_instance_valid(game.player),"startup camp has no live player")
 var item=game.profiles.inventory.contents(game.profiles.profile,"stash_main")[0]
 game.profiles.saves.fail=true
 game._inventory_command({"from":"stash_main","to":"loadout_pack","item_id":item.instance_id,"quantity":1})
 check(game.save_failed and game.paused,"camp transfer commit failure opens recovery menu")
 game._resume()
 check(game.save_failed and not game.playing,"camp retry cannot bypass a still failing storage device")
 game.profiles.saves.fail=false
 game._resume()
 check(not game.playing and game.inventory_panel.visible,"retrying camp save returns to camp without starting a missing raid")
 game.free()
 await process_frame

 game=make_game()
 game._reset()
 var old_raid=game.profiles.profile.active_raid.raid_id
 game.hp=0
 game.profiles.saves.fail=true
 game._finish(false,"old failed settlement")
 check(not game.pending_settlement.is_empty(),"failed settlement retains retry intent")
 game._reset(true)
 check(not game.training_mode and game.runtime_raid_id==old_raid,"uncommitted settlement prevents switching to practice")
 game.profiles.saves.fail=false
 var committed_before=game.profiles.saves.committed.size()
 game._resume()
 check(game.profiles.profile.active_raid.is_empty() and game.pending_settlement.is_empty(),"successful retry settles the original raid and clears retry intent")
 var dead_active_written=false
 for stored in game.profiles.saves.committed.slice(committed_before):
  var active=stored.get("active_raid",{})
  if not active.is_empty() and float(active.get("snapshot",{}).get("player",{}).get("health",{}).get("hp",100))<=0.0: dead_active_written=true
 check(not dead_active_written,"settlement retry never publishes a dead active raid that a crash could resume")
 game.profiles.quick_equip()
 game._reset()
 var new_raid=game.profiles.profile.active_raid.raid_id
 check(old_raid!=new_raid,"subsequent deployment has a fresh identity")
 game.profiles.saves.fail=true
 game._checkpoint()
 game.profiles.saves.fail=false
 game._resume()
 check(game.profiles.profile.active_raid.get("raid_id","")==new_raid,"old failed settlement must never settle a newer raid on retry")
 game._save_and_return()
 var suspended=JSON.stringify(game.profiles.profile,"",true)
 game._reset(true)
 game.ammo=1; game.hp=5
 game._save_and_return()
 game._checkpoint() # The same checkpoint branch called by WM_CLOSE_REQUEST.
 check(JSON.stringify(game.profiles.profile,"",true)==suspended,"practice to camp to quit checkpoint leaves suspended raid untouched")
 game._reset()
 game.active_crate=game.crates[0]
 var cid=game.active_crate.cid
 var candidate=game.profiles.profile.duplicate(true)
 candidate.active_raid.search[cid].revealed=1
 game.profiles.commit(candidate)
 game.searching=true; game.inventory_context="search"
 game._sync_input_context(); game._refresh_search()
 await process_frame; await process_frame; await process_frame
 var revealed_id=game.profiles.revealed_ids(cid)[0]
 var item_button=game.inventory_panel._left_grid._item_buttons[revealed_id]
 var finger=InputEventScreenTouch.new()
 finger.index=91; finger.position=item_button.get_global_rect().get_center(); finger.pressed=true
 game._input(finger)
 finger.pressed=false; game._input(finger)
 check(game.inventory_panel._selected_id==revealed_id,"custom touch routing selects a revealed inventory item")
 check(game.touch_buttons.is_empty() and not game.input_router.enabled,"inventory touch releases its finger without enabling combat")
 var escape=InputEventKey.new(); escape.keycode=KEY_ESCAPE; escape.pressed=true
 game._unhandled_input(escape)
 check(not game.searching and not game.inventory_panel.visible and game.input_router.enabled,"Escape closes search and restores fresh gameplay input")
 # Restore immediately after the transfer's atomic save, without the usual close
 # checkpoint that would otherwise hide a stale presentation reserve in snapshot.
 candidate=game.profiles.profile.duplicate(true)
 game.profiles.inventory.add_item(candidate,"ammo_rifle",15,cid)
 var ammo_id=""
 for contents in game.profiles.inventory.contents(candidate,cid):
  if contents.definition_id=="ammo_rifle": ammo_id=contents.instance_id
 candidate.active_raid.search[cid].order.append(ammo_id)
 candidate.active_raid.search[cid].revealed=candidate.active_raid.search[cid].order.size()
 game.profiles.commit(candidate)
 game.searching=true; game.inventory_context="search"
 var reserve_before=game.reserve
 game._inventory_command({"from":cid,"to":"raid_pack","item_id":ammo_id,"quantity":15})
 check(game.reserve==reserve_before+15,"pickup updates runtime reserve after its atomic commit")
 check(game.profiles.profile.active_raid.snapshot.player.weapon.reserve==reserve_before,"test reaches immediate pickup snapshot with pre-transfer presentation reserve")
 game.profiles.profile=JSON.parse_string(JSON.stringify(game.profiles.profile))
 game._reset()
 check(game.reserve==reserve_before+15 and game.profiles.inventory.quantity(game.profiles.profile,"raid_pack","ammo_rifle")==reserve_before+15,"immediate crash restore preserves picked ammunition without consuming it as stale reserve")
 check(game.profiles.inventory.quantity(game.profiles.profile,cid,"ammo_rifle")==0,"immediate crash restore cannot respawn transferred ammunition")
 game.free()
 await process_frame
 print("Recovery review: %d checks; %d failures" % [checks,failures])
 quit(1 if failures else 0)
