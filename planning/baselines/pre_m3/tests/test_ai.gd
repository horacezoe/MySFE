extends SceneTree
## Real navigation/physics integration; no game.gd or user save dependency.
const NavigationWorld=preload("res://scripts/ai/navigation_world.gd")
const PerceptionSystem=preload("res://scripts/ai/perception_system.gd")
const EnemyBrain=preload("res://scripts/ai/enemy_brain.gd")

class Probe extends Node3D:
 signal physics_tick(delta: float)
 var ticks := 0
 func _physics_process(delta: float):
  ticks+=1
  if ticks>3000:
   printerr("FAIL: AI tests timed out")
   get_tree().quit(2)
  physics_tick.emit(delta)

var probe: Probe
var nav
var checks := 0
var failures := 0

func _initialize():
 probe=Probe.new()
 root.add_child(probe)
 call_deferred("run_tests")

func check(condition: bool, text: String):
 checks+=1
 if not condition:
  failures+=1
  printerr("FAIL: "+text)

func sync(frames := 2):
 for i in range(frames): await probe.physics_tick

func box(position: Vector3,size: Vector3) -> StaticBody3D:
 var body=StaticBody3D.new()
 body.collision_layer=1
 var shape=BoxShape3D.new()
 shape.size=size
 var collider=CollisionShape3D.new()
 collider.shape=shape
 body.add_child(collider)
 probe.add_child(body)
 body.global_position=position
 return body

func actor(position: Vector3) -> CharacterBody3D:
 var body=CharacterBody3D.new()
 body.collision_layer=2
 body.collision_mask=1|2
 var capsule=CapsuleShape3D.new()
 capsule.radius=0.48; capsule.height=1.7
 var collider=CollisionShape3D.new()
 collider.shape=capsule; collider.position.y=0.9
 body.add_child(collider)
 for zone in [&"torso",&"head"]:
  var hitbox=Area3D.new()
  hitbox.collision_layer=4; hitbox.collision_mask=0
  hitbox.monitoring=false
  hitbox.set_meta("actor",body); hitbox.set_meta("zone",zone)
  hitbox.position.y=1.05 if zone==&"torso" else 1.62
  var hitshape=BoxShape3D.new()
  hitshape.size=Vector3(0.64,0.7,0.4) if zone==&"torso" else Vector3(0.5,0.5,0.5)
  var hitcollider=CollisionShape3D.new()
  hitcollider.shape=hitshape
  hitbox.add_child(hitcollider)
  body.add_child(hitbox)
 probe.add_child(body)
 body.global_position=position
 body.set_meta("hp",100)
 return body

func run_tests():
 box(Vector3(0,-0.5,0),Vector3(120,1,120))
 await sync()
 await test_perception()
 await test_states()
 await test_navigation()
 print("AI checks: %d passed / %d total" % [checks-failures,checks])
 probe.queue_free()
 await process_frame
 quit(1 if failures else 0)

func test_perception():
 var guard=actor(Vector3(-25,0,0))
 var target=actor(Vector3(-25,0,-8))
 var sensor=PerceptionSystem.new()
 await sync()
 var first: Dictionary=sensor.observe(guard,target,1.0/60.0)
 check(first.visible and not first.confirmed,"visible target requires confirmation time")
 var seen: Dictionary={}
 for i in range(30):
  var delta: float=await probe.physics_tick
  seen=sensor.observe(guard,target,delta)
 check(seen.visible and seen.confirmed,"repeated 8Hz samples confirm target")
 check(seen.position==target.global_position and seen.aim_point.y>0.9,"visible observation contains sampled location and aim point")
 target.global_position=Vector3(-25,0,8)
 sensor.reset()
 await sync()
 seen=sensor.observe(guard,target,0.2)
 check(not seen.visible and not seen.has("position"),"target behind observer is absent from observation")
 target.global_position=Vector3(-25,0,-25)
 sensor.reset()
 await sync()
 check(not sensor.observe(guard,target,0.2).visible,"view distance rejects distant target")
 target.global_position=Vector3(-25,0,-8)
 var wall=box(Vector3(-25,1.3,-7.4),Vector3(3,2.6,0.12))
 sensor.reset()
 await sync()
 seen=sensor.observe(guard,target,0.2)
 check(not seen.visible and not seen.confirmed and not seen.has("aim_point"),"12cm wall within 1.2m of target blocks all visual knowledge")
 wall.free()
 sensor.reset()
 await sync()
 check(sensor.observe(guard,target,0.2).visible,"visibility returns after wall is removed")
 # A low wall hides the torso but permits a head sample.
 wall=box(Vector3(-25,0.6,-7.4),Vector3(3,1.2,0.12))
 sensor.reset()
 await sync()
 seen=sensor.observe(guard,target,0.2)
 check(seen.visible and seen.aim_point.y>1.4,"head above cover is a valid visible aim point")
 guard.free(); target.free(); wall.free()
 await sync()

