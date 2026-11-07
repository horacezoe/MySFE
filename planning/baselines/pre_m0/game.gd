extends Node3D

const MAP_SIZE = 60.0
var playing = false
var hp = 100.0
var ammo = 24
var reserve = 120
var meds = 3
var remaining = 360.0
var extract_time = 0.0
var fire_delay = 0.0
var reload_time = 0.0
var bag: Array = []
var enemies: Array = []
var crates: Array = []
var world: Node3D
var player: CharacterBody3D
var camera: Camera3D
var hud: CanvasLayer
var status: Label
var timer_label: Label
var notification: Label
var notify_time = 0.0
var menu: Control
var left_id = -1
var right_id = -1
var left_origin = Vector2.ZERO
var right_origin = Vector2.ZERO
var left_vec = Vector2.ZERO
var right_vec = Vector2.ZERO
var aim = Vector3(1,0,0)
var mouse_fire = false
var touch_fire = false
var third_person = true
var yaw = -2.35
var pitch = -0.10
var gun: Node3D
var view_button: Button
var search_ui: Control
var search_list: VBoxContainer
var bag_label: Label
var searching = false
var active_crate = null
var hit_marker: Label
var hit_time = 0.0
var damage_label: Label
var damage_time = 0.0
var shot_label: Label
var shot_time = 0.0
var recoil = 0.0
var move_phase = 0.0
var muzzle: Node3D
var sound_players: Array[AudioStreamPlayer] = []
var sound_index = 0
var shot_sound: AudioStreamWAV
var hit_sound: AudioStreamWAV
var reload_sound: AudioStreamWAV
var ground_material: StandardMaterial3D
var aim_hint: Label
var crouching = false
var touch_sprint = false
var jump_requested = false
var crouch_button: Button
var stance_height = 1.55
var wealth = 0
var wins = 0
var exit_pos = Vector3(25, 0, 25)
var rng = RandomNumberGenerator.new()

