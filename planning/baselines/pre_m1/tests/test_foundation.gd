extends SceneTree
## Integration checks against real Godot physics; no game.gd dependency.
## Run: godot --headless --path ember-3d --script res://tests/test_foundation.gd
const PlayerMotor = preload("res://scripts/player/player_motor.gd")
const CameraRig = preload("res://scripts/player/camera_rig.gd")
const ActionState = preload("res://scripts/player/action_state.gd")
const AimResolver = preload("res://scripts/combat/aim_resolver.gd")

class Probe extends Node3D:
 signal physics_tick(delta: float)
 var ticks := 0
 func _physics_process(delta: float) -> void:
  ticks += 1
  if ticks > 1800:
   printerr("FAIL: foundation test timed out")
   get_tree().quit(2)
   return
  physics_tick.emit(delta)

var _probe: Probe
var _checks := 0
var _failures := 0

func _initialize() -> void:
 _probe = Probe.new()
 root.add_child(_probe)
 call_deferred("_run")

func _check(ok: bool, label: String) -> void:
 _checks += 1
 if not ok:
  _failures += 1
  printerr("FAIL: " + label)

func _frame(move := Vector2.ZERO, sprint := false, jump := false, crouch := false, fire := false) -> Dictionary:
 return {"move": move, "sprint": sprint, "jump": jump, "crouch": crouch, "fire": fire}

func _box(position: Vector3, size: Vector3) -> StaticBody3D:
 var body := StaticBody3D.new()
 var collider := CollisionShape3D.new()
 var shape := BoxShape3D.new()
 shape.size = size
 collider.shape = shape
 body.add_child(collider)
 _probe.add_child(body)
 body.global_position = position
 return body

func _player(position: Vector3) -> CharacterBody3D:
 var body := CharacterBody3D.new()
 var collider := CollisionShape3D.new()
 collider.name = "BodyCollider"
 var capsule := CapsuleShape3D.new()
 capsule.radius = 0.48
 capsule.height = 1.7
 collider.shape = capsule
 collider.position.y = 0.9
 body.add_child(collider)
 var visual := Node3D.new()
 visual.name = "Visual"
 body.add_child(visual)
 for leg_name in ["LeftLeg", "RightLeg"]:
  var leg := Node3D.new()
  leg.name = leg_name
  visual.add_child(leg)
 _probe.add_child(body)
 body.global_position = position
 return body

func _weapon(parent: Node3D, position: Vector3, scale_factor := 1.0) -> Node3D:
 var weapon := Node3D.new()
 parent.add_child(weapon)
 weapon.position = position
 weapon.scale = Vector3.ONE * scale_factor
 var muzzle := Marker3D.new()
 muzzle.name = "Muzzle"
 muzzle.position = Vector3(0, 0.03, -0.92)
 weapon.add_child(muzzle)
 return weapon

func _sync(frames := 2) -> void:
 for i in range(frames):
  await _probe.physics_tick

func _move(body: CharacterBody3D, motor: RefCounted, frame: Dictionary, frames: int) -> float:
 var elapsed := 0.0
 for i in range(frames):
  var delta: float = await _probe.physics_tick
  motor.step(body, frame, 0.0, true, delta)
  elapsed += delta
 return elapsed

func _run() -> void:
 _box(Vector3(20, -0.5, 0), Vector3(160, 1, 160))
 await _sync()
 await _test_motor()
 _test_camera_angles()
 await _test_aim_at_distances()
 await _test_muzzle_obstruction()
 await _test_ai_visibility()
 await _test_camera_wall()
 _test_action_state()
 print("Foundation checks: %d passed / %d total" % [_checks - _failures, _checks])
 quit(1 if _failures > 0 else 0)

