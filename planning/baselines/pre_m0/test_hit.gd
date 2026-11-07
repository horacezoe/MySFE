extends SceneTree
func _initialize(): call_deferred("run_check")
func run_check():
 var game=load("res://main.tscn").instantiate()
 root.add_child(game)
 await process_frame
 game._reset()
 game._toggle_view()
 game.player.position=Vector3(-25,0,-25)
 game.yaw=0.0
 game.pitch=0.0
 var enemy=game.enemies[0]
 enemy.node.position=Vector3(-25,0,-30)
 await physics_frame
 await physics_frame
 var before=enemy.hp
 game._fire()
 assert(enemy.hp==before-25)
 assert(game.hit_marker.visible)
 print("HIT_FEEDBACK_OK health=",enemy.hp)
 quit()
