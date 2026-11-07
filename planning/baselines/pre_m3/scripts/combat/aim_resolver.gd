extends RefCounted

const Layers = preload("res://scripts/collision_layers.gd")

func exclusions(actor: CollisionObject3D) -> Array[RID]:
 var result: Array[RID] = [actor.get_rid()]
 var hitboxes=actor.get_node_or_null("Hitboxes")
 if hitboxes:
  for child in hitboxes.get_children():
   if child is CollisionObject3D: result.append(child.get_rid())
 return result

func target_point(camera: Camera3D, player: CharacterBody3D) -> Vector3:
 var from := camera.global_position
 var direction := -camera.global_basis.z
 var q := PhysicsRayQueryParameters3D.create(from,from+direction*60.0,Layers.SHOT_MASK)
 q.collide_with_areas=true
 q.exclude = exclusions(player)
 var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
 return hit.position if not hit.is_empty() else from+direction*60.0

func solve(player: CharacterBody3D, mount: Vector3, muzzle_pos: Vector3, target: Vector3) -> Dictionary:
 var space := player.get_world_3d().direct_space_state
 var q := PhysicsRayQueryParameters3D.create(mount,muzzle_pos,Layers.WORLD)
 q.hit_from_inside=true
 q.exclude = exclusions(player)
 var bridge := space.intersect_ray(q)
 var shape := SphereShape3D.new()
 shape.radius = 0.035
 var sq := PhysicsShapeQueryParameters3D.new()
 sq.shape = shape
 sq.collision_mask = Layers.WORLD
 sq.transform = Transform3D(Basis.IDENTITY,muzzle_pos)
 sq.exclude = exclusions(player)
 var blocked := not bridge.is_empty() or not space.intersect_shape(sq,1).is_empty()
 var direction := (target-muzzle_pos).normalized()
 return {"blocked":blocked,"origin":muzzle_pos,"target":target,"direction":direction}

func cast_shot(player: CharacterBody3D, solution: Dictionary) -> Dictionary:
 if solution.blocked: return {}
 var q := PhysicsRayQueryParameters3D.create(solution.origin,solution.target+solution.direction*0.03,Layers.SHOT_MASK)
 q.collide_with_areas=true
 q.exclude = exclusions(player)
 return player.get_world_3d().direct_space_state.intersect_ray(q)

func visible(observer: CollisionObject3D, from: Vector3, target: CollisionObject3D, endpoint: Vector3) -> bool:
 var q := PhysicsRayQueryParameters3D.create(from,endpoint,Layers.SHOT_MASK)
 q.collide_with_areas=true
 q.exclude = exclusions(observer)
 var result := observer.get_world_3d().direct_space_state.intersect_ray(q)
 return not result.is_empty() and (result.collider == target or (result.collider.has_meta("actor") and result.collider.get_meta("actor")==target))
