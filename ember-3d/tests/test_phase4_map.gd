extends SceneTree
## Actual depot geometry, capsule clearance, occlusion and navigation queries.
const DepotMap=preload("res://scripts/world/depot_map.gd")
const NavigationWorld=preload("res://scripts/ai/navigation_world.gd")

class Harness:
 extends Node3D
 signal tick
 var world: Node3D
 var world_obstacles: Array[Rect2]=[]
 func _init(): world=self
 func _physics_process(_delta): tick.emit()
 func box(parent: Node3D,size: Vector3,position: Vector3,color: Color,solid := false) -> Node3D:
  var node: Node3D=StaticBody3D.new() if solid else Node3D.new()
  if solid:
   node.collision_layer=1|16; node.collision_mask=2
   var shape=BoxShape3D.new(); shape.size=size
   var collider=CollisionShape3D.new(); collider.shape=shape; node.add_child(collider)
   if parent==world and size.y>0.6 and absf(position.x)<40:
    world_obstacles.append(Rect2(position.x-size.x*0.5,position.z-size.z*0.5,size.x,size.z))
  parent.add_child(node); node.position=position
  var mesh=MeshInstance3D.new(); var cube=BoxMesh.new(); cube.size=size; mesh.mesh=cube
  var material=StandardMaterial3D.new(); material.albedo_color=color; mesh.material_override=material
  node.add_child(mesh)
  return node

var harness: Harness
var nav=NavigationWorld.new()
var map_data: Dictionary
var checks=0
var failures=0

func _initialize(): call_deferred("run_tests")

func check(condition: bool,label: String):
 checks+=1
 if not condition: failures+=1; push_error("DEPOT: "+label)

func sync(count := 3):
 for i in range(count): await harness.tick

func run_tests():
 create_timer(25).timeout.connect(func(): push_error("Depot map timeout"); quit(1))
 harness=Harness.new(); root.add_child(harness)
 var map_builder=DepotMap.new(); map_data=map_builder.definition()
 harness.box(harness,Vector3(64,0.5,64),Vector3(0,-0.25,0),Color.GRAY,true)
 map_builder.build(harness)
 nav.build(harness,map_data.bounds,harness.world_obstacles)
 await sync(8)
 check(nav.ready(),"real static navigation synchronized")
 check(map_data.id=="depot_v1" and map_data.crates.size()==15 and map_data.guards.size()==9,"stable map identity and saved actor counts")
 check(map_data.spawn==Vector3(-26,0,-26) and map_data.crates[0]==Vector3(-22,0,-22),"entry and first searchable crate preserve baseline")
 check(map_data.zones.size()==4 and map_data.exits.size()==2,"four readable areas and two exit choices")
 check(map_data.exits[0].position==Vector3(25,0,25) and map_data.exits[0].required_item=="","always-open conventional exit")
 check(map_data.exits[1].required_item=="depot_pass" and map_data.exits[1].wait<map_data.exits[0].wait,"pass exit is distinct and faster")
 check(harness.world_obstacles.size()==map_data.walls.size(),"raised roofs never enter floor navigation occupancy")
 check(harness.find_children("*","Node",true,false).size()<650,"geometry fits bounded mobile prototype node budget")
 check(_clear_capsule(map_data.spawn),"spawn has standing capsule clearance")
 var start=nav.closest_point(map_data.spawn)
 check(start.distance_to(map_data.spawn)<0.25,"spawn lies on navigation floor")
 for i in range(map_data.crates.size()):
  var position: Vector3=map_data.crates[i]
  check(map_data.bounds.has_point(Vector2(position.x,position.z)),"crate within map "+str(i))
  check(_clear_capsule(position),"crate placement is not trapped in a wall "+str(i))
  var approach=nav.closest_point(position)
  var path=NavigationServer3D.map_get_path(nav.map,start,approach,true)
  check(not path.is_empty() and path[-1].distance_to(approach)<0.15 and approach.distance_to(position)<1.8,"spawn can reach searchable distance of crate "+str(i))
  var ray=PhysicsRayQueryParameters3D.create(approach+Vector3(0,1.55,0),position+Vector3(0,0.4,0),1)
  check(harness.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"crate approach has unobstructed search ray "+str(i))
 var identities={}
 for guard in map_data.guards:
  check(not identities.has(guard.id) and guard.route.size()==3,"stable unique guard identity and three-point patrol "+guard.id)
  identities[guard.id]=true
  check(guard.position==guard.route[0] and _clear_capsule(guard.position),"guard spawn clear "+guard.id)
  for position in guard.route:
   var nearest=nav.closest_point(position)
   var path=NavigationServer3D.map_get_path(nav.map,start,nearest,true)
   check(_clear_capsule(position) and nearest.distance_to(position)<0.75 and not path.is_empty() and path[-1].distance_to(nearest)<0.2,"patrol waypoint reachable "+guard.id+" "+str(position))
  var sight=PhysicsRayQueryParameters3D.create(guard.position+Vector3(0,1.5,0),map_data.spawn+Vector3(0,1.55,0),1)
  check(not harness.get_world_3d().direct_space_state.intersect_ray(sight).is_empty(),"spawn is shielded from initial guard line of sight "+guard.id)
 check(map_data.guards[6].id=="guard_06" and map_data.guards[6].label=="仓区指挥官","officer objective uses fixed actor identity")
 for exit in map_data.exits:
  var end=nav.closest_point(exit.position)
  var path=NavigationServer3D.map_get_path(nav.map,start,end,true)
  check(_clear_capsule(exit.position) and end.distance_to(exit.position)<0.25 and not path.is_empty() and path[-1].distance_to(end)<0.2,"exit is reachable "+exit.id)
 var survey=map_data.survey
 var end=nav.closest_point(survey.position)
 var path=NavigationServer3D.map_get_path(nav.map,start,end,true)
 check(survey.id=="signal_station" and _clear_capsule(survey.position) and not path.is_empty() and path[-1].distance_to(end)<0.2,"communication objective is inside reachable building")
 # An upward ray sees the physical roof, while horizontal navigation stays free.
 var roof_ray=PhysicsRayQueryParameters3D.create(Vector3(-6,1.7,-7),Vector3(-6,8,-7),1|16)
 var roof_hit=harness.get_world_3d().direct_space_state.intersect_ray(roof_ray)
 check(not roof_hit.is_empty() and roof_hit.position.y>4.0,"warehouse roof constrains camera and jumps above standing clearance")
 nav.dispose(); harness.queue_free()
 await process_frame
 print("Phase4 map: %d/%d checks passed" % [checks-failures,checks])
 quit(1 if failures else 0)

func _clear_capsule(position: Vector3) -> bool:
 var shape=CapsuleShape3D.new(); shape.radius=0.48; shape.height=1.7
 var query=PhysicsShapeQueryParameters3D.new(); query.shape=shape; query.collision_mask=1
 query.transform=Transform3D(Basis.IDENTITY,position+Vector3(0,0.9,0))
 query.margin=0.001
 return harness.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
