extends RefCounted
## Original, single-level depot. Geometry is separate from saved raid identities.
## Raised roofs have physical/camera collision but never obstruct floor navigation.
const MAP_ID="depot_v1"
const WALL=Color("737c75")
const SUPPLY=Color("637f74")
const SIGNAL=Color("797c84")
const AMBER=Color("b79962")

func definition() -> Dictionary:
 var crates: Array[Vector3]=[
  Vector3(-22,0,-22),Vector3(-24,0,-8),Vector3(-6,0,-7),
  Vector3(3,0,-7),Vector3(-6,0,5),Vector3(-24,0,8),
  Vector3(22,0,0),Vector3(3,0,5),Vector3(18,0,-9),
  Vector3(25,0,8),Vector3(-21,0,18),Vector3(-7,0,20),
  Vector3(4,0,23),Vector3(18,0,20),Vector3(25,0,18),
 ]
 var routes: Array=[
  [Vector3(-17,0,-7),Vector3(-17,0,1),Vector3(-17,0,9)],
  [Vector3(-7,0,-6),Vector3(-4,0,-6),Vector3(-4,0,4)],
  [Vector3(3,0,4),Vector3(3,0,-5),Vector3(1,0,-5)],
  [Vector3(10,0,-17),Vector3(20,0,-17),Vector3(25,0,-17)],
  [Vector3(-7,0,16),Vector3(-15,0,16),Vector3(-15,0,24)],
  [Vector3(10,0,9),Vector3(10,0,-3),Vector3(10,0,-12)],
  [Vector3(23,0,0),Vector3(20,0,0),Vector3(22,0,8)],
  [Vector3(19,0,16),Vector3(26,0,16),Vector3(26,0,23)],
  [Vector3(-23,0,13),Vector3(-27,0,17),Vector3(-27,0,23)],
 ]
 var guards: Array=[]
 for i in range(routes.size()):
  guards.append({"id":"guard_%02d" % i,"position":routes[i][0],"route":routes[i],"label":"仓区指挥官" if i==6 else "转运站守卫"})
 var walls: Array[Rect2]=[]
 for part in _solids():
  var size: Vector3=part.size; var position: Vector3=part.position
  walls.append(Rect2(position.x-size.x*0.5,position.z-size.z*0.5,size.x,size.z))
 return {"id":MAP_ID,"name":"灰湾转运站","spawn":Vector3(-26,0,-26),"spawn_yaw":-2.35,
  "bounds":Rect2(-30.5,-30.5,61,61),"crates":crates,"guards":guards,"walls":walls,
  "zones":[
   {"id":"supply","title":"西侧补给区","rect":Rect2(-30.5,-30.5,17.5,43.5),"risk":"低"},
   {"id":"warehouse","title":"中央仓库","rect":Rect2(-13,-14,25,27),"risk":"中"},
   {"id":"signal","title":"通信站","rect":Rect2(12,-21,18.5,34),"risk":"高"},
   {"id":"freight","title":"南侧货运场","rect":Rect2(-30.5,13,61,17.5),"risk":"中 / 东侧高"},
  ],
  "survey":{"id":"signal_station","position":Vector3(22,0,0),"radius":2.8},
  "exits":[
   {"id":"south_gate","title":"货运公路","position":Vector3(25,0,25),"radius":3.6,"wait":5.0,"required_item":""},
   {"id":"service_gate","title":"维修通道","position":Vector3(-25,0,24),"radius":3.2,"wait":3.0,"required_item":"depot_pass"},
  ]}

func _part(position: Vector3,size: Vector3,color: Color,kind := "wall") -> Dictionary:
 return {"position":position,"size":size,"color":color,"kind":kind}

