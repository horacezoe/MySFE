extends SceneTree
## Real-scene inventory/checkpoint integration. test_mode is always memory-only.

class PhysicsTask:
 extends Node
 signal completed
 var pending: Callable
 func run(callback: Callable):
  pending=callback
  await completed
 func _physics_process(_delta):
  if pending.is_valid():
   var callback=pending
   pending=Callable()
   callback.call()
   completed.emit()

var game
var tick: PhysicsTask
var checks=0
var failures=0

func _initialize():
 call_deferred("run_tests")

func check(condition: bool,label: String):
 checks+=1
 if not condition:
  failures+=1
  push_error("PHASE3: "+label)

func frames(count: int):
 for index in range(count):
  await tick.run(func(): game._physics_process(1.0/60.0))

func snapshot(value) -> String:
 return JSON.stringify(value,"",true)

func pack_quantity(id: String) -> int:
 return game.profiles.inventory.quantity(game.profiles.profile,"raid_pack",id)

func run_tests():
 create_timer(40).timeout.connect(func(): push_error("Phase3 timeout"); quit(1))
 game=load("res://main.tscn").instantiate()
 game.test_mode=true
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 tick=PhysicsTask.new(); root.add_child(tick)
 await tick.run(func(): game._reset(); game.deployment_grace=1000)
 await frames(4)
 check(game.profiles.memory_only and game.enemies.size()==9,"isolated in-memory raid retains all guards")
 await test_search()
 await test_bag_pause()
 await test_consumables()
 await test_checkpoint_restore()
 await test_practice_isolation()
 await test_focus_checkpoint()
 check(game.profiles.inventory.validate(game.profiles.profile).ok,"final inventory remains valid")
 game.free(); tick.queue_free()
 await process_frame
 print("PHASE3: %d/%d checks passed" % [checks-failures,checks])
 quit(1 if failures else 0)

func test_search():
 var crate=game.crates[0]
 var cid=crate.cid
 var original_order=game.profiles.profile.active_raid.search[cid].order.duplicate()
 var original_items=snapshot(game.profiles.profile.containers[cid].placements)
 await tick.run(func(): game.player.position=crate.node.position+Vector3(0,-0.4,1.4))
 await frames(2)
 await tick.run(func(): game._interact())
 check(game.searching and game.inventory_panel.visible,"real nearby crate opens search panel")
 if not game.searching: return
 check(game.profiles.revealed_ids(cid).is_empty(),"new crate starts unrevealed")
 var hidden=crate.items[0].duplicate(true)
 var before=snapshot(game.profiles.profile)
 game._take_item(hidden)
 check(snapshot(game.profiles.profile)==before,"unrevealed pickup rejected without profile changes")
 check(game.profiles.inventory.owner_of(game.profiles.profile,hidden.instance_id)==cid,"hidden item stays owned by crate")
 game._advance_search(0.35)
 check(game.profiles.revealed_ids(cid).is_empty(),"search waits for reveal duration")
 game._close_search()
 await tick.run(func(): game._interact())
 check(snapshot(game.profiles.profile.containers[cid].placements)==original_items,"closing early does not reroll loot")
 check(is_equal_approx(game.search_elapsed,0.35),"partial search duration survives reopen")
 game._advance_search(0.36)
 check(game.profiles.revealed_ids(cid).size()==1,"search reveals exactly one item after threshold")
 var chosen=crate.items[0].duplicate(true)
 var before_quantity=pack_quantity(chosen.definition_id)
 game._take_item(chosen)
 check(pack_quantity(chosen.definition_id)==before_quantity+int(chosen.quantity),"revealed pickup updates authoritative pack")
 check(game.profiles.inventory.owner_of(game.profiles.profile,chosen.instance_id)=="raid_pack","picked instance has one new owner")
 game._close_search()
 await tick.run(func(): game._interact())
 check(game.profiles.revealed_ids(cid).size()==1 and game.profiles.profile.active_raid.search[cid].order==original_order,"reopen preserves reveal order after taking first item")
 game._advance_search(10.0)
 check(game.profiles.revealed_ids(cid).size()==original_order.size(),"all original slots eventually revealed")
 check(not game.profiles.profile.containers[cid].placements.any(func(p): return p.item_id==chosen.instance_id),"reopening cannot respawn transferred identity")
 game._close_search()

