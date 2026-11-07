extends Node3D

const BUILD_ID = "phase5-loot-20261106"
const CharacterVisual=preload("res://scripts/presentation/character_visual.gd")
const RifleVisual=preload("res://scripts/presentation/rifle_visual.gd")
const CombatFeedback=preload("res://scripts/presentation/combat_feedback.gd")
var feedback: Node3D
var footstep_distance=0.0
var reload_audio_stage=-1
const DepotMap=preload("res://scripts/world/depot_map.gd")
const OperationPanel=preload("res://scripts/ui/operation_panel.gd")
const ExtractionController=preload("res://scripts/raid/extraction_controller.gd")
var map_builder=DepotMap.new()
var map_definition: Dictionary={}
var world_map_id=""
var extraction=ExtractionController.new()
var operation_panel: Control
var operation_in_raid=false
var raid_events: Dictionary={"visits":[],"kills":[]}
var objective_clock=0.0
var objective_label: Label
var zone_label: Label
const ProfileService=preload("res://scripts/raid/profile_service.gd")
const RaidSnapshot=preload("res://scripts/raid/raid_snapshot.gd")
const InventoryPanel=preload("res://scripts/ui/inventory_panel.gd")
var profiles=ProfileService.new()
var snapshot_codec=RaidSnapshot.new()
var inventory_panel: Control
var inventory_context="camp"
var checkpoint_elapsed=0.0
var search_elapsed=0.0
var save_failed=false
var pending_settlement: Dictionary={}
var save_path_override=""
var runtime_raid_id=""
var save_error_context="game"
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
var extract_time: float:
 get: return extraction.remaining
 set(value): extraction.remaining=value
var fire_delay: float:
 get: return weapon_runtime.cooldown
 set(value): weapon_runtime.cooldown=value
var reload_time: float:
 get: return weapon_runtime.reload_remaining
 set(value): weapon_runtime.reload_remaining=value
var bag: Array = []
var enemies: Array = []
var crates: Array = []
var corpses: Array = []
var interact_hint: Label
var interact_button: Button
var interaction_clock=0.0
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
var ground_material: StandardMaterial3D
var aim_hint: Label
var crouch_button: Button
var wealth = 0
var wins = 0
var exit_pos = Vector3(25, 0, 25)
var rng = RandomNumberGenerator.new()

func _ready():
 get_window().title="余烬行动 · 第五阶段 · 敌人搜索"
 get_tree().auto_accept_quit=false
 weapon_runtime.configure(PLAYER_WEAPON,731)
 rng.randomize()
 input_router.setup_actions()
 _load_save()
 _build_world()
 _build_ui()
 _build_audio()
 _open_camp("第五阶段 · 骨骼人物 / 步枪样板 / 双手换弹 / 空间音效")
 if not test_mode and not profiles.blocked: _open_operation()
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
 var visual=CharacterVisual.new()
 visual.name="Visual"
 body.add_child(visual)
 visual.setup(color)
 var carried=RifleVisual.new()
 carried.name="CarriedRifle"
 visual.add_child(carried)
 carried.setup(false)
 carried.position=Vector3(0.10,1.34,-0.10)
 visual.attach_weapon(carried)
 visual.seek_pose({"grounded":true})
 return body

func _build_audio():
 feedback=CombatFeedback.new()
 feedback.name="CombatFeedback"
 add_child(feedback)
 feedback.setup()

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
 map_definition=_desired_map_definition()
 world_map_id=map_definition.id
 exit_pos=map_definition.exits[0].position
 world_obstacles.clear()
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
 environment.tonemap_mode=Environment.TONE_MAPPER_ACES
 environment.fog_enabled=true
 environment.fog_light_color=Color("aebbb0")
 environment.fog_density=0.008
 environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 environment.ambient_light_color = Color("d1e0ca")
 environment.ambient_light_energy = 0.28
 env.environment = environment
 world.add_child(env)
 var light = DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-55,-30,0)
 light.light_energy = 0.7
 light.shadow_enabled = true
 light.directional_shadow_max_distance=55.0
 light.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
 world.add_child(light)
 box(world,Vector3(64,0.5,64),Vector3(0,-0.3,0),Color("526552"),true)
 ground_material=_ground_texture()
 for x in range(-30,31,10):
  for z in range(-30,31,10):
   var tile=box(world,Vector3(10,0.02,10),Vector3(x,0,z),Color("586c57"))
   tile.get_child(0).material_override=ground_material
 if world_map_id=="legacy_v3": _build_legacy_cover()
 else: map_builder.build(self)
 for p in [Vector3(-32,1,0),Vector3(32,1,0)]: box(world,Vector3(1,2,65),p,Color("536256"),true)
 for p in [Vector3(0,1,-32),Vector3(0,1,32)]: box(world,Vector3(65,2,1),p,Color("536256"),true)
 if world_map_id=="legacy_v3":
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
 for entry in map_definition.exits:
  var ex=MeshInstance3D.new()
  var cyl=CylinderMesh.new(); cyl.top_radius=entry.radius; cyl.bottom_radius=entry.radius; cyl.height=0.07
  ex.mesh=cyl; ex.material_override=mat(Color("a6d879") if entry.required_item.is_empty() else Color("ddb565"))
  ex.position=entry.position+Vector3(0,0.07,0); world.add_child(ex)
  var sign=Label3D.new(); sign.text=entry.title+"\n"+("需通行证 · E 撤离" if not entry.required_item.is_empty() else "E 撤离")
  sign.position=entry.position+Vector3(0,2.8,0); sign.font_size=52; sign.pixel_size=0.008
  sign.billboard=BaseMaterial3D.BILLBOARD_ENABLED; sign.modulate=Color("d9edb3"); world.add_child(sign)
 camera = Camera3D.new()
 world.add_child(camera)
 camera.projection = Camera3D.PROJECTION_PERSPECTIVE
 camera.fov = 70
 camera.current = true
 gun=RifleVisual.new()
 camera.add_child(gun)
 gun.position=Vector3(0.29,-0.23,-0.55)
 gun.setup(true)
 muzzle=gun.get_node("Flash")
 gun.visible=false
 world_navigation.build(world,map_definition.bounds,world_obstacles)