func _solids() -> Array:
 var result: Array=[]
 # Spawn depot shields all initial guard sightlines. Its east doorway is 4 m.
 for wall in [Vector4(-24.5,-19,11,0.5),Vector4(-19,-26.5,0.5,7)]:
  result.append(_part(Vector3(wall.x,1.8,wall.y),Vector3(wall.z,3.6,wall.w),SUPPLY))
 # Central warehouse: north/south and side loading doors, each at least 4 m.
 for wall in [
  Vector4(-7,-11,8,0.5),Vector4(4,-11,6,0.5),
  Vector4(-7,9,8,0.5),Vector4(4,9,6,0.5),
  Vector4(-11,-7,0.5,8),Vector4(-11,5,0.5,8),
  Vector4(7,-7,0.5,8),Vector4(7,5,0.5,8),
  Vector4(-1,-6,0.45,2),Vector4(-1,4,0.45,2),
 ]:
  result.append(_part(Vector3(wall.x,2,wall.y),Vector3(wall.z,4,wall.w),WALL))
 # Communication building: three entrances and two interior rooms.
 for wall in [
  Vector4(14,-8.5,0.5,9),Vector4(14,8,0.5,8),
  Vector4(17,-13,6,0.5),Vector4(26.5,-13,5,0.5),
  Vector4(29,-0.5,0.5,25),
  Vector4(16.5,12,5,0.5),Vector4(26.5,12,5,0.5),
  Vector4(23.5,-4,11,0.45),Vector4(17,4,6,0.45),
 ]:
  result.append(_part(Vector3(wall.x,2,wall.y),Vector3(wall.z,4,wall.w),SIGNAL))
 # Containers form alternative cover routes across the freight yard.
 result.append(_part(Vector3(-8,1.4,25),Vector3(9,2.8,3),Color("68776c"),"container"))
 result.append(_part(Vector3(7,1.4,17),Vector3(9,2.8,3),Color("967653"),"container"))
 result.append(_part(Vector3(15,1.4,25),Vector3(3,2.8,8),Color("627881"),"container"))
 result.append(_part(Vector3(-27,1.4,1),Vector3(4,2.8,6),Color("697b74"),"container"))
 # Supplies, shelves and low concrete cover stay away from door approaches.
 result.append(_part(Vector3(-27,0.6,-9),Vector3(2,1.2,2.5),Color("9a896d"),"cargo"))
 result.append(_part(Vector3(-7.5,0.9,2),Vector3(2,1.8,1),Color("7e806c"),"rack"))
 result.append(_part(Vector3(4.5,0.9,1.5),Vector3(2,1.8,1),Color("7e806c"),"rack"))
 result.append(_part(Vector3(16.5,1.1,0),Vector3(1,2.2,3),Color("555e5d"),"rack"))
 result.append(_part(Vector3(27,1.1,-8),Vector3(1,2.2,5),Color("555e5d"),"rack"))
 result.append(_part(Vector3(22,0.72,1.6),Vector3(2.8,1.35,0.6),Color("4a5a59"),"desk"))
 result.append(_part(Vector3(10,0.65,-23),Vector3(5,1.3,1),Color("868a78"),"cover"))
 result.append(_part(Vector3(-18,0.65,17),Vector3(1,1.3,5),Color("868a78"),"cover"))
 result.append(_part(Vector3(22,0.65,21),Vector3(4,1.3,1),Color("868a78"),"cover"))
 return result

