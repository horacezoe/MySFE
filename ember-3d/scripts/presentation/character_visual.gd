extends Node3D
## Original, offline procedural tactical operator. Meshes are authored here,
## merged by material, and actually deformed by Skeleton3D/Skin.
## Presentation only: the owner supplies state and explicitly advances time.

const Builder = preload("res://scripts/presentation/character_mesh_builder.gd")
static var _fabric_cache: Dictionary = {}
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var skin_mesh: MeshInstance3D
var stride_phase := 0.0
var _bones: Dictionary = {}
var _rests: Dictionary = {}
var _weapon: Node3D
var _weapon_living_transform := Transform3D.IDENTITY
var _weapon_death_captured := false
var _clock := 0.0
var _crouch := 0.0
var _landing := 0.0
var _was_grounded := true
var _dead := false
var _death := 0.0
var _triangles := 0
var _base_color := Color("6b7161")

func setup(color: Color):
	if is_instance_valid(skeleton): return
	_base_color = color
	set_process(false)
	set_physics_process(false)
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	_bone("Pelvis", "", Vector3(0, 0.91, 0))
	_bone("Spine", "Pelvis", Vector3(0, 1.06, 0))
	_bone("Chest", "Spine", Vector3(0, 1.29, 0))
	_bone("Neck", "Chest", Vector3(0, 1.50, 0))
	_bone("Head", "Neck", Vector3(0, 1.63, -0.008))
	for side in ["Left", "Right"]:
		var sign_value := -1.0 if side == "Left" else 1.0
		_bone(side + "Clavicle", "Chest", Vector3(sign_value * 0.13, 1.40, 0))
		_bone(side + "UpperArm", side + "Clavicle", Vector3(sign_value * 0.235, 1.39, 0))
		_bone(side + "Forearm", side + "UpperArm", Vector3(sign_value * 0.26, 1.09, 0))
		_bone(side + "Hand", side + "Forearm", Vector3(sign_value * 0.275, 0.82, 0))
		_bone(side + "Thigh", "Pelvis", Vector3(sign_value * 0.115, 0.88, 0))
		_bone(side + "Shin", side + "Thigh", Vector3(sign_value * 0.115, 0.48, 0))
		_bone(side + "Foot", side + "Shin", Vector3(sign_value * 0.115, 0.10, 0))
	skeleton.reset_bone_poses()
	_build_geometry()
	_build_animation_graph()
	reset_pose()
	step(0.001, {})

func _bone(bone_name: String, parent_name: String, global_rest: Vector3):
	var id := skeleton.get_bone_count()
	skeleton.add_bone(bone_name)
	_bones[bone_name] = id
	_rests[bone_name] = global_rest
	var origin := global_rest
	if not parent_name.is_empty():
		skeleton.set_bone_parent(id, _bones[parent_name])
		origin -= _rests[parent_name]
	skeleton.set_bone_rest(id, Transform3D(Basis.IDENTITY, origin))

func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result

