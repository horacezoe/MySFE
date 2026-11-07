extends RefCounted
## Static floor navigation for the prototype's rectangular, single-level map.
## Geometry is authored as adjacent walkable polygons; obstacles are expanded
## before rasterization to leave room for the actors' movement capsules.

var region: NavigationRegion3D
var map: RID
var cell_size := 1.0
var clearance := 0.60

func build(world: Node3D, bounds: Rect2, obstacles: Array[Rect2]) -> RID:
 dispose()
 var columns := maxi(1,int(floor(bounds.size.x/cell_size)))
 var rows := maxi(1,int(floor(bounds.size.y/cell_size)))
 var mesh := NavigationMesh.new()
 mesh.agent_radius=0.48
 mesh.agent_height=1.8
 mesh.cell_size=0.25
 mesh.cell_height=0.25
 var vertices := PackedVector3Array()
 for z in range(rows+1):
  for x in range(columns+1):
   vertices.append(Vector3(bounds.position.x+x*cell_size,0,bounds.position.y+z*cell_size))
 mesh.set_vertices(vertices)
 for z in range(rows):
  for x in range(columns):
   var cell := Rect2(bounds.position+Vector2(x,z)*cell_size,Vector2.ONE*cell_size)
   var blocked := false
   for obstacle in obstacles:
    if cell.intersects(obstacle.grow(clearance)):
     blocked=true
     break
   if blocked: continue
   var base := z*(columns+1)+x
   mesh.add_polygon(PackedInt32Array([base,base+columns+1,base+columns+2,base+1]))
 region=NavigationRegion3D.new()
 region.name="StaticNavigation"
 region.navigation_mesh=mesh
 region.navigation_layers=1
 world.add_child(region)
 map=NavigationServer3D.map_create()
 NavigationServer3D.map_set_cell_size(map,0.25)
 NavigationServer3D.map_set_cell_height(map,0.25)
 NavigationServer3D.map_set_active(map,true)
 region.set_navigation_map(map)
 return map

func ready() -> bool:
 # A freshly activated empty map can already have iteration 1 while the region
 # is still synchronizing. Confirm that its polygons are queryable as well.
 return map.is_valid() and is_instance_valid(region) and NavigationServer3D.map_get_iteration_id(map)>0 and NavigationServer3D.region_get_iteration_id(region.get_rid())>0 and NavigationServer3D.map_get_closest_point_owner(map,Vector3.ZERO)==region.get_rid()

func closest_point(point: Vector3) -> Vector3:
 return NavigationServer3D.map_get_closest_point(map,point) if ready() else point

func dispose() -> void:
 if is_instance_valid(region): region.free()
 region=null
 if map.is_valid(): NavigationServer3D.free_rid(map)
 map=RID()
