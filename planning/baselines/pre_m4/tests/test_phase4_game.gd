extends SceneTree
## Real scene campaign loop; profile is isolated in memory, including fault IO.
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

class FaultStore:
 extends RefCounted
 var generation=0
 var root_path="res://tests/in_memory_phase4"
 var fail=false
 var committed: Array=[]
 func configure(path: String,_validator: Callable=Callable()): root_path=path
 func commit_snapshot(candidate: Dictionary,_generation: int) -> Dictionary:
  if fail: return {"ok":false,"reason":"injected_before_write"}
  committed.append(candidate.duplicate(true)); generation+=1
  return {"ok":true,"generation":generation}

var game
var tick: PhysicsTask
var checks=0
var failures=0
var initial_currency=0
var store: FaultStore

func _initialize(): call_deferred("run")

func check(condition: bool,label: String):
 checks+=1
 if not condition:
  failures+=1
  push_error("PHASE4 GAME: "+label)

func frames(count: int):
 for i in range(count): await tick.run(func(): game._physics_process(1.0/60.0))

func key(code: Key,down: bool):
 var event=InputEventKey.new(); event.device=0; event.physical_keycode=code; event.keycode=code; event.pressed=down
 root.push_input(event,true)

func touch(id: int,position: Vector2,down: bool):
 var event=InputEventScreenTouch.new(); event.index=id; event.position=position; event.pressed=down
 root.push_input(event,true)

func start_raid(rule_id: String):
 check(game.profiles.profile.active_raid.is_empty(),"previous raid fully settled before new deployment")
 check(game.profiles.set_difficulty(rule_id).ok and game.profiles.quick_equip().ok,"camp can choose rules and equip for next raid")
 await tick.run(func(): game._reset(); game.deployment_grace=10000)
 await frames(4)
 check(game.playing and not game.save_failed,"prepared scene enters active play")

func move_to(position: Vector3):
 await tick.run(func(): game.player.position=position; game.player.velocity=Vector3.ZERO)
 await frames(2)

func search_crate(index: int):
 var crate=game.crates[index]
 await move_to(crate.node.position+Vector3(0,-0.4,1.4))
 await tick.run(func(): game._interact())
 check(game.searching and game.active_crate!=null and game.active_crate.cid==crate.cid,"real proximity opens crate "+crate.cid)
 if not game.searching: return
 game._advance_search(10)
 game._take_all()
 check(game.profiles.profile.active_raid.search[crate.cid].revealed>0,"search progress persisted for "+crate.cid)
 game._close_search()

func extract(id: String):
 var exit=game.extraction.definition(id)
 await move_to(exit.position)
 await tick.run(func(): game._interact())
 check(game.extraction.exit_id==id and game.extract_time>0,"selected exit starts actual countdown "+id)
 await tick.run(func(): game.extract_time=0.01)
 await frames(2)

func quantity(id: String,cids: Array=["stash_main","overflow"]) -> int:
 var result=0
 for cid in cids: result+=game.profiles.inventory.quantity(game.profiles.profile,cid,id)
 return result

