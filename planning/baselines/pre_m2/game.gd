extends Node3D

const BUILD_ID = "phase2-20261106"
const InputRouter = preload("res://scripts/input/input_router.gd")
const PlayerMotor = preload("res://scripts/player/player_motor.gd")
const CameraRig = preload("res://scripts/player/camera_rig.gd")
const ActionState = preload("res://scripts/player/action_state.gd")
const AimResolver = preload("res://scripts/combat/aim_resolver.gd")
const TrainingRange = preload("res://scripts/training_range.gd")
const CombatDrill = preload("res://scripts/combat_drill.gd")
const HealthState = preload("res://scripts/combat/health_state.gd")
const WeaponController = preload("res://scripts/combat/weapon_controller.gd")
const CombatResolver = preload("res://scripts/combat/combat_resolver.gd")
const EnemyBrain = preload("res://scripts/ai/enemy_brain.gd")
const PerceptionSystem = preload("res://scripts/ai/perception_system.gd")
const NavigationWorld = preload("res://scripts/ai/navigation_world.gd")
const Layers = preload("res://scripts/collision_layers.gd")
const PLAYER_WEAPON = preload("res://data/weapons/player_rifle.tres")
const GUARD_WEAPON = preload("res://data/weapons/guard_rifle.tres")
const PLAYER_ARMOR = preload("res://data/armor/player_light.tres")
const GUARD_ARMOR = preload("res://data/armor/guard_light.tres")
var player_health = HealthState.new()
var weapon_runtime = WeaponController.new()
var combat = CombatResolver.new()
var world_navigation = NavigationWorld.new()
var drill_navigation
var world_obstacles: Array[Rect2] = []
var combat_drill = false
var deployment_grace = 3.0
var aim_toggled = false
var aim_button: Button
var healing_remaining = 0.0
var last_shot: Dictionary = {}
var last_enemy_shot: Dictionary = {}
var kills = 0
var world_sounds: Array[AudioStreamPlayer3D] = []
var world_sound_index = 0
var combat_status: Label
var input_router = InputRouter.new()
var motor = PlayerMotor.new()
var rig = CameraRig.new()
var actions = ActionState.new()
var aim_resolver = AimResolver.new()
var aim_solution: Dictionary = {}
var touch_buttons: Dictionary = {}
var training_mode = false
var training_root: Node3D
var training_hits = 0
var paused = false
var test_mode = false
var hud_root: Control
var crosshair: Control
var primary_button: Button
var camp_button: Button
var playing = false
# Compatibility properties forward to the single runtime authority.
var hp: float:
 get: return player_health.hp
 set(value): player_health.hp=clampf(value,0.0,player_health.max_hp)
var ammo: int:
 get: return weapon_runtime.ammo
 set(value): weapon_runtime.ammo=value
var reserve: int:
 get: return weapon_runtime.reserve
 set(value): weapon_runtime.reserve=value
var meds = 3
var remaining = 360.0
var extract_time = 0.0
var fire_delay: float:
 get: return weapon_runtime.cooldown
 set(value): weapon_runtime.cooldown=value
var reload_time: float:
 get: return weapon_runtime.reload_remaining
 set(value): weapon_runtime.reload_remaining=value
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
var muzzle: Node3D
var sound_players: Array[AudioStreamPlayer] = []
var sound_index = 0
var shot_sound: AudioStreamWAV
var hit_sound: AudioStreamWAV
var reload_sound: AudioStreamWAV
var ground_material: StandardMaterial3D
var aim_hint: Label
var crouch_button: Button
var wealth = 0
var wins = 0
var exit_pos = Vector3(25, 0, 25)
var rng = RandomNumberGenerator.new()

func _ready():
 get_window().title="余烬行动 · 第二阶段试玩"
 weapon_runtime.configure(PLAYER_WEAPON,731)
 rng.randomize()
 input_router.setup_actions()
 _load_save()
 _build_world()
 _build_ui()
 _build_audio()
 _show_menu("余烬行动 3D", "第二阶段 · 枪械与 AI 试玩\n战斗演练：利用掩体、观察巡逻、开枪引开守卫。\n\nWASD 移动 · Shift 快跑 · 空格跳跃 · C 蹲下\nV 切换视角 · X / 右键瞄准 · R 换弹\nE 搜索 · Q 治疗（开火会中断）\n点击画面锁定鼠标，再次按左键开火；Esc 暂停。\n触屏：左侧移动，右侧观察，按住开火。")
 if OS.get_cmdline_user_args().has("--training"): _reset.call_deferred(true)
 elif OS.get_cmdline_user_args().has("--combat-drill"): _reset.call_deferred(true,true)

func mat(c: Color, rough = 1.0) -> StandardMaterial3D:
 var m = StandardMaterial3D.new()
 m.albedo_color = c
 m.roughness = rough
 return m

