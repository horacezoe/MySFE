extends Control
## Presentation only. Authoritative placement and weight checks live in InventoryService.

signal item_selected(item_id: String, container_id: String)
signal cell_selected(container_id: String, x: int, y: int, slot: String)

var cell_size := 42.0
var container_id := ""
var _catalog: RefCounted
var _state: Dictionary = {}
var _container: Dictionary = {}
var _revealed: Array = []
var _masked := false
var _selected := ""
var _signature := ""
var _preview := Rect2i(-1,-1,0,0)
var _preview_valid := false
var _preview_panel: Panel
var _item_buttons: Dictionary = {}

func _ready() -> void:
 mouse_filter=Control.MOUSE_FILTER_IGNORE

func render(state: Dictionary, cid: String, catalog: RefCounted, selected_id := "", mask_unrevealed := false, revealed_ids: Array = []) -> void:
 _state=state
 _catalog=catalog
 container_id=cid
 _container=state.get("containers",{}).get(cid,{})
 _selected=selected_id
 _masked=mask_unrevealed
 _revealed=revealed_ids
 var visible_items: Dictionary={}
 for placement in _container.get("placements",[]):
  var id=String(placement.get("item_id",""))
  visible_items[id]=state.get("items",{}).get(id,{})
 var signature=JSON.stringify([cid,_container,visible_items,selected_id,mask_unrevealed,revealed_ids,cell_size])
 if signature==_signature: return
 _signature=signature
 for child in get_children():
  remove_child(child)
  child.queue_free()
 _item_buttons.clear()
 _preview=Rect2i(-1,-1,0,0)
 var kind=String(_container.get("kind","grid"))
 if _container.is_empty():
  custom_minimum_size=Vector2(260,100)
  _message("暂无容器",Vector2(8,24))
 elif kind=="slots": _build_slots()
 elif kind=="list": _build_list()
 else: _build_grid()
 _preview_panel=Panel.new()
 _preview_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
 _preview_panel.visible=false
 add_child(_preview_panel)

func _build_grid() -> void:
 var width=int(_container.get("width",6))
 var height=int(_container.get("height",5))
 custom_minimum_size=Vector2(width*cell_size,height*cell_size)
 size=custom_minimum_size
 for y in range(height):
  for x in range(width):
   var cell=_button("",Vector2(x,y)*cell_size,Vector2.ONE*(cell_size-2),Color("202b29"))
   cell.tooltip_text="选择放置位置：第 %d 列，第 %d 行" % [x+1,y+1]
   cell.pressed.connect(func(): cell_selected.emit(container_id,x,y,""))
 for placement in _container.get("placements",[]):
  var id=String(placement.get("item_id",""))
  var item: Dictionary=_state.get("items",{}).get(id,{})
  var definition=_definition(item)
  var footprint=Vector2i(1,1)
  if definition!=null:
   footprint=definition.footprint(bool(placement.get("rotated",false)))
  var pos=Vector2(int(placement.get("x",0)),int(placement.get("y",0)))*cell_size
  var extent=Vector2(footprint)*cell_size-Vector2(2,2)
  _item_button(id,item,definition,pos,extent)

func _build_slots() -> void:
 var slots: Array=_container.get("slots",["weapon","helmet","vest"])
 custom_minimum_size=Vector2(306,slots.size()*54)
 size=custom_minimum_size
 var occupied: Dictionary={}
 for placement in _container.get("placements",[]): occupied[String(placement.get("slot",""))]=String(placement.get("item_id",""))
 for i in range(slots.size()):
  var slot=String(slots[i])
  var label={"weapon":"主武器","helmet":"头盔","vest":"防弹衣"}.get(slot,slot)
  if occupied.has(slot):
   var id=occupied[slot]
   var item: Dictionary=_state.get("items",{}).get(id,{})
   var definition=_definition(item)
   var button=_item_button(id,item,definition,Vector2(0,i*54),Vector2(304,50))
   button.text=label+"  ·  "+(definition.display_name if definition!=null else "未知物品")
  else:
   var button=_button(label+"  ·  未装备",Vector2(0,i*54),Vector2(304,50),Color("26322f"))
   button.pressed.connect(func(): cell_selected.emit(container_id,-1,-1,slot))

