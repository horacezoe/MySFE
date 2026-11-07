extends RefCounted

var crouching := false
var eye_height := 1.55
var move_phase := 0.0
var sprinting := false
var blocked_stand := false

func can_stand(body: CharacterBody3D) -> bool:
 # Sweep the upper hemisphere through the extra standing volume. Checking a
 # complete standing capsule would mistake the existing floor contact for a roof.
 var shape := SphereShape3D.new()
 shape.radius = 0.48
 var query := PhysicsShapeQueryParameters3D.new()
 query.shape = shape
 query.transform = Transform3D(Basis.IDENTITY, body.global_position + Vector3(0,0.62,0))
 query.motion = Vector3(0,0.65,0)
 query.exclude = [body.get_rid()]
 query.margin = 0.001
 var space := body.get_world_3d().direct_space_state
 if not space.intersect_shape(query,1).is_empty(): return false
 return space.cast_motion(query)[0]>=1.0

func step(body: CharacterBody3D, frame: Dictionary, yaw: float, sprint_allowed: bool, delta: float) -> void:
 blocked_stand = false
 if frame.crouch:
  if not crouching: crouching = true
  elif can_stand(body): crouching = false
  else: blocked_stand = true
 if frame.jump and body.is_on_floor():
  if not crouching or can_stand(body):
   crouching = false
   body.velocity.y = 7.4
  else: blocked_stand = true
 sprinting = frame.sprint and sprint_allowed and not crouching and frame.move.length() > 0.1
 var speed := 3.3 if crouching else 10.0 if sprinting else 6.5
 var forward := Vector3(-sin(yaw),0,-cos(yaw))
 var side := Vector3(cos(yaw),0,-sin(yaw))
 var planar: Vector3 = (side*frame.move.x-forward*frame.move.y)*speed
 body.velocity.x = planar.x
 body.velocity.z = planar.z
 if not body.is_on_floor(): body.velocity.y -= 20.0*delta
 elif body.velocity.y < 0: body.velocity.y = -0.1
 var collider: CollisionShape3D = body.get_node("BodyCollider")
 collider.shape.height = 1.05 if crouching else 1.7
 collider.position.y = 0.575 if crouching else 0.9
 body.move_and_slide()
 eye_height = move_toward(eye_height,0.96 if crouching else 1.55,delta*3.0)
 move_phase += delta*(12.0 if sprinting else 8.0)*frame.move.length()
 var visual: Node3D = body.get_node("Visual")
 visual.scale.y = move_toward(visual.scale.y,0.62 if crouching else 1.0,delta*3.0)
 var stride: float = sin(move_phase)*0.4*frame.move.length() if body.is_on_floor() else 0.12
 visual.get_node("LeftLeg").rotation.x = stride
 visual.get_node("RightLeg").rotation.x = -stride