func box(parent: Node3D, size: Vector3, position: Vector3, color: Color, solid = false) -> Node3D:
 var n: Node3D
 if solid:
  var b = StaticBody3D.new()
  b.collision_layer=Layers.WORLD|Layers.CAMERA
  b.collision_mask=Layers.ACTOR
  var col = CollisionShape3D.new()
  var shape = BoxShape3D.new()
  shape.size = size
  col.shape = shape
  b.add_child(col)
  n = b
  if parent==world and size.y>0.6 and absf(position.x)<40:
   world_obstacles.append(Rect2(Vector2(position.x-size.x*0.5,position.z-size.z*0.5),Vector2(size.x,size.z)))
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
 body.collision_layer=Layers.ACTOR
 body.collision_mask=Layers.WORLD|Layers.ACTOR
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
 var marker=Marker3D.new()
 marker.name="Muzzle"
 marker.position=Vector3(0,0.03,-0.92)
 parent.add_child(marker)
 var flash=Node3D.new()
 flash.name="Flash"
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
 world_navigation.build(world,Rect2(-30.5,-30.5,61,61),world_obstacles)

func _reset(practice := false,drill := false):
 _stop_audio()
 _cancel_controls()
 training_mode=practice
 combat_drill=drill
 kills=0; deployment_grace=3.0; healing_remaining=0.0
 last_shot={}; last_enemy_shot={}
 if drill_navigation!=null:
  drill_navigation.dispose()
  drill_navigation=null
 paused=false
 training_hits=0
 if is_instance_valid(training_root):
  training_root.free()
  training_root=null
 for e in enemies:
  if is_instance_valid(e.node): e.node.free()
 for c in crates:
  if is_instance_valid(c.node): c.node.free()
 enemies.clear()
 crates.clear()
 if is_instance_valid(player): player.free()
 player = character(world,Color("b7d88d"),Vector3(-26,0,-26))
 player_health=HealthState.new()
 player_health.configure_armor(PLAYER_ARMOR)
 combat.attach_actor(player,player_health,&"player")
 weapon_runtime.configure(PLAYER_WEAPON,731 if test_mode else randi())
 meds=3; remaining=360; extract_time=0
 motor=PlayerMotor.new()
 actions=ActionState.new()
 rig.recoil_pitch=0.0
 recoil=0.0
 hit_time=0; shot_time=0; damage_time=0
 hit_marker.visible=false; damage_label.visible=false; shot_label.visible=false; muzzle.visible=false
 if is_instance_valid(crouch_button): crouch_button.text="蹲下"
 bag.clear()
 rig.yaw=-2.35; rig.pitch=-0.1
 _apply_view()
 var enemy_points = [Vector3(-18,0,-19),Vector3(-8,0,-12),Vector3(4,0,-18),Vector3(18,0,-7),Vector3(-21,0,12),Vector3(-2,0,0),Vector3(8,0,12),Vector3(-4,0,25),Vector3(23,0,17)]
 for p in enemy_points:
  var route: Array[Vector3]=[p,p+Vector3(4,0,-3),p+Vector3(5,0,4)]
  _register_guard(character(world,Color("b86a55"),p),route,world_navigation.map,false)
 var points = [Vector3(-22,0,-22),Vector3(-10,0,-17),Vector3(0,0,-25),Vector3(15,0,-24),Vector3(24,0,-12),Vector3(-23,0,-2),Vector3(-11,0,0),Vector3(1,0,-5),Vector3(13,0,0),Vector3(24,0,4),Vector3(-24,0,18),Vector3(-12,0,16),Vector3(1,0,14),Vector3(9,0,25),Vector3(21,0,22)]
 var names = ["医疗物资","军用电池","加密芯片","精密零件","稀有合金","军用口粮","战术手表","电子元件"]
 var values = [120,180,320,150,250,80,280,140]
 for p in points:
  var contents=[]
  for n in range(rng.randi_range(2,4)):
   var idx = rng.randi_range(0,names.size()-1)
   contents.append({"name":names[idx],"value":values[idx]})
  crates.append({"node":box(world,Vector3(1,0.8,1),p+Vector3(0,0.4,0),Color("d5a35b")),"items":contents,"opened":false})
 if training_mode:
  for e in enemies: e.node.free()
  for c in crates: c.node.free()
  enemies.clear(); crates.clear()
  var range_data=CombatDrill.new().build(self) if combat_drill else TrainingRange.new().build(self)
  training_root=range_data.root
  player.position=range_data.spawn
  rig.yaw=range_data.yaw; rig.pitch=range_data.pitch
  if combat_drill:
   drill_navigation=NavigationWorld.new()
   var drill_map=drill_navigation.build(training_root,range_data.bounds,range_data.obstacles)
   for i in range(range_data.enemies.size()):
    var route: Array[Vector3]=[]
    route.assign(range_data.routes[i])
    _register_guard(character(training_root,Color("b86a55"),range_data.enemies[i]),route,drill_map,false)
  else:
   for target in range_data.targets:
    var route: Array[Vector3]=[target.origin]
    _register_guard(target.node,route,RID(),true)
 playing=true
 searching=false
 active_crate=null
 search_ui.visible=false
 menu.visible=false
 _sync_input_context()
 _toast("战斗演练：观察巡逻，利用墙体；Esc 可重开" if combat_drill else ("靶场：头 / 躯干 / 四肢伤害不同；R 换弹" if training_mode else "搜索补给箱，利用掩体避开巡逻；3 秒后行动开始"),5)