func _reset(practice := false,drill := false):
 if save_failed: return
 if not practice:
  if profiles.blocked: _storage_error(profiles.last_error); return
  if profiles.profile.active_raid.is_empty():
   var started=profiles.begin_raid(731 if test_mode else int(randi()%2147483647))
   if not started.ok:
    if operation_panel.visible: operation_panel.set_notice(_reason(started.reason),true)
    else: inventory_panel.set_notice(_reason(started.reason),true)
    return
 elif playing and not training_mode:
  if not _checkpoint(): return
 _ensure_world_map()
 _stop_audio()
 if is_instance_valid(feedback): feedback.reset()
 gun.reset_pose()
 footstep_distance=0.0; reload_audio_stage=-1
 _cancel_controls()
 training_mode=practice
 runtime_raid_id="" if practice else profiles.profile.active_raid.raid_id
 combat_drill=drill
 kills=0; deployment_grace=3.0; healing_remaining=0.0
 objective_label.text=""; zone_label.text=""
 objective_clock=0.0
 raid_events={"visits":[],"kills":[]} if practice else profiles.profile.active_raid.events.duplicate(true)
 extraction.configure(map_definition.exits)
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
 corpses.clear()
 if is_instance_valid(player): player.free()
 player = character(world,Color("697466"),map_definition.spawn)
 player_health=HealthState.new()
 player_health.configure_armor(PLAYER_ARMOR)
 combat.attach_actor(player,player_health,&"player")
 weapon_runtime.configure(PLAYER_WEAPON,731 if test_mode else randi())
 meds=3; remaining=360 if practice else _active_rule().duration; extract_time=0
 motor=PlayerMotor.new()
 actions=ActionState.new()
 rig.recoil_pitch=0.0
 recoil=0.0
 hit_time=0; shot_time=0; damage_time=0
 hit_marker.visible=false; damage_label.visible=false; shot_label.visible=false; muzzle.visible=false
 if is_instance_valid(crouch_button): crouch_button.text="蹲下"
 bag.clear()
 rig.yaw=map_definition.spawn_yaw; rig.pitch=-0.1
 _apply_view()
 for guard in map_definition.guards:
  var route: Array[Vector3]=[]; route.assign(guard.route)
  _register_guard(character(world,Color("827660"),guard.position),route,world_navigation.map,false)
  enemies[-1].id=guard.id; enemies[-1].title=guard.label
 var points=map_definition.crates
 for index in range(points.size()):
  var p=points[index]
  crates.append({"node":box(world,Vector3(1,0.8,1),p+Vector3(0,0.4,0),Color("d5a35b")),"cid":"loot_%02d" % index,"items":[],"opened":false})
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
    _register_guard(character(training_root,Color("827660"),range_data.enemies[i]),route,drill_map,false)
  else:
   for target in range_data.targets:
    var route: Array[Vector3]=[target.origin]
    _register_guard(target.node,route,RID(),true)
 playing=true
 searching=false
 active_crate=null
 search_ui.visible=false
 menu.visible=false
 inventory_panel.visible=false
 operation_panel.visible=false
 save_failed=false; checkpoint_elapsed=0
 if not training_mode:
  _apply_guard_rules()
  _sync_inventory_runtime()
  snapshot_codec.apply(self,profiles.profile.active_raid.snapshot)
  # Item ownership is authoritative after a pickup; checkpoint presentation may
  # still describe the pre-transfer reserve from the same atomic transaction.
  _sync_inventory_runtime()
  _sync_crates()
  if not _checkpoint(): return
  if hp<=0: _finish(false,"上次行动已阵亡。"); return
 _sync_input_context()
 _toast("战斗演练：观察巡逻，利用墙体；Esc 可重开" if combat_drill else ("靶场：头 / 躯干 / 四肢伤害不同；R 换弹" if training_mode else "搜索补给箱，利用掩体避开巡逻；M 查看地图与任务"),5)

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
   0: interact_button=b; b.pressed.connect(_queue_action.bind(&"interact"))
   1: b.pressed.connect(_queue_action.bind(&"heal"))
   2: b.pressed.connect(_queue_action.bind(&"reload"))
   3: b.pressed.connect(_pause_game)
   4: view_button=b; b.pressed.connect(_queue_action.bind(&"view"))
 var inventory_button=Button.new(); inventory_button.text="背包 B"; inventory_button.add_theme_font_size_override("font_size",20); root.add_child(inventory_button)
 _anchor(inventory_button,Control.PRESET_BOTTOM_LEFT,Rect2(35,-210,110,60))
 inventory_button.pressed.connect(_open_bag)
 var operation_button=Button.new(); operation_button.text="地图 M"; operation_button.add_theme_font_size_override("font_size",20); root.add_child(operation_button)
 _anchor(operation_button,Control.PRESET_TOP_RIGHT,Rect2(-155,62,130,50))
 operation_button.pressed.connect(_open_operation)
 objective_label=Label.new(); objective_label.add_theme_font_size_override("font_size",18); root.add_child(objective_label)
 _anchor(objective_label,Control.PRESET_TOP_LEFT,Rect2(20,86,580,70))
 zone_label=Label.new(); zone_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; zone_label.add_theme_font_size_override("font_size",20); root.add_child(zone_label)
 _anchor(zone_label,Control.PRESET_CENTER_TOP,Rect2(-180,18,360,30))
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
 interact_hint=Label.new(); interact_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; interact_hint.add_theme_font_size_override("font_size",18); interact_hint.add_theme_color_override("font_color",Color("e6d99e")); root.add_child(interact_hint)
 _anchor(interact_hint,Control.PRESET_CENTER,Rect2(-260,74,520,30))
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
 if not profiles.profile.is_empty(): slider.value=float(profiles.profile.get("settings",{}).get("sensitivity",1.0))
 _anchor(timer_label,Control.PRESET_TOP_RIGHT,Rect2(-320,18,300,36))
 _anchor(notification,Control.PRESET_CENTER_TOP,Rect2(-320,164,640,50))
 _anchor(hit_marker,Control.PRESET_CENTER,Rect2(-19,-33,38,60))
 _anchor(damage_label,Control.PRESET_CENTER,Rect2(-150,-75,300,35)); damage_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 _anchor(shot_label,Control.PRESET_CENTER,Rect2(-10,25,30,30))
 _ignore_labels(hud)
 inventory_panel=InventoryPanel.new(); hud.add_child(inventory_panel); inventory_panel.setup(profiles.inventory.catalog)
 inventory_panel.command_requested.connect(_inventory_command)
 inventory_panel.closed.connect(_close_inventory)
 inventory_panel.depart.connect(_reset.bind(false))
 inventory_panel.resume_raid.connect(_reset.bind(false))
 inventory_panel.quick_equip.connect(func(): _camp_action(profiles.quick_equip()))
 inventory_panel.purchase.connect(func(id): _camp_action(profiles.purchase(id)))
 inventory_panel.sell.connect(func(id,amount): _camp_action(profiles.sell(id,amount)))
 inventory_panel.sort_requested.connect(_sort_inventory)
 inventory_panel.save_and_return.connect(_save_and_return)
 inventory_panel.abandon_raid.connect(_abandon_raid)
 inventory_panel.operation_requested.connect(_open_operation)
 inventory_panel.visible=false
 operation_panel=OperationPanel.new(); hud.add_child(operation_panel)
 operation_panel.setup(profiles.missions,profiles.rules)
 operation_panel.closed.connect(_close_operation)
 operation_panel.warehouse_requested.connect(_operation_warehouse)
 operation_panel.depart.connect(_reset.bind(false))
 operation_panel.resume_raid.connect(_reset.bind(false))
 operation_panel.mission_accepted.connect(func(id): _operation_result(profiles.accept_mission(id)))
 operation_panel.mission_claimed.connect(func(id): _operation_result(profiles.claim_mission(id)))
 operation_panel.difficulty_changed.connect(func(id): _operation_result(profiles.set_difficulty(id)))
 operation_panel.visible=false
 for label in [status,combat_status,timer_label,notification,objective_label,zone_label]:
  label.add_theme_color_override("font_outline_color",Color(0.03,0.06,0.04,0.9)); label.add_theme_constant_override("outline_size",4)

