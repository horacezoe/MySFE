extends SceneTree
const Rifle = preload("res://scripts/presentation/rifle_visual.gd")
var checks := 0
var failures := 0

func _initialize(): call_deferred("preview" if "--rifle-preview" in OS.get_cmdline_user_args() else "run_tests")

func preview() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.14,0.17,0.19)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.78,0.83,0.88)
	environment.environment.ambient_light_energy = 0.7
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-35,0)
	light.light_energy = 2.1
	scene.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(1.15,0.42,-0.07)
	scene.add_child(camera)
	camera.look_at(Vector3(0,-0.06,-0.16))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.95
	var rifle = Rifle.new()
	scene.add_child(rifle)
	rifle.setup(false)
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/rifle_visual_side.png")
	rifle.free()
	rifle = Rifle.new()
	scene.add_child(rifle)
	rifle.setup(true)
	rifle.position = Vector3(0.18,-0.20,-0.68)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 68.0
	camera.position = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/rifle_visual_fp.png")
	rifle.step(0.016,{"reload_progress":0.45})
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/rifle_visual_reload.png")
	quit()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func finite_nodes(node: Node) -> bool:
	if node is Node3D and not node.transform.is_finite(): return false
	for child in node.get_children():
		if not finite_nodes(child): return false
	return true