func _fabric_texture(camouflage: bool) -> ImageTexture:
	# Original tileable 128px fabric: restrained field camo plus woven threads.
	# Static texture data costs 64 KiB and requires no downloaded assets/shader.
	if _fabric_cache.has(camouflage): return _fabric_cache[camouflage]
	var image := Image.create(128, 128, true, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var u := TAU * float(x) / 128.0
			var v := TAU * float(y) / 128.0
			var pattern := sin(u * 3.0 + sin(v * 2.0) * 1.6) + cos(v * 3.0 + sin(u * 4.0)) * 0.7
			var grain := float((x * 73 + y * 151 + x * y * 3) % 19) / 19.0
			var weave := 0.025 if (x + y) % 3 == 0 else -0.015
			var tint := Color(0.92, 0.94, 0.88)
			if camouflage:
				if pattern > 0.8: tint = Color(1.08, 1.04, 0.91)
				elif pattern < -0.7: tint = Color(0.69, 0.73, 0.66)
			tint *= 0.95 + grain * 0.075 + weave
			tint.a = 1.0
			image.set_pixel(x, y, tint)
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_fabric_cache[camouflage] = texture
	return texture

func _build_geometry():
	var material_list: Array[StandardMaterial3D] = [
		_material(_base_color.darkened(0.10), 0.96),
		_material(_base_color.darkened(0.36), 0.87),
		_material(Color("252b29"), 0.88),
		_material(Color("797e70"), 0.70, 0.12),
		_material(Color("243a40"), 0.16, 0.65),
		_material(Color("ae8d70"), 0.92),
		_material(Color("a8a48d"), 0.90)
	]
	var builder = Builder.new(material_list.size())
	material_list[0].albedo_texture = _fabric_texture(true)
	material_list[1].albedo_texture = _fabric_texture(false)
	material_list[0].texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material_list[1].texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var pelvis: int = _bones.Pelvis
	var chest: int = _bones.Chest
	var head: int = _bones.Head
	# Anatomical clothing volumes. Adult head/body ratio is about 1:7.4.
	builder.ellipsoid(0, Vector3(0, 0.94, 0), Vector3(0.195, 0.16, 0.13), pelvis)
	builder.limb(0, Vector3(0, 1.37, 0), Vector3(0, 1.015, 0), Vector2(0.213, 0.128), chest, _bones.Spine)
	builder.rounded_box(1, Vector3(0, 1.22, -0.125), Vector3(0.37, 0.34, 0.075), 0.027, chest)
	builder.rounded_box(1, Vector3(0, 1.23, 0.127), Vector3(0.34, 0.35, 0.065), 0.024, chest)
	# Shoulder webbing, plate carrier, cummerbund and stitched MOLLE rows.
	for sign_value in [-1.0, 1.0]:
		builder.rounded_box(1, Vector3(sign_value * 0.145, 1.40, -0.035), Vector3(0.065, 0.055, 0.28), 0.012, chest)
		builder.rounded_box(1, Vector3(sign_value * 0.19, 1.15, 0), Vector3(0.045, 0.14, 0.25), 0.015, chest)
	for y in [1.13, 1.20, 1.27]:
		builder.rounded_box(6, Vector3(0, y, -0.171), Vector3(0.32, 0.009, 0.009), 0.002, chest)
	for x in [-0.12, -0.04, 0.04, 0.12]:
		builder.rounded_box(1, Vector3(x, 1.13, -0.185), Vector3(0.065, 0.145, 0.055), 0.009, chest)
		builder.rounded_box(6, Vector3(x, 1.196, -0.217), Vector3(0.043, 0.015, 0.008), 0.002, chest)
	builder.rounded_box(2, Vector3(0.12, 1.36, -0.164), Vector3(0.055, 0.068, 0.026), 0.006, chest)
	builder.rounded_box(3, Vector3(0.12, 1.40, -0.164), Vector3(0.008, 0.10, 0.008), 0.002, chest)
	builder.rounded_box(6, Vector3(-0.08, 1.33, -0.169), Vector3(0.10, 0.037, 0.012), 0.005, chest)
	# Close fitting field pack: curved shell, compression straps and top handle.
	builder.rounded_box(1, Vector3(0, 1.23, 0.215), Vector3(0.285, 0.38, 0.15), 0.045, chest)
	builder.rounded_box(0, Vector3(0, 1.16, 0.30), Vector3(0.23, 0.21, 0.06), 0.025, chest)
	for x in [-0.09, 0.09]:
		builder.rounded_box(2, Vector3(x, 1.23, 0.315), Vector3(0.018, 0.33, 0.014), 0.003, chest)
	builder.rounded_box(2, Vector3(0, 1.44, 0.22), Vector3(0.11, 0.022, 0.035), 0.008, chest)
	# Neck, face, helmet shell, goggle frame and opaque ballistic lenses.
	builder.limb(5, Vector3(0, 1.57, 0), Vector3(0, 1.45, 0), Vector2(0.061, 0.058), _bones.Neck)
	builder.limb(1, Vector3(0, 1.49, 0), Vector3(0, 1.385, 0), Vector2(0.080, 0.074), _bones.Neck)
	builder.rounded_box(0, Vector3(0, 1.372, 0.006), Vector3(0.34, 0.064, 0.22), 0.022, chest)
	builder.ellipsoid(5, Vector3(0, 1.635, -0.008), Vector3(0.105, 0.145, 0.101), head, Basis.IDENTITY, 16, 10)
	builder.ellipsoid(1, Vector3(0, 1.58, -0.010), Vector3(0.104, 0.091, 0.105), head)
	builder.rounded_box(1, Vector3(0, 1.592, -0.098), Vector3(0.157, 0.087, 0.032), 0.012, head)
	builder.ellipsoid(0, Vector3(0, 1.721, 0.003), Vector3(0.124, 0.104, 0.123), head, Basis.IDENTITY, 16, 9)
	builder.rounded_box(2, Vector3(0, 1.683, -0.100), Vector3(0.224, 0.068, 0.039), 0.014, head)
	for x in [-0.052, 0.052]:
		builder.rounded_box(4, Vector3(x, 1.683, -0.122), Vector3(0.091, 0.044, 0.009), 0.009, head)
	for sign_value in [-1.0, 1.0]:
		builder.rounded_box(2, Vector3(sign_value * 0.115, 1.657, 0), Vector3(0.025, 0.088, 0.075), 0.012, head)
		builder.rounded_box(3, Vector3(sign_value * 0.126, 1.72, 0.012), Vector3(0.018, 0.025, 0.087), 0.006, head)
		builder.limb(2, Vector3(sign_value * 0.09, 1.64, 0.025), Vector3(sign_value * 0.055, 1.542, -0.032), Vector2(0.012, 0.008), head)
	builder.rounded_box(3, Vector3(0, 1.763, -0.104), Vector3(0.038, 0.035, 0.023), 0.005, head)
	# Belt and side utility pouches remain attached to the pelvis while crouching.
	builder.rounded_box(2, Vector3(0, 1.005, 0), Vector3(0.38, 0.042, 0.26), 0.025, pelvis)
	builder.rounded_box(3, Vector3(0, 1.005, -0.139), Vector3(0.052, 0.033, 0.015), 0.006, pelvis)
	for side in ["Left", "Right"]:
		var sign_value := -1.0 if side == "Left" else 1.0
		var upper: int = _bones[side + "UpperArm"]
		var forearm: int = _bones[side + "Forearm"]
		var hand: int = _bones[side + "Hand"]
		var thigh: int = _bones[side + "Thigh"]
		var shin: int = _bones[side + "Shin"]
		var foot: int = _bones[side + "Foot"]
		builder.limb(0, _rests[side + "UpperArm"], _rests[side + "Forearm"], Vector2(0.073, 0.074), upper, _bones[side + "Clavicle"])
		builder.limb(0, _rests[side + "Forearm"], _rests[side + "Hand"], Vector2(0.055, 0.061), forearm, upper)
		builder.ellipsoid(0, _rests[side + "UpperArm"], Vector3(0.078, 0.071, 0.079), upper, Basis.IDENTITY, 12, 6, _bones[side + "Clavicle"], 0.35)
		builder.ellipsoid(0, _rests[side + "Forearm"], Vector3(0.052, 0.052, 0.056), forearm, Basis.IDENTITY, 12, 6, upper, 0.35)
		builder.ellipsoid(1, Vector3(sign_value * 0.26, 1.095, 0.042), Vector3(0.058, 0.063, 0.025), forearm)
		builder.rounded_box(1, Vector3(sign_value * 0.295, 1.30, 0), Vector3(0.025, 0.11, 0.11), 0.008, upper)
		builder.rounded_box(6, Vector3(sign_value * 0.31, 1.32, -0.014), Vector3(0.008, 0.035, 0.060), 0.003, upper)
		builder.ellipsoid(2, Vector3(sign_value * 0.276, 0.781, 0), Vector3(0.043, 0.065, 0.029), hand)
		builder.rounded_box(3, Vector3(sign_value * 0.276, 0.788, 0.027), Vector3(0.061, 0.035, 0.012), 0.008, hand)
		for digit in 4:
			builder.ellipsoid(2, Vector3(sign_value * 0.276 + (digit - 1.5) * 0.016, 0.744, -0.024), Vector3(0.009, 0.027, 0.018), hand, Basis(Vector3.RIGHT, -0.8), 8, 5)
		builder.ellipsoid(2, Vector3(sign_value * 0.311, 0.783, -0.025), Vector3(0.014, 0.031, 0.015), hand, Basis(Vector3.FORWARD, sign_value * 0.6), 8, 5)
		builder.limb(0, _rests[side + "Thigh"], _rests[side + "Shin"], Vector2(0.096, 0.112), thigh, pelvis)
		builder.limb(0, _rests[side + "Shin"], _rests[side + "Foot"], Vector2(0.066, 0.072), shin, thigh)
		builder.ellipsoid(0, _rests[side + "Shin"], Vector3(0.066, 0.069, 0.078), shin, Basis.IDENTITY, 12, 6, thigh, 0.35)
		builder.ellipsoid(2, Vector3(sign_value * 0.115, 0.49, -0.067), Vector3(0.073, 0.087, 0.045), shin)
		builder.ellipsoid(3, Vector3(sign_value * 0.115, 0.49, -0.10), Vector3(0.053, 0.061, 0.018), shin)
		builder.rounded_box(1, Vector3(sign_value * 0.20, 0.72, 0), Vector3(0.064, 0.17, 0.13), 0.015, thigh)
		builder.rounded_box(2, Vector3(sign_value * 0.115, 0.091, -0.045), Vector3(0.133, 0.15, 0.24), 0.032, foot)
		builder.rounded_box(1, Vector3(sign_value * 0.115, 0.032, -0.048), Vector3(0.14, 0.035, 0.255), 0.012, foot)
		for y in [0.10, 0.13, 0.16]:
			builder.rounded_box(6, Vector3(sign_value * 0.115, y, -0.108 + (y - 0.10) * 0.6), Vector3(0.07, 0.007, 0.01), 0.002, foot)
	skin_mesh = MeshInstance3D.new()
	skin_mesh.name = "SkinnedOperator"
	skin_mesh.mesh = builder.build(material_list)
	skin_mesh.skin = skeleton.create_skin_from_rest_transforms()
	skin_mesh.skeleton = NodePath("../Skeleton3D")
	# Covers crouch, articulated arms and the sideways corpse without hiding a
	# skinned mesh when its rest-pose AABB leaves the camera's frustum.
	skin_mesh.custom_aabb = AABB(Vector3(-1.8, -0.1, -1.0), Vector3(3.6, 2.1, 2.0))
	add_child(skin_mesh)
	_triangles = builder.triangles

func _build_animation_graph():
	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	animation_player.root_node = NodePath("..")
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	add_child(animation_player)
	var library := AnimationLibrary.new()
	for clip_name in ["idle", "walk", "run"]:
		var clip := Animation.new()
		clip.length = 1.0
		clip.loop_mode = Animation.LOOP_LINEAR
		var amplitude := 0.012 if clip_name == "idle" else (0.023 if clip_name == "walk" else 0.038)
		for bone_name in ["Chest", "Head"]:
			var track := clip.add_track(Animation.TYPE_ROTATION_3D)
			clip.track_set_path(track, NodePath("Skeleton3D:" + bone_name))
			for key in 5:
				var angle := sin(key / 4.0 * TAU) * amplitude * (1.0 if bone_name == "Chest" else -0.45)
				clip.rotation_track_insert_key(track, key / 4.0, Quaternion(Vector3.FORWARD, angle))
		library.add_animation(clip_name, clip)
	animation_player.add_animation_library("", library)
	animation_tree = AnimationTree.new()
	animation_tree.name = "AnimationTree"
	animation_tree.anim_player = NodePath("../AnimationPlayer")
	animation_tree.root_node = NodePath("..")
	animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var blend := AnimationNodeBlendSpace1D.new()
	blend.min_space = 0.0
	blend.max_space = 2.0
	blend.sync = true
	var names := ["idle", "walk", "run"]
	for i in names.size():
		var clip_node := AnimationNodeAnimation.new()
		clip_node.animation = names[i]
		blend.add_blend_point(clip_node, float(i), -1, names[i])
	animation_tree.tree_root = blend
	add_child(animation_tree)
	animation_tree.active = true

func attach_weapon(weapon: Node3D):
	_weapon = weapon
	_weapon_death_captured = false

func reset_pose():
	_dead = false
	_death = 0.0
	_clock = 0.0
	_crouch = 0.0
	_landing = 0.0
	_was_grounded = true
	stride_phase = 0.0
	if _weapon_death_captured and is_instance_valid(_weapon):
		_weapon.transform = _weapon_living_transform
	_weapon_death_captured = false
	if is_instance_valid(skeleton): skeleton.reset_bone_poses()

func seek_pose(frame: Dictionary):
	# Snapshot restoration is an explicit pose seek, distinct from step(0),
	# which must remain a strict pause. No locomotion time is consumed.
	if _dead and not frame.get("dead", false): reset_pose()
	_crouch = 1.0 if frame.get("crouching", false) else 0.0
	_was_grounded = bool(frame.get("grounded", true))
	_landing = 0.0
	if frame.get("dead", false):
		set_dead_pose(true)
		return
	var preserved_clock := _clock
	var preserved_phase := stride_phase
	step(0.000001, frame)
	_clock = preserved_clock
	stride_phase = preserved_phase

func set_dead_pose(immediate := true):
	_dead = true
	if immediate: _death = 1.0
	_apply_dead_pose()

func _rotation(bone_name: String, rotation_value: Quaternion):
	skeleton.set_bone_pose_rotation(_bones[bone_name], rotation_value.normalized())

func _global_point(bone_name: String) -> Vector3:
	return skeleton.get_bone_global_pose(_bones[bone_name]).origin

func _aim_bone(bone_name: String, child_name: String, direction: Vector3):
	var id: int = _bones[bone_name]
	var parent_id := skeleton.get_bone_parent(id)
	var parent_basis := Basis.IDENTITY if parent_id < 0 else skeleton.get_bone_global_pose(parent_id).basis
	var rest_direction: Vector3 = (_rests[child_name] - _rests[bone_name]).normalized()
	var local_direction := parent_basis.inverse() * direction.normalized()
	_rotation(bone_name, Quaternion(rest_direction, local_direction))

func _solve_chain(first_name: String, middle_name: String, tip_name: String, target: Vector3, pole: Vector3):
	var start := _global_point(first_name)
	var first_length: float = _rests[first_name].distance_to(_rests[middle_name])
	var second_length: float = _rests[middle_name].distance_to(_rests[tip_name])
	var to_target := target - start
	var distance := clampf(to_target.length(), absf(first_length - second_length) + 0.015, first_length + second_length - 0.008)
	var forward := to_target.normalized() if to_target.length_squared() > 0.0001 else Vector3.DOWN
	var sideways := (pole - forward * pole.dot(forward)).normalized()
	if sideways.length_squared() < 0.01: sideways = Vector3.FORWARD
	var along := (first_length * first_length - second_length * second_length + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, first_length * first_length - along * along))
	var elbow := start + forward * along + sideways * height
	var tip := start + forward * distance
	_aim_bone(first_name, middle_name, elbow - start)
	_aim_bone(middle_name, tip_name, tip - elbow)