func _show_menu(title: String, text: String):
 operation_panel.visible=false
 inventory_panel.visible=false
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

func _search_point(entry: Dictionary) -> Vector3:
 var node: Node3D=entry.node
 if entry.get("kind","")=="corpse":
  var visual=node.get_node("Visual")
  var point: Vector3=visual.to_global(visual.pose_markers().torso)
  point.y=maxf(point.y,node.global_position.y+0.22)
  return point
 return node.global_position

func _can_reach_search(entry: Dictionary,max_distance := 2.3) -> bool:
 if not is_instance_valid(player) or not is_instance_valid(entry.get("node")): return false
 if entry.get("kind","")=="corpse" and entry.enemy.health.hp>0: return false
 var point=_search_point(entry)
 if player.global_position.distance_to(point)>=max_distance: return false
 var query=PhysicsRayQueryParameters3D.create(player.global_position+Vector3(0,motor.eye_height,0),point,Layers.WORLD)
 query.exclude=[player.get_rid()]
 return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _nearest_search_target() -> Dictionary:
 var nearest: Dictionary={}
 var distance=INF
 for entry in crates+corpses:
  if not _can_reach_search(entry): continue
  var current=player.global_position.distance_squared_to(_search_point(entry))
  if current<distance:
   nearest=entry; distance=current
 return nearest

func _interaction_search_target() -> Dictionary:
 var target=_nearest_search_target()
 if target.is_empty() or extraction.nearby(player.position).is_empty(): return target
 # In an exit, looking at the body/container selects search; looking away
 # retains extraction. A full bag or a pile of bodies cannot trap the player.
 var direction=(_search_point(target)-camera.global_position).normalized()
 return target if direction.dot(-camera.global_basis.z)>0.98 else {}

func _open_search(entry: Dictionary):
 var candidate=_runtime_candidate()
 if not candidate.get("active_raid",{}).get("search",{}).has(entry.cid): return
 candidate.active_raid.search[entry.cid].opened=true
 var saved=profiles.commit(candidate)
 if not saved.ok: _storage_error(saved.reason); return
 active_crate=entry
 _sync_crates()
 searching=true
 inventory_context="search"; search_elapsed=float(profiles.profile.active_raid.search[entry.cid].elapsed)
 _cancel_controls(); _sync_input_context()
 _refresh_search()

func _interact():
 if not playing or searching: return
 if training_mode:
  if combat_drill: _toast("演练不产生战利品；进入封锁区可搜索被击败的守卫",4)
  return
 var target=_interaction_search_target()
 if not target.is_empty():
  _open_search(target)
  return
 if not extraction.nearby(player.position).is_empty():
  var result=extraction.begin(player.position,hp>0,_has_raid_item)
  if not result.ok: _toast(_reason(result.reason),4); return
  if result.reason=="started":
   if not _checkpoint(): return
   _toast("%s · 留在区域 %.0f 秒%s" % [result.exit.title,result.exit.wait,"，撤离时消耗通行证" if not result.exit.required_item.is_empty() else ""],4)
  return
 _toast("靠近补给箱或被击败的守卫后搜索")

func _refresh_search():
 inventory_panel.render(profiles.profile,"search",active_crate.cid,"raid_pack",profiles.revealed_ids(active_crate.cid))
 var search=profiles.profile.active_raid.search[active_crate.cid]
 var body=search.get("kind","")=="corpse"
 if profiles.inventory.contents(profiles.profile,active_crate.cid).is_empty():
  inventory_panel.set_notice("敌人物资已取空 · 可以关闭并继续行动" if body else "补给箱已取空 · 可以关闭并继续行动")
 elif search.revealed<search.order.size():
  inventory_panel.set_notice(("正在搜查敌人物资" if body else "正在搜索")+" %d / %d · 每 0.7 秒揭示一件；搜索时世界暂停" % [search.revealed,search.order.size()])
 else:
  inventory_panel.set_notice("搜索完成 · 选择物资拾取；背包满时剩余物资留在"+("原处" if body else "箱内"))

func _update_interaction_prompt(delta: float):
 interaction_clock+=delta
 if interaction_clock<0.12: return
 interaction_clock=0.0
 interact_hint.text=""
 interact_button.text="搜索 / 撤离"
 if training_mode: return
 for entry in corpses:
  var label: Label3D=entry.enemy.label
  var point=_search_point(entry)
  label.position=entry.node.to_local(point)+Vector3(0,0.40,0)
  label.font_size=20; label.pixel_size=0.002; label.outline_size=4
  label.scale=Vector3.ONE*maxf(1.0,camera.global_position.distance_to(point)*0.5)
  label.text="物资已取空" if entry.items.is_empty() else "敌人物资 · 可搜索"
  label.modulate=Color("adb29c") if entry.items.is_empty() else Color("e6d99e")
  label.visible=_can_reach_search(entry,8.0)
 var nearby=_interaction_search_target()
 if not nearby.is_empty():
  var body=nearby.get("kind","")=="corpse"
  interact_button.text="搜索敌人" if body else "搜索补给"
  interact_hint.text="E / 搜索按钮 · "+("敌人物资已取空" if body and nearby.items.is_empty() else "搜查敌人物资" if body else "搜索补给箱")
 elif not extraction.nearby(player.position).is_empty():
  interact_button.text="开始撤离"
  interact_hint.text="E / 撤离按钮 · 查看撤离条件"

func _take_item(item):
 if active_crate==null or not item.has("instance_id"): return
 _inventory_command({"item_id":item.instance_id,"quantity":item.quantity,"from":active_crate.cid,"to":"raid_pack"})

func _take_all():
 if active_crate!=null: _inventory_command({"action":"take_all","from":active_crate.cid,"to":"raid_pack"})

func _close_search():
 if not training_mode and not _checkpoint(): return
 searching=false
 search_ui.visible=false
 inventory_panel.visible=false
 operation_panel.visible=false
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
  reload_audio_stage=-1
  _toast("正在换弹…",weapon_runtime.definition.reload_duration)

func _pause_game():
 if not playing: return
 if not training_mode and not _checkpoint(): return
 playing=false; paused=true
 searching=false; inventory_panel.visible=false
 operation_panel.visible=false
 _cancel_controls()
 _sync_input_context()
 var panel=menu.get_child(1)
 panel.get_node("Title").text="行动暂停"
 panel.get_node("Body").text="继续后需重新按下移动或开火。\n可以在这里调整观察灵敏度。"
 panel.get_node("Info").text=("战斗演练 · 无损失" if combat_drill else "靶场练习 · 无损失") if training_mode else "进度已保存；返回营地后可继续本局。"
 camp_button.text="返回营地" if training_mode else "保存并返回营地"
 primary_button.text="继续行动"
 camp_button.visible=true
 menu.visible=true