func _ready():
 rng.randomize()
 _load_save()
 _build_world()
 _build_ui()
 _build_audio()
 _show_menu("余烬行动 3D", "单人离线搜打撤\n搜索补给，击退巡逻者，带着战利品撤离。\n\n左侧拖动移动 · 右侧拖动观察 · 按住开火
点击“切换视角”在第一、第三人称之间切换\n靠近补给箱或撤离区后，点击交互按钮。\n\n电脑：点击画面锁定鼠标，自由转动视角；Esc 释放鼠标。WASD 移动，左键开火，V 切换视角，空格跳跃，Shift 快跑，C 蹲下。E 搜索，R 换弹，Q 治疗。")

func mat(c: Color, rough = 1.0) -> StandardMaterial3D:
 var m = StandardMaterial3D.new()
 m.albedo_color = c
 m.roughness = rough
 return m

func box(parent: Node3D, size: Vector3, position: Vector3, color: Color, solid = false) -> Node3D:
 var n: Node3D
 if solid:
  var b = StaticBody3D.new()
  var col = CollisionShape3D.new()
  var shape = BoxShape3D.new()
  shape.size = size
  col.shape = shape
  b.add_child(col)
  n = b
 else:
  n = Node3D.new()
 parent.add_child(n)
 n.position = position
 var mesh = MeshInstance3D.new()
 var cube = BoxMesh.new()
 cube.size = size
 mesh.mesh = cube
 mesh.material_override = mat(color)
 n.add_child(mesh)
 return n

func character(parent: Node3D, color: Color, pos: Vector3) -> CharacterBody3D:
 var body = CharacterBody3D.new()
 parent.add_child(body)
 body.position = pos
 var col = CollisionShape3D.new()
 var shape = CapsuleShape3D.new()
 shape.radius = 0.48
 shape.height = 1.7
 col.shape = shape
 col.position.y = 0.9
 col.name="BodyCollider"
 body.add_child(col)
 var visual=Node3D.new()
 visual.name="Visual"
 body.add_child(visual)
 box(visual,Vector3(0.64,0.72,0.37),Vector3(0,1.05,0),color.darkened(0.14))
 box(visual,Vector3(0.66,0.55,0.42),Vector3(0,1.03,-0.04),Color("68715a") if color.g>color.r else Color("6b5b50"))
 box(visual,Vector3(0.54,0.16,0.15),Vector3(0,0.86,-0.26),Color("394238"))
 for x in [-0.18,0.0,0.18]: box(visual,Vector3(0.14,0.20,0.10),Vector3(x,0.99,-0.29),Color("414b3b"))
 box(visual,Vector3(0.48,0.52,0.22),Vector3(0,1.08,0.29),Color("424c3d"))
 for x in [-0.20,0.20]:
  var leg=box(visual,Vector3(0.22,0.62,0.24),Vector3(x,0.38,0),Color("454d3e"))
  leg.name="LeftLeg" if x<0 else "RightLeg"
  box(visual,Vector3(0.24,0.12,0.32),Vector3(x,0.08,-0.045),Color("292f28"))
 for x in [-0.42,0.42]:
  box(visual,Vector3(0.20,0.55,0.24),Vector3(x,1.00,0),color.darkened(0.2))
  box(visual,Vector3(0.22,0.12,0.26),Vector3(x,1.23,0),Color("5e6854"))
 var head = MeshInstance3D.new()
 var sphere = SphereMesh.new()
 sphere.radius = 0.29
 sphere.height = 0.58
 head.mesh = sphere
 head.material_override = mat(Color("cbb99a"))
 head.position.y = 1.62
 visual.add_child(head)
 var helmet=MeshInstance3D.new()
 var helm=SphereMesh.new(); helm.radius=0.31; helm.height=0.35
 helmet.mesh=helm; helmet.material_override=mat(Color("525d4a")); helmet.position.y=1.80; visual.add_child(helmet)
 box(visual,Vector3(0.48,0.10,0.04),Vector3(0,1.68,-0.265),Color("222d2a"))
 var carried=Node3D.new()
 visual.add_child(carried)
 carried.name="CarriedRifle"
 carried.position=Vector3(0.38,1.2,-0.2)
 carried.scale=Vector3.ONE*0.8
 _rifle(carried,false)
 return body

func _rifle(parent: Node3D, first_person: bool) -> Node3D:
 var metal=Color("292e2b")
 var polymer=Color("454a3b")
 var dark=Color("171c1a")
 box(parent,Vector3(0.14,0.17,0.43),Vector3(0,0,0),metal)
 box(parent,Vector3(0.11,0.12,0.34),Vector3(0,0.015,-0.37),polymer)
 var barrel=MeshInstance3D.new()
 var barrel_mesh=CylinderMesh.new(); barrel_mesh.top_radius=0.027; barrel_mesh.bottom_radius=0.027; barrel_mesh.height=0.36
 barrel.mesh=barrel_mesh; barrel.material_override=mat(dark); barrel.rotation_degrees.x=90; barrel.position=Vector3(0,0.03,-0.67); parent.add_child(barrel)
 for z in [-0.47,-0.39,-0.31,-0.23]:
  box(parent,Vector3(0.125,0.018,0.025),Vector3(0,0.075,z),Color("252a27"))
 box(parent,Vector3(0.02,0.035,0.17),Vector3(0.075,0.005,-0.01),Color("697063"))
 box(parent,Vector3(0.09,0.09,0.08),Vector3(0,0.03,-0.85),metal)
 box(parent,Vector3(0.12,0.10,0.24),Vector3(0,-0.01,0.31),polymer)
 var stock=box(parent,Vector3(0.15,0.17,0.09),Vector3(0,-0.015,0.46),dark)
 var magazine=box(parent,Vector3(0.105,0.23,0.15),Vector3(0,-0.18,-0.08),Color("353a33"))
 magazine.rotation_degrees.x=-12
 var grip=box(parent,Vector3(0.09,0.22,0.10),Vector3(0,-0.17,0.12),dark)
 grip.rotation_degrees.x=-18
 box(parent,Vector3(0.07,0.04,0.38),Vector3(0,0.11,-0.04),dark)
 box(parent,Vector3(0.11,0.09,0.15),Vector3(0,0.17,-0.05),Color("363b37"))
 box(parent,Vector3(0.075,0.035,0.045),Vector3(0,0.225,-0.08),Color("83a095"))
 box(parent,Vector3(0.055,0.09,0.05),Vector3(0,0.12,-0.58),dark)
 if first_person:
  var hand=box(parent,Vector3(0.19,0.15,0.30),Vector3(0.10,-0.20,0.10),Color("606751"))
  hand.rotation_degrees.z=-22
  var forearm=box(parent,Vector3(0.18,0.18,0.38),Vector3(0.18,-0.25,0.35),Color("495644"))
  forearm.rotation_degrees.z=-18
 var flash=Node3D.new()
 parent.add_child(flash)
 flash.position=Vector3(0,0.03,-0.92)
 for angle in [0.0,60.0,120.0]:
  var blade=box(flash,Vector3(0.05,0.38,0.045),Vector3.ZERO,Color("ffcc6c"))
  blade.rotation_degrees.z=angle
 flash.visible=false
 return flash

func _build_audio():
 shot_sound=_synth_sound("shot")
 hit_sound=_synth_sound("hit")
 reload_sound=_synth_sound("reload")
 for i in range(6):
  var audio=AudioStreamPlayer.new()
  audio.volume_db=-8
  add_child(audio)
  sound_players.append(audio)

func _synth_sound(kind: String) -> AudioStreamWAV:
 var rate=22050
 var duration=0.22 if kind=="shot" else 0.09 if kind=="hit" else 0.34
 var count=int(rate*duration)
 var data=PackedByteArray()
 data.resize(count*2)
 for i in range(count):
  var t=float(i)/rate
  var v=0.0
  if kind=="shot":
   v=(rng.randf_range(-1,1)*exp(-t*35.0)*0.7 + sin(TAU*(95.0*t-100.0*t*t))*exp(-t*20.0)*0.6)
  elif kind=="hit":
   v=sin(TAU*1250*t)*exp(-t*45.0)*0.35
  else:
   var burst=exp(-abs(t-0.035)*95.0)+exp(-abs(t-0.21)*90.0)
   v=(rng.randf_range(-1,1)*0.4+sin(TAU*1800*t)*0.15)*burst
  data.encode_s16(i*2,int(clampf(v,-1.0,1.0)*22000))
 var stream=AudioStreamWAV.new()
 stream.format=AudioStreamWAV.FORMAT_16_BITS
 stream.mix_rate=rate
 stream.stereo=false
 stream.data=data
 return stream

func _play_sound(stream: AudioStreamWAV):
 var audio=sound_players[sound_index]
 sound_index=(sound_index+1)%sound_players.size()
 audio.stream=stream
 audio.pitch_scale=rng.randf_range(0.95,1.05)
 audio.play()

func _tracer(from: Vector3, to: Vector3):
 var length=from.distance_to(to)
 if length<0.1: return
 var node=MeshInstance3D.new()
 var beam=BoxMesh.new()
 beam.size=Vector3(0.035,0.035,length)
 node.mesh=beam
 var glow=mat(Color("ffd18a"))
 glow.emission_enabled=true
 glow.emission=Color("ffae53")
 glow.emission_energy_multiplier=1.5
 node.material_override=glow
 world.add_child(node)
 node.global_position=(from+to)*0.5
 node.look_at(to,Vector3.UP)
 var tween=create_tween()
 tween.tween_interval(0.07)
 tween.tween_callback(node.queue_free)

func _ground_texture() -> StandardMaterial3D:
 var image=Image.create(128,128,false,Image.FORMAT_RGB8)
 var noise=FastNoiseLite.new(); noise.seed=731; noise.frequency=0.065
 for y in range(128):
  for x in range(128):
   var n=noise.get_noise_2d(x,y)*0.09
   var grain=sin(float(x)*13.1+float(y)*17.9)*0.012
   image.set_pixel(x,y,Color(0.31+n+grain,0.36+n+grain,0.29+n+grain))
 var material=StandardMaterial3D.new()
 material.albedo_texture=ImageTexture.create_from_image(image)
 material.roughness=0.95
 return material

func _build_world():
 world = Node3D.new()
 add_child(world)
 var env = WorldEnvironment.new()
 var environment = Environment.new()
 environment.background_mode = Environment.BG_SKY
 var sky=Sky.new()
 var sky_material=ProceduralSkyMaterial.new()
 sky_material.sky_top_color=Color("526c75"); sky_material.sky_horizon_color=Color("bac6b6")
 sky_material.ground_bottom_color=Color("465447"); sky_material.ground_horizon_color=Color("a3af9b")
 sky.sky_material=sky_material
 environment.sky=sky
 environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
 environment.fog_enabled=true
 environment.fog_light_color=Color("aebbb0")
 environment.fog_density=0.008
 environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 environment.ambient_light_color = Color("d1e0ca")
 environment.ambient_light_energy = 0.8
 env.environment = environment
 world.add_child(env)
 var light = DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-55,-30,0)
 light.light_energy = 1.1
 light.shadow_enabled = false
 world.add_child(light)
 box(world,Vector3(64,0.5,64),Vector3(0,-0.3,0),Color("526552"),true)
 ground_material=_ground_texture()
 for x in range(-30,31,10):
  for z in range(-30,31,10):
   var tile=box(world,Vector3(10,0.02,10),Vector3(x,0,z),Color("586c57"))
   tile.get_child(0).material_override=ground_material
 for v in [Vector4(-18,-14,10,2),Vector4(-13,-9,2,8),Vector4(-3,-20,12,2),Vector4(9,-12,2,12),Vector4(20,-20,10,2),Vector4(-19,4,12,2),Vector4(-6,7,2,12),Vector4(5,3,11,2),Vector4(16,10,2,10),Vector4(-17,20,10,2),Vector4(3,20,10,2)]:
  box(world,Vector3(v.z,2.8,v.w),Vector3(v.x,1.4,v.y),Color("777d6d"),true)
  box(world,Vector3(v.z+0.1,0.15,v.w+0.1),Vector3(v.x,2.72,v.y),Color("505950"))
  if v.z>v.w:
   for offset in range(-int(v.z/2)+1,int(v.z/2),2):
    box(world,Vector3(0.06,2.5,0.05),Vector3(v.x+offset,1.3,v.y-v.w/2-0.04),Color("626a5f"))
  else:
   for offset in range(-int(v.w/2)+1,int(v.w/2),2):
    box(world,Vector3(0.05,2.5,0.06),Vector3(v.x-v.z/2-0.04,1.3,v.y+offset),Color("626a5f"))
 for p in [Vector3(-32,1,0),Vector3(32,1,0)]: box(world,Vector3(1,2,65),p,Color("536256"),true)
 for p in [Vector3(0,1,-32),Vector3(0,1,32)]: box(world,Vector3(65,2,1),p,Color("536256"),true)
 var decor_rng=RandomNumberGenerator.new(); decor_rng.seed=1873
 for i in range(90):
  var x=decor_rng.randf_range(-29,29); var z=decor_rng.randf_range(-29,29)
  var shrub=Node3D.new(); world.add_child(shrub); shrub.position=Vector3(x,0,z)
  for j in range(3):
   var blade=box(shrub,Vector3(0.05,decor_rng.randf_range(0.18,0.42),0.28),Vector3((j-1)*0.12,0.15,0),Color("65765c"))
   blade.rotation.y=decor_rng.randf_range(0,PI)
 for p in [Vector3(-23,0,5),Vector3(12,0,-23),Vector3(21,0,13),Vector3(-4,0,23),Vector3(0,0,-10)]:
  box(world,Vector3(2.6,0.12,1.9),p+Vector3(0,0.08,0),Color("625d4c"))
  for i in range(3): box(world,Vector3(0.75,0.55,0.85),p+Vector3((i-1)*0.82,0.39,0),Color("756f59"))
 var ex = MeshInstance3D.new()
 var cyl = CylinderMesh.new()
 cyl.top_radius = 3.2
 cyl.bottom_radius = 3.2
 cyl.height = 0.07
 ex.mesh = cyl
 ex.material_override = mat(Color("a6d879"))
 ex.position = exit_pos + Vector3(0,0.07,0)
 world.add_child(ex)
 camera = Camera3D.new()
 world.add_child(camera)
 camera.projection = Camera3D.PROJECTION_PERSPECTIVE
 camera.fov = 70
 camera.current = true
 gun=Node3D.new()
 camera.add_child(gun)
 gun.position=Vector3(0.29,-0.23,-0.55)
 muzzle=_rifle(gun,true)
 gun.visible=false

