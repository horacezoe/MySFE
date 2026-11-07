extends SceneTree
## Real scene presentation regression. All profile writes stay memory-only.
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
var checks=0
var failures=0

func _initialize(): call_deferred("run")

func check(condition: bool,label: String):
 checks+=1
 if not condition:
  failures+=1
  push_error("PHASE5 INTEGRATION: "+label)

func frames(count: int):
 for i in range(count): await tick.run(func(): game._physics_process(1.0/60.0))

func bone_pose(visual: Node3D,bone_name: String) -> Transform3D:
 return visual.skeleton.get_bone_global_pose(visual.skeleton.find_bone(bone_name))

func skinned_top(visual: Node3D) -> float:
 # Reproduce vertex skinning on the CPU for a geometric ceiling check. This
 # tests the actual helmet and clothing, not just the collider or AABB hint.
 var skin: Skin=visual.skin_mesh.skin
 var poses: Array[Transform3D]=[]
 for index in skin.get_bind_count():
  poses.append(visual.skeleton.get_bone_global_pose(skin.get_bind_bone(index))*skin.get_bind_pose(index))
 var highest=-INF
 var mesh: ArrayMesh=visual.skin_mesh.mesh
 for surface in mesh.get_surface_count():
  var arrays: Array=mesh.surface_get_arrays(surface)
  var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
  var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
  for index in vertices.size():
   var position=Vector3.ZERO
   for influence in range(4):
    var offset=index*4+influence
    position+=(poses[bones[offset]]*vertices[index])*weights[offset]
   highest=maxf(highest,position.y)
 return highest

func run():
 create_timer(65).timeout.connect(func(): push_error("Phase5 integration timeout"); quit(1))
 game=load("res://main.tscn").instantiate(); game.test_mode=true; root.add_child(game)
 game.set_physics_process(false); game.set_process(false)
 tick=PhysicsTask.new(); root.add_child(tick)
 check(game.profiles.memory_only,"test profile cannot write personal saves")
 await tick.run(func(): game._reset(true))
 await frames(10)
 await test_aim_and_pose()
 await test_reload_hand_tracking()
 await test_pause_and_authority()
 await test_restore_and_death()
 await test_pool_lifecycle()
 game.free(); tick.queue_free()
 await create_timer(0.15).timeout
 print("Phase5 Integration: %d checks; %d failures" % [checks,failures])
 quit(1 if failures else 0)

