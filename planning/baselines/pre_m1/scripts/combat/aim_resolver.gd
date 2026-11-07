extends RefCounted

func target_point(camera: Camera3D, player: CharacterBody3D) -> Vector3:
 var from := camera.global_position
 var direction := -camera.global_basis.z
 var q := PhysicsRayQueryParameters3D.create(from,from+direction*50.0)
 q.exclude = [player.get_rid()]
 var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
 return hit.position if not hit.is_empty() else from+direction*50.0

func solve(player: CharacterBody3D, mount: Vector3, muzzle_pos: Vector3, target: Vector3) -> Dictionary:
 var space := player.get_world_3d().direct_space_state
 var q := PhysicsRayQueryParameters3D.create(mount,muzzle_pos)
 q.exclude = [player.get_rid()]
 var bridge := space.intersect_ray(q)
 var shape := SphereShape3D.new()
 shape.radius = 0.035
 var sq := PhysicsShapeQueryParameters3D.new()
 sq.shape = shape
 sq.transform = Transform3D(Basis.IDENTITY,muzzle_pos)
 sq.exclude = [player.get_rid()]
 var blocked := not bridge.is_empty() or not space.intersect_shape(sq,1).is_empty()
 var direction := (target-muzzle_pos).normalized()
 return {"blocked":blocked,"origin":muzzle_pos,"target":target,"direction":direction}

func cast_shot(player: CharacterBody3D, solution: Dictionary) -> Dictionary:
 if solution.blocked: return {}
 var q := PhysicsRayQueryParameters3D.create(solution.origin,solution.target+solution.direction*0.03)
 q.exclude = [player.get_rid()]
 return player.get_world_3d().direct_space_state.intersect_ray(q)

func visible(observer: CollisionObject3D, from: Vector3, target: CollisionObject3D, endpoint: Vector3) -> bool:
 var q := PhysicsRayQueryParameters3D.create(from,endpoint)
 q.exclude = [observer.get_rid()]
 var result := observer.get_world_3d().direct_space_state.intersect_ray(q)
 return not result.is_empty() and result.collider == target