func _reset():
 for e in enemies:
  if is_instance_valid(e.node): e.node.queue_free()
 for c in crates:
  if is_instance_valid(c.node): c.node.queue_free()
 enemies.clear()
 crates.clear()
 if is_instance_valid(player): player.queue_free()
 player = character(world,Color("b7d88d"),Vector3(-26,0,-26))
 hp=100; ammo=24; reserve=120; meds=3; remaining=360; extract_time=0; reload_time=0; fire_delay=0
 crouching=false; touch_sprint=false; jump_requested=false; stance_height=1.55
 if is_instance_valid(crouch_button): crouch_button.text="蹲下"
 bag.clear()
 left_id=-1; right_id=-1; left_vec=Vector2.ZERO; right_vec=Vector2.ZERO; touch_fire=false; mouse_fire=false
 yaw=-2.35; pitch=-0.1
 _apply_view()
 var enemy_points = [Vector3(-18,0,-19),Vector3(-8,0,-12),Vector3(4,0,-18),Vector3(18,0,-7),Vector3(-21,0,12),Vector3(-2,0,0),Vector3(8,0,12),Vector3(-4,0,25),Vector3(23,0,17)]
 for p in enemy_points:
  enemies.append({"node":character(world,Color("b86a55"),p),"hp":75.0,"cool":rng.randf_range(0.5,2.0),"origin":p})
 var points = [Vector3(-22,0,-22),Vector3(-10,0,-17),Vector3(0,0,-25),Vector3(15,0,-24),Vector3(24,0,-12),Vector3(-23,0,-2),Vector3(-11,0,0),Vector3(1,0,-5),Vector3(13,0,0),Vector3(24,0,4),Vector3(-24,0,18),Vector3(-12,0,16),Vector3(1,0,14),Vector3(9,0,25),Vector3(21,0,22)]
 var names = ["医疗物资","军用电池","加密芯片","精密零件","稀有合金","军用口粮","战术手表","电子元件"]
 var values = [120,180,320,150,250,80,280,140]
 for p in points:
  var contents=[]
  for n in range(rng.randi_range(2,4)):
   var idx = rng.randi_range(0,names.size()-1)
   contents.append({"name":names[idx],"value":values[idx]})
  crates.append({"node":box(world,Vector3(1,0.8,1),p+Vector3(0,0.4,0),Color("d5a35b")),"items":contents,"opened":false})
 playing=true
 searching=false
 search_ui.visible=false
 menu.visible=false
 _toast("搜索橙色补给箱，前往绿色撤离区",5)