func _build_list() -> void:
 var placements: Array=_container.get("placements",[])
 custom_minimum_size=Vector2(420,maxi(80,placements.size()*58))
 size=custom_minimum_size
 if placements.is_empty(): _message("收件区为空",Vector2(12,25))
 for i in range(placements.size()):
  var id=String(placements[i].get("item_id",""))
  var item: Dictionary=_state.get("items",{}).get(id,{})
  var definition=_definition(item)
  var button=_item_button(id,item,definition,Vector2(0,i*58),Vector2(418,54))
  button.text=(definition.display_name if definition!=null else "未知物品")+"  ×%d" % int(item.get("quantity",1))

func _definition(item: Dictionary):
 return _catalog.get_definition(String(item.get("definition_id",""))) if _catalog!=null else null

func _item_button(id: String,item: Dictionary,definition,position: Vector2,extent: Vector2) -> Button:
 var known=not _masked or _revealed.has(id)
 var color=definition.color.darkened(0.62) if definition!=null and known else Color("28312f")
 var full_name=String(definition.display_name) if definition!=null else "未知物品"
 var short_name=full_name if extent.x>=100 else full_name.right(2)
 var quantity=int(item.get("quantity",1))
 var text=short_name+("\n×%d" % quantity if quantity>1 else "") if known else "?"
 var button=_button(text,position,extent,color,id==_selected)
 button.set_meta("item_id",id)
 button.disabled=not known
 button.tooltip_text=(full_name+"  ×%d" % quantity) if known else "正在搜索"
 button.pressed.connect(func(): item_selected.emit(id,container_id))
 _item_buttons[id]=button
 return button

func _button(text: String,position: Vector2,extent: Vector2,color: Color,selected := false) -> Button:
 var button=Button.new()
 button.text=text
 button.position=position
 button.size=extent
 button.focus_mode=Control.FOCUS_NONE
 button.add_theme_font_size_override("font_size",15 if extent.x<100 else 17)
 button.add_theme_color_override("font_color",Color("eef0dc"))
 button.add_theme_stylebox_override("normal",_style(color,selected))
 button.add_theme_stylebox_override("hover",_style(color.lightened(0.16),true))
 button.add_theme_stylebox_override("pressed",_style(color.lightened(0.23),true))
 button.add_theme_stylebox_override("disabled",_style(Color("28312f"),false))
 add_child(button)
 return button

func _style(color: Color,selected: bool) -> StyleBoxFlat:
 var style=StyleBoxFlat.new()
 style.bg_color=color
 style.border_color=Color("e1c782") if selected else Color("53615b")
 style.set_border_width_all(2 if selected else 1)
 style.set_corner_radius_all(3)
 return style

func _message(text: String,position: Vector2):
 var label=Label.new(); label.text=text; label.position=position; label.mouse_filter=Control.MOUSE_FILTER_IGNORE; label.add_theme_font_size_override("font_size",20); add_child(label)

func preview(x: int,y: int,footprint: Vector2i,valid: bool):
 _preview=Rect2i(x,y,footprint.x,footprint.y)
 _preview_valid=valid
 if not is_instance_valid(_preview_panel): return
 _preview_panel.position=Vector2(x,y)*cell_size
 _preview_panel.size=Vector2(footprint)*cell_size-Vector2(2,2)
 var style=StyleBoxFlat.new()
 style.bg_color=Color(0.72,0.91,0.63,0.20) if valid else Color(1,0.3,0.2,0.25)
 style.border_color=Color("d8eda6") if valid else Color("ff8a73")
 style.set_border_width_all(3)
 _preview_panel.add_theme_stylebox_override("panel",style)
 _preview_panel.visible=x>=0 and y>=0

func clear_preview():
 _preview=Rect2i(-1,-1,0,0)
 if is_instance_valid(_preview_panel): _preview_panel.visible=false