func _build_ui():
 hud = CanvasLayer.new()
 add_child(hud)
 var root = Control.new()
 hud_root=root
 root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 root.mouse_filter=Control.MOUSE_FILTER_IGNORE
 hud.add_child(root)
 status = Label.new(); status.position=Vector2(20,18); status.add_theme_font_size_override("font_size",22); root.add_child(status)
 timer_label = Label.new(); timer_label.position=Vector2(960,18); timer_label.add_theme_font_size_override("font_size",22); root.add_child(timer_label)
 notification=Label.new(); notification.position=Vector2(320,75); notification.add_theme_font_size_override("font_size",20); root.add_child(notification)
 var names = ["搜索 / 撤离","治疗","换弹","暂停","切换视角"]
 for i in range(names.size()):
  var b=Button.new(); b.text=names[i]; b.position=Vector2(245+i*140,650); b.size=Vector2(132,52); b.add_theme_font_size_override("font_size",19); b.focus_mode=Control.FOCUS_NONE; root.add_child(b)
  _anchor(b,Control.PRESET_CENTER_BOTTOM,Rect2(-395+i*140,-70,132,52))
  match i:
   0: b.pressed.connect(_queue_action.bind(&"interact"))
   1: b.pressed.connect(_queue_action.bind(&"heal"))
   2: b.pressed.connect(_queue_action.bind(&"reload"))
   3: b.pressed.connect(_pause_game)
   4: view_button=b; b.pressed.connect(_queue_action.bind(&"view"))
 var fire_button=Button.new(); fire_button.text="开火"; fire_button.position=Vector2(1100,530); fire_button.size=Vector2(135,100); fire_button.add_theme_font_size_override("font_size",26); fire_button.focus_mode=Control.FOCUS_NONE; root.add_child(fire_button)
 _anchor(fire_button,Control.PRESET_BOTTOM_RIGHT,Rect2(-180,-190,135,100))
 fire_button.button_down.connect(func(): input_router.set_action(&"fire",true))
 fire_button.button_up.connect(func(): input_router.set_action(&"fire",false))
 var jump_button=Button.new(); jump_button.text="跳跃"; jump_button.position=Vector2(1130,400); jump_button.size=Vector2(105,72); jump_button.add_theme_font_size_override("font_size",23); root.add_child(jump_button)
 _anchor(jump_button,Control.PRESET_BOTTOM_RIGHT,Rect2(-150,-320,105,72))
 jump_button.pressed.connect(_queue_action.bind(&"jump"))
 crouch_button=Button.new(); crouch_button.text="蹲下"; crouch_button.position=Vector2(1010,540); crouch_button.size=Vector2(85,90); crouch_button.add_theme_font_size_override("font_size",22); root.add_child(crouch_button)
 _anchor(crouch_button,Control.PRESET_BOTTOM_RIGHT,Rect2(-280,-180,85,90))
 crouch_button.pressed.connect(_queue_action.bind(&"crouch"))
 var sprint_button=Button.new(); sprint_button.text="快跑\n按住"; sprint_button.position=Vector2(35,410); sprint_button.size=Vector2(95,85); sprint_button.add_theme_font_size_override("font_size",20); root.add_child(sprint_button)
 _anchor(sprint_button,Control.PRESET_BOTTOM_LEFT,Rect2(35,-310,95,85))
 sprint_button.button_down.connect(func(): input_router.set_action(&"sprint",true))
 sprint_button.button_up.connect(func(): input_router.set_action(&"sprint",false))
 aim_button=Button.new(); aim_button.text="瞄准"; aim_button.add_theme_font_size_override("font_size",22); root.add_child(aim_button)
 _anchor(aim_button,Control.PRESET_BOTTOM_RIGHT,Rect2(-280,-280,85,75))
 aim_button.pressed.connect(_queue_action.bind(&"aim_toggle"))
 combat_status=Label.new(); combat_status.add_theme_font_size_override("font_size",19); root.add_child(combat_status)
 _anchor(combat_status,Control.PRESET_TOP_LEFT,Rect2(20,50,700,30))
 crosshair=Control.new()
 crosshair.set_script(preload("res://scripts/presentation/crosshair.gd"))
 root.add_child(crosshair)
 crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 aim_hint=Label.new(); aim_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; aim_hint.add_theme_font_size_override("font_size",18); aim_hint.add_theme_color_override("font_color",Color("ffb08a")); root.add_child(aim_hint)
 _anchor(aim_hint,Control.PRESET_CENTER,Rect2(-180,40,360,30))
 hit_marker=Label.new(); hit_marker.text="×"; hit_marker.position=Vector2(621,325); hit_marker.add_theme_font_size_override("font_size",48); hit_marker.add_theme_color_override("font_color",Color("ffdc85")); hit_marker.visible=false; root.add_child(hit_marker)
 damage_label=Label.new(); damage_label.position=Vector2(590,285); damage_label.add_theme_font_size_override("font_size",24); damage_label.add_theme_color_override("font_color",Color("ffb084")); damage_label.visible=false; root.add_child(damage_label)
 shot_label=Label.new(); shot_label.text="◆"; shot_label.position=Vector2(623,377); shot_label.add_theme_font_size_override("font_size",22); shot_label.add_theme_color_override("font_color",Color("ffdf82")); shot_label.visible=false; root.add_child(shot_label)
 search_ui=Control.new(); search_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.add_child(search_ui)
 var shade=ColorRect.new(); shade.color=Color(0.02,0.04,0.03,0.9); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); search_ui.add_child(shade)
 var layout=HBoxContainer.new(); layout.add_theme_constant_override("separation",45); search_ui.add_child(layout)
 _anchor(layout,Control.PRESET_CENTER,Rect2(-520,-270,1040,540))
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
 var panel=VBoxContainer.new(); panel.add_theme_constant_override("separation",12); menu.add_child(panel)
 _anchor(panel,Control.PRESET_CENTER,Rect2(-350,-320,700,640))
 var title=Label.new(); title.name="Title"; title.add_theme_font_size_override("font_size",44); panel.add_child(title)
 var body=Label.new(); body.name="Body"; body.add_theme_font_size_override("font_size",21); body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; panel.add_child(body)
 var info=Label.new(); info.name="Info"; info.add_theme_font_size_override("font_size",20); panel.add_child(info)
 var start=Button.new(); start.name="Start"; start.text="进入封锁区"; start.custom_minimum_size=Vector2(240,60); start.add_theme_font_size_override("font_size",24); start.pressed.connect(_primary_action); panel.add_child(start)
 primary_button=start

 var practice=Button.new(); practice.text="靶场练习 · 不损失物资"; practice.custom_minimum_size=Vector2(240,52); practice.add_theme_font_size_override("font_size",22); practice.pressed.connect(_reset.bind(true)); panel.add_child(practice)
 var drill_button=Button.new(); drill_button.text="战斗演练 · 两名守卫 / 无损失"; drill_button.custom_minimum_size=Vector2(240,52); drill_button.add_theme_font_size_override("font_size",22); drill_button.pressed.connect(_reset.bind(true,true)); panel.add_child(drill_button)
 camp_button=Button.new(); camp_button.text="结束本局，返回营地"; camp_button.custom_minimum_size=Vector2(240,44); camp_button.pressed.connect(_return_camp); panel.add_child(camp_button)
 var sensitivity=HBoxContainer.new(); panel.add_child(sensitivity)
 var sensitivity_label=Label.new(); sensitivity_label.text="观察灵敏度  1.00×"; sensitivity_label.custom_minimum_size.x=230; sensitivity.add_child(sensitivity_label)
 var slider=HSlider.new(); slider.min_value=0.3; slider.max_value=2.5; slider.step=0.05; slider.value=1; slider.custom_minimum_size=Vector2(400,36); slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL; sensitivity.add_child(slider)
 # +/- are also usable on touch devices without mouse emulation.
 for adjustment in [-0.15,0.15]:
  var adjust=Button.new(); adjust.text="−" if adjustment<0 else "+"; adjust.custom_minimum_size=Vector2(44,36); sensitivity.add_child(adjust)
  adjust.pressed.connect(func(): slider.value+=adjustment)
 slider.value_changed.connect(func(value): input_router.mouse_sensitivity=0.003*value; input_router.touch_sensitivity=3.0*value; sensitivity_label.text="观察灵敏度  %.2f×" % value)
 _anchor(timer_label,Control.PRESET_TOP_RIGHT,Rect2(-320,18,300,36))
 _anchor(notification,Control.PRESET_CENTER_TOP,Rect2(-320,75,640,40))
 _anchor(hit_marker,Control.PRESET_CENTER,Rect2(-19,-33,38,60))
 _anchor(damage_label,Control.PRESET_CENTER,Rect2(-150,-75,300,35)); damage_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 _anchor(shot_label,Control.PRESET_CENTER,Rect2(-10,25,30,30))
 _ignore_labels(hud)