func _build_ui():
 hud = CanvasLayer.new()
 add_child(hud)
 var root = Control.new()
 root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 root.mouse_filter=Control.MOUSE_FILTER_IGNORE
 hud.add_child(root)
 status = Label.new(); status.position=Vector2(20,18); status.add_theme_font_size_override("font_size",22); root.add_child(status)
 timer_label = Label.new(); timer_label.position=Vector2(960,18); timer_label.add_theme_font_size_override("font_size",22); root.add_child(timer_label)
 notification=Label.new(); notification.position=Vector2(320,75); notification.add_theme_font_size_override("font_size",20); root.add_child(notification)
 var names = ["搜索 / 撤离","治疗","换弹","暂停","切换视角"]
 for i in range(names.size()):
  var b=Button.new(); b.text=names[i]; b.position=Vector2(245+i*140,650); b.size=Vector2(132,52); b.add_theme_font_size_override("font_size",19); b.focus_mode=Control.FOCUS_NONE; root.add_child(b)
  match i:
   0: b.pressed.connect(_interact)
   1: b.pressed.connect(_heal)
   2: b.pressed.connect(_reload)
   3: b.pressed.connect(_pause_game)
   4: view_button=b; b.pressed.connect(_toggle_view)
 var fire_button=Button.new(); fire_button.text="开火"; fire_button.position=Vector2(1100,530); fire_button.size=Vector2(135,100); fire_button.add_theme_font_size_override("font_size",26); fire_button.focus_mode=Control.FOCUS_NONE; root.add_child(fire_button)
 fire_button.button_down.connect(func(): touch_fire=true)
 fire_button.button_up.connect(func(): touch_fire=false)
 var jump_button=Button.new(); jump_button.text="跳跃"; jump_button.position=Vector2(1130,400); jump_button.size=Vector2(105,72); jump_button.add_theme_font_size_override("font_size",23); root.add_child(jump_button)
 jump_button.pressed.connect(_jump)
 crouch_button=Button.new(); crouch_button.text="蹲下"; crouch_button.position=Vector2(1010,540); crouch_button.size=Vector2(85,90); crouch_button.add_theme_font_size_override("font_size",22); root.add_child(crouch_button)
 crouch_button.pressed.connect(_toggle_crouch)
 var sprint_button=Button.new(); sprint_button.text="快跑\n按住"; sprint_button.position=Vector2(35,410); sprint_button.size=Vector2(95,85); sprint_button.add_theme_font_size_override("font_size",20); root.add_child(sprint_button)
 sprint_button.button_down.connect(func(): touch_sprint=true)
 sprint_button.button_up.connect(func(): touch_sprint=false)
 var cross=Label.new(); cross.text="+"; cross.position=Vector2(630,337); cross.add_theme_font_size_override("font_size",30); cross.mouse_filter=Control.MOUSE_FILTER_IGNORE; root.add_child(cross)
 hit_marker=Label.new(); hit_marker.text="×"; hit_marker.position=Vector2(621,325); hit_marker.add_theme_font_size_override("font_size",48); hit_marker.add_theme_color_override("font_color",Color("ffdc85")); hit_marker.visible=false; root.add_child(hit_marker)
 damage_label=Label.new(); damage_label.position=Vector2(590,285); damage_label.add_theme_font_size_override("font_size",24); damage_label.add_theme_color_override("font_color",Color("ffb084")); damage_label.visible=false; root.add_child(damage_label)
 shot_label=Label.new(); shot_label.text="◆"; shot_label.position=Vector2(623,377); shot_label.add_theme_font_size_override("font_size",22); shot_label.add_theme_color_override("font_color",Color("ffdf82")); shot_label.visible=false; root.add_child(shot_label)
 search_ui=Control.new(); search_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.add_child(search_ui)
 var shade=ColorRect.new(); shade.color=Color(0.02,0.04,0.03,0.9); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); search_ui.add_child(shade)
 var layout=HBoxContainer.new(); layout.position=Vector2(120,85); layout.size=Vector2(1040,540); layout.add_theme_constant_override("separation",45); search_ui.add_child(layout)
 var left=VBoxContainer.new(); left.custom_minimum_size=Vector2(495,0); left.add_theme_constant_override("separation",12); layout.add_child(left)
 var search_title=Label.new(); search_title.text="补给箱  /  搜索结果"; search_title.add_theme_font_size_override("font_size",30); left.add_child(search_title)
 var hint=Label.new(); hint.text="选择物资放入背包；每个格子可携带一件。"; hint.add_theme_font_size_override("font_size",18); left.add_child(hint)
 search_list=VBoxContainer.new(); search_list.add_theme_constant_override("separation",8); left.add_child(search_list)
 var right=VBoxContainer.new(); right.custom_minimum_size=Vector2(470,0); right.add_theme_constant_override("separation",15); layout.add_child(right)
 var bag_title=Label.new(); bag_title.text="行动背包  /  8 格"; bag_title.add_theme_font_size_override("font_size",30); right.add_child(bag_title)
 bag_label=Label.new(); bag_label.add_theme_font_size_override("font_size",20); right.add_child(bag_label)
 var take_all=Button.new(); take_all.text="全部拾取"; take_all.custom_minimum_size=Vector2(0,54); take_all.add_theme_font_size_override("font_size",21); take_all.pressed.connect(_take_all); right.add_child(take_all)
 var close=Button.new(); close.text="关闭搜索，继续行动"; close.custom_minimum_size=Vector2(0,54); close.add_theme_font_size_override("font_size",21); close.pressed.connect(_close_search); right.add_child(close)
 search_ui.visible=false
 menu=Control.new(); menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.add_child(menu)
 var bg=ColorRect.new(); bg.color=Color(0.03,0.07,0.06,0.92); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); menu.add_child(bg)
 var panel=VBoxContainer.new(); panel.position=Vector2(290,100); panel.size=Vector2(700,520); panel.add_theme_constant_override("separation",24); menu.add_child(panel)
 var title=Label.new(); title.name="Title"; title.add_theme_font_size_override("font_size",54); panel.add_child(title)
 var body=Label.new(); body.name="Body"; body.add_theme_font_size_override("font_size",23); body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; panel.add_child(body)
 var info=Label.new(); info.name="Info"; info.add_theme_font_size_override("font_size",20); panel.add_child(info)
 var start=Button.new(); start.name="Start"; start.text="进入封锁区"; start.custom_minimum_size=Vector2(240,60); start.add_theme_font_size_override("font_size",24); start.pressed.connect(_reset); panel.add_child(start)

