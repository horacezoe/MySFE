extends Node3D
## Original, bounded presentation effects. The game owns all timing and damage.
## stop() silences the mixer for pause; reset() also clears the visual pools.

const TRACER_CAPACITY := 12
const IMPACT_CAPACITY := 12
const CASING_CAPACITY := 12
const LOCAL_VOICES := 4
const WORLD_VOICES := 8
const TRACER_LIFE := 0.045
const IMPACT_LIFE := 0.18
const CASING_LIFE := 0.7
const SAMPLE_RATE := 24000

static var _sound_bank: Dictionary = {}
var volume_db := 0.0
var _ready_once := false
var _random := RandomNumberGenerator.new()
var _tracers: Array[Dictionary] = []
var _impacts: Array[Dictionary] = []
var _casings: Array[Dictionary] = []
var _local_voices: Array[AudioStreamPlayer] = []
var _world_voices: Array[AudioStreamPlayer3D] = []
var _tracer_cursor := 0
var _impact_cursor := 0
var _casing_cursor := 0
var _local_cursor := 0
var _world_cursor := 0
var _local_started_frames := PackedInt64Array()
var _world_started_frames := PackedInt64Array()
var _audio_started := 0
var _audio_dropped := 0

func setup() -> void:
 if _ready_once: return
 _ready_once=true
 _local_started_frames.resize(LOCAL_VOICES)
 _world_started_frames.resize(WORLD_VOICES)
 _local_started_frames.fill(-1)
 _world_started_frames.fill(-1)
 _random.seed=592731
 set_process(false)
 set_physics_process(false)
 _ensure_sounds()
 var tracer_mesh := BoxMesh.new()
 tracer_mesh.size=Vector3(0.012,0.012,1.0)
 var tracer_material := _material(Color("ffd0a0"),0.6,0.0)
 tracer_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 tracer_material.emission_enabled=true
 tracer_material.emission=Color("ffc28c")
 tracer_material.emission_energy_multiplier=1.4
 var impact_mesh := _impact_mesh()
 var impact_material := _material(Color("e4bd83"),0.8,0.0)
 impact_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 impact_material.cull_mode=BaseMaterial3D.CULL_DISABLED
 var casing_mesh := CylinderMesh.new()
 casing_mesh.top_radius=0.0048
 casing_mesh.bottom_radius=0.0058
 casing_mesh.height=0.033
 casing_mesh.radial_segments=8
 casing_mesh.rings=1
 var casing_material := _material(Color("b79043"),0.32,0.78)
 for i in range(TRACER_CAPACITY):
  _tracers.append({"node":_instance("Tracer%02d" % i,tracer_mesh,tracer_material),"age":-1.0,"origin":Vector3.ZERO,"direction":Vector3.FORWARD,"distance":0.0})
 for i in range(IMPACT_CAPACITY):
  _impacts.append({"node":_instance("Impact%02d" % i,impact_mesh,impact_material),"age":-1.0})
 for i in range(CASING_CAPACITY):
  _casings.append({"node":_instance("Casing%02d" % i,casing_mesh,casing_material),"age":-1.0,"origin":Vector3.ZERO,"velocity":Vector3.ZERO,"spin":Vector3.ZERO,"rotation":Vector3.ZERO})
 for i in range(LOCAL_VOICES):
  var voice := AudioStreamPlayer.new()
  voice.name="LocalVoice%02d" % i
  voice.max_polyphony=1
  add_child(voice)
  _local_voices.append(voice)
 for i in range(WORLD_VOICES):
  var voice := AudioStreamPlayer3D.new()
  voice.name="SpatialVoice%02d" % i
  voice.max_polyphony=1
  voice.max_distance=65.0
  voice.unit_size=5.0
  voice.attenuation_model=AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
  voice.attenuation_filter_cutoff_hz=5500.0
  voice.attenuation_filter_db=-12.0
  add_child(voice)
  _world_voices.append(voice)

