extends SceneTree
## Reproducible rendered QA using an isolated, in-memory profile.
var game
func _initialize(): call_deferred("capture")

func settle():
 for i in range(8):
  await physics_frame
  game._physics_process(1.0/60.0)
 await process_frame
 await RenderingServer.frame_post_draw

func shot(name: String):
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://tests/phase5_"+name+".png")

func capture():
 root.size=Vector2i(1280,800)
 game=load("res://main.tscn").instantiate()
 game.test_mode=true
 root.add_child(game)
 game.set_physics_process(false)
 game._reset(true)
 game.rig.third_person=false
 game.rig.yaw=0.25; game.rig.pitch=-0.06
 game._apply_view()
 await settle()
 await shot("first_person")
 game.aim_toggled=true
 await settle()
 await shot("ads")
 game.aim_toggled=false
 game.ammo=10; game.reload_time=0.8
 await settle()
 await shot("reload")
 game.reload_time=0
 game.rig.third_person=true
 game._apply_view()
 await settle()
 await shot("third_person")
 game._queue_action(&"crouch")
 await settle()
 await settle()
 await shot("crouch")
 # Close inspection of the actual training actor and its skinned mesh.
 game.hud_root.visible=false
 game.gun.visible=false
 var target=game.enemies[0].node
 game.camera.global_position=target.global_position+Vector3(1.7,1.45,2.2)
 game.camera.look_at(target.global_position+Vector3(0,1.0,0))
 await shot("operator")
 game.hud_root.visible=true
 game._reset()
 await settle()
 await shot("depot")
 print("PHASE5 rendered QA captures completed")
 game.free()
 await process_frame
 quit()
