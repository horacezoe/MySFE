extends SceneTree
## Actual scene / ray / inventory / JSON-slot regression. Never reads personal saves.
const ProfileService=preload("res://scripts/raid/profile_service.gd")

class PhysicsTask:
 extends Node
 signal completed
 var pending: Callable
 func run(callback: Callable):
  pending=callback
  await completed
 func _physics_process(_delta):
  if pending.is_valid():
   var callback=pending; pending=Callable(); callback.call(); completed.emit()

var game
var tick: PhysicsTask
var fixture_root="res://tests/.corpse-game-%s-%s" % [OS.get_process_id(),Time.get_ticks_usec()]
var checks=0
var failures=0
var collected_rifle=""
var shot: Dictionary={}

func _initialize(): call_deferred("run")

func check(condition: bool,label: String):
 checks+=1
 if not condition:
  failures+=1
  push_error("CORPSE GAME: "+label)

func encoded(value) -> String: return game.profiles.saves.canonical_json(value)
func quantity(cid: String,id: String) -> int: return game.profiles.inventory.quantity(game.profiles.profile,cid,id)

func free_game():
 if is_instance_valid(game):
  # A test coroutine resumes directly inside PhysicsTask.completed. Do not
  # destroy audio/physics nodes in that same callback that just played a shot.
  # Stop voices while their owners still exist, finish the physics callback,
  # and let the idle/deferred work run before destroying the scene.
  game._stop_audio()
  await physics_frame
  await process_frame
  game.free()
 game=null

func boot() -> bool:
 await free_game()
 await process_frame
 game=load("res://main.tscn").instantiate()
 game.test_mode=true
 game.save_path_override=fixture_root
 root.add_child(game)
 game.set_physics_process(false); game.set_process(false)
 var loaded=game.profiles.initialize(false,fixture_root,"")
 check(loaded.ok,"fresh scene reads only isolated fixture slots")
 if not loaded.ok: return false
 await tick.run(func(): game._reset(); game.deployment_grace=10000.0)
 check(game.playing and not game.save_failed,"normal raid starts or resumes through durable profile")
 game.box(game.world,Vector3(30,0.5,30),Vector3(100,-0.3,0),Color("626858"),true)
 await physics_frame
 return game.playing

func corpse(index: int) -> Dictionary:
 var cid="loot_guard_%02d" % index
 for entry in game.corpses:
  if entry.cid==cid: return entry
 return {}

func item_in(cid: String,definition_id: String) -> Dictionary:
 for item in game.profiles.inventory.contents(game.profiles.profile,cid):
  if item.definition_id==definition_id: return item
 return {}

func near(entry: Dictionary,distance:=1.4):
 var point: Vector3=game._search_point(entry)
 game.player.position=Vector3(point.x,entry.node.position.y,point.z+distance)
 game.player.velocity=Vector3.ZERO

func kill_guard(index: int):
 var enemy: Dictionary=game.enemies[index]
 enemy.weapon.ammo=5; enemy.weapon.reserve=17
 enemy.node.position=Vector3(100+index*5,0,-2)
 game.player.position=enemy.node.position+Vector3(0,0,3)
 game.combat.sync_visual_pose(enemy.node)
 await physics_frame
 await tick.run(func():
  var definition=game.weapon_runtime.definition
  var lethal=definition.duplicate(); lethal.base_damage=1000.0
  game.weapon_runtime.definition=lethal; game.weapon_runtime.cooldown=0
  var origin: Vector3=enemy.node.global_position+Vector3(0,1.2,2.5)
  shot=game.weapon_runtime.request_fire(game.player,{"blocked":false,"origin":origin,"direction":Vector3.FORWARD},game.combat,0.0)
  game.weapon_runtime.definition=definition
  if shot.get("accepted",false): game._present_shot(shot,game.player)
 )
 check(shot.get("accepted",false) and shot.get("actor")==enemy.node and shot.get("killed",false),"real accepted ray kills intended guard")
 enemy.node.get_node("Visual").set_dead_pose(true)

func run():
 create_timer(90).timeout.connect(func(): push_error("Corpse game test timeout"); finish(false))
 tick=PhysicsTask.new(); root.add_child(tick)
 if not await boot(): finish(false); return
 await test_death_and_reach()
 if failures: finish(); return
 await test_exit_overlap()
 if failures: finish(); return
 await test_search_and_restart()
 if failures: finish(); return
 await test_failure_and_empty()
 if failures: finish(); return
 await test_death_commit_failure()
 if failures: finish(); return
 await test_settlement_and_training()
 finish()