func _resume():
 if save_failed:
  if save_error_context=="camp":
   var retried=profiles.commit(profiles.profile)
   if not retried.ok: _storage_error(retried.reason); return
   save_failed=false
   _open_camp("存档写入已恢复，请重新执行刚才未提交的物品操作。")
   return
  if not pending_settlement.is_empty():
   var pending=pending_settlement.duplicate(); pending_settlement.clear()
   if pending.get("raid_id","")!=profiles.profile.active_raid.get("raid_id",""):
    _open_camp("已保留当前进度，旧结算请求已失效。"); return
   playing=true; _finish(pending.success,pending.why); return
  if not _checkpoint(): return
 inventory_panel.visible=false
 operation_panel.visible=false
 menu.visible=false; playing=true; paused=false
 _cancel_controls()
 _sync_input_context()

func _save():
 _checkpoint()
func _load_save():
 var root_path="res://user_data/saves" if OS.get_name()=="Windows" and OS.has_feature("editor") else "user://saves"
 if not save_path_override.is_empty(): root_path=save_path_override
 var legacy=OS.get_environment("EMBER_LEGACY_FILE")
 if legacy.is_empty(): legacy="user://progress.json"
 profiles.initialize(test_mode,root_path,legacy)
 if not profiles.profile.is_empty(): wealth=int(profiles.profile.currency); wins=int(profiles.profile.wins)

func _finish(success: bool, why: String):
 if not playing: return
 if combat_drill:
  weapon_runtime.disable()
  _show_menu("演练结束",why+"\n演练不影响仓库，可再次进入练习。")
  return
 if training_mode: return
 # Death is authoritative even when it coincides with an exit's final tick.
 if hp<=0: success=false
 var candidate=_runtime_candidate()
 var chosen_exit=extraction.definition(extraction.exit_id)
 if success and not chosen_exit.is_empty():
  if not chosen_exit.required_item.is_empty():
   var consumed=profiles.inventory.consume(candidate,"raid_pack",chosen_exit.required_item,1)
   if not consumed.ok:
    extraction.cancel(); _toast("通行证不足，撤离已取消"); return
   candidate=consumed.candidate
  candidate.active_raid.exit_id=chosen_exit.id
 var result=profiles.settle(profiles.profile.active_raid.raid_id,success,candidate)
 if not result.ok:
  pending_settlement={"raid_id":profiles.profile.active_raid.raid_id,"success":success,"why":why}; _storage_error(result.reason); return
 pending_settlement.clear()
 save_failed=false
 wealth=int(profiles.profile.currency); wins=int(profiles.profile.wins)
 var failure_text="舒适规则：已穿戴装备送回仓库，背包物资丢失。" if result.get("kept_equipment",false) else "标准规则：本局装备与背包丢失，仓库保留。"
 _show_menu("撤离成功" if success else "行动结束",("装备与物资已入库，仓库满时进入收件区。\n到行动简报提交任务领取奖励；出售物资后获得资产。" if success else why+"\n"+failure_text+"\n快速配装后可继续出发。"))
 primary_button.text="返回行动简报"

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
  if operation_panel.visible: _close_operation(); return
  if inventory_panel.visible: _close_inventory(); return
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
 if frame.get("operation",false): _open_operation()
 if frame.get("bag",false): _open_bag()
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
 feedback.step(delta)
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
 if not training_mode and was_reloading and reload_time<=0:
  if not _checkpoint(): return
 if healing_remaining>0:
  healing_remaining=maxf(0.0,healing_remaining-delta)
  if healing_remaining<=0:
   meds-=1; player_health.heal(45); _toast("治疗完成",1.0)
   if not training_mode and not _checkpoint(): return
  frame.move*=0.45
 var sprint_allowed=not frame.fire and not frame.aim and reload_time<=0 and healing_remaining<=0
 motor.step(player,frame,rig.yaw,sprint_allowed,delta)
 actions.step(frame,reload_time>0 or healing_remaining>0,delta,motor.crouching)
 rig.aiming=frame.aim and player.is_on_floor() and reload_time<=0 and healing_remaining<=0 and actions.raise_time<=0
 aim_button.text="取消瞄准" if rig.aiming else "瞄准"
 crouch_button.text="起身" if motor.crouching else "蹲下"
 if motor.blocked_stand: _toast("上方空间不足，暂时无法起身",1.5)
 player.rotation.y=rig.yaw
 rig.update_camera(camera,player,motor.eye_height,[player.get_rid()],delta)
 _update_aim(frame.move.length())
 _update_player_visual(delta)
 if frame.fire and actions.can_fire(reload_time>0 or healing_remaining>0):
  if ammo>0: _try_fire()
  elif reserve>0: _reload()
 if not playing: return
 _update_enemies(delta)
 if not playing: return
 _update_interaction_prompt(delta)
 if not training_mode:
  if hp<=0: _finish(false,"你在行动中倒下了。"); return
  _update_objectives(delta)
  if not playing: return
  var exit_state=extraction.step(delta,player.position,hp>0,_has_raid_item)
  if exit_state.status=="cancelled": _toast(_reason(exit_state.reason))
  elif exit_state.status=="complete": _finish(true,exit_state.exit.title); return
 var value=0
 for c in bag: value+=int(c.value)
 status.text="生命 %d   弹药 %d/%d   医疗 %d   背包 %.1f/25 kg" % [hp,ammo,reserve,meds,0.0 if training_mode else profiles.inventory.weight(profiles.profile,"raid_pack")]
 combat_status.text="头盔 %.0f  ·  护甲 %.0f  ·  击败 %d  ·  %s" % [player_health.head_armor,player_health.body_armor,kills,_weapon_status()]
 timer_label.text=("演练 · 守卫 %d/2" % kills if combat_drill else "靶场 · 命中 %d 次" % training_hits) if training_mode else ("撤离 %.1f 秒" % extract_time if extract_time>0 else "剩余 %d:%02d · 撤离 %d 米" % [int(remaining)/60,int(remaining)%60,int(player.position.distance_to(exit_pos))])
 if not training_mode:
  checkpoint_elapsed+=delta
  if checkpoint_elapsed>=10.0: _checkpoint()

