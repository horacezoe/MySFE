extends SceneTree

const CharacterVisual = preload("res://scripts/presentation/character_visual.gd")
var checks := 0
var failures := 0

func _initialize():
	call_deferred("run_tests")

func check(condition: bool, description: String):
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func run_tests():
	var visual = CharacterVisual.new()
	visual.name = "Visual"
	root.add_child(visual)
	visual.setup(Color("67735c"))
	if "--capture" in OS.get_cmdline_user_args():
		await capture_previews(visual)
	var metrics: Dictionary = visual.metrics()
	print("CHARACTER METRICS: ", metrics)
	check(metrics.bones >= 19 and metrics.bones <= 30, "articulated human rig budget")
	check(metrics.triangles < 18000 and metrics.triangles > 3000, "detailed mobile mesh triangle budget")
	check(metrics.surfaces <= 7 and metrics.node_count <= 8, "geometry merged by material")
	check(visual.skin_mesh.skin.get_bind_count() == metrics.bones, "skin binds every authored bone")
	var weights_checked := 0
	var blended_vertices := 0
	for surface in visual.skin_mesh.mesh.get_surface_count():
		var arrays: Array = visual.skin_mesh.mesh.surface_get_arrays(surface)
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		check(weights.size() == arrays[Mesh.ARRAY_VERTEX].size() * 4, "four skin weights per vertex")
		for i in range(0, weights.size(), 4):
			if is_equal_approx(weights[i] + weights[i + 1] + weights[i + 2] + weights[i + 3], 1.0): weights_checked += 1
			if weights[i + 1] > 0.0: blended_vertices += 1
			if bones[i] < 0 or bones[i] >= metrics.bones: failures += 1
	check(weights_checked > 3000 and blended_vertices > 500, "normalized skin with blended shoulder/limb vertices")
	var bounds: AABB = visual.skin_mesh.mesh.get_aabb()
	check(bounds.end.y < 1.86 and bounds.end.y > 1.79 and bounds.position.y >= -0.01, "adult height and ground-aligned boots")
	var idle: Dictionary = visual.pose_markers()
	check(absf(idle.head.y - 1.63) < 0.04, "adult head rests at expected hitbox height")
	check(absf(idle.left_foot.y - 0.10) < 0.02, "standing ankle ground clearance")
	var rest_head: Quaternion = visual.skeleton.get_bone_pose_rotation(visual.skeleton.find_bone("Head"))
	for i in 12: visual.step(1.0 / 60.0, {})
	var animated_head: Quaternion = visual.skeleton.get_bone_pose_rotation(visual.skeleton.find_bone("Head"))
	check(rest_head.angle_to(animated_head) > 0.0001, "AnimationTree actually advances a skeleton bone")
	var before_pause: Transform3D = visual.skeleton.get_bone_global_pose(visual.skeleton.find_bone("Chest"))
	await process_frame
	await process_frame
	check(before_pause.is_equal_approx(visual.skeleton.get_bone_global_pose(visual.skeleton.find_bone("Chest"))), "no automatic animation while owner is paused")
	visual.step(0.0, {"speed": 4.0, "crouching": true})
	check(before_pause.is_equal_approx(visual.skeleton.get_bone_global_pose(visual.skeleton.find_bone("Chest"))), "zero delta cannot move pose")
	for i in 30: visual.step(1.0 / 60.0, {"speed": 3.0, "local_velocity": Vector3(0, 0, -3)})
	var walking: Dictionary = visual.pose_markers()
	check(absf(walking.left_foot.z - walking.right_foot.z) > 0.03, "walking alternates foot placement")
	for i in 20: visual.step(1.0 / 60.0, {"speed": 5.0, "sprinting": true})
	var running: Dictionary = visual.pose_markers()
	check(walking.left_hand.distance_to(running.left_hand) > 0.04, "sprint has a lowered weapon-ready arm pose")
	for i in 20: visual.step(1.0 / 60.0, {"crouching": true})
	var crouching: Dictionary = visual.pose_markers()
	check(crouching.head.y < idle.head.y - 0.30, "crouch lowers pelvis and head")
	check(crouching.head.y + 0.195 <= 1.28, "crouched helmet clears the physical low passage")
	check(skinned_bounds(visual).end.y <= 1.28, "actual weighted crouch mesh fits beneath low ceiling")
	check(visual.scale.is_equal_approx(Vector3.ONE), "crouch preserves adult proportions")
	check(crouching.left_knee.z < -0.20 and absf(crouching.left_foot.y - 0.10) < 0.03, "bent knees support grounded crouch")
	visual.reset_pose()
	visual.seek_pose({"crouching": true})
	check(visual.pose_markers().head.y < 1.10 and is_zero_approx(visual.stride_phase), "snapshot seek restores crouch immediately without stride advancement")
	for segment_name in ["left_thigh", "right_thigh", "left_shin", "right_shin", "left_upper_arm", "right_upper_arm", "left_forearm", "right_forearm"]:
		var segment: Dictionary = visual.pose_markers()[segment_name]
		check(segment.start.distance_to(segment.end) > 0.25 and segment.start.distance_to(segment.end) < 0.42, "hitbox marker segment matches anatomical bone length")
	visual.reset_pose()
	visual.step(1.0 / 60.0, {"grounded": false})
	var airborne: Dictionary = visual.pose_markers()
	check(airborne.left_foot.y > 0.24 and airborne.right_foot.y > 0.32, "airborne knees tuck")
	visual.step(1.0 / 60.0, {"grounded": true})
	check(visual.pose_markers().pelvis.y < 0.87, "landing visibly absorbs impact")
	visual.reset_pose()
	visual.step(1.0 / 60.0, {"reload_progress": 0.5})
	var reloading: Vector3 = visual.pose_markers().left_hand
	check(reloading.y < idle.left_hand.y - 0.12, "reload support hand reaches the magazine")
	visual.step(1.0 / 60.0, {"healing_progress": 0.3})
	check(visual.pose_markers().right_hand.x < 0.0, "medical action crosses hands to treatment point")
	var rifle := Node3D.new()
	rifle.name = "CarriedRifle"
	visual.add_child(rifle)
	for grip_name in ["GripRight", "GripLeft"]:
		var grip := Marker3D.new()
		grip.name = grip_name
		grip.position = Vector3(0.14, 1.21, -0.24) if grip_name == "GripRight" else Vector3(-0.05, 1.24, -0.43)
		rifle.add_child(grip)
	visual.attach_weapon(rifle)
	var rifle_transform := rifle.transform
	visual.step(1.0 / 60.0, {"aim_pitch": 0.2, "aiming": true})
	check(visual.pose_markers().right_hand.distance_to(rifle.get_node("GripRight").position) < 0.025, "right hand IK follows reachable rifle grip")
	check(visual.pose_markers().left_hand.distance_to(rifle.get_node("GripLeft").position) < 0.025, "support hand IK follows reachable rifle grip")
	check(rifle.transform.is_equal_approx(rifle_transform), "live character pose never changes owner-controlled gun aim")
	var original_transform: Transform3D = visual.transform
	for sample in 90:
		visual.step(1.0 / 60.0, {"speed": 5.0, "local_velocity": Vector3(2, 0, -3), "aim_pitch": sin(sample * 0.2), "crouching": sample % 40 > 20, "grounded": sample % 30 < 20, "sprinting": true})
		for bone in visual.skeleton.get_bone_count():
			var pose: Transform3D = visual.skeleton.get_bone_global_pose(bone)
			check(pose.origin.is_finite() and pose.basis.is_finite() and pose.origin.length() < 2.5, "sampled animated joint remains finite and in bounds")
	check(visual.transform.is_equal_approx(original_transform), "animation has no root motion")
	visual.set_dead_pose(true)
	var dead_head: Vector3 = visual.pose_markers().head
	var corpse_weapon: Transform3D = rifle.transform
	check(skinned_bounds(visual).position.y >= -0.01, "corpse mesh rests on the ground instead of sinking through it")
	check(dead_head.y < 0.50, "restored corpse lies near the ground")
	check(not corpse_weapon.is_equal_approx(rifle_transform), "corpse carries rifle with falling body")
	for i in 60: visual.step(1.0 / 60.0, {"dead": true})
	check(dead_head.is_equal_approx(visual.pose_markers().head), "completed corpse pose is stable")
	check(corpse_weapon.is_equal_approx(rifle.transform), "corpse rifle has stable transform")
	visual.reset_pose()
	visual.step(1.0 / 60.0, {})
	check(visual.pose_markers().head.y > 1.55, "reset restores living stance")
	check(rifle.transform.is_equal_approx(rifle_transform), "reset restores live owner rifle transform")
	visual.free()
	await process_frame
	print("CHARACTER VISUAL: ", checks - failures, "/", checks, " checks passed")
	quit(1 if failures else 0)

