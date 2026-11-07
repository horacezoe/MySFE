extends "res://tests/test_game.gd"

func run_tests():
 create_timer(35).timeout.connect(func(): push_error("Action test timeout"); quit(1))
 game=load("res://main.tscn").instantiate()
 game.test_mode=true
 root.add_child(game)
 game.set_physics_process(false)
 tick=PhysicsTask.new()
 root.add_child(tick)
 await tick.run(func(): game._reset(true))
 await frames(8)
 game.hp=40
 game._heal()
 check(game.healing_remaining>0 and game.meds==3 and game.hp==40,"healing locks time without consuming medicine or health")
 await frames(15)
 game._queue_action(&"fire")
 await frames(1)
 check(game.healing_remaining==0 and game.meds==3 and game.hp==40,"fire cancels healing and preserves medicine")
 game._heal()
 game._pause_game()
 var timer=game.healing_remaining
 await frames(5)
 check(is_equal_approx(timer,game.healing_remaining),"pause freezes healing")
 game._resume()
 await frames(135)
 check(game.hp==85 and game.meds==2 and game.healing_remaining==0,"healing completes once with one medicine")
 game._queue_action(&"aim_toggle")
 await frames(20)
 check(game.rig.aiming and is_equal_approx(game.camera.fov,48),"aim input narrows camera FOV")
 game.input_router.set_action(&"move_forward",true)
 game.input_router.set_action(&"sprint",true)
 await frames(2)
 check(not game.motor.sprinting,"aim prevents sprint")
 game.input_router.cancel_all()
 game._queue_action(&"jump")
 await frames(4)
 check(not game.rig.aiming and not game.player.is_on_floor(),"airborne disables aim")
 game._pause_game(); game._resume()
 await frames(90)
 check(not game.rig.aiming and not game.aim_toggled,"context switch clears aim toggle")
 game._queue_action(&"crouch")
 for i in range(12):
  await frames(1)
  check(is_equal_approx(game.player.get_node("Hitboxes").scale.y,game.player.get_node("Visual").scale.y),"crouch hitboxes track rendered pose")
 game.ammo=4
 game._reload()
 await frames(3)
 game._heal()
 check(game.healing_remaining==0,"reload rejects concurrent healing")
 await tick.run(func(): game._reset())
 game.ammo=4; game._reload(); game.hp=0; game.healing_remaining=1.0
 game._finish(false,"test death")
 check(game.weapon_runtime.disabled and game.reload_time==0 and game.healing_remaining==0,"raid death cancels weapon and healing")
 var before=game.ammo
 check(not game._try_fire() and game.ammo==before,"result screen rejects firing")
 game.free(); tick.queue_free()
 # Let the audio mixer acknowledge the final stop before terminating SceneTree.
 await create_timer(0.15).timeout
 print("ACTIONS: ",checks-failures,"/",checks," checks passed")
 quit(1 if failures else 0)