func test_bag_pause():
 game.input_router.set_action(&"move_forward",true)
 game.input_router.set_action(&"fire",true)
 game.input_router.set_action(&"aim",true)
 game._open_bag()
 var position=game.player.position
 var remaining=game.remaining
 var ammo=game.ammo
 var enemy_position=game.enemies[0].node.position
 var frame=game.input_router.consume_frame()
 check(game.searching and game.inventory_context=="bag" and game.inventory_panel.visible,"bag opens as a modal inventory")
 check(not game.input_router.enabled and frame.move==Vector2.ZERO and not frame.fire,"bag opening clears held movement and fire")
 await frames(12)
 check(game.remaining==remaining and game.player.position==position,"bag pauses raid clock and player movement")
 check(game.enemies[0].node.position==enemy_position and game.ammo==ammo,"bag pauses guards and shooting")
 game._close_inventory()
 await frames(2)
 check(game.playing and not game.searching and game.input_router.enabled,"closing bag resumes gameplay")
 check(game.ammo==ammo and game.player.velocity.x==0 and game.player.velocity.z==0,"bag close cannot revive held controls")

func test_consumables():
 game.ammo=10
 game.fire_delay=0
 check(game._checkpoint(),"spent loaded rounds checkpoint")
 var reserve_before=pack_quantity("ammo_rifle")
 var total_before=game.ammo+reserve_before
 game._reload()
 check(game.reload_time>0,"raid reload starts")
 await frames(int(ceil(game.weapon_runtime.definition.reload_duration*60))+2)
 check(game.ammo==24 and game.reserve==reserve_before-14,"reload moves reserve rounds into magazine")
 check(pack_quantity("ammo_rifle")==game.reserve and game.ammo+game.reserve==total_before,"reload consumes inventory quantity without increasing total ammunition")
 var after_reload=snapshot(game.profiles.profile.items)
 game._checkpoint()
 check(snapshot(game.profiles.profile.items)==after_reload,"repeated checkpoint cannot consume reserve twice")
 var meds_before=pack_quantity("medkit_basic")
 game.hp=62
 game._heal()
 check(game.healing_remaining>0,"raid healing starts")
 await frames(134)
 check(game.hp==100 and game.meds==meds_before-1,"healing completes once with capped health")
 check(pack_quantity("medkit_basic")==meds_before-1,"healing consumes authoritative medkit")
 game._checkpoint()
 check(pack_quantity("medkit_basic")==meds_before-1 and game.reserve==reserve_before-14,"later checkpoint never restores consumed items")