func _show_menu(title: String, text: String):
 playing=false
 Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 mouse_fire=false; touch_fire=false
 var panel=menu.get_child(1)
 panel.get_node("Title").text=title
 panel.get_node("Body").text=text
 panel.get_node("Info").text="仓库资产：%d 点   ·   成功撤离：%d 次" % [wealth,wins]
 panel.get_node("Start").text="再次进入" if wins>0 or hp<=0 else "进入封锁区"
 menu.visible=true

func _toast(text: String, duration=2.5):
 notification.text=text
 notify_time=duration

func _interact():
 if not playing: return
 if player.position.distance_to(exit_pos)<3.6:
  if extract_time<=0: extract_time=5.0; _toast("撤离信号已发送，留在绿色区域 5 秒",4)
  return
 for c in crates:
  if player.position.distance_to(c.node.position)<2.3:
   active_crate=c
   c.opened=true
   c.node.get_child(0).material_override=mat(Color("8b9a77"))
   searching=true
   Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
   touch_fire=false; touch_sprint=false; mouse_fire=false; left_id=-1; right_id=-1; left_vec=Vector2.ZERO
   _refresh_search()
   search_ui.visible=true
   return
 _toast("附近没有可搜索的补给箱")

func _refresh_search():
 for child in search_list.get_children(): child.queue_free()
 if active_crate.items.is_empty():
  var empty=Label.new(); empty.text="箱内没有剩余物资"; empty.add_theme_font_size_override("font_size",22); search_list.add_child(empty)
 for item in active_crate.items:
  var row=Button.new()
  row.text="%s    ·    %d 点     ＋拾取" % [item.name,item.value]
  row.custom_minimum_size=Vector2(0,57)
  row.add_theme_font_size_override("font_size",20)
  row.pressed.connect(_take_item.bind(item))
  search_list.add_child(row)
 var text="已使用 %d / 8 格\n\n" % bag.size()
 var total=0
 for item in bag:
  text += "%s    %d 点\n" % [item.name,item.value]
  total+=item.value
 text += "\n总价值：%d 点" % total
 bag_label.text=text