func build(game) -> void:
 # Roads and painted loading bays are flat visual surfaces, not collision.
 _slab(game,Vector3(-15,0.025,-5),Vector3(5,0.035,48),Color("4e5856"))
 _slab(game,Vector3(5,0.027,-17),Vector3(48,0.035,5),Color("505a58"))
 _slab(game,Vector3(2,0.029,15),Vector3(55,0.035,5),Color("505a58"))
 _slab(game,Vector3(25,0.031,20),Vector3(6,0.035,19),Color("505a58"))
 _slab(game,Vector3(-25,0.033,22),Vector3(6,0.035,14),Color("505a58"))
 for z in range(-26,15,5): _slab(game,Vector3(-15,0.06,z),Vector3(0.12,0.025,2.1),Color("c9c0a0"))
 for x in range(-10,28,5): _slab(game,Vector3(x,0.063,-17),Vector3(2.1,0.025,0.12),Color("c9c0a0"))
 # Floor tones distinguish the quiet supplies, warehouse and restricted building.
 _slab(game,Vector3(-25,0.04,-25),Vector3(12,0.04,12),Color("666f65"))
 _slab(game,Vector3(-2,0.04,-1),Vector3(18,0.04,20),Color("747770"))
 _slab(game,Vector3(21.5,0.04,-0.5),Vector3(15,0.04,25),Color("686f73"))
 for part in _solids():
  var node=game.box(game.world,part.size,part.position,part.color,true)
  node.name="Depot_"+part.kind
  if part.kind=="wall":
   _slab(game,part.position+Vector3(0,part.size.y*0.5-0.08,0),Vector3(part.size.x+0.04,0.16,part.size.z+0.04),part.color.darkened(0.25))
  elif part.kind=="container": _container_detail(game,part)
  elif part.kind=="rack":
   for y in [0.18,0.85,1.52]: _slab(game,Vector3(part.position.x,y,part.position.z),Vector3(part.size.x+0.06,0.07,part.size.z+0.06),Color("3f4846"))
 # High roofs allow first person and shoulder cameras, while roof colliders are
 # explicitly excluded from floor occupancy used by NavigationWorld.
 _roof(game,Vector3(-25,3.85,-25),Vector3(12.5,0.2,12.5),Color("596b62"))
 _roof(game,Vector3(-7,4.25,-1),Vector3(8.6,0.2,20.5),Color("596761"))
 _roof(game,Vector3(4,4.25,-1),Vector3(6.6,0.2,20.5),Color("596761"))
 # The two warehouse roofs leave a skylight strip above the central aisle.
 _roof(game,Vector3(21.5,4.3,-8.5),Vector3(15.5,0.2,9.5),Color("5f6870"))
 _roof(game,Vector3(21.5,4.3,8),Vector3(15.5,0.2,8.5),Color("5f6870"))
 # Communication desk / antenna are visible landmarks without new occluders.
 _slab(game,Vector3(22,1.65,1.55),Vector3(1.25,0.68,0.10),Color("86b6aa"))
 _slab(game,Vector3(27,5.4,-9),Vector3(0.12,2.2,0.12),Color("cad0bd"))
 _slab(game,Vector3(27,6.2,-9),Vector3(2.0,0.1,0.1),Color("cad0bd"))
 for x in [18.0,21.0,24.0]:
  _slab(game,Vector3(x,0.07,-14.2),Vector3(0.6,0.03,1.1),AMBER)
 _sign(game,"补给站  A",Vector3(-24,3.1,-18.65),Color("d2e0c1"))
 _sign(game,"中央仓库  B",Vector3(-1,4.0,-11.5),Color("ddd5b1"))
 _sign(game,"通信站  C\n限制区域",Vector3(13.6,3.8,0),Color("e9bd83"))
 _sign(game,"货运场  D",Vector3(5,3.7,17),Color("d4d3bd"))
 _sign(game,"维修通道\n需要通行证",Vector3(-25,3.1,27.5),Color("b9d1d1"))
 _sign(game,"货运公路\n常规撤离",Vector3(25,3.1,28.7),Color("bbdaa0"))
 _sign(game,"信号记录终端",Vector3(22,2.5,1.6),Color("b0e4d0"))
 # Gate silhouettes frame the two destinations without blocking their centers.
 for center in [Vector3(-25,0,27.5),Vector3(25,0,28.7)]:
  for side in [-4.0,4.0]: _slab(game,center+Vector3(side,1.9,0),Vector3(0.24,3.8,0.24),Color("4d5f56"))
  _slab(game,center+Vector3(0,3.8,0),Vector3(8.4,0.25,0.3),Color("4d5f56"))

func _slab(game,position: Vector3,size: Vector3,color: Color) -> Node3D:
 return game.box(game.world,size,position,color,false)

func _roof(game,position: Vector3,size: Vector3,color: Color):
 var mesh=_slab(game,position,size,color)
 mesh.name="RaisedRoof"
 var body=StaticBody3D.new(); body.collision_layer=1|16; body.collision_mask=2
 mesh.add_child(body)
 var collider=CollisionShape3D.new(); var shape=BoxShape3D.new(); shape.size=size
 collider.shape=shape; body.add_child(collider)

func _container_detail(game,part: Dictionary):
 var along_x=part.size.x>part.size.z
 var count=int((part.size.x if along_x else part.size.z)/1.2)
 for i in range(count):
  var offset=(i-float(count-1)*0.5)*1.2
  var p=part.position+Vector3(offset if along_x else -part.size.x*0.5-0.02,0,-part.size.z*0.5-0.02 if along_x else offset)
  _slab(game,p,Vector3(0.055,2.5,0.055),part.color.darkened(0.22))
 _slab(game,part.position+Vector3(0,1.42,0),Vector3(part.size.x+0.08,0.10,part.size.z+0.08),part.color.darkened(0.2))

func _sign(game,text: String,position: Vector3,color: Color):
 var label=Label3D.new(); label.text=text; label.position=position
 label.font_size=44; label.pixel_size=0.009; label.modulate=color
 label.outline_size=7; label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
 game.world.add_child(label)