func run_tests() -> void:
	var fp = Rifle.new()
	var world = Rifle.new()
	root.add_child(fp)
	root.add_child(world)
	fp.setup(true)
	world.setup(false)
	for socket in ["Muzzle","Aim","GripRight","GripLeft","Eject"]:
		check(fp.get_node(socket) is Marker3D,"direct fixed socket " + socket)
		check(fp.get_marker_position(socket).is_equal_approx(world.get_marker_position(socket)),"shared first/third person socket " + socket)
	check(fp.get_node("Magazine") is Node3D and fp.get_node("Flash") is Node3D,"direct presentation attachments")
	check(fp.get_node("Arms/RightHand") != null and fp.get_node("Arms/LeftHand") != null,"both gloved hands exist")
	check(world.get_node_or_null("Arms") == null,"world rifle does not duplicate character arms")
	var second = Rifle.new()
	root.add_child(second)
	second.setup(false)
	check(second.get_node("Body").mesh == world.get_node("Body").mesh,"guards reuse cached static mesh")
	check(fp.get_node("Body").mesh.get_aabb().end.z < 0.16,"view model stock does not obscure the trigger hand")
	second.queue_free()
	var body: Mesh = world.get_node("Body").mesh
	var bounds := body.get_aabb()
	check(bounds.position.z < -0.718 and bounds.end.z > 0.37 and bounds.size.z < 1.15,"physical compact rifle has correct full-length bounds")
	check(absf(bounds.position.z-fp.get_marker_position("Muzzle").z) < 0.003,"muzzle marker lies at physical barrel crown")
	check(fp.get_marker_position("Aim").y > 0.12,"optic aiming axis above receiver")
	var metal_count := 0
	var rough_count := 0
	for i in range(body.get_surface_count()):
		var mat: StandardMaterial3D = body.surface_get_material(i)
		if mat.metallic > 0.5: metal_count += 1
		if mat.roughness > 0.7: rough_count += 1
	check(metal_count >= 2 and rough_count >= 2,"metal, polymer and rubber have distinct PBR response")
	var initial_metrics: Dictionary = fp.metrics()
	check(initial_metrics.triangles > 1500 and initial_metrics.triangles < 14000,"detailed view model triangle budget")
	check(initial_metrics.node_count < 30 and initial_metrics.surfaces < 30,"batched model node/surface budget")
	check(world.metrics().triangles < 9000 and world.metrics().surfaces < 16,"world rifle mobile budget")
	# Actual grip geometry must be in a normal first-person camera frustum, not
	# merely represented by two nodes that stay outside the rendered image.
	for hand in ["RightHand","LeftHand"]:
		var p: Vector3 = fp.get_node("Arms/"+hand).position+Vector3(0.22,-0.22,-0.62)
		check(p.z < -0.1 and absf(p.y / p.z) < tan(deg_to_rad(34.0)) and absf(p.x / p.z) < 1.15,"visible first-person " + hand + " grip")
		var hand_bounds: AABB = fp.get_node("Arms/"+hand).mesh.get_aabb()
		check(hand_bounds.size.x > 0.05 and hand_bounds.size.y > 0.07 and hand_bounds.size.z > 0.06,"volumetric palm and segmented fingers " + hand)
	var saved_transform := Transform3D(Basis.from_euler(Vector3(0.1,0.45,-0.03)),Vector3(1,2,3))
	fp.transform = saved_transform
	var marker_before: Vector3 = fp.get_node("Muzzle").global_position
	var rest_left: Vector3 = fp.get_node("Arms/LeftHand").position
	var rest_mag: Vector3 = fp.get_node("Magazine").position
	fp.step(0.016,{"reload_progress":0.45})
	var out_mag: Vector3 = fp.get_node("Magazine").position
	var out_left: Vector3 = fp.get_node("Arms/LeftHand").position
	check(out_mag.distance_to(rest_mag)>0.2,"reload extracts physical magazine")
	check(out_left.distance_to(rest_left)>0.25,"reload left hand leaves handguard")
	fp.step(0.0,{"reload_progress":0.73})
	check(fp.get_node("Magazine").position.distance_to(rest_mag)<0.001,"magazine fully reseated before charging action")
	fp.step(0.0,{"reload_progress":0.89})
	check(fp.get_node("ChargingHandle").position.z>0.06,"reload pulls charging handle")
	check(fp.get_node("Arms/LeftHand").position.distance_to(Vector3(-0.063,0.06,0.185))<0.001,"hand contacts charging handle during pull")
	fp.step(0.0,{"reload_progress":0.45})
	check(fp.get_node("Magazine").position.is_equal_approx(out_mag) and fp.get_node("Arms/LeftHand").position.is_equal_approx(out_left),"out-of-order seek restores exact reload pose")
	for i in range(101):
		fp.step(0.016,{"reload_progress":float(i)/100.0,"speed":5.0,"sprinting":true,"recoil":0.7})
		check(finite_nodes(fp),"finite reload transforms phase %d" % i)
	check(fp.get_node("Magazine").position.is_equal_approx(rest_mag),"end reload returns magazine home")
	check(fp.get_node("Arms/LeftHand").position.is_equal_approx(rest_left),"end reload returns support hand")
	check(fp.transform.is_equal_approx(saved_transform) and fp.get_node("Muzzle").global_position.is_equal_approx(marker_before),"presentation never overrides owner aim or muzzle transform")
	fp.fire()
	check(fp.get_node("Flash").visible,"shot starts flash")
	fp.step(0.025,{})
	check(fp.get_node("Bolt").position.z>0.01,"shot cycles physical bolt")
	var frozen_bolt: Vector3 = fp.get_node("Bolt").position
	for i in range(5): await process_frame
	check(fp.get_node("Flash").visible and fp.get_node("Bolt").position == frozen_bolt,"no automatic presentation clock during pause")
	fp.step(0.1,{})
	check(not fp.get_node("Flash").visible and fp.get_node("Bolt").position.is_zero_approx(),"flash and bolt settle after supplied time")
	for i in range(60):
		fp.fire()
		fp.step(0.016,{"reload_progress":float(i%10)/9.0,"healing_progress":0.4})
	check(fp.metrics().node_count == initial_metrics.node_count,"actions never clone attachments")
	fp.step(0.0,{"dead":true})
	check(not fp.get_node("Flash").visible and not fp.get_node("Arms").visible,"death hides first-person muzzle and arms")
	fp.reset_pose()
	check(fp.get_node("Magazine").position.is_equal_approx(rest_mag) and not fp.get_node("Flash").visible,"reset restores quiet pose")
	fp.step(0.016,{})
	check(fp.get_node("Arms").visible,"resume restores first-person arms")
	fp.setup(true)
	check(fp.metrics().node_count == initial_metrics.node_count,"repeated setup cannot duplicate geometry")
	print("Rifle budgets: ",fp.metrics()," world: ",world.metrics())
	fp.queue_free()
	world.queue_free()
	await process_frame
	print("Rifle visual checks: %d passed / %d total" % [checks-failures,checks])
	quit(1 if failures else 0)
