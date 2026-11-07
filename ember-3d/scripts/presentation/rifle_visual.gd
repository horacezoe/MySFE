extends Node3D
## Kestrel K-14: original compact rifle and two-hand view model.
## The owner is the only clock. No process callback, timers or tweens are used.
## Marker transforms remain fixed; visual actions never change ballistics or root aim.

const Builder = preload("res://scripts/presentation/rifle_mesh_builder.gd")
const SOCKETS := {
	"Muzzle": Vector3(0,0.032,-0.72),
	"Aim": Vector3(0,0.145,-0.16),
	"GripRight": Vector3(0.035,-0.105,0.09),
	"GripLeft": Vector3(-0.035,-0.03,-0.335),
	"Eject": Vector3(0.067,0.035,-0.015),
}
const MAGAZINE_REST := Vector3(0,-0.07,-0.105)
static var _assets: Dictionary = {}
var first_person := false
var configured := false
var _magazine: Node3D
var _bolt: Node3D
var _charging_handle: Node3D
var _flash: Node3D
var _hands: Dictionary = {}
var _forearms: Dictionary = {}
var _flash_time := 0.0
var _bolt_time := 0.0
var _phase := 0.0
var _last_reload := -1.0
var _last_heal := -1.0

func setup(view_model: bool) -> void:
	if configured:
		assert(first_person == view_model, "A rifle's presentation kind cannot change after setup")
		reset_pose()
		return
	configured = true
	first_person = view_model
	_build_assets()
	# A view model omits the shoulder stock behind the camera-side wrist. The
	# complete stock is present on every world model; muzzle/optic stay identical.
	_instance("Body",_assets.view_body if first_person else _assets.body,self)
	for socket_name: String in SOCKETS:
		var marker := Marker3D.new()
		marker.name = socket_name
		marker.position = SOCKETS[socket_name]
		add_child(marker)
	_magazine = Node3D.new()
	_magazine.name = "Magazine"
	add_child(_magazine)
	_instance("Shell",_assets.magazine,_magazine)
	_bolt = _instance("Bolt",_assets.bolt,self)
	_charging_handle = _instance("ChargingHandle",_assets.handle,self)
	_flash = Node3D.new()
	_flash.name = "Flash"
	_flash.position = SOCKETS.Muzzle
	add_child(_flash)
	_instance("MuzzleGas",_assets.flash,_flash)
	if first_person:
		var arms := Node3D.new()
		arms.name = "Arms"
		add_child(arms)
		for side in ["Right","Left"]:
			var hand := _instance(side+"Hand",_assets[side.to_lower()+"_hand"],arms)
			_hands[side] = hand
			var forearm := _instance(side+"Forearm",_assets.sleeve,arms)
			_forearms[side] = forearm
	reset_pose()