func _show_menu(title: String, text: String):
 _stop_audio()
 playing=false; paused=false; searching=false
 weapon_runtime.disable()
 healing_remaining=0.0
 _cancel_controls()
 _sync_input_context()
 search_ui.visible=false
 var panel=menu.get_child(1)
 panel.get_node("Title").text=title
 panel.get_node("Body").text=text
 panel.get_node("Info").text="仓库资产：%d 点   ·   成功撤离：%d 次" % [wealth,wins]
 primary_button.text="进入封锁区"
 camp_button.visible=false
 menu.visible=true

func _toast(text: String, duration=2.5):
 notification.text=text
 notify_time=duration

func _interact():
 if not playing or searching or training_mode: return
 if player.position.distance_to(exit_pos)<3.6:
  if extract_time<=0: extract_time=5.0; _toast("撤离信号已发送，留在绿色区域 5 秒",4)
  return
 for c in crates:
  if player.position.distance_to(c.node.position)<2.3:
   var q=PhysicsRayQueryParameters3D.create(player.position+Vector3(0,motor.eye_height,0),c.node.position,Layers.WORLD)
   q.exclude=[player.get_rid()]
   if not get_world_3d().direct_space_state.intersect_ray(q).is_empty(): continue
   active_crate=c
   c.opened=true
   c.node.get_child(0).material_override=mat(Color("8b9a77"))
   searching=true
   _cancel_controls()
   _sync_input_context()
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
 _cancel_controls()
 _sync_input_context()
 _toast("搜索结束，点击画面继续观察",1.5)