func _update_aim(move_amount := 0.0):
 var target=aim_resolver.target_point(camera,player)
 var mount=player.global_position+Vector3(0,motor.eye_height-0.15,0)
 var target_behind=(target-mount).dot(rig.direction())<=0.1
 var visual_target=mount+rig.direction()*60.0 if target_behind else target
 var sway=sin(motor.move_phase)*0.008*move_amount
 # At ADS the sight marker lies on the camera axis. Use the same physical
 # muzzle for aim obstruction and damage in either view.
 gun.position=Vector3(0.22+sway,-0.22-abs(sway)*0.5,-0.62+recoil*0.045)
 gun.look_at(visual_target,Vector3.UP)
 if rig.aiming:
  gun.basis=Basis.IDENTITY
  gun.position=Vector3(0,-gun.get_node("Aim").position.y,-0.62+recoil*0.045)
 elif reload_time>0:
  gun.rotate_object_local(Vector3.FORWARD,0.18*sin(_reload_progress(weapon_runtime)*PI))
  gun.position.y+=0.075*sin(_reload_progress(weapon_runtime)*PI)
 elif motor.sprinting:
  gun.rotate_object_local(Vector3.RIGHT,-0.38)
  gun.position.y-=0.05
 var carried=player.get_node("Visual/CarriedRifle")
 carried.position=Vector3(0.10,1.34-(1.55-motor.eye_height)*0.88,-0.10)
 carried.look_at(visual_target,Vector3.UP)
 if motor.sprinting: carried.rotate_object_local(Vector3.RIGHT,-0.38)
 var current_weapon=carried if rig.third_person else gun
 var origin=current_weapon.get_node("Muzzle").global_position
 aim_solution=aim_resolver.solve(player,mount,origin,target)
 aim_solution.blocked=aim_solution.blocked or target_behind
 crosshair.visible=not rig.aiming or rig.third_person or aim_solution.blocked
 crosshair.blocked=aim_solution.blocked
 crosshair.spread_pixels=4.0+_player_spread()*400.0
 aim_hint.text="枪口受阻 · 后退或换个角度" if aim_solution.blocked else ("举枪中" if actions.raise_time>0 else "")

func _try_fire() -> bool:
 if not playing or searching or healing_remaining>0 or not actions.can_fire(reload_time>0): return false
 last_shot=weapon_runtime.request_fire(player,aim_solution,combat,_player_spread())
 if not last_shot.accepted: return false
 shot_time=0.08; recoil=1.0; shot_label.visible=true
 gun.fire()
 player.get_node("Visual/CarriedRifle").fire()
 _present_shot(last_shot,player)
 for enemy in enemies:
  if enemy.brain!=null: enemy.brain.hear(player.global_position,1.0)
 rig.kick()
 return true

func _reload_progress(state) -> float:
 return clampf(1.0-state.reload_remaining/state.definition.reload_duration,0,1) if state.reload_remaining>0 else -1.0

func _visual_frame(body: CharacterBody3D,state,dead: bool) -> Dictionary:
 return {"speed":Vector2(body.velocity.x,body.velocity.z).length(),"local_velocity":body.basis.inverse()*body.velocity,"grounded":body.is_on_floor(),"crouching":false,"sprinting":false,"aiming":false,"aim_pitch":0.0,"reload_progress":_reload_progress(state),"healing_progress":-1.0,"recoil":0.0,"dead":dead}

func _update_player_visual(delta: float):
 var frame=_visual_frame(player,weapon_runtime,hp<=0)
 frame.merge({"crouching":motor.crouching,"sprinting":motor.sprinting,"aiming":rig.aiming,"aim_pitch":rig.pitch,"recoil":recoil,"healing_progress":1.0-healing_remaining/2.2 if healing_remaining>0 else -1.0},true)
 gun.step(delta,frame)
 var visual=player.get_node("Visual")
 visual.get_node("CarriedRifle").step(delta,frame)
 if delta<=0: visual.seek_pose(frame)
 else: visual.step(delta,frame)
 combat.sync_visual_pose(player)
 if delta<=0: return
 footstep_distance+=frame.speed*delta if frame.grounded else 0.0
 var interval=2.8 if motor.sprinting else 1.9 if motor.crouching else 2.2
 if footstep_distance>=interval and frame.speed>0.1:
  footstep_distance=fmod(footstep_distance,interval)
  feedback.footstep(player.global_position,motor.sprinting,motor.crouching)
 if frame.reload_progress<0: reload_audio_stage=-1
 else:
  var stage=0 if frame.reload_progress<0.35 else 1 if frame.reload_progress<0.75 else 2
  if stage!=reload_audio_stage:
   feedback.reload_stage(player.global_position+Vector3(0,motor.eye_height,0),stage,true)
   reload_audio_stage=stage

func _update_enemies(delta):
 for enemy in enemies:
  var node: CharacterBody3D=enemy.node
  if not is_instance_valid(node): continue
  var visual=node.get_node("Visual")
  var rifle=visual.get_node("CarriedRifle")
  var dead=enemy.health.hp<=0
  if dead or enemy.brain==null:
   var pose=_visual_frame(node,enemy.weapon,dead)
   pose.grounded=true
   rifle.step(delta,pose); visual.step(delta,pose)
   if not dead: combat.sync_visual_pose(node)
   continue
  var previous_reload=enemy.weapon.reload_remaining
  enemy.weapon.tick(delta)
  var observation={"visible":false,"confirmed":false}
  if deployment_grace<=0: observation=enemy.sensor.observe(node,player,delta)
  var intent=enemy.brain.step(delta,observation)
  if intent.aiming: rifle.look_at(intent.aim_point,Vector3.UP)
  else: rifle.rotation=Vector3(-0.25,0,0)
  var speed=Vector2(node.velocity.x,node.velocity.z).length()
  enemy.stride+=delta*speed
  if enemy.stride>2.3 and speed>0.1 and node.position.distance_to(player.position)<22:
   enemy.stride=fmod(enemy.stride,2.3)
   feedback.footstep(node.global_position,false,false)
  if enemy.weapon.ammo<=0: enemy.weapon.request_reload()
  var pose=_visual_frame(node,enemy.weapon,false)
  pose.aiming=intent.aiming
  rifle.step(delta,pose); visual.step(delta,pose)
  combat.sync_visual_pose(node)
  if previous_reload<=0 and enemy.weapon.reload_remaining>0: feedback.reload_stage(node.global_position,0,false)
  if intent.fire:
   var solution=aim_resolver.solve(node,node.global_position+Vector3(0,1.3,0),rifle.get_node("Muzzle").global_position,intent.aim_point)
   var spread=enemy.weapon.definition.move_spread if speed>0.1 else enemy.weapon.definition.aim_spread
   var shot=enemy.weapon.request_fire(node,solution,combat,spread)
   if shot.accepted:
    rifle.fire()
    last_enemy_shot=shot
    _present_shot(shot,node)
    if hp<=0: _finish(false,"你在交战中倒下了。"); return
  var label: Label3D=enemy.label
  var role="指挥官 · " if not training_mode and world_map_id=="depot_v1" and enemy.get("id","")=="guard_06" else ""
  label.text=role+(_guard_state_text(enemy.brain.state) if enemy.weapon.reload_remaining<=0 else "换弹中")
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
 else: _open_camp(); _open_operation()

func _return_camp():
 _save_and_return()

func _sync_input_context():
 input_router.set_enabled(playing and not searching)
 if is_instance_valid(interact_hint):
  interact_hint.visible=playing and not searching
  if not playing: interact_hint.text=""
 if not playing or searching: _stop_audio()

