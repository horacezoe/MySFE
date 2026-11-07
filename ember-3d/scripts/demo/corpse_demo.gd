extends SceneTree
## Safe interactive sample: a fresh memory-only raid, never personal save slots.
var game

func _initialize(): call_deferred("run")

func run():
 game=load("res://main.tscn").instantiate()
 game.test_mode=true
 root.add_child(game)
 game.set_physics_process(false)
 game._reset()
 game.deployment_grace=100000.0
 game.box(game.world,Vector3(24,0.5,24),Vector3(100,-0.3,0),Color("65736b"),true)
 game.box(game.world,Vector3(24,2.8,0.3),Vector3(100,1.35,-11),Color("46564e"),true)
 var enemy=game.enemies[0]
 enemy.node.position=Vector3(100,0,0)
 enemy.node.rotation.y=PI
 enemy.weapon.ammo=7; enemy.weapon.reserve=24
 game.player.position=Vector3(100,0,2.0)
 game.combat.sync_visual_pose(enemy.node)
 await physics_frame
 await physics_frame
 # Use the normal accepted-shot/death/checkpoint path, including actual armor.
 var original=game.weapon_runtime.definition
 var tuning=original.duplicate(); tuning.base_damage=1000.0
 game.weapon_runtime.definition=tuning
 var shot=game.weapon_runtime.request_fire(game.player,{"blocked":false,"origin":Vector3(100,1.2,1.8),"direction":Vector3.FORWARD},game.combat,0.0)
 game.weapon_runtime.definition=original
 if not shot.get("killed",false):
  push_error("Corpse demo could not prepare its guard")
  quit(1)
  return
 game._present_shot(shot,game.player)
 game.hit_time=0; game.damage_time=0; game.shot_time=0
 game.feedback.reset()
 enemy.node.get_node("Visual").set_dead_pose(true)
 var entry: Dictionary=game.corpses[0]
 var point: Vector3=game._search_point(entry)
 game.player.position=Vector3(point.x,0,point.z+1.45)
 game.rig.third_person=false
 game.rig.yaw=0; game.rig.pitch=-0.60; game.rig.recoil_pitch=0
 game._apply_view()
 for i in range(4):
  await physics_frame
  game._physics_process(1.0/60.0)
 game._toast("敌人搜索练习 · 按 E / 搜索敌人，再逐件拾取；本次练习不保存进度",1000)
 root.title="余烬行动 · 敌人搜索练习 · 不保存进度"
 if OS.get_cmdline_user_args().has("--capture"):
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://tests/corpse_nearby.png")
  game._interact()
  game._advance_search(10.0)
  await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://tests/corpse_search.png")
  print("CORPSE DEMO capture complete")
  game.free()
  await create_timer(0.15).timeout
  quit()
 else:
  game.set_physics_process(true)