func _heal():
 if not playing or searching or healing_remaining>0: return
 if meds>0 and hp>0 and hp<100 and reload_time<=0:
  healing_remaining=2.2; _toast("治疗中 · 开火会中断",2.2)
 else: _toast("生命已满、药包不足或正在换弹")

func _reload():
 if playing and not searching and healing_remaining<=0 and weapon_runtime.request_reload():
  _play_sound(reload_sound); _toast("正在换弹…",weapon_runtime.definition.reload_duration)

func _pause_game():
 if not playing: return
 playing=false; paused=true
 _cancel_controls()
 _sync_input_context()
 var panel=menu.get_child(1)
 panel.get_node("Title").text="行动暂停"
 panel.get_node("Body").text="继续后需重新按下移动或开火。\n可以在这里调整观察灵敏度。"
 panel.get_node("Info").text=("战斗演练 · 无损失" if combat_drill else "靶场练习 · 无损失") if training_mode else "本局尚未结算；返回营地会放弃本局物资。"
 primary_button.text="继续行动"
 camp_button.visible=true
 menu.visible=true

func _resume():
 menu.visible=false; playing=true; paused=false
 _cancel_controls()
 _sync_input_context()

func _save():
 if test_mode or training_mode: return
 var f=FileAccess.open("user://progress.json",FileAccess.WRITE)
 if f: f.store_string(JSON.stringify({"wealth":wealth,"wins":wins}))
func _load_save():
 if test_mode: return
 if FileAccess.file_exists("user://progress.json"):
  var data=JSON.parse_string(FileAccess.get_file_as_string("user://progress.json"))
  if data is Dictionary: wealth=int(data.get("wealth",0)); wins=int(data.get("wins",0))

func _finish(success: bool, why: String):
 if not playing: return
 if combat_drill:
  weapon_runtime.disable()
  _show_menu("演练结束",why+"\n演练不影响仓库，可再次进入练习。")
  return
 if training_mode: return
 var total=0
 for c in bag: total+=int(c.value)
 if success:
  wealth+=total; wins+=1; _save()
  _show_menu("撤离成功", "安全带回 %d 件物资，价值 %d 点。\n%s" % [bag.size(),total,why])
 else: _show_menu("行动结束",why+"\n本局携带的物资已丢失。")

func _jump():
 _queue_action(&"jump")

func _toggle_crouch():
 _queue_action(&"crouch")

func _toggle_view():
 rig.third_person=not rig.third_person
 _apply_view()
 _toast("第三人称" if rig.third_person else "第一人称",1.5)

func _apply_view():
 if not is_instance_valid(player): return
 player.get_node("Visual").visible=rig.third_person
 gun.visible=not rig.third_person
 if is_instance_valid(view_button): view_button.text="切换：第三人称" if rig.third_person else "切换：第一人称"

func _unhandled_input(event):
 if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
  if searching and playing: _close_search(); return
  if paused: _resume(); return
 if not playing or searching: return
 input_router.screen_size=Vector2(DisplayServer.window_get_size())
 var request=input_router.handle(event,get_viewport().get_visible_rect().size,Input.mouse_mode==Input.MOUSE_MODE_CAPTURED)
 if request==&"capture": Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 elif request==&"pause": _pause_game()