func _take_item(item):
 if bag.size()>=8: _toast("背包已满"); return
 if active_crate.items.has(item):
  bag.append(item)
  active_crate.items.erase(item)
 _refresh_search()

func _take_all():
 while not active_crate.items.is_empty() and bag.size()<8:
  bag.append(active_crate.items.pop_front())
 _refresh_search()

func _close_search():
 searching=false
 search_ui.visible=false
 _toast("搜索结束，继续行动",1.5)

func _heal():
 if not playing: return
 if meds>0 and hp<100:
  meds-=1; hp=minf(100,hp+45); _toast("使用医疗包")
 else: _toast("生命值已满或医疗包不足")

func _reload():
 if playing and reload_time<=0 and ammo<24 and reserve>0:
  reload_time=1.2; _play_sound(reload_sound); _toast("正在换弹…",1.2)

func _pause_game():
 if not playing: return
 playing=false
 Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 mouse_fire=false; touch_fire=false
 var panel=menu.get_child(1)
 panel.get_node("Title").text="行动暂停"
 panel.get_node("Body").text="休息一下。继续行动后计时恢复。"
 panel.get_node("Info").text=""
 var b=panel.get_node("Start")
 b.text="继续行动"
 b.pressed.disconnect(_reset)
 b.pressed.connect(_resume,CONNECT_ONE_SHOT)
 menu.visible=true

func _resume():
 menu.visible=false; playing=true
 var b=menu.get_child(1).get_node("Start")
 if not b.pressed.is_connected(_reset): b.pressed.connect(_reset)

func _save():
 var f=FileAccess.open("user://progress.json",FileAccess.WRITE)
 if f: f.store_string(JSON.stringify({"wealth":wealth,"wins":wins}))
func _load_save():
 if FileAccess.file_exists("user://progress.json"):
  var data=JSON.parse_string(FileAccess.get_file_as_string("user://progress.json"))
  if data is Dictionary: wealth=int(data.get("wealth",0)); wins=int(data.get("wins",0))

func _finish(success: bool, why: String):
 var total=0
 for c in bag: total+=int(c.value)
 if success:
  wealth+=total; wins+=1; _save()
  _show_menu("撤离成功", "安全带回 %d 件物资，价值 %d 点。\n%s" % [bag.size(),total,why])
 else: _show_menu("行动结束",why+"\n本局携带的物资已丢失。")

func _jump():
 if not playing or searching: return
 jump_requested=true

func _toggle_crouch():
 if not playing or searching: return
 crouching=not crouching
 crouch_button.text="起身" if crouching else "蹲下"