func test_states():
 var guard=actor(Vector3(25,0,0))
 var brain=EnemyBrain.new()
 brain.setup(guard,[Vector3(25,0,0)],RID(),123)
 await sync()
 var visible={"visible":true,"confirmed":true,"position":Vector3(25,0,-10),"aim_point":Vector3(25,1.05,-10)}
 var fired_early := false
 var shots := 0
 for i in range(90):
  var delta: float=await probe.physics_tick
  var result: Dictionary=brain.step(delta,visible)
  if i<30 and result.fire: fired_early=true
  if result.fire: shots+=1
 check(not fired_early,"confirmed target still gets an alert/reaction window")
 check(brain.state==brain.ENGAGE and shots>0,"guard fires intentions after reacting and facing target")
 check(shots<=3,"burst cadence limits requests instead of firing every tick")
 check(guard.get_meta("hp")==100,"brain emits intent without applying health damage")
 var remembered: Vector3=brain.last_known
 var hidden={"visible":false,"confirmed":false}
 var hidden_shots := 0
 for i in range(30):
  var delta: float=await probe.physics_tick
  if brain.step(delta,hidden).fire: hidden_shots+=1
 check(brain.state==brain.INVESTIGATE and brain.last_known==remembered,"losing target investigates only its last known position")
 check(hidden_shots==0,"hidden target never produces a firing request")
 brain.hear(Vector3(25,0,4),1.0)
 check(brain.last_known==Vector3(25,0,4),"gunshot event updates remembered sound position")
 brain.hear(Vector3(25,0,100),1.0)
 check(brain.last_known==Vector3(25,0,4),"inaudible sound cannot update memory")
 brain.hear(guard.global_position,1.0)
 await probe.physics_tick
 brain.step(1.0/60.0,hidden)
 check(brain.state==brain.SEARCH,"reaching investigation point begins timed search")
 brain.search_duration=0.1
 for i in range(15):
  var delta: float=await probe.physics_tick
  brain.step(delta,hidden)
 check(brain.state==brain.PATROL and not brain.has_memory,"finished search returns home and clears stale memory")
 guard.rotation.y=PI
 brain.take_hit(Vector3(25,0,-10))
 var old_rotation: float=guard.rotation.y
 await probe.physics_tick
 var result: Dictionary=brain.step(1.0/60.0,visible)
 check(absf(wrapf(guard.rotation.y-old_rotation,-PI,PI))<=brain.turn_speed/60.0+0.001,"alert turns at a bounded rate")
 check(not result.fire,"cannot instantly turn and shoot a target behind")
 brain.die()
 await probe.physics_tick
 result=brain.step(1.0/60.0,visible)
 check(brain.state==brain.DEAD and not result.fire and guard.velocity==Vector3.ZERO,"dead guard stops all actions")
 guard.free()
 await sync()

func test_navigation():
 var wall=box(Vector3(0,1.4,0),Vector3(2,2.8,10))
 nav=NavigationWorld.new()
 var obstacles: Array[Rect2]=[Rect2(-1,-5,2,10)]
 nav.build(probe,Rect2(-12,-12,24,24),obstacles)
 for i in range(10):
  await probe.physics_tick
  if nav.ready(): break
 check(nav.ready(),"navigation map synchronizes before queries")
 var path: PackedVector3Array=NavigationServer3D.map_get_path(nav.map,Vector3(-7,0,0),Vector3(7,0,0),true)
 check(path.size()>2,"route around wall has intermediate waypoints")
 var path_around := false
 for point in path:
  if absf(point.z)>5.5: path_around=true
 check(path_around,"navmesh expanded obstacle prevents corner cutting")
 var guard=actor(Vector3(-7,0,0))
 var brain=EnemyBrain.new()
 brain.setup(guard,[Vector3(-7,0,0)],nav.map,456)
 brain.investigate_timeout=14.0
 brain.hear(Vector3(7,0,0),1.0)
 var furthest_z := 0.0
 var penetrated := false
 for i in range(780):
  var delta: float=await probe.physics_tick
  brain.step(delta,{"visible":false,"confirmed":false})
  furthest_z=maxf(furthest_z,absf(guard.global_position.z))
  if absf(guard.global_position.x)<1.45 and absf(guard.global_position.z)<5.45: penetrated=true
  if brain.state==brain.SEARCH: break
 check(not penetrated,"real capsule never passes through the wall")
 check(furthest_z>5.5,"NavigationAgent drives actor around the wall")
 check(brain.state==brain.SEARCH and Vector2(guard.position.x-7,guard.position.z).length()<1.0,"actor reaches last heard location via navigation")
 # Destination inside solid geometry must time out safely, never chase forever.
 brain.investigate_timeout=0.3
 brain.hear(Vector3.ZERO,1.0)
 for i in range(25):
  var delta: float=await probe.physics_tick
  brain.step(delta,{"visible":false,"confirmed":false})
 check(brain.state==brain.SEARCH,"unreachable investigation point has a bounded timeout")
 guard.free()
 nav.dispose()
 check(not nav.map.is_valid() and not is_instance_valid(nav.region),"navigation dispose releases region and map")
 wall.free()
 await sync()
