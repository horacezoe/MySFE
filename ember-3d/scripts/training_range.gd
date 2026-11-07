extends RefCounted

# Phase-one practice arena, kept away from the extraction map.
# The caller owns this root and the target actors after build().
func build(game: Node3D) -> Dictionary:
 var root = Node3D.new()
 root.name = "TrainingRange"
 game.world.add_child(root)
 var spawn = Vector3(100.0, 0.0, 20.0)
 var floor_color = Color("6b7167")
 var wall_color = Color("4b554d")
 var accent = Color("c9b66e")
 game.box(root, Vector3(70.0, 0.5, 100.0), Vector3(100.0, -0.3, 0.0), floor_color, true)
 # Boundary walls protect the arena without closing either practice station.
 game.box(root, Vector3(0.3, 3.0, 100.0), Vector3(65.0, 1.45, 0.0), wall_color, true)
 game.box(root, Vector3(0.3, 3.0, 100.0), Vector3(135.0, 1.45, 0.0), wall_color, true)
 game.box(root, Vector3(70.0, 3.0, 0.3), Vector3(100.0, 1.45, -50.0), wall_color, true)
 game.box(root, Vector3(70.0, 3.0, 0.3), Vector3(100.0, 1.45, 50.0), wall_color, true)
 game.box(root, Vector3(13.0, 0.025, 0.25), Vector3(100.0, -0.025, 20.0), accent)
 _label(root, "射击起点  /  操作训练\n左侧 5 米  ·  右侧 15 米  ·  正前方 40 米", Vector3(100.0, 3.2, 23.0), 32)

 # Distances are measured horizontally from the spawn marker; lateral offsets
 # keep all three actors visible without one blocking another.
 var positions: Array[Vector3] = [
  spawn + Vector3(-2.0, 0.0, -sqrt(21.0)),
  spawn + Vector3(5.0, 0.0, -sqrt(200.0)),
  spawn + Vector3(0.0, 0.0, -40.0),
 ]
 var distances: Array[int] = [5, 15, 40]
 var targets: Array = []
 for index in range(positions.size()):
  var origin = positions[index]
  var actor: CharacterBody3D = game.character(root, Color("777a62"), origin)
  actor.name = "Target%dMeters" % distances[index]
  actor.rotation.y = PI
  targets.append({"node": actor, "hp": 75.0, "cool": 999.0, "origin": origin})
  game.box(root, Vector3(1.7, 0.03, 1.4), origin + Vector3(0, -0.025, 0), Color("8a8e7a"))
  _label(root, "%d 米靶位" % distances[index], origin + Vector3(0, 2.6, 0), 30)

 # A 12 cm wall is deliberately thinner than the former 35 cm ray offset.
 # Approach from +Z and aim at the rear visual bullseye. Neither the wall nor
 # marker is a new enemy, so the public target list still contains three actors.
 var thin_wall = game.box(root, Vector3(7.0, 2.5, 0.12), Vector3(120.0, 1.20, 10.0), Color("707e82"), true)
 thin_wall.name = "ThinWall12cm"
 game.box(root, Vector3(2.0, 2.0, 0.18), Vector3(120.0, 1.0, 5.0), Color("c6c5ac"), true)
 game.box(root, Vector3(0.9, 0.9, 0.03), Vector3(120.0, 1.15, 5.11), Color("a96646"))
 game.box(root, Vector3(0.3, 0.3, 0.04), Vector3(120.0, 1.15, 5.13), Color("e8dcae"))
 _label(root, "近墙射击测试\n靠近薄墙时枪口不能穿墙\n绕过两侧可看见后方标靶", Vector3(120.0, 3.5, 13.0), 31)
 game.box(root, Vector3(7.0, 0.025, 0.2), Vector3(120.0, -0.025, 15.0), accent)

 # 1.28 m underside clearance admits the crouched capsule but rejects standing.
 # Both ends remain open, with side walls and a roof as independently collidable
 # geometry so the standing-clearance query is exercised.
 var tunnel_center = Vector3(80.0, 0.0, 12.0)
 game.box(root, Vector3(0.20, 1.35, 8.0), tunnel_center + Vector3(-2.0, 0.625, 0), wall_color, true)
 game.box(root, Vector3(0.20, 1.35, 8.0), tunnel_center + Vector3(2.0, 0.625, 0), wall_color, true)
 var roof = game.box(root, Vector3(4.2, 0.24, 8.0), tunnel_center + Vector3(0, 1.40, 0), Color("8a8067"), true)
 roof.name = "CrouchClearanceRoof"
 _label(root, "低顶蹲行通道\n按 C 或蹲下按钮进入\n顶棚下不能起身或跳起", Vector3(80.0, 2.9, 19.0), 31)
 game.box(root, Vector3(3.6, 0.025, 0.2), Vector3(80.0, -0.025, 17.0), accent)
 _label(root, "返回射击区 →", Vector3(84.0, 1.8, 12.0), 28)

 return {
  "root": root,
  "spawn": spawn,
  "yaw": 0.0,
  "pitch": -0.035,
  "targets": targets,
 }

func _label(parent: Node3D, text: String, position: Vector3, font_size: int) -> Label3D:
 var label = Label3D.new()
 label.text = text
 label.position = position
 label.font_size = font_size
 label.outline_size = 8
 label.pixel_size = 0.008
 label.modulate = Color("f1edcf")
 label.outline_modulate = Color("1b251f")
 label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 parent.add_child(label)
 return label

