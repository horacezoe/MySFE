extends Control

var blocked := false:
 set(value):
  blocked = value
  queue_redraw()
var spread_pixels := 4.0:
 set(value):
  spread_pixels=value
  queue_redraw()

func _ready() -> void:
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 resized.connect(queue_redraw)

func _draw() -> void:
 var center := size*0.5
 var color := Color("ff865e") if blocked else Color("eef4dd")
 for axis in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
  draw_line(center+axis*spread_pixels,center+axis*(spread_pixels+7),Color(0.02,0.04,0.03,0.8),4)
  draw_line(center+axis*spread_pixels,center+axis*(spread_pixels+7),color,2)
 draw_circle(center,1.3,color)
