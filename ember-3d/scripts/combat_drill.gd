extends RefCounted

# A repeatable two-guard encounter. Geometry only: game owns AI and session rules.
func build(game: Node3D) -> Dictionary:
 var root := Node3D.new()
 root.name = "CombatDrill"
 game.world.add_child(root)
 var obstacles: Array[Rect2] = []
 var wall_color := Color("616f69")
 var accent := Color("c8b977")
 game.box(root,Vector3(50,0.5,60),Vector3(220,-0.3,0),Color("697466"),true)

 # Bounds match the inner faces; the navigation builder applies actor clearance.
 _wall(game,root,Vector3(1,3.4,58),Vector3(195.5,1.65,0),wall_color,obstacles)
 _wall(game,root,Vector3(1,3.4,58),Vector3(244.5,1.65,0),wall_color,obstacles)
 _wall(game,root,Vector3(48,3.4,1),Vector3(220,1.65,-28.5),wall_color,obstacles)
 _wall(game,root,Vector3(48,3.4,1),Vector3(220,1.65,28.5),wall_color,obstacles)

 # This L blocks both initial guard-to-spawn sightlines. Routes remain open on
 # either side; the right-hand approach must also round the north end of the L.
 var central := _wall(game,root,Vector3(14,3,0.6),Vector3(220,1.45,8),Color("7b8272"),obstacles)
 central.name = "CentralCover"
 _wall(game,root,Vector3(0.6,3,10),Vector3(226.7,1.45,3),Color("7b8272"),obstacles)
 game.box(root,Vector3(14.15,0.13,0.75),Vector3(220,2.99,8),accent)

 # The thin partition exercises close-wall aiming without closing the west lane.
 var thin := _wall(game,root,Vector3(6,2.6,0.12),Vector3(205,1.25,9),Color("737f83"),obstacles)
 thin.name = "ThinCover12cm"
 _wall(game,root,Vector3(4,1.8,0.7),Vector3(236,0.85,5),Color("837d65"),obstacles)
 _wall(game,root,Vector3(5,2.5,0.8),Vector3(220,1.2,-15),wall_color,obstacles)

 # Approach markings are visual only, so they cannot obstruct navigation or fire.
 game.box(root,Vector3(10,0.025,0.2),Vector3(220,-0.025,20),accent)
 for x in [210.5,231.0]:
  game.box(root,Vector3(0.18,0.025,8),Vector3(x,-0.025,14),accent)
 _label(root,"守望训练场",Vector3(220,4.3,8),36)
 _label(root,"开枪会引起调查\n敌人失去视线后搜索\n可随时 Esc 重开演练",Vector3(220,3.5,8.4),23)
 _label(root,"← 左翼绕行",Vector3(211,1.5,12),23)
 _label(root,"右翼绕行 →",Vector3(230,1.5,12),23)
 _label(root,"利用掩体，观察后再前进",Vector3(205,3.1,9),23)

 var left_route: Array[Vector3] = [Vector3(214,0,0),Vector3(207,0,0),Vector3(207,0,-10),Vector3(214,0,-10)]
 var right_route: Array[Vector3] = [Vector3(232,0,-12),Vector3(237,0,-12),Vector3(237,0,-1),Vector3(232,0,-1)]
 var enemies: Array[Vector3] = [left_route[0],right_route[0]]
 return {
  "root":root,
  "spawn":Vector3(220,0,20),
  "yaw":0.0,
  "pitch":-0.035,
  "enemies":enemies,
  "routes":[left_route,right_route],
  "obstacles":obstacles,
  "bounds":Rect2(196,-28,48,56),
 }

func _wall(game: Node3D, parent: Node3D, size: Vector3, position: Vector3, color: Color, obstacles: Array[Rect2]) -> Node3D:
 var wall: Node3D = game.box(parent,size,position,color,true)
 obstacles.append(Rect2(position.x-size.x*0.5,position.z-size.z*0.5,size.x,size.z))
 return wall

func _label(parent: Node3D, text: String, position: Vector3, font_size: int) -> void:
 var label := Label3D.new()
 label.text=text
 label.position=position
 label.font_size=font_size
 label.outline_size=7
 label.pixel_size=0.006
 label.modulate=Color("eee7c8")
 label.outline_modulate=Color("202b26")
 label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
 parent.add_child(label)