func _cancel_controls():
 _stop_audio()
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
 if what==NOTIFICATION_WM_CLOSE_REQUEST:
  if training_mode or not is_instance_valid(player) or profiles.profile.is_empty() or profiles.profile.active_raid.is_empty() or _checkpoint(): get_tree().quit()
  return
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
   var context: Node=operation_panel if operation_panel.visible else (inventory_panel if inventory_panel.visible else (menu if menu.visible else (search_ui if search_ui.visible else hud_root)))
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
 if node is Control and node.clip_contents and not node.get_global_rect().has_point(point): return null
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
 feedback.shot(shot.origin,shot.end_point,shot.get("normal",Vector3.UP),shot.hit_world,shooter==player)
 var rifle=gun if shooter==player and not rig.third_person else shooter.get_node("Visual/CarriedRifle")
 feedback.casing(rifle.get_node("Eject").global_position,rifle.global_basis.x)
 if shot.actor==null or shot.health_damage+shot.armor_damage<=0: return
 if shot.actor==player:
  damage_label.text="受击  生命 -%.1f / 护甲 -%.1f" % [shot.health_damage,shot.armor_damage]
  damage_label.add_theme_color_override("font_color",Color("ff7568")); damage_label.visible=true; damage_time=0.9
  return
 if shooter==player:
  hit_marker.visible=true; hit_time=0.25; feedback.hit()
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
    enemy.node.get_node("Visual").set_dead_pose(false)
    kills+=1; damage_label.text="击败守卫"; damage_time=1.2
    if not training_mode: _record_raid_event("kill",enemy.get("id",""))
    if combat_drill and kills>=2: _toast("演练完成！Esc 可重开或返回营地",8)
  break

func _exit_tree():
 _stop_audio()
 # The save validator is bound to ProfileService; release its reference cycle.
 profiles.saves.configure(profiles.saves.root_path)
 if drill_navigation!=null: drill_navigation.dispose()
 world_navigation.dispose()

func _stop_audio():
 if is_instance_valid(feedback): feedback.stop()

func _runtime_candidate() -> Dictionary:
 var candidate=profiles.profile.duplicate(true)
 if training_mode or candidate.get("active_raid",{}).is_empty() or not is_instance_valid(player) or runtime_raid_id!=candidate.active_raid.raid_id: return candidate
 # Pack quantities own reserves. Loaded ammunition belongs to the rifle instance.
 for pair in [["ammo_rifle",reserve],["medkit_basic",meds]]:
  var stored=profiles.inventory.quantity(candidate,"raid_pack",pair[0])
  var used=stored-int(pair[1])
  if used>0:
   var consumed=profiles.inventory.consume(candidate,"raid_pack",pair[0],used)
   if consumed.ok: candidate=consumed.candidate
 var rifle=profiles.equipment(candidate,"weapon")
 if not rifle.is_empty(): rifle.runtime={"ammo":ammo}
 for pair in [["helmet",player_health.head_armor],["vest",player_health.body_armor]]:
  var item=profiles.equipment(candidate,pair[0])
  if not item.is_empty(): item.durability=pair[1]
 candidate.active_raid.snapshot=snapshot_codec.capture(self)
 candidate.active_raid.events=raid_events.duplicate(true)
 if searching and inventory_context=="search" and active_crate!=null:
  candidate.active_raid.search[active_crate.cid].elapsed=search_elapsed
 candidate.settings.sensitivity=input_router.mouse_sensitivity/0.003
 return candidate

func _sync_inventory_runtime():
 if profiles.profile.active_raid.is_empty(): return
 bag=profiles.inventory.contents(profiles.profile,"raid_pack")
 reserve=profiles.inventory.quantity(profiles.profile,"raid_pack","ammo_rifle")
 meds=profiles.inventory.quantity(profiles.profile,"raid_pack","medkit_basic")
 var rifle=profiles.equipment(profiles.profile,"weapon")
 ammo=int(rifle.get("runtime",{}).get("ammo",0))
 var helmet=profiles.equipment(profiles.profile,"helmet")
 var vest=profiles.equipment(profiles.profile,"vest")
 player_health.head_armor=float(helmet.get("durability",0))
 player_health.body_armor=float(vest.get("durability",0))

func _sync_crates():
 if profiles.profile.active_raid.is_empty(): return
 for crate in crates:
  crate.items=profiles.inventory.contents(profiles.profile,crate.cid)
  crate.opened=profiles.profile.active_raid.search[crate.cid].opened
  crate.node.get_child(0).material_override=mat(Color("8b9a77") if crate.opened else Color("d5a35b"))
 _sync_corpses()

func _sync_corpses():
 if training_mode or profiles.profile.active_raid.is_empty():
  corpses.clear()
  return
 var previous={}
 for entry in corpses: previous[entry.cid]=entry
 var current: Array=[]
 for index in range(enemies.size()):
  var enemy=enemies[index]
  if not is_instance_valid(enemy.node) or enemy.health.hp>0 or enemy.brain==null: continue
  var cid="loot_guard_%02d" % index
  var search=profiles.profile.active_raid.search.get(cid,{})
  if search.is_empty(): continue
  var contents=profiles.inventory.contents(profiles.profile,cid)
  var entry: Dictionary=previous.get(cid,{"node":enemy.node,"cid":cid,"kind":"corpse","enemy":enemy})
  entry.items=contents; entry.opened=search.opened
  current.append(entry)
  var has_rifle=false
  for item in contents:
   if item.definition_id=="rifle_basic": has_rifle=true; break
  enemy.node.get_node("Visual/CarriedRifle").visible=has_rifle
 corpses=current
 interaction_clock=0.12

func _checkpoint() -> bool:
 if training_mode or profiles.profile.is_empty() or profiles.profile.active_raid.is_empty(): return true
 var result=profiles.commit(_runtime_candidate())
 if not result.ok: _storage_error(result.reason); return false
 save_failed=false; checkpoint_elapsed=0
 _sync_inventory_runtime()
 _sync_crates()
 return true

func _storage_error(reason: String):
 if not save_failed: save_error_context="game" if runtime_raid_id!="" and is_instance_valid(player) and (playing or paused) else "camp"
 save_failed=true; playing=false; paused=true; searching=false
 _cancel_controls(); _sync_input_context()
 inventory_panel.visible=false; search_ui.visible=false
 operation_panel.visible=false
 menu.visible=true
 var panel=menu.get_child(1)
 panel.get_node("Title").text="存档暂未完成"
 panel.get_node("Body").text="%s\n操作尚未提交，游戏已暂停。处理后重试，已有正式存档保留。" % _reason(reason)
 panel.get_node("Info").text="存档目录："+ProjectSettings.globalize_path(profiles.saves.root_path)
 primary_button.text="重试保存并继续"
 camp_button.visible=false