func run():
 create_timer(65).timeout.connect(func(): push_error("Phase4 game timeout"); quit(1))
 game=load("res://main.tscn").instantiate(); game.test_mode=true; root.add_child(game)
 game.set_physics_process(false); game.set_process(false)
 store=FaultStore.new(); game.profiles.saves=store; game.profiles.memory_only=false
 tick=PhysicsTask.new(); root.add_child(tick)
 initial_currency=game.profiles.profile.currency
 game._open_operation()
 check(game.operation_panel.visible and not game.playing,"camp brief opens without creating gameplay state")
 for id in ["collect_medical","survey_depot","eliminate_officer"]:
  game.operation_panel.mission_accepted.emit(id)
  check(game.profiles.profile.missions[id].status=="active","mission accepted through integrated UI "+id)
 game.operation_panel.difficulty_changed.emit("comfort")
 check(game.profiles.profile.settings.difficulty=="comfort","brief rule intention reaches persistent service")
 game._operation_warehouse()
 await start_raid("comfort")
 check(game.world_map_id=="depot_v1" and game.enemies.size()==9 and game.crates.size()==15,"new original map has stable nine guards and fifteen crates")
 check(game.enemies[6].id=="guard_06" and game.map_definition.survey.id=="signal_station","scene binds named mission identities")
 check(game.remaining>599 and game.remaining<=600,"comfort has ten-minute duration")
 check(is_equal_approx(game.enemies[0].weapon.definition.base_damage,game.GUARD_WEAPON.base_damage*0.65),"comfort applies lower real weapon damage")
 check(is_equal_approx(game.enemies[0].sensor.view_distance,18) and is_equal_approx(game.enemies[0].brain.reaction_time,1),"comfort modifies actual perception and reaction")
 await test_map_controls()
 await search_crate(0)
 await search_crate(5)
 check(quantity("loot_medical",["raid_pack"])>=2,"low-risk route supplies required medical objective")
 var first_id=game.profiles.profile.active_raid.raid_id
 await extract("south_gate")
 check(game.profiles.profile.active_raid.is_empty() and game.profiles.profile.wins==1,"first complete search/extract cycle settles once")
 check(game.profiles.profile.currency==initial_currency and quantity("loot_medical")>=2,"extraction returns physical items without auto-selling")
 check(game.profiles.profile.missions.collect_medical.status=="ready","returned medical items enable delivery")
 var medical_before=quantity("loot_medical")
 game._primary_action(); game.operation_panel.mission_claimed.emit("collect_medical")
 check(game.profiles.profile.currency==initial_currency+400 and quantity("loot_medical")==medical_before-2,"UI delivery consumes exactly two medical items and awards 400")
 game.operation_panel.mission_claimed.emit("collect_medical")
 check(game.profiles.profile.currency==initial_currency+400,"duplicate delivery cannot award twice")
 check(game.profiles.settle(first_id,true).reason=="already_settled" and game.profiles.profile.wins==1,"late settlement callback cannot duplicate first raid")
 await start_raid("comfort")
 await test_conditional_exit()
 check(game.profiles.profile.wins==2 and game.profiles.profile.active_raid.is_empty(),"second raid conditional extraction completes once after retry")
 check(game.profiles.profile.missions.survey_depot.status=="ready","successful extraction promotes actual surveyed location")
 var claimed=game.profiles.claim_mission("survey_depot")
 check(claimed.ok and game.profiles.profile.currency==initial_currency+900,"survey mission awards exactly 500")
 await start_raid("standard")
 check(game.remaining>359 and game.remaining<=360,"standard has six-minute duration")
 check(is_equal_approx(game.enemies[0].weapon.definition.base_damage,game.GUARD_WEAPON.base_damage),"standard keeps full guard damage")
 check(is_equal_approx(game.enemies[0].sensor.view_distance,22) and is_equal_approx(game.enemies[0].brain.reaction_time,0.65),"standard applies full perception and reaction")
 await search_crate(0)
 await test_officer_shot()
 await extract("south_gate")
 check(game.profiles.profile.wins==3 and game.profiles.profile.missions.eliminate_officer.status=="ready","third search/kill/extract cycle enables named target delivery")
 check(game.profiles.claim_mission("eliminate_officer").ok and game.profiles.profile.currency==initial_currency+1600,"three claimed tasks conserve the total 1600 reward ledger")
 var stable_currency=game.profiles.profile.currency
 for id in ["collect_medical","survey_depot","eliminate_officer"]: game.profiles.claim_mission(id)
 check(game.profiles.profile.currency==stable_currency,"reclaiming all completed tasks preserves reward total")
 await test_death_priority("standard",false)
 await test_death_priority("comfort",true)
 check(game.profiles.profile.wins==3 and game.profiles.profile.currency==stable_currency,"failed raids add no wins or mission rewards")
 check(game.profiles.validate(game.profiles.profile).ok,"final profile passes inventory/campaign integrity validation")
 game.free(); tick.queue_free()
 await create_timer(0.15).timeout
 print("Phase4 Game: %d checks; %d failures" % [checks,failures])
 quit(1 if failures else 0)

func test_map_controls():
 game.input_router.set_action(&"move_forward",true)
 key(KEY_M,true); key(KEY_M,false)
 await frames(1)
 check(game.operation_panel.visible and game.searching and not game.input_router.enabled,"native M opens tactical map and removes combat input")
 var paused_time=game.remaining
 var paused_enemy=game.enemies[0].brain.state_elapsed
 await frames(18)
 check(game.remaining==paused_time and game.enemies[0].brain.state_elapsed==paused_enemy,"map freezes raid and enemy simulation")
 check(game.operation_panel._map.markers.all(func(marker): return marker.kind!="enemy"),"integrated tactical map never includes enemy positions")
 key(KEY_ESCAPE,true); key(KEY_ESCAPE,false)
 check(not game.operation_panel.visible and not game.searching and game.input_router.enabled,"Escape closes tactical map and resumes correct context")
 check(game.input_router.consume_frame().move==Vector2.ZERO,"closing map cannot revive a held movement input")
 for i in range(3): await process_frame
 var button: Button
 for child in game.hud_root.get_children():
  if child is Button and child.text=="地图 M": button=child
 check(button!=null,"touch HUD includes operation map button")
 if button!=null:
  var point=button.get_global_rect().get_center()
  touch(7,point,true); touch(7,point,false)
  check(game.operation_panel.visible and game.touch_buttons.is_empty(),"real touchscreen events open map and release their ownership")
  game._close_operation()