func test_aim_and_pose():
 var visual=game.player.get_node("Visual")
 check(visual.metrics().skinned and visual.skeleton.get_bone_count()>=18,"scene uses a bound anatomical skeleton")
 check(visual.animation_tree.active,"scene enables real animation blend tree")
 for third in [false,true]:
  await tick.run(func(): game.rig.third_person=third; game._apply_view(); game.rig.pitch=0.12; game.rig.yaw=0.2)
  await frames(2)
  var rifle=visual.get_node("CarriedRifle") if third else game.gun
  check(game.aim_solution.origin.distance_to(rifle.get_node("Muzzle").global_position)<0.0001,"view selects physical muzzle "+str(third))
  check(game.aim_solution.direction.distance_to((game.aim_solution.target-game.aim_solution.origin).normalized())<0.0001,"view ray converges from real muzzle "+str(third))
  check(game.gun.visible!=third,"only first-person rifle appears in first-person view")
 await tick.run(func(): game.rig.third_person=false; game._apply_view(); game._queue_action(&"aim_toggle"))
 await frames(25)
 check(game.rig.aiming,"ADS activates when grounded and ready")
 var aim: Vector3=game.gun.get_node("Aim").global_position
 var in_camera: Vector3=game.camera.to_local(aim)
 check(absf(in_camera.x)<0.001 and absf(in_camera.y)<0.001 and in_camera.z<0,"actual optic marker lies on camera sight axis")
 var center=game.camera.get_viewport().get_visible_rect().size*0.5
 check(game.camera.unproject_position(aim).distance_to(center)<0.1,"ADS sight projects into visible center")
 game._queue_action(&"aim_toggle")
 game._queue_action(&"crouch")
 var previous_head: float=visual.pose_markers().head.y
 for i in range(12):
  await frames(1)
  var markers: Dictionary=visual.pose_markers()
  check(game.player.get_node("Hitboxes/Head").position.distance_to(markers.head)<0.001,"transition hitbox follows current head pose "+str(i))
 check(visual.pose_markers().head.y<previous_head-0.25,"crouch lowers skeleton head instead of scaling mesh")
 check(visual.scale==Vector3.ONE and game.player.get_node("Hitboxes").scale==Vector3.ONE,"crouch leaves both model and hitbox root at full scale")
 game.rig.pitch=0.0
 await frames(2)
 check(visual.pose_markers().head.y+0.18<=1.28,"crouched helmet clearance fits the existing 1.28 metre training tunnel")
 check(skinned_top(visual)<=1.28,"actual skinned helmet and clothing stay below tunnel ceiling")
 for side in ["Left","Right"]:
  var palm: Vector3=visual.pose_markers()[side.to_lower()+"_hand"]
  var grip: Vector3=visual.to_local(visual.get_node("CarriedRifle/Grip"+side).global_position)
  check(palm.distance_to(grip)<0.05,"crouched arm can reach actual carried rifle grip "+side)
 for mapping in [["LeftLeg","left_thigh"],["RightLeg","right_thigh"],["LeftShin","left_shin"],["RightShin","right_shin"],["LeftArm","left_upper_arm"],["RightArm","right_upper_arm"],["LeftForearm","left_forearm"],["RightForearm","right_forearm"]]:
  var segment: Dictionary=visual.pose_markers()[mapping[1]]
  var area: Node3D=game.player.get_node("Hitboxes/"+mapping[0])
  check(area.position.distance_to((segment.start+segment.end)*0.5)<0.001,"anatomical segment center follows bones "+mapping[0])
  check(absf(area.basis.y.normalized().dot((segment.end-segment.start).normalized()))>0.999,"anatomical segment points along bent limb "+mapping[0])
 game._queue_action(&"crouch")
 await frames(14)

func test_reload_hand_tracking():
 var visual: Node3D=game.player.get_node("Visual")
 var rifle: Node3D=visual.get_node("CarriedRifle")
 game.rig.third_person=true; game._apply_view()
 game.ammo=7; game.reserve=50
 for crouched in [false,true]:
  if game.motor.crouching!=crouched:
   game._queue_action(&"crouch")
   await frames(15)
  for phase in [0.2,0.45,0.65,0.88]:
   await tick.run(func():
    game.weapon_runtime.reload_remaining=game.weapon_runtime.definition.reload_duration*(1.0-phase)
    game._update_aim()
    game._update_player_visual(0.0)
   )
   var target: Vector3=visual.to_local(rifle.to_global(rifle.left_hand_target(phase)))
   var actual: Vector3=visual.pose_markers().left_hand
   check(actual.distance_to(target)<0.03,"third-person support hand tracks real reload grip at %.2f, crouched=%s" % [phase,crouched])
  game.weapon_runtime.cancel_reload()
 check(game.ammo==7 and game.reserve==50,"seeking both view reload poses leaves real ammunition unchanged")
 game.weapon_runtime.cancel_reload()
 if game.motor.crouching: game._queue_action(&"crouch")
 await frames(15)