func test_death_and_reach():
 check(game.corpses.is_empty(),"living guards have no searchable loot container")
 game.player.position=Vector3(100,0,1)
 game.enemies[0].node.position=Vector3(100,0,0)
 await physics_frame
 await tick.run(func(): game._interact())
 check(not game.searching,"standing living enemy cannot be searched")
 await kill_guard(0)
 var entry=corpse(0)
 check(not entry.is_empty(),"death immediately publishes a searchable corpse without an accepted mission")
 if entry.is_empty(): return
 check(game.profiles.profile.active_raid.snapshot.enemies[0].health.hp==0,"death and loot share one durable snapshot")
 check(game.enemies[0].brain.state==&"Dead" and game.enemies[0].node.collision_layer==0,"loot does not reactivate dead AI or body collision")
 var rifle=item_in(entry.cid,"rifle_basic")
 check(not rifle.is_empty() and int(rifle.runtime.ammo)==5,"corpse rifle retains guard's five loaded rounds")
 check(quantity(entry.cid,"ammo_rifle")==17,"corpse contains exact remaining reserve")
 near(entry,3.1)
 await physics_frame
 await tick.run(func(): game._interact())
 check(not game.searching,"distant corpse cannot be searched")
 near(entry)
 await physics_frame
 var selection={"value":{}}
 await tick.run(func(): selection.value=game._nearest_search_target())
 check(selection.value.get("cid","")==entry.cid,"fallen torso point is reachable from normal interaction distance")
 var point: Vector3=game._search_point(entry)
 var wall=game.box(game.world,Vector3(3,3,0.12),Vector3(point.x,1.25,point.z+0.7),Color("71766a"),true)
 await physics_frame
 await tick.run(func(): game._interact())
 check(not game.searching,"opaque world wall blocks corpse search")
 wall.free(); await physics_frame
 var crate: Dictionary=game.crates[0]
 var original: Vector3=crate.node.position
 crate.node.position=game.player.position+Vector3(0.65,0.4,0)
 await tick.run(func(): selection.value=game._nearest_search_target())
 check(selection.value.get("cid","")==crate.cid,"closer supply crate wins over farther corpse")
 crate.node.position=game.player.position+Vector3(4,0.4,0)
 await tick.run(func(): selection.value=game._nearest_search_target())
 check(selection.value.get("cid","")==entry.cid,"corpse wins when the crate is farther away")
 crate.node.position=original

func test_exit_overlap():
 var entry=corpse(0)
 var body_position: Vector3=entry.node.position
 var player_position: Vector3=game.player.position
 var camera_transform: Transform3D=game.camera.global_transform
 entry.node.position=game.exit_pos
 near(entry)
 game.camera.global_position=game.player.global_position+Vector3(0,1.55,0)
 var point: Vector3=game._search_point(entry)
 game.camera.look_at(game.camera.global_position+(game.camera.global_position-point).normalized())
 await physics_frame
 await tick.run(func():
  game._update_interaction_prompt(1.0)
  game._interact()
 )
 check(game.extraction.remaining>0 and not game.searching,"looking away from an overlapping corpse still starts extraction")
 check(game.interact_button.text.contains("撤离"),"exit-overlap HUD offers extraction when looking away")
 game.extraction.cancel()
 game.camera.look_at(point)
 await tick.run(func():
  game._update_interaction_prompt(1.0)
  game._interact()
 )
 check(game.searching and game.active_crate.cid==entry.cid and game.extraction.remaining==0,"looking directly at overlapping corpse opens search instead of starting exit")
 check(game.interact_button.text.contains("搜"),"exit-overlap HUD identifies aimed corpse search")
 if game.searching: game._close_search()
 game.extraction.cancel()
 entry.node.position=body_position
 game.player.position=player_position
 game.camera.global_transform=camera_transform
 check(game._checkpoint(),"overlap fixture restores original actor positions and cancelled extraction")