func test_checkpoint_restore():
 game.hp=61
 game.ammo=7
 game.weapon_runtime.cooldown=0.12
 game.weapon_runtime.reload_remaining=0.7
 game.motor.crouching=true
 game.player.position=Vector3(-25,0.05,-24)
 game.player.velocity=Vector3.ZERO
 game.rig.yaw=0.73; game.rig.pitch=-0.16; game.rig.third_person=false
 game.remaining=245.5
 game.enemies[0].health.hp=0
 game.enemies[0].brain.die(); game.enemies[0].weapon.disable()
 game.kills=1
 var guard=game.enemies[1]
 guard.node.position+=Vector3(0.25,0,0.25)
 guard.brain.state=&"Investigate"
 guard.brain.last_known=Vector3(-4,0,-9)
 guard.brain.aim_point=Vector3(-4,1.05,-9)
 guard.brain.has_memory=true
 guard.brain.state_elapsed=0.37
 var expected_guard_position=guard.node.position
 var raid_id=game.profiles.profile.active_raid.raid_id
 var previous_search=game.profiles.profile.active_raid.search.duplicate(true)
 game._save_and_return()
 # A newly recorded death now creates one searchable corpse in this same
 # checkpoint. Existing crate orders/timers must remain byte-for-byte intact.
 var searches=game.profiles.profile.active_raid.search
 var retained=true
 for cid in previous_search:
  retained=retained and snapshot(searches.get(cid,{}))==snapshot(previous_search[cid])
 check(retained and searches.size()==previous_search.size()+1 and searches.has("loot_guard_00"),"death checkpoint adds one corpse without changing prior crate search progress")
 var expected_search=snapshot(searches)
 var saved=game.profiles.profile.active_raid.snapshot.duplicate(true)
 check(not game.playing and game.inventory_context=="camp" and game.profiles.profile.active_raid.raid_id==raid_id,"save-and-return retains suspended raid")
 check(saved.player.health.hp==61 and saved.player.weapon.ammo==7 and saved.player.crouching,"checkpoint captures player combat state")
 check(saved.enemies.size()==9 and saved.enemies[0].health.hp==0 and saved.enemies[1].brain.state=="Investigate","checkpoint captures all guards and AI state")
 await tick.run(func(): game._reset())
 check(game.profiles.profile.active_raid.raid_id==raid_id and game.enemies.size()==9,"resume restores same raid and guard identities")
 check(game.hp==61 and game.ammo==7 and game.remaining==245.5,"resume restores health ammunition and raid clock")
 check(game.player.position.distance_to(Vector3(-25,0.05,-24))<0.001 and is_equal_approx(game.rig.yaw,0.73) and is_equal_approx(game.rig.pitch,-0.16),"resume restores player position and free-view angles")
 check(game.motor.crouching and is_equal_approx(game.player.get_node("BodyCollider").shape.height,1.05) and not game.rig.third_person,"resume restores crouch collision and perspective")
 check(is_equal_approx(game.reload_time,0.7) and is_equal_approx(game.weapon_runtime.cooldown,0.12),"resume preserves reload and weapon cooldown")
 check(game.enemies[0].health.hp==0 and game.enemies[0].brain.state==&"Dead" and game.enemies[0].node.collision_layer==0,"dead guard stays dead and non-colliding")
 check(game.enemies[1].node.position.distance_to(expected_guard_position)<0.001 and game.enemies[1].brain.state==&"Investigate" and game.enemies[1].brain.last_known==Vector3(-4,0,-9),"living guard restores location and memory")
 check(snapshot(game.profiles.profile.active_raid.search)==expected_search,"resume retains search progress and fixed loot")

func test_practice_isolation():
 game._save_and_return()
 var before=snapshot(game.profiles.profile)
 await tick.run(func(): game._reset(true))
 check(game.training_mode and game.enemies.size()==3,"practice creates isolated targets")
 game.ammo=1; game.hp=50
 game._reload()
 await frames(int(ceil(game.weapon_runtime.definition.reload_duration*60))+2)
 game._heal()
 await frames(134)
 game._checkpoint()
 check(snapshot(game.profiles.profile)==before,"practice reload healing and checkpoint do not modify suspended raid")
 game._save_and_return()
 check(snapshot(game.profiles.profile)==before,"returning from practice preserves profile")
 await tick.run(func(): game._reset())
 check(not game.training_mode and game.hp==61 and game.ammo==7 and game.enemies[0].health.hp==0,"continuing raid ignores practice health ammo and targets")

func test_focus_checkpoint():
 game.hp=47
 game.player.position=Vector3(-24.5,0.05,-24)
 game.input_router.set_action(&"move_forward",true)
 game.input_router.set_action(&"fire",true)
 game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
 var saved=game.profiles.profile.active_raid.snapshot
 check(game.paused and not game.playing and not game.input_router.enabled,"focus loss pauses and disables input")
 check(saved.player.health.hp==47 and saved.player.position[0]==-24.5,"focus loss writes latest checkpoint")
 var remaining=game.remaining
 await frames(4)
 check(game.remaining==remaining,"focus pause freezes raid time")
 game._resume()
 var frame=game.input_router.consume_frame()
 check(frame.move==Vector2.ZERO and not frame.fire,"focus return needs fresh controls")