func test_pause_and_authority():
 var visual=game.player.get_node("Visual")
 game.ammo=7; game.reserve=50
 game._reload()
 await frames(35)
 check(game.reload_time>0 and game.ammo==7,"reload animation has not committed ammunition early")
 var magazine: Node3D=game.gun.get_node("Magazine")
 check(magazine.position.distance_to(game.gun.MAGAZINE_REST)>0.15,"magazine is visibly removed during reload")
 await tick.run(func(): game.feedback.shot(Vector3(100,1,20),Vector3(100,1,16),Vector3.UP,true,true); game._pause_game())
 var reload_before: float=game.reload_time
 var magazine_before: Transform3D=magazine.transform
 var head_before: Transform3D=bone_pose(visual,"Head")
 var effect_ages: Array=[]
 for pool in [game.feedback._tracers,game.feedback._impacts,game.feedback._casings]:
  for effect in pool: effect_ages.append(effect.age)
 await frames(10)
 check(is_equal_approx(game.reload_time,reload_before),"pause freezes authoritative reload clock")
 check(magazine.transform.is_equal_approx(magazine_before),"pause freezes magazine keyframe")
 check(bone_pose(visual,"Head").is_equal_approx(head_before),"pause freezes skeleton blend and breathing")
 var after_ages: Array=[]
 for pool in [game.feedback._tracers,game.feedback._impacts,game.feedback._casings]:
  for effect in pool: after_ages.append(effect.age)
 check(after_ages==effect_ages,"pause freezes all pooled effect lifetimes")
 check(game.feedback.metrics().voices_playing==0,"pause stops local and spatial audio voices")
 game._resume()
 await frames(80)
 check(game.ammo==24 and game.reload_time==0,"resume completes exactly one magazine fill")
 var ammo_after: int=game.ammo
 game.gun.step(3.0,{"reload_progress":1.0})
 visual.step(3.0,{"reload_progress":1.0,"grounded":true})
 await frames(3)
 check(game.ammo==ammo_after,"presentation seeks cannot transfer ammunition a second time")
 check(magazine.position.distance_to(game.gun.MAGAZINE_REST)<0.0001,"completed reload seats magazine")
 check(game.feedback.metrics().active==0,"resumed effects expire instead of persisting forever")