func test_search_and_restart():
 var entry=corpse(0)
 near(entry)
 await tick.run(func(): game._interact())
 check(game.searching and game.active_crate.cid==entry.cid and game.inventory_panel.visible,"E opens the existing search inventory for the corpse")
 check(game.inventory_panel._title.text.contains("敌人") or game.inventory_panel._title.text.contains("遗留"),"search title identifies enemy loot")
 var rifle=item_in(entry.cid,"rifle_basic")
 var before=encoded(game.profiles.profile)
 game._take_item(rifle)
 check(encoded(game.profiles.profile)==before,"hidden corpse rifle cannot be transferred before reveal")
 game._advance_search(0.69)
 check(game.profiles.revealed_ids(entry.cid).is_empty(),"search does not reveal a corpse item early")
 game._advance_search(0.02)
 check(game.profiles.revealed_ids(entry.cid).size()==1,"corpse reveals one item after normal search interval")
 var progress: Dictionary=game.profiles.profile.active_raid.search[entry.cid].duplicate(true)
 game._close_search()
 await tick.run(func(): game._interact())
 check(game.profiles.profile.active_raid.search[entry.cid].revealed==progress.revealed,"closing and reopening preserves reveal progress")
 game._advance_search(20.0)
 collected_rifle=rifle.instance_id
 game._take_item(rifle)
 check(game.profiles.inventory.owner_of(game.profiles.profile,collected_rifle)=="raid_pack","selected corpse rifle transfers into real raid backpack")
 check(int(game.profiles.profile.items[collected_rifle].runtime.ammo)==5,"pickup preserves loaded ammunition")
 check(not game.enemies[0].node.get_node("Visual/CarriedRifle").visible,"taken rifle disappears from the corpse model")
 var current=encoded(game.profiles.profile)
 game._take_item(rifle)
 check(encoded(game.profiles.profile)==current,"repeated stale pickup cannot duplicate the same rifle")
 game._close_search()
 var ids: Array=game.profiles.profile.active_raid.search[entry.cid].order.duplicate()
 if not await boot(): return
 entry=corpse(0)
 check(not entry.is_empty() and game.enemies[0].health.hp==0 and game.enemies[0].brain.state==&"Dead","fresh disk scene restores searchable corpse and dead guard")
 check(game.profiles.profile.active_raid.search[entry.cid].order==ids,"restart preserves exact original drop identity and order")
 check(game.profiles.inventory.owner_of(game.profiles.profile,collected_rifle)=="raid_pack","disk restart retains picked rifle exactly once")
 check(not game.enemies[0].node.get_node("Visual/CarriedRifle").visible,"restored corpse does not show already taken rifle")
 near(entry)
 await tick.run(func(): game._interact())
 check(game.searching and game.profiles.revealed_ids(entry.cid).size()==ids.size(),"fully searched corpse stays revealed after restart")

func test_failure_and_empty():
 var entry=corpse(0)
 var ammo=item_in(entry.cid,"ammo_rifle")
 check(not ammo.is_empty(),"reserve remains for atomic pickup test")
 if ammo.is_empty(): return
 var before=encoded(game.profiles.profile)
 var generation=game.profiles.saves.generation
 game.profiles.saves.fault_point="before_replace"
 game._take_item(ammo)
 check(game.save_failed and game.paused and not game.playing,"failed corpse pickup pauses instead of publishing unsaved inventory")
 check(encoded(game.profiles.profile)==before and game.profiles.saves.generation==generation,"failed pickup preserves prior profile and disk generation")
 check(game.profiles.inventory.owner_of(game.profiles.profile,ammo.instance_id)==entry.cid,"failed pickup remains in corpse container")
 var observer=ProfileService.new()
 var loaded=observer.initialize(false,fixture_root,"")
 check(loaded.ok and observer.saves.canonical_json(observer.profile)==before,"independent disk reader sees no failed pickup")
 observer.saves.configure(fixture_root)
 game.profiles.saves.fault_point=""
 game._resume()
 near(entry)
 await tick.run(func(): game._interact())
 var reserve=quantity("raid_pack","ammo_rifle")
 game._take_item(ammo)
 check(quantity("raid_pack","ammo_rifle")==reserve+17 and game.reserve==reserve+17,"successful retry consumes corpse reserve exactly once and updates runtime")
 # Explicitly fill the remaining pack weight allowance; all source items must
 # remain if nothing fits, instead of disappearing during take-all.
 var candidate=game.profiles.profile.duplicate(true)
 candidate.containers.raid_pack.weight_limit=game.profiles.inventory.weight(candidate,"raid_pack")
 check(game.profiles.commit(candidate).ok,"fixture locks backpack at its current weight")
 var remaining_ids=[]
 for item in game.profiles.inventory.contents(game.profiles.profile,entry.cid): remaining_ids.append(item.instance_id)
 game._take_all()
 var retained=[]
 for item in game.profiles.inventory.contents(game.profiles.profile,entry.cid): retained.append(item.instance_id)
 check(retained==remaining_ids and not retained.is_empty(),"full pack leaves unclaimed corpse items in place")
 candidate=game.profiles.profile.duplicate(true); candidate.containers.raid_pack.weight_limit=25.0
 check(game.profiles.commit(candidate).ok,"restore normal pack limit")
 game._take_all()
 check(game.profiles.inventory.contents(game.profiles.profile,entry.cid).is_empty(),"available bag can take all remaining revealed corpse items")
 var next_seq=game.profiles.profile.next_item_seq
 game._close_search()
 if not await boot(): return
 entry=corpse(0)
 check(not entry.is_empty() and entry.items.is_empty(),"empty corpse remains recorded after disk restart")
 check(game.profiles.profile.next_item_seq==next_seq,"empty corpse reload allocates no replacement items")
 near(entry)
 await tick.run(func(): game._interact())
 check(game.searching and game.active_crate.cid==entry.cid,"empty corpse can be inspected without respawning loot")
 game._take_all(); game._close_search()
 check(game.profiles.profile.next_item_seq==next_seq,"empty reopen and take-all cannot regenerate loot")