func _instance(node_name: String, mesh: Mesh, parent: Node3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if first_person else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	return instance

static func _material(color: Color, roughness: float, metallic := 0.0, fabric := false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	# Small deterministic baked texture: machining grain or woven textile.
	var texture := Image.create(64,64,false,Image.FORMAT_RGB8)
	for y in range(64):
		for x in range(64):
			var grain := float((x*197+y*67+x*y*13)%19)/19.0
			var weave := (0.91 if (x+y)%4 == 0 else 1.0) if fabric else 1.0
			var value := (0.88+grain*0.12)*weave
			texture.set_pixel(x,y,Color(value,value,value))
	texture.generate_mipmaps()
	result.albedo_texture = ImageTexture.create_from_image(texture)
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return result

static func _build_assets() -> void:
	if not _assets.is_empty(): return
	var steel := _material(Color(0.14,0.16,0.17),0.39,0.82)
	var edge := _material(Color(0.31,0.33,0.32),0.34,0.76)
	var polymer := _material(Color(0.19,0.205,0.18),0.77,0.04)
	var rubber := _material(Color(0.055,0.064,0.059),0.93)
	var recess := _material(Color(0.018,0.023,0.021),0.86)
	var tan := _material(Color(0.34,0.30,0.225),0.88,0.0,true)
	var glove := _material(Color(0.12,0.14,0.115),0.91,0.0,true)
	var dot := StandardMaterial3D.new()
	dot.albedo_color = Color(1,0.07,0.025)
	dot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.emission_enabled = true
	dot.emission = Color(1,0.04,0.015)
	dot.emission_energy_multiplier = 2.0
	var b = Builder.new()
	# Upper/lower receiver: distinct angular metal shells with bevel highlights.
	b.box(Vector3(0.112,0.105,0.31),Vector3(0,0.024,-0.035),steel,Vector3.ZERO,0.012)
	b.box(Vector3(0.10,0.073,0.205),Vector3(0,-0.048,-0.025),polymer,Vector3.ZERO,0.009)
	b.box(Vector3(0.115,0.077,0.105),Vector3(0,-0.063,-0.115),steel,Vector3.ZERO,0.008)
	# Handguard has a hollow-looking front, inset cooling slots and metal edge strips.
	b.box(Vector3(0.101,0.092,0.28),Vector3(0,0.019,-0.326),polymer,Vector3.ZERO,0.014)
	for side in [-1.0,1.0]:
		for i in range(5):
			var z := -0.225-float(i)*0.043
			b.box(Vector3(0.003,0.024,0.025),Vector3(side*0.0508,0.025,z),recess,Vector3.ZERO,0.001)
			b.box(Vector3(0.003,0.003,0.027),Vector3(side*0.052,0.038,z),edge)
		b.box(Vector3(0.008,0.009,0.245),Vector3(side*0.044,-0.026,-0.326),steel,Vector3.ZERO,0.002)
	# Exposed barrel, gas block, recessed crown and slotted muzzle brake.
	b.cylinder(0.014,0.209,Vector3(0,0.032,-0.5555),steel)
	b.cylinder(0.021,0.03,Vector3(0,0.032,-0.492),edge)
	b.cylinder(0.022,0.058,Vector3(0,0.032,-0.688),steel,Vector3(PI*0.5,0,0),12)
	b.cylinder(0.0125,0.001,Vector3(0,0.032,-0.719),recess,Vector3(PI*0.5,0,0),12)
	for side in [-1.0,1.0]:
		for i in range(3): b.box(Vector3(0.002,0.014,0.007),Vector3(side*0.021,0.032,-0.672-float(i)*0.014),recess)
	# Picatinny rail teeth use one batched mesh, not separate nodes.
	b.box(Vector3(0.037,0.013,0.49),Vector3(0,0.079,-0.205),steel,Vector3.ZERO,0.003)
	for i in range(22): b.box(Vector3(0.051,0.008,0.012),Vector3(0,0.089,-0.433+float(i)*0.022),edge,Vector3.ZERO,0.002)
	# Separate angled pistol grip, stippled inset and open trigger guard.
	b.box(Vector3(0.061,0.143,0.077),Vector3(0,-0.128,0.075),polymer,Vector3(-0.30,0,0),0.012)
	for side in [-1.0,1.0]:
		b.box(Vector3(0.003,0.087,0.045),Vector3(side*0.031,-0.14,0.078),rubber,Vector3(-0.3,0,0),0.001)
		for pin in [Vector3(side*0.058,0.026,0.061),Vector3(side*0.058,0.026,-0.137)]:
			b.cylinder(0.007,0.004,pin,edge,Vector3(0,0,PI*0.5),8)
	b.box(Vector3(0.019,0.012,0.10),Vector3(0,-0.102,-0.016),steel,Vector3.ZERO,0.003)
	b.box(Vector3(0.019,0.054,0.012),Vector3(0,-0.078,-0.060),steel,Vector3(0.15,0,0),0.003)
	b.box(Vector3(0.01,0.040,0.011),Vector3(0,-0.066,-0.009),edge,Vector3(0.2,0,0),0.002)
	# Ejection port is visibly recessed behind the animated bolt.
	b.box(Vector3(0.002,0.034,0.077),Vector3(0.057,0.032,-0.018),recess,Vector3.ZERO,0.001)
	b.box(Vector3(0.005,0.011,0.058),Vector3(0.060,0.007,-0.018),steel,Vector3.ZERO,0.003)
	# Reflex sight: empty window, thin housing, low base. Nothing opaque across Aim.
	b.box(Vector3(0.063,0.018,0.074),Vector3(0,0.103,-0.16),steel,Vector3.ZERO,0.004)
	for side in [-1.0,1.0]:
		b.box(Vector3(0.008,0.063,0.018),Vector3(side*0.035,0.145,-0.16),steel,Vector3(0,0,side*0.08),0.003)
	b.box(Vector3(0.065,0.007,0.018),Vector3(0,0.178,-0.16),steel,Vector3.ZERO,0.003)
	b.cylinder(0.012,0.013,Vector3(0.046,0.132,-0.16),rubber,Vector3(0,0,PI*0.5),10)
	b.ellipsoid(Vector3(0.0032,0.0032,0.0008),Vector3(0,0.145,-0.171),dot)
	_assets.view_body = b.finish()
	# Full world-model buffer tube, cheek rest, skeleton stock and shoulder pad.
	b.cylinder(0.022,0.20,Vector3(0,0.035,0.202),steel)
	b.box(Vector3(0.078,0.054,0.16),Vector3(0,0.037,0.253),polymer,Vector3.ZERO,0.009)
	b.box(Vector3(0.058,0.046,0.154),Vector3(0,-0.035,0.257),polymer,Vector3(-0.33,0,0),0.009)
	b.box(Vector3(0.082,0.167,0.036),Vector3(0,-0.024,0.351),polymer,Vector3(-0.13,0,0),0.008)
	b.box(Vector3(0.084,0.163,0.013),Vector3(0,-0.024,0.375),rubber,Vector3(-0.13,0,0),0.004)
	for i in range(8): b.box(Vector3(0.074,0.004,0.003),Vector3(0,-0.088+float(i)*0.018,0.384),recess)
	_assets.body = b.finish()
	# Curved magazine: three overlapping bevelled shell sections and ribs.
	b = Builder.new()
	b.box(Vector3(0.070,0.065,0.091),Vector3(0,-0.030,0),steel,Vector3.ZERO,0.005)
	b.box(Vector3(0.071,0.083,0.096),Vector3(0,-0.101,0.008),polymer,Vector3(-0.13,0,0),0.006)
	b.box(Vector3(0.072,0.080,0.096),Vector3(0,-0.175,0.025),polymer,Vector3(-0.25,0,0),0.006)
	b.box(Vector3(0.083,0.017,0.106),Vector3(0,-0.214,0.036),rubber,Vector3(-0.25,0,0),0.004)
	for side in [-1.0,1.0]:
		for rib in range(3): b.box(Vector3(0.003,0.126,0.006),Vector3(side*0.037,-0.132,-0.020+float(rib)*0.026),recess,Vector3(-0.20,0,0),0.001)
	_assets.magazine = b.finish()
	b = Builder.new()
	b.box(Vector3(0.004,0.022,0.050),Vector3(0.060,0.032,-0.018),edge,Vector3.ZERO,0.002)
	_assets.bolt = b.finish()
	b = Builder.new()
	b.box(Vector3(0.124,0.014,0.019),Vector3(0,0.061,0.122),steel,Vector3.ZERO,0.004)
	_assets.handle = b.finish()
	var fire := StandardMaterial3D.new()
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.albedo_color = Color(1.0,0.77,0.26)
	b = Builder.new()
	b.cylinder(0.023,0.095,Vector3(0,0,-0.045),fire,Vector3(-PI*0.5,0,0),7,0.001)
	b.ellipsoid(Vector3(0.039,0.039,0.035),Vector3(0,0,-0.012),fire)
	_assets.flash = b.finish()
	_assets.right_hand = _hand_mesh(true,glove,rubber,tan)
	_assets.left_hand = _hand_mesh(false,glove,rubber,tan)
	b = Builder.new()
	# Unit-height sleeve, shaped by per-frame wrist/elbow placement.
	b.cylinder(0.055,1.0,Vector3.ZERO,tan,Vector3.ZERO,10,0.037)
	b.cylinder(0.039,0.10,Vector3(0,0.45,0),glove,Vector3.ZERO,10)
	_assets.sleeve = b.finish()

static func _hand_mesh(right: bool, glove: Material, rubber: Material, trim: Material) -> ArrayMesh:
	var b = Builder.new()
	var s := 1.0 if right else -1.0
	# Palm and knuckles face outside; three joint finger arcs wrap the grip.
	b.ellipsoid(Vector3(0.040,0.084,0.074),Vector3(s*0.014,0,0),glove)
	b.box(Vector3(0.006,0.039,0.045),Vector3(s*0.033,0.008,-0.004),rubber,Vector3.ZERO,0.002)
	for finger in range(4):
		var y := 0.027-float(finger)*0.017
		var a := Vector3(s*0.020,y,-0.027)
		if right and finger == 0:
			# Trigger finger reaches forward into the open guard; the other three
			# fingers support the grip rather than all four making the same fist.
			var joint := Vector3(0.015,0.034,-0.063)
			var middle := Vector3(-0.017,0.029,-0.082)
			b.link(a,joint,0.009,0.008,glove,8)
			b.link(joint,middle,0.008,0.007,glove,8)
			b.link(middle,Vector3(-0.032,0.022,-0.080),0.007,0.006,rubber,8)
			continue
		var c := Vector3(-s*0.029,y,-0.018)
		var tip := Vector3(-s*0.036,y,0.010)
		b.link(a,Vector3(-s*0.010,y,-0.039),0.009,0.0085,glove,8)
		b.link(Vector3(-s*0.010,y,-0.039),c,0.0085,0.0075,glove,8)
		b.link(c,tip,0.0075,0.0065,rubber,8)
		b.ellipsoid(Vector3(0.020,0.015,0.019),a,rubber)
	# Thumb crosses the rear of the grip independently from four fingers.
	b.link(Vector3(s*0.019,-0.019,0.027),Vector3(s*0.003,0.015,0.041),0.012,0.009,glove,8)
	b.link(Vector3(s*0.003,0.015,0.041),Vector3(-s*0.025,0.026,0.025),0.009,0.007,glove,8)
	b.box(Vector3(0.037,0.012,0.049),Vector3(s*0.014,-0.043,0.013),trim,Vector3.ZERO,0.004)
	return b.finish()

func fire() -> void:
	if not configured: return
	_flash_time = 0.045
	_bolt_time = 0.10
	_flash.visible = true
	_flash.scale = Vector3.ONE

func reset_pose() -> void:
	if not configured: return
	_flash_time = 0.0
	_bolt_time = 0.0
	_phase = 0.0
	_last_reload = -1.0
	_last_heal = -1.0
	_flash.visible = false
	_flash.scale = Vector3.ONE
	_bolt.position = Vector3.ZERO
	_charging_handle.position = Vector3.ZERO
	_magazine.position = MAGAZINE_REST
	_magazine.rotation = Vector3.ZERO
	_update_hands(-1.0,-1.0,0.0)
	if first_person: get_node("Arms").visible = true

func step(delta: float, frame: Dictionary) -> void:
	if not configured: return
	var dt := clampf(delta if is_finite(delta) else 0.0,0.0,0.10)
	_flash_time = maxf(0.0,_flash_time-dt)
	_bolt_time = maxf(0.0,_bolt_time-dt)
	_flash.visible = _flash_time > 0.0 and not bool(frame.get("dead",false))
	_flash.scale = Vector3.ONE * (0.75+0.25*_flash_time/0.045)
	_bolt.position.z = sin((_bolt_time/0.10)*PI)*0.038
	var reload := _progress(frame.get("reload_progress",-1.0))
	var heal := _progress(frame.get("healing_progress",-1.0))
	_last_reload = reload
	_last_heal = heal
	# Reload is a pure function of the supplied phase, safe to seek after resume.
	_magazine.position = MAGAZINE_REST
	_magazine.rotation = Vector3.ZERO
	_charging_handle.position = Vector3.ZERO
	if reload >= 0.0:
		var out := _sample(reload,[0.0,0.18,0.38,0.56,0.73,1.0],[0.0,0.0,1.0,1.0,0.0,0.0])
		_magazine.position += Vector3(-0.13,-0.22,0.075)*out
		_magazine.rotation = Vector3(0.18,0.0,-0.28)*out
		var handle := _sample(reload,[0.0,0.83,0.89,0.94,1.0],[0.0,0.0,1.0,0.0,0.0])
		_charging_handle.position.z = handle*0.065
		_bolt.position.z = maxf(_bolt.position.z,handle*0.038)
	var speed := clampf(float(frame.get("speed",0.0)),0.0,12.0)
	_phase += dt * (3.4+speed*1.7)
	var breathing := sin(_phase)*0.0015 if reload < 0 and heal < 0 else 0.0
	_update_hands(reload,heal,breathing)
	if first_person: get_node("Arms").visible = not bool(frame.get("dead",false))

func _progress(value: Variant) -> float:
	var number := float(value)
	return clampf(number,0.0,1.0) if is_finite(number) and number >= 0 else -1.0

func _sample(t: float, times: Array, values: Array) -> float:
	for k in range(1,times.size()):
		if t <= float(times[k]):
			var amount := smoothstep(float(times[k-1]),float(times[k]),t)
			return lerpf(float(values[k-1]),float(values[k]),amount)
	return float(values.back())

func left_hand_target(t: float) -> Vector3:
	var grip: Vector3 = SOCKETS.GripLeft
	var times := [0.0,0.14,0.18,0.38,0.56,0.73,0.82,0.89,0.94,1.0]
	var mag_hold := MAGAZINE_REST+Vector3(-0.047,-0.10,0.005)
	var mag_out := mag_hold+Vector3(-0.13,-0.22,0.075)
	var handle_hold := Vector3(-0.063,0.06,0.12)
	var points := [grip,mag_hold,mag_hold,mag_out,mag_out,mag_hold,handle_hold,handle_hold+Vector3(0,0,0.065),handle_hold,grip]
	for k in range(1,times.size()):
		if t <= float(times[k]): return (points[k-1] as Vector3).lerp(points[k],smoothstep(float(times[k-1]),float(times[k]),t))
	return grip

func _update_hands(reload: float, heal: float, breathing: float) -> void:
	if not first_person: return
	var right: Node3D = _hands.Right
	var left: Node3D = _hands.Left
	right.position = SOCKETS.GripRight
	right.rotation = Vector3(-0.27,0,0.07)
	left.position = left_hand_target(reload) if reload >= 0.0 else SOCKETS.GripLeft
	left.rotation = Vector3(PI*0.5,0,-0.1)
	if reload >= 0:
		var grasp := _sample(reload,[0.0,0.14,0.73,0.82,0.94,1.0],[0.0,1.0,1.0,0.0,0.0,0.0])
		left.rotation = Vector3(lerpf(PI*0.5,0.0,grasp),0,-0.1-grasp*0.15)
	if heal >= 0:
		var activity := sin(heal*PI)
		left.position += Vector3(-0.08,-0.16,0.25)*activity
		left.rotation.z -= activity*0.6
	for side in ["Right","Left"]:
		var hand: Node3D = _hands[side]
		var sleeve: Node3D = _forearms[side]
		var wrist := hand.position+hand.basis*Vector3(0,-0.055,0.016)
		var elbow := Vector3(0.22,-0.26,0.34) if side == "Right" else Vector3(-0.24,-0.22,0.25)
		elbow.y += breathing
		var direction := wrist-elbow
		sleeve.transform = Transform3D(Basis(Quaternion(Vector3.UP,direction.normalized())).scaled_local(Vector3(1,direction.length(),1)),(wrist+elbow)*0.5)

func get_marker_position(marker_name: String) -> Vector3:
	var marker := get_node_or_null(NodePath(marker_name)) as Marker3D
	return marker.position if marker != null else Vector3.ZERO

func metrics() -> Dictionary:
	var result := {"triangles":0,"surfaces":0,"node_count":0,"mesh_instances":0,"reload_progress":_last_reload,"healing_progress":_last_heal,"body_bounds":get_node("Body").mesh.get_aabb() if configured else AABB()}
	_measure(self,result)
	return result

func _measure(node: Node, result: Dictionary) -> void:
	result.node_count += 1
	if node is MeshInstance3D:
		result.mesh_instances += 1
		var mesh: Mesh = node.mesh
		result.surfaces += mesh.get_surface_count()
		for surface in range(mesh.get_surface_count()):
			var count: int = mesh.surface_get_array_index_len(surface)
			result.triangles += (count if count > 0 else mesh.surface_get_array_len(surface))/3
	for child in node.get_children(): _measure(child,result)
