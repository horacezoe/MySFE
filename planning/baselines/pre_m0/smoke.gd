extends SceneTree
func _initialize(): call_deferred("run_check")
func run_check():
 var game=load("res://main.tscn").instantiate()
 root.add_child(game)
 await process_frame
 game._reset()
 await physics_frame
 var crate=game.crates[0]
 game.player.position=crate.node.position-Vector3(0,0.4,0)
 game._interact()
 assert(game.searching and game.search_ui.visible)
 var n=crate.items.size()
 game._take_item(crate.items[0])
 assert(game.bag.size()==1 and crate.items.size()==n-1)
 game._close_search()
 game._interact()
 assert(crate.items.size()==n-1)
 game._close_search()
 game._toggle_view()
 await physics_frame
 assert(game.gun.visible)
 game._toggle_view()
 await physics_frame
 assert(not game.gun.visible)
 print("SEARCH_AND_VIEW_OK")
 quit()
