extends SceneTree

const Feedback=preload("res://scripts/presentation/combat_feedback.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
 call_deferred("run_tests")

func check(value: bool,message: String) -> void:
 checks+=1
 if not value:
  failures+=1
  push_error(message)

func run_tests() -> void:
 var fx=Feedback.new()
 root.add_child(fx)
 fx.setup()
 var initial: Dictionary=fx.metrics()
 check(initial.node_count==49,"effect and voice pools allocate exactly 49 nodes including owner")
 check(initial.active==0 and initial.voices==12,"pools initialize inactive with bounded voices")
 check(initial.sound_count==10,"original sound bank includes shot, hit, impact, steps and reload stages")
 check(not fx.is_processing() and not fx.is_physics_processing(),"external game loop owns all presentation time")
 fx.setup()
 check(fx.metrics().node_count==initial.node_count,"repeated setup does not duplicate pools")
 for index in range(100):
  var origin := Vector3(float(index)*0.02,1.2,0.0)
  fx.shot(origin,Vector3(0.0,1.2,-30.0),Vector3.BACK,true,index%2==0)
  fx.casing(origin,Vector3.RIGHT)
 check(fx.metrics().node_count==initial.node_count,"100 shots recycle nodes instead of allocating effects")
 check(fx.metrics().active==36,"effect count is bounded by three 12-instance pools")
 check(fx.metrics().voices_playing<=12,"burst playback never exceeds fixed voice pool")
 var old_position: Vector3=fx.get_node("Casing00").position
 fx.step(0.02)
 check(fx.get_node("Casing00").position.distance_to(old_position)>0.01,"casing follows explicit velocity and gravity")
 var frozen_position: Vector3=fx.get_node("Casing00").position
 var active_before: int=fx.metrics().active
 fx.stop()
 check(fx.metrics().voices_playing==0,"pause silences all audio voices")
 await process_frame
 await process_frame
 check(fx.get_node("Casing00").position==frozen_position and fx.metrics().active==active_before,"without step pause freezes effect transforms and lifetimes")
 fx.step(0.04)
 check(not fx.get_node("Tracer00").visible,"short tracer expires at configured lifetime")
 check(fx.get_node("Impact00").visible and fx.get_node("Casing00").visible,"impact and casing outlive tracer")
 fx.step(0.13)
 check(not fx.get_node("Impact00").visible and fx.get_node("Casing00").visible,"impact expires independently of casing")
 fx.step(0.6)
 check(fx.metrics().active==0,"all pooled effects expire without deleting their nodes")
 check(fx.metrics().node_count==initial.node_count,"expired pools retain fixed allocation")
 # Analytic trajectory is independent of the caller's step subdivision.
 var other=Feedback.new()
 root.add_child(other)
 other.setup()
 fx.reset()
 fx._random.seed=91
 other._random.seed=91
 fx.casing(Vector3(0.0,1.6,0.0),Vector3.RIGHT)
 other.casing(Vector3(0.0,1.6,0.0),Vector3.RIGHT)
 fx.step(0.4)
 for i in range(4): other.step(0.1)
 var fx_casing: Node3D=fx._casings[(fx._casing_cursor+11)%12].node
 var other_casing: Node3D=other._casings[0].node
 check(fx_casing.position.is_equal_approx(other_casing.position),"casing position does not depend on frame subdivision")
 check(fx_casing.rotation.is_equal_approx(other_casing.rotation),"casing spin does not depend on frame subdivision")
 # Parallel directions and zero normals must not generate invalid look-at bases.
 for direction in [Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.RIGHT]:
  fx.shot(Vector3.ZERO,direction*4.0,Vector3.ZERO,true,true)
 fx.shot(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,false,true)
 fx.shot(Vector3(NAN,0.0,0.0),Vector3.ZERO,Vector3.ZERO,true,true)
 fx.casing(Vector3.ZERO,Vector3.ZERO)
 fx.step(0.01)
 for child in fx.get_children():
  if child is MeshInstance3D:
   check(child.transform.is_finite(),"pooled effect transform remains finite: "+child.name)
 var before_invalid: int=fx.metrics().active
 fx.step(-1.0)
 fx.step(NAN)
 check(fx.metrics().active==before_invalid,"invalid delta cannot alter effect time")
 for stage in range(4): fx.reload_stage(Vector3.ONE,stage,true)
 fx.reload_stage(Vector3.ONE,99,false)
 fx.footstep(Vector3.ONE,false,false)
 fx.footstep(Vector3.ONE,true,false)
 fx.footstep(Vector3.ONE,false,true)
 fx.hit()
 check(fx.metrics().node_count==initial.node_count,"foley and reload cues reuse fixed audio voices")
 for kind in Feedback._sound_bank:
  var sound: AudioStreamWAV=Feedback._sound_bank[kind]
  check(sound.data.size()>0 and sound.mix_rate==24000 and not sound.stereo,"cached mono spatial audio has valid PCM: "+kind)
  var peak := 0
  for i in range(sound.data.size()/2): peak=maxi(peak,absi(sound.data.decode_s16(i*2)))
  check(peak>100 and peak<32767,"original audio is audible and never digitally clipped: "+kind)
 fx.reset()
 other.reset()
 check(fx.metrics().active==0 and fx.metrics().voices_playing==0,"reset clears all visible and audible feedback")
 fx.free()
 other.free()
 await create_timer(0.15).timeout
 print("COMBAT FEEDBACK: ",checks-failures,"/",checks," checks passed")
 quit(1 if failures else 0)