func _test_motor() -> void:
 var player := _player(Vector3(0, 0.1, 0))
 var motor = PlayerMotor.new()
 await _move(player, motor, _frame(), 30)
 _check(player.is_on_floor(), "player settles on a real physics floor")
 var start := player.global_position
 var elapsed: float = await _move(player, motor, _frame(Vector2(0, -1)), 20)
 _check(absf((start.z - player.global_position.z) / elapsed - 6.5) < 0.06, "walk moves at 6.5 m/s")
 start = player.global_position
 elapsed = await _move(player, motor, _frame(Vector2(0, -1), true), 20)
 _check(absf((start.z - player.global_position.z) / elapsed - 10.0) < 0.06, "sprint moves at 10 m/s")
 await _move(player, motor, _frame(Vector2.ZERO, false, false, true), 1)
 start = player.global_position
 elapsed = await _move(player, motor, _frame(Vector2(0, -1)), 20)
 _check(motor.crouching and absf((start.z - player.global_position.z) / elapsed - 3.3) < 0.06, "crouching moves at 3.3 m/s")
 var ceiling := _box(player.global_position + Vector3(0, 1.30, 0), Vector3(3, 0.3, 3))
 await _sync()
 await _move(player, motor, _frame(Vector2.ZERO, false, false, true), 1)
 _check(motor.crouching and motor.blocked_stand, "low ceiling prevents standing")
 ceiling.free()
 await _sync()
 await _move(player, motor, _frame(Vector2.ZERO, false, false, true), 1)
 _check(not motor.crouching, "removing low ceiling allows standing on the floor")
 # A fresh actor isolates jump behavior from any failed crouch assertion.
 player.free()
 player = _player(Vector3(0, 0.1, 0))
 motor = PlayerMotor.new()
 await _move(player, motor, _frame(), 30)
 var floor_y := player.global_position.y
 await _move(player, motor, _frame(Vector2.ZERO, false, true), 1)
 _check(player.velocity.y > 7.0 and player.global_position.y > floor_y, "jump starts upward from the floor")
 var upward_speed := player.velocity.y
 await _move(player, motor, _frame(Vector2.ZERO, false, true), 1)
 _check(player.velocity.y < upward_speed, "second airborne jump edge cannot reset vertical speed")
 var highest := player.global_position.y
 var landed := false
 for i in range(100):
  await _move(player, motor, _frame(), 1)
  highest = maxf(highest, player.global_position.y)
  if player.is_on_floor():
   landed = true
   break
 _check(highest - floor_y > 1.2, "jump traverses a measurable upward arc")
 _check(landed and absf(player.global_position.y - floor_y) < 0.03, "single jump lands back on the floor")
 player.free()
 await _sync()

func _test_camera_angles() -> void:
 var rig = CameraRig.new()
 rig.yaw = 0.0
 rig.pitch = 0.0
 rig.add_look(Vector2(0, 10))
 _check(is_equal_approx(rig.pitch, deg_to_rad(80.0)) and rig.direction().y > 0.98, "camera clamps upward look to +80 degrees")
 rig.add_look(Vector2(0, -20))
 _check(is_equal_approx(rig.pitch, deg_to_rad(-80.0)) and rig.direction().y < -0.98, "camera clamps downward look to -80 degrees")
 var other = CameraRig.new()
 rig.yaw = 0.0
 rig.pitch = 0.0
 other.yaw = 0.0
 other.pitch = 0.0
 for i in range(60): rig.add_look(Vector2(0.002, 0.001))
 for i in range(30): other.add_look(Vector2(0.004, 0.002))
 _check(rig.direction().is_equal_approx(other.direction()), "equal cumulative look is independent of frame count")
 _check(rig.yaw > 0.0 and rig.pitch > 0.0, "look delta sign is applied directly")

func _test_aim_at_distances() -> void:
 var player := _player(Vector3(10, 0, 0))
 var camera := Camera3D.new()
 _probe.add_child(camera)
 var first_weapon := _weapon(camera, Vector3(0.29, -0.23, -0.55))
 var third_weapon := _weapon(player.get_node("Visual"), Vector3(0.38, 1.2, -0.2), 0.8)
 var rig = CameraRig.new()
 var resolver = AimResolver.new()
 rig.yaw = 0.0
 rig.pitch = 0.0
 await _sync()
 for third_person in [false, true]:
  rig.third_person = third_person
  for distance in [5.0, 15.0, 40.0]:
   var target_center := Vector3(10, 1.55, -distance)
   var target := _box(target_center, Vector3(0.6, 0.6, 0.12))
   await _sync()
   rig.update_camera(camera, player, 1.55, [player.get_rid()], 1.0 / 60.0)
   camera.look_at(target_center, Vector3.UP)
   var point: Vector3 = resolver.target_point(camera, player)
   var weapon: Node3D = third_weapon if third_person else first_weapon
   weapon.look_at(point, Vector3.UP)
   var origin: Vector3 = weapon.get_node("Muzzle").global_position
   var solution: Dictionary = resolver.solve(player, player.global_position + Vector3(0, 1.4, 0), origin, point)
   var hit: Dictionary = resolver.cast_shot(player, solution)
   var mode := "third person" if third_person else "first person"
   _check(not solution.blocked and not hit.is_empty() and hit.collider == target, "%s real muzzle hits %dm target" % [mode, int(distance)])
   _check((point - origin).normalized().is_equal_approx(solution.direction), "%s %dm shot uses muzzle-to-reticle direction" % [mode, int(distance)])
   target.free()
   await _sync()
 player.free()
 camera.free()
 await _sync()

