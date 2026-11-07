extends SceneTree
## Scene lifecycle migration checks: no personal or on-disk profiles are opened.
class PhysicsTask:
 extends Node
 signal completed
 var pending: Callable
 func run(callback: Callable):
  pending=callback
  await completed
 func _physics_process(_delta):
  if pending.is_valid():
   var callback=pending; pending=Callable()
   callback.call(); completed.emit()

var game
var tick: PhysicsTask
var checks=0
var failures=0

func _initialize(): call_deferred("run_tests")

func check(condition: bool,label: String):
 checks+=1
 if not condition: failures+=1; push_error("LEGACY WORLD: "+label)

func frames(count: int):
 for i in range(count): await tick.run(func(): game._physics_process(1.0/60.0))

func sync(count := 5):
 for i in range(count): await tick.run(func(): pass)

func sync_navigation():
 for i in range(120):
  await sync(1)
  if game.world_navigation.ready(): return

func encoded(value) -> String: return JSON.stringify(value,"",true)

func run_tests():
 create_timer(35).timeout.connect(func(): push_error("Legacy world timeout"); quit(1))
 game=load("res://main.tscn").instantiate(); game.test_mode=true
 root.add_child(game); game.set_physics_process(false); game.set_process(false)
 tick=PhysicsTask.new(); root.add_child(tick)
 check(game.profiles.memory_only,"scene fixture never opens personal saves")
 check(game.profiles.set_difficulty("standard").ok,"old-rule fixture uses standard difficulty")
 await tick.run(func(): game._reset())
 await sync_navigation()
 var first_world=weakref(game.world)
 var first_map: RID=game.world_navigation.map
 var legacy_definition=game._legacy_map_definition()
 var old_profile=make_phase3_profile(legacy_definition)
 check(game.profiles.validate(old_profile).ok,"phase-three-shaped profile is valid before migration")
 var item_snapshot=encoded(old_profile.items)
 var old_id=old_profile.active_raid.raid_id
 var upgraded=game.profiles._upgrade_profile(old_profile)
 check(upgraded.active_raid.map_id=="legacy_v3" and upgraded.active_raid.rule_id=="standard","upgrade freezes old map and loss rules")
 check(encoded(upgraded.items)==item_snapshot and upgraded.currency==old_profile.currency and upgraded.wins==old_profile.wins,"upgrade preserves every old item and economy value")
 check(game.profiles.commit(upgraded).ok,"upgraded candidate commits in memory")
 await tick.run(func(): game._reset())
 await sync_navigation()
 check(first_world.get_ref()==null and not NavigationServer3D.get_maps().has(first_map),"switch to legacy frees prior world and navigation RID")
 check(game.world_map_id=="legacy_v3" and game.map_definition.id=="legacy_v3" and game.world_navigation.ready(),"legacy geometry and navigation selected on resume")
 check(game.enemies.size()==9 and game.crates.size()==15,"legacy actor and container counts preserved")
 check(game.extraction.exits.size()==1 and game.extraction.definition("service_gate").is_empty(),"legacy raid exposes only its original south gate")
 check(game.world.find_children("RaisedRoof*","Node3D",true,false).is_empty() and game.world_obstacles.size()==15,"new depot roofs and walls do not alter legacy geometry")
 for i in range(9):
  check(game.enemies[i].node.position==legacy_definition.guards[i].position and game.enemies[i].brain.route==legacy_definition.guards[i].route,"original guard position and route preserved "+str(i))
 for i in range(15):
  check(game.crates[i].node.position.is_equal_approx(legacy_definition.crates[i]+Vector3(0,0.4,0)),"original crate position preserved "+str(i))
 check(game.player.position==Vector3(25,0,25) and game.hp==73 and game.ammo==11,"legacy player position health and loaded ammunition restored")
 check(is_equal_approx(game.extract_time,2.25) and game.extraction.exit_id=="south_gate" and is_equal_approx(game.remaining,127.5),"old scalar extraction countdown resumes without resetting")
 check(game.enemies[2].health.hp==0 and game.enemies[2].brain.state==&"Dead" and game.enemies[2].node.collision_layer==0,"legacy dead guard cannot respawn during migration")
 check(game.profiles.profile.active_raid.mission_ids.is_empty() and game.raid_events.visits.is_empty() and game.raid_events.kills.is_empty(),"migrated raid has no retroactive mission credit")
 check(game.profiles.profile.active_raid.snapshot.has("extraction"),"first resumed checkpoint adds structured extraction safely")
 var missions_before=encoded(game.profiles.profile.missions)
 game._record_raid_event("visit","signal_station")
 game._record_raid_event("kill","guard_06")
 check(encoded(game.profiles.profile.missions)==missions_before and game.raid_events.visits.is_empty() and game.raid_events.kills.is_empty(),"old raid cannot accrue unaccepted phase-four events")
 var legacy_world=weakref(game.world)
 var legacy_nav: RID=game.world_navigation.map
 var wealth_before=game.wealth
 var wins_before=game.wins
 await tick.run(func(): game.extract_time=0.02)
 await frames(3)
 check(not game.playing and game.profiles.profile.active_raid.is_empty() and game.profiles.profile.settled_raids.has(old_id),"legacy countdown completes real extraction once")
 check(game.wealth==wealth_before and game.wins==wins_before+1 and encoded(game.profiles.profile.missions)==missions_before,"legacy extraction preserves physical economy and grants no retroactive task rewards")
 check(game.profiles.quick_equip().ok,"returned legacy equipment can prepare next operation")
 await tick.run(func(): game._reset())
 await sync_navigation()
 check(game.world_map_id=="depot_v1" and game.profiles.profile.active_raid.map_id=="depot_v1","first new raid enters current depot map")
 check(legacy_world.get_ref()==null and not NavigationServer3D.get_maps().has(legacy_nav),"leaving legacy world releases old geometry and navigation RID")
 check(game.world_navigation.ready() and game.extraction.exits.size()==2,"new depot navigation and both exits are active")
 check(game.enemies.size()==9 and game.crates.size()==15 and game.world.find_children("RaisedRoof*","Node3D",true,false).size()==5,"new depot restores stable actor counts and raised roof geometry")
 check(game.enemies[6].node.position==Vector3(23,0,0) and game.enemies[6].id=="guard_06","new officer uses depot position and stable task identity")
 check(game.crates[6].node.position.is_equal_approx(Vector3(22,0.4,0)) and game.crates[1].node.position.is_equal_approx(Vector3(-24,0.4,-8)),"new supply points replace old coordinates after settlement")
 check(game.profiles.profile.active_raid.rule_id=="standard","migration keeps selected standard rule for the next raid")
 await test_practice_switch()
 game.free(); tick.queue_free()
 await create_timer(0.15).timeout
 print("Phase4 legacy: %d/%d checks passed" % [checks-failures,checks])
 quit(1 if failures else 0)

