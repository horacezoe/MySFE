extends SceneTree
## Desktop-only reproducible render/CPU sample; never loads a personal profile.
func _initialize(): call_deferred("run")

func run():
 root.size=Vector2i(1280,800)
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 Engine.max_fps=0
 var game=load("res://main.tscn").instantiate()
 game.test_mode=true
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 game._reset(true)
 game.rig.third_person=true
 game.rig.yaw=0.25
 game._apply_view()
 # The same sample scene contains player + three visible target operators.
 for i in range(120):
  game._physics_process(1.0/60.0)
  await process_frame
 var samples: Array[float]=[]
 var began=Time.get_ticks_usec()
 var cpu_total=0.0
 var previous=began
 var draws=0; var primitives=0
 while Time.get_ticks_usec()-began<8000000:
  var cpu_start=Time.get_ticks_usec()
  game._physics_process(1.0/60.0)
  cpu_total+=(Time.get_ticks_usec()-cpu_start)/1000.0
  await process_frame
  var now=Time.get_ticks_usec()
  samples.append((now-previous)/1000.0)
  previous=now
  draws=maxi(draws,root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
  primitives=maxi(primitives,root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
 samples.sort()
 var elapsed=(Time.get_ticks_usec()-began)/1000000.0
 print("DESKTOP PRESENTATION BENCHMARK ",JSON.stringify({"build":game.BUILD_ID,"gpu":RenderingServer.get_video_adapter_name(),"viewport":"1280x800","seconds":elapsed,"frames":samples.size(),"fps":samples.size()/elapsed,"frame_p95_ms":samples[int(samples.size()*0.95)],"physics_cpu_mean_ms":cpu_total/samples.size(),"max_draw_calls":draws,"max_primitives":primitives}))
 game.free()
 await create_timer(0.15).timeout
 quit()