func _world_orientation(bone_name: String, orientation: Basis):
	var parent := skeleton.get_bone_parent(_bones[bone_name])
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	_rotation(bone_name, (parent_basis.inverse() * orientation).get_rotation_quaternion())

func step(delta: float, frame: Dictionary):
	if not is_instance_valid(skeleton) or delta <= 0.0: return
	var dt := minf(delta, 0.1)
	if bool(frame.get("dead", false)): _dead = true
	if _dead:
		_death = minf(1.0, _death + dt * 2.5)
		_apply_dead_pose()
		return
	_clock += dt
	var speed := maxf(0.0, float(frame.get("speed", 0.0)))
	var grounded := bool(frame.get("grounded", true))
	var running := bool(frame.get("sprinting", false)) and speed > 0.1
	var moving := clampf(speed / 1.2, 0.0, 1.0)
	_crouch = move_toward(_crouch, 1.0 if frame.get("crouching", false) else 0.0, dt * 7.5)
	if grounded and not _was_grounded: _landing = 1.0
	_was_grounded = grounded
	_landing = maxf(0.0, _landing - dt * 5.5)
	stride_phase += dt * (11.0 if running else 7.5) * moving
	# The AnimationTree really drives chest/head bone tracks. The arm IK and
	# foot placement are layered afterwards, preserving a stable sight line.
	skeleton.reset_bone_poses()
	animation_tree.set("parameters/blend_position", 2.0 if running else moving)
	animation_tree.advance(dt * (1.6 if running else 1.0))
	# Deep tactical crouch keeps the helmet under the 1.28 m low passage.
	var pelvis := Vector3(0, 0.91 - 0.55 * _crouch, 0.055 * _crouch)
	pelvis.y += sin(stride_phase * 2.0) * (0.013 if running else 0.007) * moving * (1.0 - _crouch * 0.5)
	pelvis.y -= _landing * 0.075
	skeleton.set_bone_pose_position(_bones.Pelvis, pelvis)
	var pitch := clampf(float(frame.get("aim_pitch", 0.0)), -0.85, 0.85)
	_rotation("Spine", Quaternion(Vector3.RIGHT, pitch * 0.22 - _crouch * 0.12 - (0.10 if running else 0.0)))
	var chest_pose := skeleton.get_bone_pose_rotation(_bones.Chest)
	_rotation("Chest", Quaternion(Vector3.RIGHT, pitch * 0.30) * chest_pose)
	var head_pose := skeleton.get_bone_pose_rotation(_bones.Head)
	_rotation("Head", Quaternion(Vector3.RIGHT, pitch * 0.32) * head_pose)
	var local_velocity: Vector3 = frame.get("local_velocity", Vector3(0, 0, -speed))
	var travel := Vector3(local_velocity.x, 0, local_velocity.z).normalized()
	if travel.length_squared() < 0.01: travel = Vector3.FORWARD
	for side in ["Left", "Right"]:
		var sign_value := -1.0 if side == "Left" else 1.0
		var phase := stride_phase + (PI if side == "Right" else 0.0)
		var stride := (0.24 if running else 0.15) * moving * (1.0 - 0.55 * _crouch)
		var foot_target := Vector3(sign_value * (0.115 + 0.035 * _crouch), 0.10, -0.035 * _crouch)
		foot_target += travel * sin(phase) * stride
		foot_target.y += maxf(0.0, cos(phase)) * (0.11 if running else 0.06) * moving
		if not grounded:
			foot_target = Vector3(sign_value * 0.13, 0.28 + (0.10 if side == "Right" else 0.0), 0.08 if side == "Right" else -0.10)
		_solve_chain(side + "Thigh", side + "Shin", side + "Foot", foot_target, Vector3(sign_value * 0.12, 0, -1))
		_world_orientation(side + "Foot", Basis(Vector3.RIGHT, -0.14 if not grounded else 0.0))
	_pose_arms(frame, running)