func _instance(label: String, mesh: Mesh, material: Material) -> MeshInstance3D:
 var node := MeshInstance3D.new()
 node.name=label
 node.mesh=mesh
 node.material_override=material
 node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 node.visible=false
 add_child(node)
 return node

func _material(color: Color,roughness: float,metallic: float) -> StandardMaterial3D:
 var material := StandardMaterial3D.new()
 material.albedo_color=color
 material.roughness=roughness
 material.metallic=metallic
 return material

func _impact_mesh() -> ArrayMesh:
 # One mesh per burst: eight short tapered streaks on the impact plane.
 var vertices := PackedVector3Array()
 var normals := PackedVector3Array()
 for i in range(8):
  var angle := TAU*float(i)/8.0
  var along := Vector3(cos(angle),sin(angle),0.0)
  var across := Vector3(-sin(angle),cos(angle),0.0)
  var length := 0.12 if i%2==0 else 0.078
  for vertex in [along*0.008-across*0.009,along*length,along*0.008+across*0.009]:
   vertices.append(vertex)
   normals.append(Vector3.BACK)
 var arrays := []
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=vertices
 arrays[Mesh.ARRAY_NORMAL]=normals
 var mesh := ArrayMesh.new()
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 return mesh

func shot(origin: Vector3,end_point: Vector3,normal: Vector3,hit_world: bool,local_shooter: bool) -> void:
 setup()
 if not origin.is_finite() or not end_point.is_finite(): return
 var offset := end_point-origin
 var distance := offset.length()
 if distance>0.02:
  var effect: Dictionary=_tracers[_tracer_cursor]
  _tracer_cursor=(_tracer_cursor+1)%TRACER_CAPACITY
  effect.age=0.0
  effect.origin=origin
  effect.direction=offset/distance
  effect.distance=distance
  _draw_tracer(effect)
 if hit_world:
  var effect: Dictionary=_impacts[_impact_cursor]
  _impact_cursor=(_impact_cursor+1)%IMPACT_CAPACITY
  effect.age=0.0
  var node: MeshInstance3D=effect.node
  var direction := normal.normalized() if normal.is_finite() and normal.length_squared()>0.001 else Vector3.UP
  node.global_position=end_point+direction*0.012
  node.global_basis=_basis(direction)
  node.scale=Vector3.ONE*0.28
  node.transparency=0.0
  node.visible=true
  _play("impact",end_point,false,-25.0,0.12)
 _play("shot",origin,local_shooter,-10.0 if local_shooter else -7.0,0.045)

func casing(origin: Vector3,direction: Vector3) -> void:
 setup()
 if not origin.is_finite() or not direction.is_finite(): return
 var effect: Dictionary=_casings[_casing_cursor]
 _casing_cursor=(_casing_cursor+1)%CASING_CAPACITY
 effect.age=0.0
 effect.origin=origin
 var side := direction.normalized() if direction.length_squared()>0.001 else Vector3.RIGHT
 effect.velocity=side*_random.randf_range(1.4,2.1)+Vector3.UP*_random.randf_range(0.8,1.2)
 effect.rotation=Vector3(_random.randf(),_random.randf(),_random.randf())*TAU
 effect.spin=Vector3(_random.randf_range(9.0,15.0),_random.randf_range(-5.0,5.0),_random.randf_range(6.0,14.0))
 var node: MeshInstance3D=effect.node
 node.global_position=origin
 node.rotation=effect.rotation
 node.scale=Vector3.ONE
 node.transparency=0.0
 node.visible=true