func _physics_process(delta):
 if not playing or searching: return
 var frame=input_router.consume_frame()
 if frame.interact: _interact()
 if searching or not playing: return
 if frame.heal: _heal()
 if frame.reload: _reload()
 if frame.view: _toggle_view()
 if frame.aim_toggle: aim_toggled=not aim_toggled
 frame.aim=frame.aim or aim_toggled
 if frame.fire and healing_remaining>0:
  healing_remaining=0.0; _toast("治疗已中断，医疗包保留",1.5)
 rig.add_look(frame.look*(0.6 if rig.aiming else 1.0))
 hit_time=maxf(0.0,hit_time-delta); hit_marker.visible=hit_time>0
 damage_time=maxf(0.0,damage_time-delta); damage_label.visible=damage_time>0
 shot_time=maxf(0.0,shot_time-delta)
 shot_label.visible=shot_time>0
 muzzle.visible=shot_time>0 and not rig.third_person
 player.get_node("Visual/CarriedRifle/Flash").visible=shot_time>0 and rig.third_person
 recoil=move_toward(recoil,0.0,delta*5.5)
 deployment_grace=maxf(0.0,deployment_grace-delta)
 if not training_mode:
  remaining-=delta
  if remaining<=0: _finish(false,"行动时间耗尽。"); return
 if notify_time>0:
  notify_time-=delta
  if notify_time<=0: notification.text=""
 elif combat_drill:
  notification.text="左右绕过掩体 · 枪声会引来附近守卫 · Esc 暂停 / 重开" if kills<2 else "演练完成 · Esc 可重开或返回营地"
 var was_reloading=reload_time>0
 weapon_runtime.tick(delta)
 if training_mode and not combat_drill and was_reloading and reload_time<=0: reserve=120
 if healing_remaining>0:
  healing_remaining=maxf(0.0,healing_remaining-delta)
  if healing_remaining<=0:
   meds-=1; player_health.heal(45); _toast("治疗完成",1.0)
  frame.move*=0.45
 var sprint_allowed=not frame.fire and not frame.aim and reload_time<=0 and healing_remaining<=0
 motor.step(player,frame,rig.yaw,sprint_allowed,delta)
 actions.step(frame,reload_time>0 or healing_remaining>0,delta,motor.crouching)
 combat.set_crouched(player,motor.crouching)
 player.get_node("Hitboxes").scale.y=player.get_node("Visual").scale.y
 rig.aiming=frame.aim and player.is_on_floor() and reload_time<=0 and healing_remaining<=0 and actions.raise_time<=0
 aim_button.text="取消瞄准" if rig.aiming else "瞄准"
 crouch_button.text="起身" if motor.crouching else "蹲下"
 if motor.blocked_stand: _toast("上方空间不足，暂时无法起身",1.5)
 player.rotation.y=rig.yaw
 rig.update_camera(camera,player,motor.eye_height,[player.get_rid()],delta)
 _update_aim(frame.move.length())
 if frame.fire and actions.can_fire(reload_time>0 or healing_remaining>0):
  if ammo>0: _try_fire()
  elif reserve>0: _reload()
 if not training_mode or combat_drill:
  _update_enemies(delta)
  if not playing: return
 if extract_time>0:
  if player.position.distance_to(exit_pos)>3.6: extract_time=0; _toast("已离开撤离区，撤离取消")
  else:
   extract_time-=delta
   if extract_time<=0: _finish(true,""); return
 var value=0
 for c in bag: value+=int(c.value)
 status.text="生命 %d   弹药 %d/%d   医疗 %d   背包 %d/8 · %d 点" % [hp,ammo,reserve,meds,bag.size(),value]
 combat_status.text="头盔 %.0f  ·  护甲 %.0f  ·  击败 %d  ·  %s" % [player_health.head_armor,player_health.body_armor,kills,_weapon_status()]
 timer_label.text=("演练 · 守卫 %d/2" % kills if combat_drill else "靶场 · 命中 %d 次" % training_hits) if training_mode else ("撤离 %.1f 秒" % extract_time if extract_time>0 else "剩余 %d:%02d · 撤离 %d 米" % [int(remaining)/60,int(remaining)%60,int(player.position.distance_to(exit_pos))])

func _update_aim(move_amount := 0.0):
 var target=aim_resolver.target_point(camera,player)
 var mount=player.global_position+Vector3(0,motor.eye_height-0.15,0)
 var target_behind=(target-mount).dot(rig.direction())<=0.1
 var visual_target=mount+rig.direction()*60.0 if target_behind else target
 var sway=sin(motor.move_phase)*0.009*move_amount
 gun.position=Vector3(0.08 if rig.aiming else 0.29+sway,-0.23-abs(sway)*0.5,-0.55+recoil*0.10)
 gun.look_at(visual_target,Vector3.UP)
 if reload_time>0: gun.rotate_object_local(Vector3.FORWARD,0.65)
 elif motor.sprinting: gun.rotate_object_local(Vector3.RIGHT,-0.25)
 var carried=player.get_node("Visual/CarriedRifle")
 carried.look_at(visual_target,Vector3.UP)
 var current_weapon=carried if rig.third_person else gun
 var origin=current_weapon.get_node("Muzzle").global_position
 aim_solution=aim_resolver.solve(player,mount,origin,target)
 aim_solution.blocked=aim_solution.blocked or target_behind
 crosshair.blocked=aim_solution.blocked
 crosshair.spread_pixels=4.0+_player_spread()*400.0
 aim_hint.text="枪口受阻 · 后退或换个角度" if aim_solution.blocked else ("举枪中" if actions.raise_time>0 else "")

func _try_fire() -> bool:
 if not playing or searching or healing_remaining>0 or not actions.can_fire(reload_time>0): return false
 last_shot=weapon_runtime.request_fire(player,aim_solution,combat,_player_spread())
 if not last_shot.accepted: return false
 shot_time=0.08; recoil=1.0; shot_label.visible=true
 muzzle.visible=not rig.third_person
 player.get_node("Visual/CarriedRifle/Flash").visible=rig.third_person
 _play_sound(shot_sound)
 _present_shot(last_shot,player)
 for enemy in enemies:
  if enemy.brain!=null: enemy.brain.hear(player.global_position,1.0)
 rig.kick()
 return true