func _pose_arms(frame: Dictionary, running: bool):
	var reload_progress := float(frame.get("reload_progress", -1.0))
	var heal_progress := float(frame.get("healing_progress", -1.0))
	var recoil := clampf(float(frame.get("recoil", 0.0)), 0.0, 1.0)
	var chest_position := _global_point("Chest")
	var vertical_shift := chest_position.y - 1.29
	var right_target := Vector3(0.16, 1.20 + vertical_shift, -0.27)
	var left_target := Vector3(-0.04, 1.23 + vertical_shift, -0.46)
	var has_weapon := is_instance_valid(_weapon) and _weapon.is_inside_tree()
	if has_weapon:
		var right_grip := _weapon.get_node_or_null("GripRight") as Node3D
		var left_grip := _weapon.get_node_or_null("GripLeft") as Node3D
		if right_grip: right_target = to_local(right_grip.global_position)
		if left_grip: left_target = to_local(left_grip.global_position)
	if running and not has_weapon:
		right_target += Vector3(0.035, -0.13, 0.08)
		left_target += Vector3(-0.045, -0.10, 0.12)
	if reload_progress >= 0.0:
		var p := clampf(reload_progress, 0.0, 1.0)
		if has_weapon and _weapon.has_method("left_hand_target"):
			# Both views use the same magazine/charging-handle choreography.
			left_target = to_local(_weapon.to_global(_weapon.left_hand_target(p)))
		else:
			var reach := sin(p * PI)
			left_target = left_target.lerp(Vector3(-0.12, 0.97 + vertical_shift, -0.20), reach)
			left_target.z -= sin(p * PI * 3.0) * 0.045
	if heal_progress >= 0.0:
		var rhythm := sin(heal_progress * TAU * 2.0)
		right_target = Vector3(-0.07, 1.16 + vertical_shift, -0.24)
		left_target = Vector3(0.02, 1.14 + vertical_shift, -0.28 + rhythm * 0.035)
	if not has_weapon: right_target.z += recoil * 0.055
	_solve_chain("RightUpperArm", "RightForearm", "RightHand", right_target, Vector3(0.8, -0.7, 0.05))
	_solve_chain("LeftUpperArm", "LeftForearm", "LeftHand", left_target, Vector3(-0.8, -0.7, 0.05))
	# Rotate gloved palms around the grip; finger volumes are authored curled.
	_world_orientation("RightHand", Basis(Vector3.RIGHT, -1.05) * Basis(Vector3.FORWARD, 0.15))
	_world_orientation("LeftHand", Basis(Vector3.RIGHT, -1.15) * Basis(Vector3.FORWARD, -0.4))

