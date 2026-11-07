extends Control
## Fixed map intelligence only: no live guards or unrevealed item contents.
var definition: Dictionary={}
var player_position=Vector3.ZERO
var show_player=false
var exit_access: Dictionary={}
var markers: Array[Dictionary]=[]
var _map_rect=Rect2()
const INK=Color("d9e2cf")
const AMBER=Color("dfb96f")
const MINT=Color("a2d3b9")

func _ready():
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 custom_minimum_size=Vector2(350,300)
 resized.connect(queue_redraw)

func render(map_definition: Dictionary,current_position:=Vector3.ZERO,in_raid:=false,access: Dictionary={}):
 definition=map_definition
 player_position=current_position
 show_player=in_raid
 exit_access=access
 markers.clear()
 if definition.has("spawn"): markers.append({"kind":"spawn","position":definition.spawn,"title":"进入点"})
 for point in definition.get("crates",[]): markers.append({"kind":"supply","position":point,"title":""})
 var survey=definition.get("survey",{})
 if not survey.is_empty(): markers.append({"kind":"survey","position":survey.position,"title":"信号站"})
 for exit in definition.get("exits",[]): markers.append({"kind":"exit","id":exit.id,"position":exit.position,"title":exit.title})
 if in_raid: markers.append({"kind":"player","position":current_position,"title":"你的位置"})
 queue_redraw()

func world_to_map(point: Vector3) -> Vector2:
 var bounds: Rect2=definition.get("bounds",Rect2(-32,-32,64,64))
 return _map_rect.position+Vector2((point.x-bounds.position.x)/bounds.size.x,(point.z-bounds.position.y)/bounds.size.y)*_map_rect.size

func _draw():
 var extent=minf(size.x-34,size.y-34)
 if extent<=0: return
 _map_rect=Rect2(Vector2((size.x-extent)*0.5,(size.y-extent)*0.5),Vector2.ONE*extent)
 draw_rect(Rect2(Vector2.ZERO,size),Color("1a2a25"))
 draw_rect(_map_rect,Color("23362c"))
 for index in range(9):
  var offset=extent*index/8.0
  draw_line(_map_rect.position+Vector2(offset,0),_map_rect.position+Vector2(offset,extent),Color("3b4a3d"),1)
  draw_line(_map_rect.position+Vector2(0,offset),_map_rect.position+Vector2(extent,offset),Color("3b4a3d"),1)
 for zone in definition.get("zones",[]):
  var rect: Rect2=zone.rect
  var start=world_to_map(Vector3(rect.position.x,0,rect.position.y))
  var end=world_to_map(Vector3(rect.end.x,0,rect.end.y))
  var color={"low":Color("5e8066"),"medium":Color("979270"),"high":Color("aa7556"),"低":Color("5e8066"),"中":Color("979270"),"高":Color("aa7556")}.get(String(zone.get("risk","medium")),Color("79876b"))
  draw_rect(Rect2(start,end-start),Color(color,0.22))
  draw_rect(Rect2(start,end-start),Color(color,0.5),false,1)
  var title=String(zone.get("title",""))
  var label_point=Vector2(start.x+7,start.y+19)
  draw_string(ThemeDB.fallback_font,label_point,title,HORIZONTAL_ALIGNMENT_LEFT,maxf(10,end.x-start.x-10),15,INK)
 for rect in definition.get("walls",[]):
  if not rect is Rect2: continue
  var start=world_to_map(Vector3(rect.position.x,0,rect.position.y))
  var end=world_to_map(Vector3(rect.end.x,0,rect.end.y))
  draw_rect(Rect2(start,end-start),Color("82917c"))
 for marker in markers:
  var point=world_to_map(marker.position)
  if not _map_rect.grow(3).has_point(point): continue
  match marker.kind:
   "supply": draw_rect(Rect2(point-Vector2.ONE*2.5,Vector2.ONE*5),Color("c4b886"))
   "spawn":
    draw_circle(point,6,MINT,false,2)
    _marker_text(point,marker.title,MINT)
   "survey":
    draw_line(point+Vector2(-7,0),point+Vector2(7,0),AMBER,2)
    draw_line(point+Vector2(0,-7),point+Vector2(0,7),AMBER,2)
    _marker_text(point,marker.title,AMBER)
   "exit":
    var open=exit_access.get(marker.id,false)
    var color=MINT if open else AMBER
    draw_rect(Rect2(point-Vector2.ONE*6,Vector2.ONE*12),color,false,2)
    _marker_text(point,marker.title,color)
   "player":
    draw_circle(point,10,Color("23362c"))
    draw_circle(point,6,Color("f3f0d7"))
    draw_circle(point,10,Color("f3f0d7"),false,1)
    _marker_text(point,marker.title,Color("f3f0d7"))
 draw_rect(_map_rect,Color("8b997e"),false,1)
 draw_string(ThemeDB.fallback_font,Vector2(_map_rect.end.x-18,_map_rect.position.y+18),"北",HORIZONTAL_ALIGNMENT_LEFT,-1,15,INK)

func _marker_text(point: Vector2,text: String,color: Color):
 var font=ThemeDB.fallback_font
 var width=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
 var x=clampf(point.x+10,_map_rect.position.x+3,_map_rect.end.x-width-3)
 var y=point.y-9 if point.y>_map_rect.position.y+30 else point.y+23
 draw_rect(Rect2(Vector2(x-2,y-14),Vector2(width+4,18)),Color(0.08,0.14,0.11,0.85))
 draw_string(font,Vector2(x,y),text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,color)