func _update_enemies(delta):
 for enemy in enemies:
  var node: CharacterBody3D=enemy.node
  if not is_instance_valid(node) or enemy.health.hp<=0 or enemy.brain==null: continue
  enemy.weapon.tick(delta)
  enemy.flash_time=maxf(0.0,enemy.flash_time-delta)
  var rifle=node.get_node("Visual/CarriedRifle")
  rifle.get_node("Flash").visible=enemy.flash_time>0
  var observation={"visible":false,"confirmed":false}
  if deployment_grace<=0: observation=enemy.sensor.observe(node,player,delta)
  var intent=enemy.brain.step(delta,observation)
  if intent.aiming: rifle.look_at(intent.aim_point,Vector3.UP)
  else: rifle.rotation=Vector3.ZERO
  var speed=Vector2(node.velocity.x,node.velocity.z).length()
  enemy.stride+=delta*speed*3.0
  node.get_node("Visual/LeftLeg").rotation.x=sin(enemy.stride)*0.4 if speed>0.1 else 0.0
  node.get_node("Visual/RightLeg").rotation.x=-node.get_node("Visual/LeftLeg").rotation.x
  if enemy.weapon.ammo<=0: enemy.weapon.request_reload()
  if intent.fire:
   var solution=aim_resolver.solve(node,node.global_position+Vector3(0,1.3,0),rifle.get_node("Muzzle").global_position,intent.aim_point)
   var spread=enemy.weapon.definition.move_spread if speed>0.1 else enemy.weapon.definition.aim_spread
   var shot=enemy.weapon.request_fire(node,solution,combat,spread)
   if shot.accepted:
    enemy.flash_time=0.08
    rifle.get_node("Flash").visible=true
    last_enemy_shot=shot
    _play_world_sound(shot_sound,shot.origin)
    _present_shot(shot,node)
    if hp<=0: _finish(false,"你在交战中倒下了。"); return
  var label: Label3D=enemy.label
  label.text=_guard_state_text(enemy.brain.state) if enemy.weapon.reload_remaining<=0 else "换弹中"
  label.modulate=Color("ff9870") if intent.aiming else Color("e2d998")
  label.visible=node.position.distance_to(player.position)<24.0 and aim_resolver.visible(player,player.position+Vector3(0,motor.eye_height,0),node,node.position+Vector3(0,1.62,0))

func _visible(a: Vector3,b: Vector3,observer: CollisionObject3D) -> bool:
 return aim_resolver.visible(observer,a+Vector3(0,1,0),player,b+Vector3(0,motor.eye_height-0.25,0))

func _fire():
 # Legacy entry delegates to the same ammunition and damage authority.
 return _try_fire()

func _queue_action(action: StringName):
 input_router.set_action(action,true)
 input_router.set_action(action,false)

func _primary_action():
 if paused: _resume()
 else: _reset(false)

func _return_camp():
 _show_menu("余烬行动 3D","选择靶场练习，或进入封锁区继续搜打撤。")

func _sync_input_context():
 input_router.set_enabled(playing and not searching)

func _cancel_controls():
 aim_toggled=false
 rig.aiming=false
 input_router.cancel_all()
 actions.cancel_all()
 for button in touch_buttons.values():
  if is_instance_valid(button): button.modulate=Color.WHITE
 touch_buttons.clear()
 Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 if is_instance_valid(player): player.velocity.x=0; player.velocity.z=0

func _notification(what):
 if what==NOTIFICATION_APPLICATION_FOCUS_OUT or what==NOTIFICATION_APPLICATION_PAUSED:
  if is_instance_valid(menu) and playing: _pause_game()
  else: _cancel_controls()

func _input(event):
 input_router.release_event(event)
 # GUI always claims a finger first. Release is tracked even outside the button.
 if event is InputEventScreenTouch:
  if not event.pressed or event.canceled:
   if touch_buttons.has(event.index):
    var button=touch_buttons[event.index]
    touch_buttons.erase(event.index)
    if is_instance_valid(button):
     button.modulate=Color.WHITE
     button.button_up.emit()
     if not event.canceled and button.is_visible_in_tree() and button.get_global_rect().has_point(event.position): button.pressed.emit()
    get_viewport().set_input_as_handled()
  elif is_instance_valid(hud):
   var context: Node=menu if menu.visible else (search_ui if search_ui.visible else hud_root)
   var button=_touch_button_at(context,event.position)
   if button!=null:
    if not touch_buttons.values().has(button):
     touch_buttons[event.index]=button
     button.modulate=Color(0.75,0.9,0.72)
     button.button_down.emit()
    get_viewport().set_input_as_handled()
 elif event is InputEventScreenDrag and touch_buttons.has(event.index): get_viewport().set_input_as_handled()

func _touch_button_at(node: Node, point: Vector2) -> Button:
 if node is CanvasItem and not node.is_visible_in_tree(): return null
 var children=node.get_children()
 children.reverse()
 for child in children:
  var button=_touch_button_at(child,point)
  if button!=null: return button
 if node is Button and not node.disabled and node.get_global_rect().has_point(point): return node
 return null

func _anchor(control: Control, preset: int, rect: Rect2):
 control.set_anchors_and_offsets_preset(preset)
 control.offset_left=rect.position.x; control.offset_top=rect.position.y
 control.offset_right=rect.end.x; control.offset_bottom=rect.end.y

func _ignore_labels(node: Node):
 if node is Label: node.mouse_filter=Control.MOUSE_FILTER_IGNORE
 if node is Button: node.focus_mode=Control.FOCUS_NONE
 for child in node.get_children(): _ignore_labels(child)