func _apply_dead_pose():
	if not is_instance_valid(skeleton): return
	skeleton.reset_bone_poses()
	var fall := smoothstep(0.0, 1.0, _death)
	skeleton.set_bone_pose_position(_bones.Pelvis, Vector3(0, lerpf(0.91, 0.32, fall), 0))
	_rotation("Pelvis", Quaternion(Vector3.FORWARD, 1.47 * fall) * Quaternion(Vector3.UP, 0.16 * fall))
	_rotation("Spine", Quaternion(Vector3.RIGHT, -0.15 * fall))
	_rotation("Head", Quaternion(Vector3.UP, 0.30 * fall))
	for side in ["Left", "Right"]:
		var sign_value := -1.0 if side == "Left" else 1.0
		_rotation(side + "Thigh", Quaternion(Vector3.RIGHT, (0.35 if side == "Left" else -0.12) * fall))
		_rotation(side + "Shin", Quaternion(Vector3.RIGHT, -0.55 * fall))
		_rotation(side + "UpperArm", Quaternion(Vector3.FORWARD, sign_value * 0.45 * fall) * Quaternion(Vector3.RIGHT, -0.35 * fall))
		_rotation(side + "Forearm", Quaternion(Vector3.RIGHT, -0.65 * fall))
	if is_instance_valid(_weapon):
		if not _weapon_death_captured:
			_weapon_living_transform = _weapon.transform
			_weapon_death_captured = true
		# Death is the sole exception to owner-controlled weapon aim: move the
		# carried rifle with the collapsing pelvis instead of leaving it afloat.
		var fall_transform := skeleton.get_bone_global_pose(_bones.Pelvis) * skeleton.get_bone_rest(_bones.Pelvis).affine_inverse()
		_weapon.transform = fall_transform * _weapon_living_transform

