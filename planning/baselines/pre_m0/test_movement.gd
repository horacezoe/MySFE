extends SceneTree
func _initialize(): call_deferred("run_check")
func run_check():
 var game=load("res://main.tscn").instantiate()
 root.add_child(game)
 await process_frame
 game._reset()
 for enemy in game.enemies: enemy.node.queue_free()
 game.enemies.clear()
 for i in range(8): await physics_frame
 assert(game.player.is_on_floor())
 game._toggle_crouch()
 for i in range(20): await physics_frame
 assert(game.crouching and game.player.get_node("BodyCollider").shape.height < 1.1)
 assert(game.stance_height < 1.1)
 game._jump()
 for i in range(5): await physics_frame
 assert(not game.crouching and game.player.position.y > 0.1)
 for i in range(80): await physics_frame
 assert(game.player.is_on_floor())
 game.left_id=0; game.left_vec=Vector2(0,-1)
 game.touch_sprint=true
 await physics_frame
 await physics_frame
 assert(Vector2(game.player.velocity.x,game.player.velocity.z).length()>9.0)
 print("MOVEMENT_OK jump crouch sprint")
 game.queue_free()
 await process_frame
 quit()