func _register_guard(node: CharacterBody3D, route: Array[Vector3], nav_map: RID, dummy: bool):
 var health=HealthState.new(75.0,0.0,0.0)
 if not dummy: health.configure_armor(GUARD_ARMOR)
 combat.attach_actor(node,health,&"guard")
 var gun_state=WeaponController.new()
 gun_state.configure(GUARD_WEAPON,1000+enemies.size())
 var brain=null
 var label: Label3D
 if not dummy:
  brain=EnemyBrain.new()
  brain.setup(node,route,nav_map,2000+enemies.size())
  var away=node.position-player.position
  node.rotation.y=atan2(-away.x,-away.z)
  label=Label3D.new(); label.text="巡逻"; label.position=Vector3(0,2.25,0); label.font_size=28; label.pixel_size=0.006; label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; node.add_child(label)
 enemies.append({"node":node,"health":health,"weapon":gun_state,"brain":brain,"sensor":PerceptionSystem.new(),"label":label,"origin":node.position,"flash_time":0.0,"stride":0.0})

func _player_spread() -> float:
 var tuning=weapon_runtime.definition
 if not player.is_on_floor(): return tuning.air_spread
 var moving=Vector2(player.velocity.x,player.velocity.z).length()>0.5
 var spread=tuning.move_spread if moving else tuning.hip_spread
 if rig.aiming: spread=tuning.aim_spread*(2.0 if moving else 1.0)
 if motor.crouching: spread*=0.65
 return spread

func _weapon_status() -> String:
 if reload_time>0: return "换弹 %.1f 秒" % reload_time
 if healing_remaining>0: return "治疗 %.1f 秒" % healing_remaining
 if motor.sprinting: return "快跑"
 if rig.aiming: return "瞄准"
 return "腰射"

func _guard_state_text(state: StringName) -> String:
 return {&"Patrol":"巡逻",&"Investigate":"发现动静",&"Alert":"准备射击",&"Engage":"交战",&"Search":"搜索中",&"Return":"返回巡逻",&"Dead":"已击败"}.get(state,"巡逻")

func _present_shot(shot: Dictionary, shooter: CharacterBody3D):
 _tracer(shot.origin,shot.end_point)
 if shot.hit_world: _impact(shot.end_point)
 if shot.actor==null or shot.health_damage+shot.armor_damage<=0: return
 if shot.actor==player:
  damage_label.text="受击  生命 -%.1f / 护甲 -%.1f" % [shot.health_damage,shot.armor_damage]
  damage_label.add_theme_color_override("font_color",Color("ff7568")); damage_label.visible=true; damage_time=0.9
  return
 if shooter==player:
  hit_marker.visible=true; hit_time=0.25; _play_sound(hit_sound)
  var zone_name={&"head":"头部",&"torso":"躯干",&"limbs":"四肢"}.get(shot.zone,"命中")
  damage_label.text="%s  -%.1f%s" % [zone_name,shot.health_damage," / 护甲 -%.1f" % shot.armor_damage if shot.armor_damage>0 else ""]
  damage_label.add_theme_color_override("font_color",Color("ff9870") if shot.zone==&"head" else Color("ffe1a3")); damage_label.visible=true; damage_time=0.9
  if training_mode and not combat_drill: training_hits+=1
 for enemy in enemies:
  if enemy.node!=shot.actor: continue
  if enemy.brain!=null: enemy.brain.take_hit(shooter.global_position)
  if shot.killed:
   if enemy.brain==null:
    enemy.health.reset()
    damage_label.text="击倒靶标 · 已复位"
   else:
    enemy.brain.die(); enemy.weapon.disable()
    enemy.node.collision_layer=0; enemy.node.collision_mask=0
    for hitbox in enemy.node.get_node("Hitboxes").get_children(): hitbox.collision_layer=0
    enemy.label.text="已击败"; enemy.label.visible=false
    enemy.node.get_node("Visual/CarriedRifle/Flash").visible=false
    create_tween().tween_property(enemy.node.get_node("Visual"),"rotation:z",PI*0.5,0.3)
    kills+=1; damage_label.text="击败守卫"; damage_time=1.2
    if combat_drill and kills>=2: _toast("演练完成！Esc 可重开或返回营地",8)
  break

func _impact(position: Vector3):
 var spark=box(world,Vector3.ONE*0.07,position,Color("ffba72"))
 var tween=create_tween()
 tween.tween_interval(0.18)
 tween.tween_callback(func(): if is_instance_valid(spark): spark.queue_free())

func _play_world_sound(stream: AudioStreamWAV,position: Vector3):
 if world_sounds.is_empty():
  for i in range(6):
   var voice=AudioStreamPlayer3D.new(); voice.volume_db=-12; voice.max_distance=45; world.add_child(voice); world_sounds.append(voice)
 var voice=world_sounds[world_sound_index]
 world_sound_index=(world_sound_index+1)%world_sounds.size()
 voice.global_position=position; voice.stream=stream; voice.play()

func _exit_tree():
 _stop_audio()
 if drill_navigation!=null: drill_navigation.dispose()
 world_navigation.dispose()

func _stop_audio():
 for voice in sound_players:
  if is_instance_valid(voice): voice.stop(); voice.stream=null
 for voice in world_sounds:
  if is_instance_valid(voice): voice.stop(); voice.stream=null