func skinned_bounds(visual: Node3D) -> AABB:
	var transforms: Array[Transform3D] = []
	var skin: Skin = visual.skin_mesh.skin
	for binding in skin.get_bind_count():
		var bone := skin.get_bind_bone(binding)
		if bone < 0: bone = visual.skeleton.find_bone(skin.get_bind_name(binding))
		transforms.append(visual.skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(binding))
	var result := AABB()
	var initialized := false
	for surface in visual.skin_mesh.mesh.get_surface_count():
		var arrays: Array = visual.skin_mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for i in vertices.size():
			var vertex := Vector3.ZERO
			for influence in 4:
				vertex += (transforms[bones[i * 4 + influence]] * vertices[i]) * weights[i * 4 + influence]
			if initialized: result = result.expand(vertex)
			else:
				result = AABB(vertex, Vector3.ZERO)
				initialized = true
	return result

func capture_previews(visual: Node3D):
	root.size = Vector2i(960, 900)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("242b30")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("b3c8dc")
	world.environment.ambient_light_energy = 0.55
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 140, 0)
	light.light_energy = 1.6
	root.add_child(light)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(2.1, 1.5, -3.1)
	camera.look_at(Vector3(0, 0.93, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.2
	camera.current = true
	DirAccess.make_dir_recursive_absolute("res://artifacts/phase5")
	for state in ["standing", "crouching", "death"]:
		visual.reset_pose()
		visual.seek_pose({"crouching": state == "crouching", "dead": state == "death"})
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/phase5/character_" + state + ".png")
	visual.reset_pose()
	visual.step(0.001, {})
	world.free()
	light.free()
	camera.free()