func test_death_commit_failure():
 var before=encoded(game.profiles.profile)
 var generation=game.profiles.saves.generation
 game.profiles.saves.fault_point="before_replace"
 await kill_guard(1)
 check(game.save_failed and not game.playing,"failed death checkpoint pauses before exposing unsaved corpse inventory")
 check(encoded(game.profiles.profile)==before and game.profiles.saves.generation==generation,"death save failure publishes neither new corpse nor dead snapshot")
 check(not game.profiles.profile.containers.has("loot_guard_01"),"failed death allocates no persistent drop")
 game.profiles.saves.fault_point=""
 game._resume()
 check(game.playing and not game.save_failed and not corpse(1).is_empty(),"retry commits pending death and one corpse container")
 var ids: Array=game.profiles.profile.active_raid.search.loot_guard_01.order.duplicate()
 if not await boot(): return
 check(game.enemies[1].health.hp==0 and game.profiles.profile.active_raid.search.loot_guard_01.order==ids,"successful death retry survives fresh disk boot without reroll")

func test_settlement_and_training():
 var raid_id: String=game.profiles.profile.active_raid.raid_id
 var unclaimed: Array=game.profiles.profile.active_raid.search.loot_guard_01.order.duplicate()
 game._finish(true,"测试撤离")
 check(game.profiles.profile.active_raid.is_empty() and game.profiles.profile.settled_raids.has(raid_id),"normal settlement closes raid after corpse looting")
 check(game.profiles.inventory.owner_of(game.profiles.profile,collected_rifle)=="stash_main","extracted corpse rifle is retained in warehouse")
 var remaining_corpse_containers=0
 for cid in game.profiles.profile.containers:
  if String(cid).begins_with("loot_guard_"): remaining_corpse_containers+=1
 check(remaining_corpse_containers==0,"settlement removes all corpse containers")
 var survivors=0
 for id in unclaimed:
  if game.profiles.profile.items.has(id): survivors+=1
 check(survivors==0,"unclaimed corpse loot is not silently awarded on extraction")
 var profile_before=encoded(game.profiles.profile)
 await tick.run(func(): game._reset(true,true))
 var enemy: Dictionary=game.enemies[0]
 var damage: Dictionary=enemy.health.apply_damage(1000,&"head",1.0)
 var feedback={"origin":enemy.node.position+Vector3(0,1.5,1),"end_point":enemy.node.position+Vector3(0,1.5,0),"normal":Vector3.BACK,"hit_world":false,"actor":enemy.node,"zone":&"head"}
 feedback.merge(damage,true)
 await tick.run(func(): game._present_shot(feedback,game.player); game.player.position=enemy.node.position+Vector3(0,0,1); game._interact())
 check(encoded(game.profiles.profile)==profile_before and game.corpses.is_empty(),"combat drill death and search cannot generate or modify real profile loot")
 game._save_and_return()
 check(encoded(game.profiles.profile)==profile_before,"returning from drill preserves extracted warehouse profile")

func finish(success:=true):
 if not success: failures+=1
 await free_game()
 if is_instance_valid(tick): tick.queue_free()
 remove_fixture(fixture_root)
 await create_timer(0.15).timeout
 print("CORPSE GAME: %d/%d checks passed" % [checks-failures,checks])
 quit(1 if failures else 0)

func remove_fixture(path: String):
 var absolute=ProjectSettings.globalize_path(path).replace("\\","/")
 var allowed=ProjectSettings.globalize_path(fixture_root).replace("\\","/")
 var tests_root=ProjectSettings.globalize_path("res://tests").replace("\\","/")
 assert(allowed.begins_with(tests_root+"/.corpse-game-"))
 assert(absolute==allowed or absolute.begins_with(allowed+"/"))
 var directory=DirAccess.open(path)
 if directory==null: return
 directory.include_hidden=true
 for name in directory.get_files(): DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(name)))
 for name in directory.get_directories(): remove_fixture(path.path_join(name))
 DirAccess.remove_absolute(absolute)