func make_phase3_profile(legacy_definition: Dictionary) -> Dictionary:
 var old=game.profiles.profile.duplicate(true)
 old.profile_version=1; old.erase("missions"); old.erase("mission_version"); old.settings.erase("difficulty")
 for key in ["map_id","rule_id","rule_version","events","mission_ids"]: old.active_raid.erase(key)
 # The new pass definition did not exist in phase three; remove only fixture data.
 for cid in old.containers:
  for placement in old.containers[cid].placements.duplicate(true):
   if old.items[placement.item_id].definition_id!="depot_pass": continue
   old.items.erase(placement.item_id); old.containers[cid].placements.erase(placement)
   if old.active_raid.search.has(cid): old.active_raid.search[cid].order.erase(placement.item_id)
 var snapshot=old.active_raid.snapshot
 snapshot.erase("extraction")
 snapshot.player.position=[25,0,25]; snapshot.player.velocity=[0,0,0]
 snapshot.player.health.hp=73.0; snapshot.player.weapon.ammo=11
 snapshot.remaining=127.5; snapshot.extract_time=2.25; snapshot.deployment_grace=1000.0; snapshot.kills=1
 var rifle=game.profiles.equipment(old,"weapon"); rifle.runtime.ammo=11
 for i in range(9):
  snapshot.enemies[i].position=game.snapshot_codec.vector(legacy_definition.guards[i].position)
  snapshot.enemies[i].brain.state="Dead" if i==2 else "Patrol"
  snapshot.enemies[i].health.hp=0.0 if i==2 else 75.0
 return old

func test_practice_switch():
 game.hp=82; game.ammo=9; game.deployment_grace=1000
 game._save_and_return()
 var before=encoded(game.profiles.profile)
 var active_id=game.profiles.profile.active_raid.raid_id
 var depot_world=weakref(game.world)
 var depot_nav: RID=game.world_navigation.map
 await tick.run(func(): game._reset(true,true))
 await sync()
 var drill_nav: RID=game.drill_navigation.map
 check(game.training_mode and game.combat_drill and game.enemies.size()==2 and game.runtime_raid_id.is_empty(),"combat practice has isolated actors and no raid authority")
 game.hp=22; game.ammo=1; game.remaining=5
 game._checkpoint(); game._save_and_return()
 check(encoded(game.profiles.profile)==before,"practice return preserves suspended current-map profile exactly")
 await tick.run(func(): game._reset())
 await sync_navigation()
 check(game.profiles.profile.active_raid.raid_id==active_id and game.hp==82 and game.ammo==9,"practice return restores original raid health ammo and identity")
 check(not game.training_mode and game.enemies.size()==9 and game.world_map_id=="depot_v1","practice resumes depot rather than accidentally selecting legacy")
 check(depot_world.get_ref()==game.world and depot_nav==game.world_navigation.map and game.world_navigation.ready(),"same-map practice return retains one current world and navigation map")
 check(game.drill_navigation==null and not NavigationServer3D.get_maps().has(drill_nav),"practice navigation is disposed on regular raid resume")