func _open_camp(message := ""):
 if profiles.blocked:
  _show_menu("存档需要处理","无法读取现有存档：%s\n已保留文件，不会用空白进度覆盖。\n仍可进入无损失靶场。" % profiles.last_error)
  primary_button.disabled=true
  return
 playing=false; paused=false; searching=false; training_mode=false; combat_drill=false
 runtime_raid_id=""
 _stop_audio(); _cancel_controls(); _sync_input_context()
 menu.visible=false; search_ui.visible=false
 operation_panel.visible=false
 inventory_context="camp"
 wealth=int(profiles.profile.currency); wins=int(profiles.profile.wins)
 inventory_panel.render(profiles.profile,"camp","stash_main","raid_pack" if not profiles.profile.active_raid.is_empty() else "loadout_pack")
 if not profiles.profile.active_raid.is_empty(): inventory_panel.set_notice("上局进度已保存。点击继续上局；出战背包与装备暂时锁定。")
 elif not message.is_empty(): inventory_panel.set_notice(message)
 elif not profiles.warning.is_empty(): inventory_panel.set_notice("已恢复可用存档："+profiles.warning)

func _open_bag():
 if not playing or searching: return
 if training_mode: _toast("练习模式不消耗仓库物资"); return
 if not _checkpoint(): return
 searching=true; inventory_context="bag"; active_crate=null
 _cancel_controls(); _sync_input_context()
 inventory_panel.render(profiles.profile,"bag","raid_pack","raid_pack")
 inventory_panel.set_notice("行动背包 · 点击物品，再点空格可移动或旋转；管理时世界暂停")

func _close_inventory():
 if inventory_context=="camp":
  _show_menu("余烬行动 · 第五阶段","WASD 移动 · Shift 快跑 · 空格跳跃 · C 蹲下\nV 切换视角 · X / 右键瞄准 · R 换弹\nE 搜索 / 撤离 · B 背包 · M 地图 / 任务 · Q 治疗\n\n先在行动简报接任务并选择规则，再到仓库配装。\n搜索和背包管理时暂停世界；Esc 暂停行动。")
  primary_button.text="打开行动简报"
 else: _close_search()

func _render_inventory():
 if inventory_context=="search" and active_crate!=null: _refresh_search()
 elif inventory_context=="bag": inventory_panel.render(profiles.profile,"bag","raid_pack","raid_pack")
 else: inventory_panel.render(profiles.profile,"camp","stash_main","raid_pack" if not profiles.profile.active_raid.is_empty() else "loadout_pack")

func _inventory_command(command: Dictionary):
 var result=profiles.execute(command,profiles.profile if inventory_context=="camp" else _runtime_candidate())
 if not result.ok:
  if not profiles.last_error.is_empty() and result.reason==profiles.last_error: _storage_error(result.reason)
  else: inventory_panel.set_notice(_reason(result.reason),true)
  return
 if inventory_context!="camp": _sync_inventory_runtime(); _sync_crates()
 _render_inventory()
 inventory_panel.set_notice("已保存 · 转移 %d 件；放不下的物资留在原处" % int(result.get("quantity",0)))

func _sort_inventory(cid: String):
 var result=profiles.sort_container(cid,profiles.profile if inventory_context=="camp" else _runtime_candidate())
 if not result.ok: inventory_panel.set_notice(_reason(result.reason),true); return
 if inventory_context!="camp": _sync_inventory_runtime()
 _render_inventory(); inventory_panel.set_notice("已整理并保存")

func _camp_action(result: Dictionary):
 if not result.ok: inventory_panel.set_notice(_reason(result.reason),true); return
 wealth=int(profiles.profile.currency); wins=int(profiles.profile.wins)
 _render_inventory(); inventory_panel.set_notice("操作已保存 · 出战前检查装备、弹药和药包")

func _save_and_return():
 if not training_mode and not _checkpoint(): return
 _open_camp("本局进度已保存，可点击继续上局。" if not profiles.profile.get("active_raid",{}).is_empty() else "营地仓库 · 配装后再次出发")

func _abandon_raid():
 if profiles.profile.active_raid.is_empty(): return
 var result=profiles.settle(profiles.profile.active_raid.raid_id,false)
 if not result.ok: inventory_panel.set_notice(_reason(result.reason),true); return
 pending_settlement.clear()
 _open_camp("已放弃本局。"+("舒适规则保留穿戴装备，背包丢失。" if result.get("kept_equipment",false) else "标准规则丢失装备与背包。")+"快速配装可继续出发。")

func _process(delta):
 if playing and searching and inventory_context=="search" and active_crate!=null: _advance_search(delta)

func _advance_search(delta: float):
 if not searching or active_crate==null or save_failed: return
 var search=profiles.profile.active_raid.search[active_crate.cid]
 if int(search.revealed)>=search.order.size(): return
 search_elapsed+=maxf(delta,0.0)
 if search_elapsed<0.7: return
 var candidate=_runtime_candidate()
 var progress=candidate.active_raid.search[active_crate.cid]
 progress.revealed=mini(progress.order.size(),int(progress.revealed)+int(search_elapsed/0.7))
 search_elapsed=fmod(search_elapsed,0.7); progress.elapsed=search_elapsed
 var result=profiles.commit(candidate)
 if not result.ok: _storage_error(result.reason); return
 _refresh_search()

func _reason(reason: String) -> String:
 var phase4={"pass_required":"维修通道需要一张通行证，可在东侧通信站补给箱搜索；撤离时消耗","left_exit":"已离开撤离区，撤离取消","mission_not_ready":"任务尚未完成，先满足目标并成功撤离","active_raid_exists":"请先继续或结束当前对局，再修改任务与规则","mission_not_available":"任务已接受或已经交付","already_claimed":"奖励已经领取","invalid_rule":"该难度规则不可用","not_at_exit":"请先到达撤离区域"}
 if phase4.has(reason): return phase4[reason]
 return {"no_space":"空间不足，请整理背包或减少数量","overweight":"超过背包 25 kg 重量限制","stale_revision":"物品已变化，请重新选择","not_revealed":"物品仍在搜索中","wrong_slot":"这件物品无法放入该装备槽","slot_occupied":"装备槽已有物品，请先卸下","equipment_locked_in_raid":"行动中装备已锁定，请在营地配装","active_raid_exists":"请先继续或放弃上局","weapon_required":"需要先装备步枪，可点击快速配装","insufficient_currency":"资产不足，可出售仓库中的物资","bound_item":"救济物资不能出售","sell_from_stash":"只有仓库与收件区中的物品可出售","stale_generation":"另一游戏窗口更新了存档，请关闭本窗口后重新打开","directory_unwritable":"存档目录无法写入","cannot_repack":"无法自动整理，请手动调整位置","invalid_transfer_context":"无法向该容器转移","temporary_verification_failed":"临时存档校验失败，已保留原有存档","write_failed":"存档写入失败，请检查目录空间与权限","replace_failed":"无法替换存档文件，请关闭占用它的程序"}.get(reason,"操作未完成："+reason)

func _desired_map_definition() -> Dictionary:
 var active=profiles.profile.get("active_raid",{})
 return _legacy_map_definition() if active.get("map_id","")=="legacy_v3" else map_builder.definition()