func step(delta: float) -> void:
 if not _ready_once or not is_finite(delta) or delta<=0.0: return
 for effect in _tracers:
  if float(effect.age)<0.0: continue
  effect.age=float(effect.age)+delta
  if float(effect.age)>=TRACER_LIFE: _expire(effect)
  else: _draw_tracer(effect)
 for effect in _impacts:
  if float(effect.age)<0.0: continue
  effect.age=float(effect.age)+delta
  if float(effect.age)>=IMPACT_LIFE: _expire(effect)
  else:
   var node: MeshInstance3D=effect.node
   var progress: float=float(effect.age)/IMPACT_LIFE
   node.scale=Vector3.ONE*(0.28+progress*1.4)
   node.transparency=progress*progress
 for effect in _casings:
  if float(effect.age)<0.0: continue
  effect.age=float(effect.age)+delta
  if float(effect.age)>=CASING_LIFE: _expire(effect)
  else:
   var node: MeshInstance3D=effect.node
   var age: float=effect.age
   node.global_position=effect.origin+effect.velocity*age+Vector3.DOWN*(4.9*age*age)
   node.rotation=effect.rotation+effect.spin*age
   node.transparency=clampf((age-0.52)/0.18,0.0,1.0)

func _draw_tracer(effect: Dictionary) -> void:
 var node: MeshInstance3D=effect.node
 var distance: float=effect.distance
 var travelled: float=minf(distance,float(effect.age)*310.0)
 var length: float=minf(5.0,maxf(0.02,distance-travelled))
 node.global_position=effect.origin+effect.direction*(travelled+length*0.5)
 node.global_basis=_basis(effect.direction)
 node.scale=Vector3(1.0,1.0,length)
 node.transparency=float(effect.age)/TRACER_LIFE*0.65
 node.visible=travelled<distance

func _basis(direction: Vector3) -> Basis:
 var helper := Vector3.RIGHT if absf(direction.dot(Vector3.UP))>0.98 else Vector3.UP
 return Basis.looking_at(direction,helper)

func _expire(effect: Dictionary) -> void:
 effect.age=-1.0
 effect.node.visible=false

func footstep(position: Vector3,sprinting: bool,crouching: bool) -> void:
 setup()
 var kind := "step_crouch" if crouching else "step_sprint" if sprinting else "step_walk"
 _play(kind,position,false,-26.0 if crouching else -17.0 if sprinting else -21.0,0.09)

func reload_stage(position: Vector3,stage: int,local_shooter: bool) -> void:
 setup()
 _play("reload%d" % clampi(stage,0,3),position,local_shooter,-17.0 if local_shooter else -23.0,0.04)

func hit() -> void:
 setup()
 _play("hit",Vector3.ZERO,true,-17.0,0.035)

func _play(kind: String,position: Vector3,local: bool,level: float,variation: float) -> void:
 if not position.is_finite(): return
 # A fixed node count alone does not bound AudioStreamPlayback allocations:
 # restarting a voice repeatedly inside one frame queues additional mixer
 # work. Each voice accepts at most one start per rendered frame; overflow
 # drops sound only and leaves every authoritative shot and visual unchanged.
 var frame := Engine.get_process_frames()
 var cursor := _local_cursor if local else _world_cursor
 var started_frames := _local_started_frames if local else _world_started_frames
 if started_frames[cursor]==frame:
  _audio_dropped+=1
  return
 if local: _local_started_frames[cursor]=frame
 else: _world_started_frames[cursor]=frame
 _audio_started+=1
 var pitch := _random.randf_range(1.0-variation,1.0+variation)
 if local:
  var voice: AudioStreamPlayer=_local_voices[_local_cursor]
  _local_cursor=(_local_cursor+1)%LOCAL_VOICES
  voice.stop()
  voice.stream=_sound_bank[kind]
  voice.volume_db=level+volume_db
  voice.pitch_scale=pitch
  voice.play()
 else:
  var voice: AudioStreamPlayer3D=_world_voices[_world_cursor]
  _world_cursor=(_world_cursor+1)%WORLD_VOICES
  voice.stop()
  voice.global_position=position
  voice.stream=_sound_bank[kind]
  voice.volume_db=level+volume_db
  voice.pitch_scale=pitch
  voice.play()

func stop() -> void:
 for voice in _local_voices:
  voice.stop()
  voice.stream=null
 for voice in _world_voices:
  voice.stop()
  voice.stream=null

func reset() -> void:
 stop()
 for pool in [_tracers,_impacts,_casings]:
  for effect in pool: _expire(effect)