func _toggle_view():
 third_person=not third_person
 _apply_view()
 _toast("第三人称" if third_person else "第一人称",1.5)

func _apply_view():
 if not is_instance_valid(player): return
 for child in player.get_children():
  if child is Node3D and not child is CollisionShape3D: child.visible=third_person
 gun.visible=not third_person
 if is_instance_valid(view_button): view_button.text="切换：第三人称" if third_person else "切换：第一人称"

func _unhandled_input(event):
 if not playing or searching: return
 if event is InputEventScreenTouch:
  if event.pressed:
   if event.position.x<640 and left_id==-1: left_id=event.index; left_origin=event.position
   elif event.position.x>=640 and right_id==-1: right_id=event.index; right_origin=event.position
  else:
   if event.index==left_id: left_id=-1; left_vec=Vector2.ZERO
   if event.index==right_id: right_id=-1; right_vec=Vector2.ZERO
 elif event is InputEventScreenDrag:
  if event.index==left_id: left_vec=((event.position-left_origin)/65.0).limit_length(1.0)
  if event.index==right_id:
   yaw-=event.relative.x*0.006
   pitch=clampf(pitch-event.relative.y*0.004,-0.65,0.5)
 elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
  if event.pressed and Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED: Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
  mouse_fire=event.pressed
 elif event is InputEventMouseMotion and (Input.mouse_mode==Input.MOUSE_MODE_CAPTURED or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
  yaw-=event.relative.x*0.006
  pitch=clampf(pitch-event.relative.y*0.004,-0.65,0.5)
 elif event is InputEventKey and event.pressed and not event.echo:
  match event.keycode:
   KEY_E: _interact()
   KEY_Q: _heal()
   KEY_R: _reload()
   KEY_V: _toggle_view()
   KEY_SPACE: _jump()
   KEY_C: _toggle_crouch()
   KEY_ESCAPE: Input.mouse_mode=Input.MOUSE_MODE_VISIBLE; mouse_fire=false

func _physics_process(delta):
 if not playing or searching: return
 if hit_time>0:
  hit_time-=delta
  if hit_time<=0: hit_marker.visible=false
 if damage_time>0:
  damage_time-=delta
  if damage_time<=0: damage_label.visible=false
 if shot_time>0:
  shot_time-=delta
  if shot_time<=0: shot_label.visible=false; muzzle.visible=false
 recoil=move_toward(recoil,0.0,delta*5.5)
 if reload_time>0:
  gun.rotation.z=lerpf(gun.rotation.z,-0.65,delta*8)
 else:
  gun.rotation.z=lerpf(gun.rotation.z,0.0,delta*8)
 remaining-=delta
 if remaining<=0: _finish(false,"行动时间耗尽。"); return
 if notify_time>0:
  notify_time-=delta
  if notify_time<=0: notification.text=""
 if reload_time>0:
  reload_time-=delta
  if reload_time<=0:
   var count=mini(24-ammo,reserve); ammo+=count; reserve-=count
 var move2=left_vec
 if left_id==-1:
  move2=Vector2(float(Input.is_key_pressed(KEY_D))-float(Input.is_key_pressed(KEY_A)),float(Input.is_key_pressed(KEY_S))-float(Input.is_key_pressed(KEY_W))).limit_length(1)
 yaw += (float(Input.is_key_pressed(KEY_LEFT))-float(Input.is_key_pressed(KEY_RIGHT)))*1.8*delta
 aim=Vector3(-sin(yaw),0,-cos(yaw)).normalized()
 var side=Vector3(cos(yaw),0,-sin(yaw))
 var sprinting=(touch_sprint or Input.is_key_pressed(KEY_SHIFT)) and not crouching
 var speed=3.3 if crouching else 10.0 if sprinting else 6.5
 var movement=(side*move2.x-aim*move2.y)*speed
 player.velocity.x=movement.x; player.velocity.z=movement.z
 if jump_requested:
  if player.is_on_floor():
   if crouching: _toggle_crouch()
   player.velocity.y=7.4
  jump_requested=false
 if not player.is_on_floor(): player.velocity.y-=20.0*delta
 elif player.velocity.y<0: player.velocity.y=-0.1
 var collider=player.get_node("BodyCollider")
 collider.shape.height=1.05 if crouching else 1.7
 collider.position.y=0.575 if crouching else 0.9
 var visual=player.get_node("Visual")
 visual.scale.y=move_toward(visual.scale.y,0.62 if crouching else 1.0,delta*3.0)
 stance_height=move_toward(stance_height,0.96 if crouching else 1.55,delta*3.0)
 player.move_and_slide()
 move_phase+=delta*(12.0 if sprinting else 8.0)*minf(move2.length(),1.0)
 var stride=sin(move_phase)*0.4*move2.length() if player.is_on_floor() else 0.12
 visual.get_node("LeftLeg").rotation.x=stride
 visual.get_node("RightLeg").rotation.x=-stride
 var sway=sin(move_phase)*0.009*move2.length()
 gun.position=Vector3(0.29+sway,-0.23-abs(sway)*0.5,-0.55+recoil*0.10)
 gun.rotation.x=recoil*0.15
 player.rotation.y=yaw
 var carried=player.get_node_or_null("Visual/CarriedRifle")
 if carried: carried.rotation.x=pitch
 var view_dir=Vector3(aim.x*cos(pitch),sin(pitch),aim.z*cos(pitch)).normalized()
 var eye=player.position+Vector3(0,stance_height,0)
 if third_person:
  var desired=eye-aim*4.5+side*0.85+Vector3(0,0.65,0)
  var q=PhysicsRayQueryParameters3D.create(eye,desired)
  var ignored: Array[RID]=[player.get_rid()]
  for e in enemies:
   if is_instance_valid(e.node): ignored.append(e.node.get_rid())
  q.exclude=ignored
  var hit=get_world_3d().direct_space_state.intersect_ray(q)
  camera.position=hit.position+(eye-desired).normalized()*0.2 if not hit.is_empty() else desired
 else: camera.position=eye
 for child in player.get_children():
  if child is Node3D and not child is CollisionShape3D: child.visible=third_person and camera.position.distance_to(eye)>1.3
 if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): mouse_fire=false
 camera.look_at(camera.position+view_dir,Vector3.UP)
 fire_delay-=delta
 if (touch_fire or mouse_fire) and fire_delay<=0 and reload_time<=0:
  if ammo>0:
   ammo-=1; fire_delay=0.16; shot_time=0.08; shot_label.visible=true; muzzle.visible=true; recoil=1.0; pitch=clampf(pitch+0.008,-0.65,0.5); _play_sound(shot_sound); _fire()
  elif reserve>0: _reload()
 for e in enemies:
  var node: CharacterBody3D=e.node
  if not is_instance_valid(node): continue
  var d=node.position.distance_to(player.position)
  if d<16:
   var direction=(player.position-node.position).normalized()
   node.rotation.y=atan2(-direction.x,-direction.z)
   if d>7: node.velocity=direction*2.3; node.move_and_slide()
   e.cool-=delta
   if d<13 and e.cool<=0 and _visible(node.position,player.position,node):
    hp-=7; e.cool=rng.randf_range(0.9,1.5)
    damage_label.text="受到攻击 -7"; damage_label.add_theme_color_override("font_color",Color("ff6b59")); damage_label.visible=true; damage_time=0.8
    if hp<=0: _finish(false,"你在封锁区中倒下了。"); return
 if extract_time>0:
  if player.position.distance_to(exit_pos)>3.6: extract_time=0; _toast("已离开撤离区，撤离取消")
  else:
   extract_time-=delta
   if extract_time<=0: _finish(true,""); return
 var value=0
 for c in bag: value+=int(c.value)
 status.text="生命 %d   弹药 %d/%d   医疗 %d   背包 %d/8 · %d 点" % [hp,ammo,reserve,meds,bag.size(),value]
 timer_label.text="撤离 %.1f 秒" % extract_time if extract_time>0 else "剩余 %d:%02d · 撤离 %d 米" % [int(remaining)/60,int(remaining)%60,int(player.position.distance_to(exit_pos))]

