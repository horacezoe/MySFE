extends RefCounted

var yaw := -2.35
var pitch := -0.10
var third_person := true
var pitch_limit := deg_to_rad(80.0)
var recoil_pitch := 0.0
var aiming := false

func add_look(delta_angle: Vector2) -> void:
 yaw = wrapf(yaw+delta_angle.x,-PI,PI)
 pitch = clampf(pitch+delta_angle.y,-pitch_limit,pitch_limit)

func kick() -> void:
 recoil_pitch = minf(recoil_pitch+0.012,0.09)

func direction() -> Vector3:
 var angle := clampf(pitch+recoil_pitch,-pitch_limit,pitch_limit)
 return Vector3(-sin(yaw)*cos(angle),sin(angle),-cos(yaw)*cos(angle))

func update_camera(camera: Camera3D, player: CharacterBody3D, eye_height: float, ignored: Array[RID], delta: float) -> void:
 recoil_pitch = move_toward(recoil_pitch,0.0,delta*0.10)
 camera.fov = move_toward(camera.fov,48.0 if aiming else 70.0,delta*150.0)
 var eye := player.global_position+Vector3(0,eye_height,0)
 var forward := Vector3(-sin(yaw),0,-cos(yaw))
 var side := Vector3(cos(yaw),0,-sin(yaw))
 if third_person:
  var desired := eye-forward*(2.2 if aiming else 3.6)+side*0.75+Vector3(0,0.45,0)
  var shape := SphereShape3D.new()
  shape.radius = 0.16
  var q := PhysicsShapeQueryParameters3D.new()
  q.shape = shape
  q.collision_mask = 16
  q.transform = Transform3D(Basis.IDENTITY,eye)
  q.motion = desired-eye
  q.exclude = ignored
  var fraction := player.get_world_3d().direct_space_state.cast_motion(q)
  camera.global_position = eye+(desired-eye)*maxf(0.0,fraction[0]-0.015)
 else: camera.global_position = eye
 camera.look_at(camera.global_position+direction(),Vector3.UP)
 player.get_node("Visual").visible = third_person and camera.global_position.distance_to(eye)>1.1
