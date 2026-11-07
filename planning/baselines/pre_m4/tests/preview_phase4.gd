extends SceneTree
## Native-window visual QA with a fresh, in-memory profile. Never personal saves.
func _initialize(): call_deferred("show_preview")
func show_preview():
 var game=load("res://main.tscn").instantiate()
 game.test_mode=true
 root.add_child(game)
 game._open_operation()
 root.title="余烬行动 · 第四阶段界面检查（临时进度）"