func _exit_tree() -> void:
 stop()

func metrics() -> Dictionary:
 var active := 0
 var voices_playing := 0
 for pool in [_tracers,_impacts,_casings]:
  for effect in pool:
   if float(effect.age)>=0.0: active+=1
 for voice in _local_voices:
  if voice.playing: voices_playing+=1
 for voice in _world_voices:
  if voice.playing: voices_playing+=1
 return {"tracer_capacity":TRACER_CAPACITY,"impact_capacity":IMPACT_CAPACITY,"casing_capacity":CASING_CAPACITY,"active":active,"voices":LOCAL_VOICES+WORLD_VOICES,"voices_playing":voices_playing,"node_count":get_child_count()+1,"sound_count":_sound_bank.size(),"audio_started":_audio_started,"audio_dropped":_audio_dropped}

static func _ensure_sounds() -> void:
 if not _sound_bank.is_empty(): return
 var noise := RandomNumberGenerator.new()
 noise.seed=718127
 for kind in ["shot","hit","impact","step_walk","step_sprint","step_crouch","reload0","reload1","reload2","reload3"]:
  _sound_bank[kind]=_synthesize(kind,noise)

static func _synthesize(kind: String,noise: RandomNumberGenerator) -> AudioStreamWAV:
 var duration := 0.42 if kind=="shot" else 0.16 if kind.begins_with("step") else 0.13
 var count := int(duration*SAMPLE_RATE)
 var data := PackedByteArray()
 data.resize(count*2)
 var low_noise := 0.0
 for i in range(count):
  var t := float(i)/SAMPLE_RATE
  var white := noise.randf_range(-1.0,1.0)
  low_noise=lerpf(low_noise,white,0.19)
  var value := 0.0
  if kind=="shot":
   # Sharp pressure transient, body resonance, short bolt click and outdoor tail.
   var attack := minf(1.0,t*1600.0)
   var crack := white*exp(-t*180.0)*0.55
   var body := (sin(TAU*(105.0*t-52.0*t*t))*0.36+low_noise*1.1)*exp(-t*24.0)
   var bolt := white*exp(-absf(t-0.047)*320.0)*0.10
   var tail := low_noise*0.23*exp(-t*9.0)*(1.0-exp(-t*70.0))
   value=(crack+body+bolt+tail)*attack
  elif kind=="hit":
   value=(sin(TAU*1450.0*t)*0.23+sin(TAU*2100.0*t)*0.10)*exp(-t*48.0)*minf(1.0,t*1000.0)
  elif kind=="impact":
   value=(white*0.36+sin(TAU*2870.0*t)*0.13)*exp(-t*62.0)*minf(1.0,t*1500.0)
  elif kind.begins_with("step"):
   var strength := 0.48 if kind=="step_sprint" else 0.26 if kind=="step_crouch" else 0.36
   var heel := exp(-t*47.0)
   var grit := exp(-absf(t-0.048)*60.0)
   value=(sin(TAU*78.0*t)*heel+low_noise*grit*0.85+white*heel*0.13)*strength*minf(1.0,t*900.0)
  else:
   var stage := int(kind.right(1))
   var pitch: float=[740.0,460.0,1180.0,1650.0][stage]
   var click := exp(-t*95.0)
   var latch := exp(-absf(t-0.041)*180.0)*(0.4 if stage==3 else 0.18)
   value=(white*0.42+sin(TAU*pitch*t)*0.20)*(click+latch)*minf(1.0,t*1800.0)
  # A tiny tail fade keeps generated clips free of terminal discontinuities.
  value*=clampf((duration-t)/0.012,0.0,1.0)
  data.encode_s16(i*2,int(clampf(value,-0.94,0.94)*32700.0))
 var stream := AudioStreamWAV.new()
 stream.format=AudioStreamWAV.FORMAT_16_BITS
 stream.mix_rate=SAMPLE_RATE
 stream.stereo=false
 stream.data=data
 return stream