func test_restore_and_death():
 await tick.run(func(): game._reset(); game.deployment_grace=10000.0)
 await frames(10)
 game._queue_action(&"crouch")
 await frames(15)
 game.ammo=6
 game._reload()
 await frames(34)
 var saved: Dictionary=game.snapshot_codec.capture(game)
 var ammo_before: int=game.ammo
 var reserve_before: int=game.reserve
 var reload_before: float=game.reload_time
 var magazine_before: Transform3D=game.gun.get_node("Magazine").transform
 game._open_bag()
 var head_before: Transform3D=bone_pose(game.player.get_node("Visual"),"Head")
 check(game.searching and game.inventory_panel.visible,"real inventory UI enters paused presentation context")
 await frames(5)
 check(is_equal_approx(game.reload_time,reload_before) and game.gun.get_node("Magazine").transform.is_equal_approx(magazine_before),"inventory management freezes reload timer and visible magazine")
 check(bone_pose(game.player.get_node("Visual"),"Head").is_equal_approx(head_before),"inventory management freezes skeletal animation")
 game._close_inventory()
 await tick.run(func():
  game.motor.crouching=false; game.motor.eye_height=1.55
  game.player.get_node("Visual").reset_pose(); game.gun.reset_pose()
  game.snapshot_codec.apply(game,saved)
 )
 check(game.motor.crouching and game.player.get_node("BodyCollider").shape.height<1.1,"snapshot restores crouched collision capsule")
 check(game.player.get_node("Visual").pose_markers().head.y<1.3,"snapshot reconstructs crouch pose before first simulation frame")
 check(game.player.get_node("Hitboxes/Head").position.distance_to(game.player.get_node("Visual").pose_markers().head)<0.001,"snapshot immediately synchronizes skeletal head hitbox")
 check(game.gun.get_node("Magazine").transform.is_equal_approx(magazine_before),"snapshot seeks magazine to persisted reload time")
 check(game.ammo==ammo_before and game.reserve==reserve_before and is_equal_approx(game.reload_time,reload_before),"snapshot presentation restore preserves exact ammunition and reload clock")
 game.weapon_runtime.cancel_reload()
 var target: Dictionary=game.enemies[0]
 var visual: Node3D=target.node.get_node("Visual")
 var position_before: Vector3=target.node.global_position
 var rifle: Node3D=visual.get_node("CarriedRifle")
 var rifle_before: Vector3=rifle.position
 # Send a real damage result through the production presentation path. This
 # avoids depending on a guard wandering into a camera ray during the test.
 var damage: Dictionary=target.health.apply_damage(10000.0,&"head",1.0)
 var shot: Dictionary={"origin":position_before+Vector3(0,1.6,1),"end_point":position_before+Vector3(0,1.6,0),"normal":Vector3.BACK,"hit_world":false,"actor":target.node,"zone":&"head"}
 shot.merge(damage,true)
 await tick.run(func(): game._present_shot(shot,game.player))
 check(target.brain.state==&"Dead" and target.weapon.disabled,"lethal damage disables AI and authoritative weapon")
 check(target.node.collision_layer==0 and target.node.collision_mask==0,"corpse no longer obstructs player movement")
 var enabled_hitboxes=0
 for area in target.node.get_node("Hitboxes").get_children(): enabled_hitboxes+=1 if area.collision_layer!=0 else 0
 check(enabled_hitboxes==0,"all expanded anatomical hitboxes turn off at death")
 await frames(45)
 check(target.node.global_position.distance_to(position_before)<0.001,"death animation cannot move gameplay actor root")
 check(rifle.position.distance_to(rifle_before)>0.3 and rifle.position.y<0.65,"carried rifle follows falling body instead of floating at shoulder")
 var settled: Transform3D=bone_pose(visual,"Head")
 var rifle_settled: Transform3D=rifle.transform
 await frames(30)
 check(bone_pose(visual,"Head").is_equal_approx(settled) and rifle.transform.is_equal_approx(rifle_settled),"finished corpse and rifle remain stable")
 var dead_snapshot: Dictionary=game.snapshot_codec.capture(game)
 await tick.run(func(): game.snapshot_codec.apply(game,dead_snapshot))
 check(bone_pose(visual,"Head").is_equal_approx(settled),"dead snapshot restores settled skeleton without replaying collapse")

func test_pool_lifecycle():
 var node_count: int=game.feedback.metrics().node_count
 for loop in range(3):
  await tick.run(func(): game._reset(true))
  var starts_before: int=game.feedback.metrics().audio_started
  var dropped_before: int=game.feedback.metrics().audio_dropped
  for i in range(100):
   game.feedback.shot(Vector3(100,1.2,20),Vector3(100,1.2,10),Vector3.UP,true,true)
   game.feedback.casing(Vector3(100,1.2,20),Vector3.RIGHT)
  check(game.feedback.metrics().node_count==node_count,"repeated scene reset and burst retain fixed effects nodes "+str(loop))
  check(game.feedback.metrics().active<=36,"all effect kinds respect pool capacity "+str(loop))
  check(game.feedback.metrics().audio_started-starts_before<=12,"same-frame burst bounds actual playback starts as well as nodes "+str(loop))
  check(game.feedback.metrics().audio_dropped>dropped_before,"over-budget sound is dropped without dropping visual effects "+str(loop))
  game.feedback.reset()
  check(game.feedback.metrics().active==0 and game.feedback.metrics().voices_playing==0,"new practice session clears every prior effect and sound "+str(loop))
  # Spatial audio submits work at the physics boundary. An idle-only wait is
  # insufficient on the unthrottled headless driver before freeing the owner.
  await physics_frame
  await physics_frame
  await process_frame
  await process_frame
  var resumed_starts: int=game.feedback.metrics().audio_started
  game.feedback.hit()
  check(game.feedback.metrics().audio_started==resumed_starts+1,"next frame restores normal audible feedback after overload "+str(loop))
  game.feedback.stop()