func _test_muzzle_obstruction() -> void:
 var player := _player(Vector3(20, 0, 0))
 var wall := _box(Vector3(20, 1.4, -0.7), Vector3(2, 2, 0.12))
 var resolver = AimResolver.new()
 await _sync()
 var mount := Vector3(20, 1.4, 0)
 var target := Vector3(20, 1.4, -10)
 var overlap: Dictionary = resolver.solve(player, mount, Vector3(20, 1.4, -0.7), target)
 var through: Dictionary = resolver.solve(player, mount, Vector3(20, 1.4, -1.0), target)
 _check(overlap.blocked, "muzzle overlapping 12cm wall is blocked")
 _check(through.blocked, "muzzle beyond 12cm wall is blocked by mount-to-muzzle segment")
 _check(resolver.cast_shot(player, through).is_empty(), "blocked muzzle cannot emit a shot")
 player.free()
 wall.free()
 await _sync()

func _test_ai_visibility() -> void:
 var observer := _player(Vector3(30, 0, 0))
 var target := _box(Vector3(30, 1.4, -5), Vector3(0.5, 0.8, 0.5))
 var wall := _box(Vector3(30, 1.4, -4.4), Vector3(2, 2, 0.12))
 var resolver = AimResolver.new()
 await _sync()
 var origin := Vector3(30, 1.4, 0)
 var endpoint := target.global_position
 var query := PhysicsRayQueryParameters3D.create(origin, endpoint)
 query.exclude = [observer.get_rid()]
 var first_hit := observer.get_world_3d().direct_space_state.intersect_ray(query)
 _check(not first_hit.is_empty() and first_hit.collider == wall and first_hit.position.distance_to(endpoint) < 1.2, "AI ray first hits a thin wall within 1.2m of target")
 _check(not resolver.visible(observer, origin, target, endpoint), "AI cannot see through a wall close to target")
 wall.free()
 await _sync()
 _check(resolver.visible(observer, origin, target, endpoint), "AI sees target after wall is removed")
 observer.free()
 target.free()
 await _sync()

func _test_camera_wall() -> void:
 var player := _player(Vector3(40, 0, 0))
 var camera := Camera3D.new()
 _probe.add_child(camera)
 var wall := _box(Vector3(40, 1.6, 1.2), Vector3(4, 3.2, 0.12))
 var rig = CameraRig.new()
 rig.yaw = 0.0
 rig.pitch = 0.0
 rig.third_person = true
 await _sync()
 rig.update_camera(camera, player, 1.55, [player.get_rid()], 1.0 / 60.0)
 _check(camera.global_position.z > 0.1 and camera.global_position.z <= 1.14 - 0.16 + 0.01, "third-person sphere cast keeps camera in front of wall")
 var query := PhysicsShapeQueryParameters3D.new()
 var sphere := SphereShape3D.new()
 sphere.radius = 0.16
 query.shape = sphere
 query.transform = Transform3D(Basis.IDENTITY, camera.global_position)
 query.exclude = [player.get_rid()]
 _check(player.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "camera collision sphere does not overlap wall")
 rig.third_person = false
 rig.update_camera(camera, player, 1.55, [player.get_rid()], 1.0 / 60.0)
 _check(camera.global_position.is_equal_approx(player.global_position + Vector3(0, 1.55, 0)), "first-person camera uses eye position")
 player.free()
 camera.free()
 wall.free()
 await _sync()

func _test_action_state() -> void:
 var actions = ActionState.new()
 var sprint_frame := _frame(Vector2(0, -1), true)
 _check(actions.step(sprint_frame, false, 0.016) and not actions.can_fire(false), "sprinting lowers weapon and prevents fire")
 actions.step(_frame(), false, 0.016)
 _check(is_equal_approx(actions.raise_time, 0.18) and not actions.can_fire(false), "ending sprint starts 0.18 second weapon raise")
 actions.step(_frame(), false, 0.17)
 _check(not actions.can_fire(false), "weapon remains blocked before raise completes")
 actions.step(_frame(), false, 0.011)
 _check(actions.can_fire(false), "weapon fires after raise completes")
 _check(not actions.can_fire(true), "reloading prevents fire")
 _check(not actions.step(sprint_frame, true, 0.016), "reloading prevents sprint")
 _check(not actions.step(sprint_frame, false, 0.016, true), "crouching prevents sprint")
 actions.cancel_all()
 _check(actions.can_fire(false) and actions.raise_time == 0.0, "cancel clears sprint and weapon raise state")