func pose_markers() -> Dictionary:
	if not is_instance_valid(skeleton): return {}
	var result := {"head": _global_point("Head"), "torso": _global_point("Chest") + Vector3(0, -0.055, 0), "pelvis": _global_point("Pelvis"), "left_knee": _global_point("LeftShin"), "right_knee": _global_point("RightShin"), "left_foot": _global_point("LeftFoot"), "right_foot": _global_point("RightFoot"), "left_hand": _global_point("LeftHand"), "right_hand": _global_point("RightHand")}
	for side in ["Left", "Right"]:
		var prefix: String = side.to_lower()
		result[prefix + "_thigh"] = {"start": _global_point(side + "Thigh"), "end": _global_point(side + "Shin")}
		result[prefix + "_shin"] = {"start": _global_point(side + "Shin"), "end": _global_point(side + "Foot")}
		result[prefix + "_upper_arm"] = {"start": _global_point(side + "UpperArm"), "end": _global_point(side + "Forearm")}
		result[prefix + "_forearm"] = {"start": _global_point(side + "Forearm"), "end": _global_point(side + "Hand")}
	return result

func metrics() -> Dictionary:
	var vertex_count := 0
	if skin_mesh:
		for surface in skin_mesh.mesh.get_surface_count():
			vertex_count += skin_mesh.mesh.surface_get_array_len(surface)
	return {"triangles": _triangles, "vertices": vertex_count, "bones": skeleton.get_bone_count() if skeleton else 0, "surfaces": skin_mesh.mesh.get_surface_count() if skin_mesh else 0, "node_count": 1 + get_child_count(), "skinned": skin_mesh != null and skin_mesh.skin != null, "rest_height_m": skin_mesh.mesh.get_aabb().end.y if skin_mesh else 0.0, "shared_texture_bytes": 174760}