func _visible(a: Vector3,b: Vector3,exclude: CollisionObject3D) -> bool:
 var target_height=stance_height-0.25 if b==player.position else 1.0
 var query=PhysicsRayQueryParameters3D.create(a+Vector3(0,1,0),b+Vector3(0,target_height,0))
 query.exclude=[exclude.get_rid()]
 var result=get_world_3d().direct_space_state.intersect_ray(query)
 return result.is_empty() or result.collider==player or result.position.distance_to(b+Vector3(0,target_height,0))<1.2

func _fire():
 var from=camera.global_position
 var direction=-camera.global_transform.basis.z
 var camera_query=PhysicsRayQueryParameters3D.create(from,from+direction*50.0)
 camera_query.exclude=[player.get_rid()]
 var camera_hit=get_world_3d().direct_space_state.intersect_ray(camera_query)
 var target=camera_hit.position if not camera_hit.is_empty() else from+direction*50.0
 var origin=player.global_position+Vector3(0,stance_height-0.1,0)+direction*0.35
 var query=PhysicsRayQueryParameters3D.create(origin,target+direction*0.1)
 query.exclude=[player.get_rid()]
 var hit=get_world_3d().direct_space_state.intersect_ray(query)
 var end=hit.position if not hit.is_empty() else target
 _tracer(origin,end)
 if hit.is_empty(): return
 for e in enemies:
  if is_instance_valid(e.node) and hit.collider==e.node:
   e.hp-=25
   hit_marker.visible=true; hit_time=0.22; _play_sound(hit_sound)
   damage_label.text="命中 -25"; damage_label.add_theme_color_override("font_color",Color("ffdb85")); damage_label.visible=true; damage_time=0.65
   if e.hp<=0:
    e.node.queue_free()
    enemies.erase(e)
    damage_label.text="击败巡逻者"; damage_label.add_theme_color_override("font_color",Color("ff765d")); damage_time=1.1
    _toast("巡逻者已被击败",1)
   return