func test_conditional_exit():
 var service=game.extraction.definition("service_gate")
 await move_to(service.position)
 await tick.run(func(): game._interact())
 check(game.extraction.exit_id.is_empty() and game.extract_time==0 and game.playing,"conditional gate refuses a player without pass")
 await move_to(game.map_definition.survey.position)
 await frames(15)
 check(game.raid_events.visits.has("signal_station") and game.profiles.profile.active_raid.events.visits.has("signal_station"),"walking into survey radius persists an accepted visit")
 check(game.profiles.profile.missions.survey_depot.status=="active","visiting alone cannot award without successful extraction")
 await search_crate(6)
 check(quantity("depot_pass",["raid_pack"])==1,"real signal-station search yields conditional exit pass")
 await move_to(service.position)
 await tick.run(func(): game._interact())
 check(game.extraction.exit_id=="service_gate" and game.extract_time>2.9,"carried pass starts the three-second gate countdown")
 check(quantity("depot_pass",["raid_pack"])==1,"starting countdown does not spend pass early")
 await move_to(service.position+Vector3(0,0,-6))
 check(game.extraction.exit_id.is_empty() and game.extract_time==0,"walking outside exit radius cancels countdown")
 check(quantity("depot_pass",["raid_pack"])==1,"cancelled extraction retains pass")
 await move_to(service.position)
 await tick.run(func(): game._interact(); game.extract_time=1.4)
 game._save_and_return()
 var saved=game.profiles.profile.active_raid.snapshot.extraction.duplicate(true)
 check(saved.exit_id=="service_gate" and is_equal_approx(saved.remaining,1.4),"parked snapshot records conditional exit identity and timer")
 await tick.run(func(): game._reset(); game.deployment_grace=10000)
 check(game.extraction.exit_id=="service_gate" and is_equal_approx(game.extract_time,1.4),"resuming scene restores the same exit instead of regular gate")
 var before_profile=JSON.stringify(game.profiles.profile,"",true)
 store.fail=true
 await tick.run(func(): game.extract_time=0.01)
 await frames(1)
 check(game.save_failed and not game.playing and not game.pending_settlement.is_empty(),"failed final save pauses and retains conditional settlement intention")
 check(JSON.stringify(game.profiles.profile,"",true)==before_profile and quantity("depot_pass",["raid_pack"])==1,"failed exit commit preserves pass and all authoritative ownership")
 var committed_before=store.committed.size()
 store.fail=false
 game._resume()
 check(store.committed.size()==committed_before+1 and game.profiles.profile.active_raid.is_empty(),"retry commits exactly one atomic terminal snapshot")
 check(quantity("depot_pass")==0,"successful conditional settlement consumes exactly one pass before returning loot")

func test_officer_shot():
 var officer=game.enemies[6]
 await tick.run(func():
  game.player.position=Vector3(-25,0,-28)
  game.player.velocity=Vector3.ZERO
  officer.node.position=Vector3(-25,0,-24)
  officer.health.hp=1; officer.health.head_armor=0; officer.health.body_armor=0
 )
 await frames(2)
 await tick.run(func():
  var origin=game.player.position+Vector3(0,1.03,0.5)
  var target=officer.node.position+Vector3(0,1.03,0)
  game.aim_solution={"blocked":false,"origin":origin,"direction":(target-origin).normalized(),"target":target}
  game.weapon_runtime.definition=game.weapon_runtime.definition.duplicate()
  game.weapon_runtime.definition.hip_spread=0; game.weapon_runtime.definition.move_spread=0; game.weapon_runtime.definition.air_spread=0
  game.fire_delay=0
  game._try_fire()
 )
 check(game.last_shot.get("accepted",false) and game.last_shot.get("actor")==officer.node and game.last_shot.get("killed",false),"real player ray and weapon kill the named guard")
 check(officer.health.hp==0 and officer.brain.state==&"Dead" and officer.node.collision_layer==0,"named target uses the real combat death lifecycle")
 check(game.raid_events.kills==["guard_06"] and game.profiles.profile.active_raid.events.kills==["guard_06"],"combat presentation records one stable mission kill event")
 game._record_raid_event("kill","guard_06")
 check(game.raid_events.kills.size()==1 and game.profiles.profile.missions.eliminate_officer.status=="active","repeat kill event cannot bypass successful extraction")
 game._save_and_return()
 await tick.run(func(): game._reset(); game.deployment_grace=10000)
 check(game.enemies[6].health.hp==0 and game.raid_events.kills==["guard_06"],"checkpoint recovery retains dead officer and unique kill event")

func test_death_priority(rule_id: String,keep_equipment: bool):
 await start_raid(rule_id)
 var rifle=game.profiles.equipment(game.profiles.profile,"weapon").instance_id
 var pack_ids=[]
 for placement in game.profiles.profile.containers.raid_pack.placements: pack_ids.append(placement.item_id)
 var raid_id=game.profiles.profile.active_raid.raid_id
 var wins_before=game.profiles.profile.wins
 await move_to(game.extraction.definition("south_gate").position)
 await tick.run(func(): game._interact(); game.extract_time=0.001; game.hp=0)
 await frames(1)
 check(not game.playing and game.profiles.profile.active_raid.is_empty(),"death and extraction final tick terminate the raid "+rule_id)
 check(not game.profiles.profile.settled_raids[raid_id].success and game.profiles.profile.wins==wins_before,"death wins over coincident completed extraction "+rule_id)
 check(game.profiles.profile.items.has(rifle)==keep_equipment,"equipped rifle obeys selected loss rule "+rule_id)
 check(pack_ids.all(func(id): return not game.profiles.profile.items.has(id)),"backpack items are lost on death in either rule "+rule_id)