func _legacy_map_definition() -> Dictionary:
 var points=[Vector3(-18,0,-19),Vector3(-8,0,-12),Vector3(4,0,-18),Vector3(18,0,-7),Vector3(-21,0,12),Vector3(-2,0,0),Vector3(8,0,12),Vector3(-4,0,25),Vector3(23,0,17)]
 var guards=[]
 for index in range(points.size()):
  var p=points[index]
  guards.append({"id":"guard_%02d" % index,"position":p,"route":[p,p+Vector3(4,0,-3),p+Vector3(5,0,4)],"label":"守卫"})
 return {"id":"legacy_v3","name":"旧版封锁区 · 保留中的对局","spawn":Vector3(-26,0,-26),"spawn_yaw":-2.35,"bounds":Rect2(-30.5,-30.5,61,61),"guards":guards,"crates":[Vector3(-22,0,-22),Vector3(-10,0,-17),Vector3(0,0,-25),Vector3(15,0,-24),Vector3(24,0,-12),Vector3(-23,0,-2),Vector3(-11,0,0),Vector3(1,0,-5),Vector3(13,0,0),Vector3(24,0,4),Vector3(-24,0,18),Vector3(-12,0,16),Vector3(1,0,14),Vector3(9,0,25),Vector3(21,0,22)],"zones":[],"survey":{},"exits":[{"id":"south_gate","title":"原撤离点","position":Vector3(25,0,25),"radius":3.6,"wait":5.0,"required_item":""}]}

func _ensure_world_map():
 var desired=_desired_map_definition()
 if world_map_id==desired.id: return
 _stop_audio()
 world_navigation.dispose()
 if drill_navigation!=null: drill_navigation.dispose(); drill_navigation=null
 if is_instance_valid(world): world.free()
 enemies.clear(); crates.clear(); corpses.clear(); player=null; training_root=null
 _build_world()

func _active_rule() -> Dictionary:
 return profiles.rules.get_rule(profiles.profile.get("active_raid",{}).get("rule_id","standard"))

func _apply_guard_rules():
 var rule=_active_rule()
 for enemy in enemies:
  var tuning=GUARD_WEAPON.duplicate()
  tuning.base_damage=GUARD_WEAPON.base_damage*float(rule.enemy_damage_scale)
  enemy.weapon.definition=tuning
  enemy.sensor.view_distance=float(rule.enemy_view_distance)
  enemy.brain.reaction_time=float(rule.enemy_reaction_time)
 if rule.id=="comfort": deployment_grace=5.0

func _has_raid_item(id: String) -> bool:
 return profiles.inventory.quantity(profiles.profile,"raid_pack",id)>0

func _record_raid_event(kind: String,target: String):
 if training_mode or runtime_raid_id.is_empty(): return
 var candidate=_runtime_candidate()
 var recorded=profiles.record_event(candidate,kind,target)
 if not recorded.ok: return
 if not recorded.get("changed",false) and kind!="kill": return
 # A physical kill/visit already happened. Retain the pending event in runtime
 # during a failed checkpoint so retry can persist it with the world snapshot.
 raid_events=candidate.active_raid.events.duplicate(true)
 var saved=profiles.commit(candidate)
 if not saved.ok: _storage_error(saved.reason); return
 _sync_crates()
 if recorded.get("changed",false): _toast("目标已记录 · 成功撤离后回营地交付",4)
 elif kind=="kill": _toast("守卫已被击败 · 靠近后按 E 搜索物资",3.5)

func _update_objectives(delta: float):
 objective_clock+=delta
 if objective_clock<0.2: return
 objective_clock=0.0
 var survey=map_definition.get("survey",{})
 if not survey.is_empty() and player.position.distance_to(survey.position)<=float(survey.radius): _record_raid_event("visit",survey.id)
 var zone_name=map_definition.name
 for zone in map_definition.zones:
  if zone.rect.has_point(Vector2(player.position.x,player.position.z)):
   zone_name=zone.title+" · "+String(zone.risk); break
 zone_label.text=zone_name
 var lines=[]
 for definition in profiles.missions.definitions():
  var state=profiles.profile.missions[definition.id]
  if state.status!="active" and state.status!="ready": continue
  var progress=int(state.progress)
  if definition.kind=="visit": progress=maxi(progress,1 if raid_events.visits.has(definition.target) else 0)
  elif definition.kind=="kill": progress=maxi(progress,1 if raid_events.kills.has(definition.target) else 0)
  else: progress=mini(definition.required,int(state.progress)+profiles.inventory.quantity(profiles.profile,"raid_pack",definition.target))
  lines.append("%s  %d/%d" % [definition.title,progress,definition.required])
 objective_label.text="\n".join(lines) if not lines.is_empty() else "M 地图 / 撤离路线 · 任务需在营地接受"

func _open_operation():
 if profiles.blocked or save_failed: return
 if playing and training_mode: _toast("练习模式不记录任务，回营地查看行动简报"); return
 operation_in_raid=playing and not training_mode
 if operation_in_raid:
  if not _checkpoint(): return
  searching=true; inventory_context="operation"; active_crate=null
  _cancel_controls(); _sync_input_context()
 inventory_panel.visible=false; menu.visible=false
 operation_panel.render(profiles.profile,_desired_map_definition(),operation_in_raid,player.position if operation_in_raid else Vector3.ZERO)
 if profiles.profile.get("active_raid",{}).get("map_id","")=="legacy_v3":
  operation_panel.set_notice("旧对局已保留：完成或放弃后，新对局将使用灰湾转运站。")

func _close_operation():
 operation_panel.visible=false
 if operation_in_raid: _close_search()
 else: _open_camp()

func _operation_warehouse():
 if operation_in_raid: return
 _open_camp()

func _operation_result(result: Dictionary):
 if not result.ok:
  operation_panel.set_notice(_reason(result.reason),true)
  return
 wealth=int(profiles.profile.currency); wins=int(profiles.profile.wins)
 operation_panel.render(profiles.profile,_desired_map_definition(),false)
 operation_panel.set_notice("已保存 · 出发前可打开仓库检查装备")

func _build_legacy_cover():
 for v in [Vector4(-18,-14,10,2),Vector4(-13,-9,2,8),Vector4(-3,-20,12,2),Vector4(9,-12,2,12),Vector4(20,-20,10,2),Vector4(-19,4,12,2),Vector4(-6,7,2,12),Vector4(5,3,11,2),Vector4(16,10,2,10),Vector4(-17,20,10,2),Vector4(3,20,10,2)]:
  box(world,Vector3(v.z,2.8,v.w),Vector3(v.x,1.4,v.y),Color("777d6d"),true)
  box(world,Vector3(v.z+0.1,0.15,v.w+0.1),Vector3(v.x,2.72,v.y),Color("505950"))
  if v.z>v.w:
   for offset in range(-int(v.z/2)+1,int(v.z/2),2):
    box(world,Vector3(0.06,2.5,0.05),Vector3(v.x+offset,1.3,v.y-v.w/2-0.04),Color("626a5f"))
  else:
   for offset in range(-int(v.w/2)+1,int(v.w/2),2):
    box(world,Vector3(0.05,2.5,0.06),Vector3(v.x-v.z/2-0.04,1.3,v.y+offset),Color("626a5f"))
