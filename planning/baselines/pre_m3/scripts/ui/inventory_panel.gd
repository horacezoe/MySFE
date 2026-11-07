extends Control
## UI emits intentions only. The caller persists a validated candidate before render().

signal command_requested(command: Dictionary)
signal closed
signal depart
signal resume_raid
signal quick_equip
signal purchase(definition_id: String)
signal sell(item_id: String,quantity: int)
signal abandon_raid
signal save_and_return
signal sort_requested(container_id: String)

const InventoryGrid=preload("res://scripts/ui/inventory_grid.gd")
var _catalog: RefCounted
var _profile: Dictionary={}
var _context="camp"
var _source_id="stash_main"
var _target_id="loadout_pack"
var _equipment_id="loadout_equipment"
var _revealed: Array=[]
var _selected_id=""
var _selected_container=""
var _quantity=1
var _rotated=false
var _placement: Dictionary={}
var _built=false
var _overflow_active=false
var _read_only=false
var _title: Label
var _account: Label
var _notice: Label
var _left_title: Label
var _right_title: Label
var _left_scroll: ScrollContainer
var _right_scroll: ScrollContainer
var _left_grid: Control
var _right_grid: Control
var _equipment_grid: Control
var _equipment_title: Label
var _middle: VBoxContainer
var _right_pager: HBoxContainer
var _details: Label
var _quantity_label: Label
var _rotate_button: Button
var _transfer_button: Button
var _place_button: Button
var _equip_button: Button
var _sell_button: Button
var _take_all_button: Button
var _overflow_button: Button
var _quick_button: Button
var _med_button: Button
var _ammo_button: Button
var _depart_button: Button
var _abandon_button: Button
var _save_button: Button
var _sort_button: Button

func setup(catalog: RefCounted):
 _catalog=catalog
 if not _built: _build()

func _ready():
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 if not _built: _build()

func render(profile: Dictionary,context: String,source_id: String="",target_id: String="",revealed_ids: Array=[]):
 if not _built: _build()
 var changed=context!=_context
 _profile=profile
 _context=context
 if changed:
  _selected_id=""; _placement={}; _overflow_active=false
 if not source_id.is_empty(): _source_id=source_id
 elif context=="camp": _source_id="stash_main"
 elif context=="bag": _source_id="raid_pack"
 if not target_id.is_empty(): _target_id=target_id
 elif context=="camp": _target_id="loadout_pack"
 elif context=="bag": _target_id="raid_pack"
 _equipment_id="raid_equipment" if _has_active_raid() else "loadout_equipment"
 _read_only=context=="camp" and _has_active_raid()
 _revealed=revealed_ids
 if _overflow_active and context=="camp": _source_id="overflow"; _target_id="stash_main"
 if not _selected_id.is_empty():
  _selected_container=_owner(_selected_id)
  if not [_source_id,_target_id,_equipment_id].has(_selected_container): _selected_id=""; _placement={}
  else: _quantity=clampi(_quantity,1,int(_profile.items[_selected_id].quantity))
 _title.text={"camp":"仓库与出战装备","search":"搜索补给","bag":"行动背包"}.get(context,"物品管理")
 _account.text="资产 %d  ·  撤离 %d 次" % [int(profile.get("currency",0)),int(profile.get("wins",0))]
 _refresh_grids()
 if not _placement.is_empty(): _refresh_preview()
 _refresh_actions()
 _refresh_details()
 if _read_only: set_notice("上局尚未结束。继续上局，或放弃后整理装备。")
 visible=true

func set_notice(text: String,is_error := false):
 if not _built: _build()
 _notice.text=text
 _notice.add_theme_color_override("font_color",Color("ffac91") if is_error else Color("d9dabd"))

func _build():
 _built=true
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var shade=ColorRect.new(); shade.color=Color(0.035,0.065,0.055,0.98); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(shade)
 var margin=MarginContainer.new(); add_child(margin); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
 var stack=VBoxContainer.new(); stack.add_theme_constant_override("separation",10); margin.add_child(stack)
 var header=HBoxContainer.new(); stack.add_child(header)
 _title=_label("仓库与出战装备",30); _title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(_title)
 _account=_label("",18); header.add_child(_account)
 _notice=_label("选择物品后，可自动转移，或点击目标空格预览放置。",17); _notice.custom_minimum_size.y=26; stack.add_child(_notice)
 var body=HBoxContainer.new(); body.add_theme_constant_override("separation",16); body.size_flags_vertical=Control.SIZE_EXPAND_FILL; stack.add_child(body)
 var left=VBoxContainer.new(); left.custom_minimum_size.x=432; left.size_flags_horizontal=Control.SIZE_EXPAND_FILL; body.add_child(left)
 var left_header=HBoxContainer.new(); left.add_child(left_header)
 _left_title=_label("仓库",21); _left_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; left_header.add_child(_left_title)
 _overflow_button=_button("收件区",88,44); _overflow_button.pressed.connect(_toggle_overflow); left_header.add_child(_overflow_button)
 _left_scroll=ScrollContainer.new(); _left_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; _left_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; left.add_child(_left_scroll)
 _left_grid=InventoryGrid.new(); _left_grid.cell_size=42; _left_scroll.add_child(_left_grid)
 _left_grid.item_selected.connect(_select_item); _left_grid.cell_selected.connect(_select_cell)
 var scroll_controls=HBoxContainer.new(); left.add_child(scroll_controls)
 for amount in [-210,210]:
  var scroll_button=_button("上移" if amount<0 else "下移",80,44); scroll_controls.add_child(scroll_button)
  scroll_button.pressed.connect(func(): _left_scroll.scroll_vertical+=amount)
 _take_all_button=_button("全部拾取",150,44); _take_all_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll_controls.add_child(_take_all_button)
 _take_all_button.pressed.connect(func(): command_requested.emit({"action":"take_all","from":_source_id,"to":"stash_main" if _source_id=="overflow" else _target_id}))
 var middle=VBoxContainer.new(); _middle=middle; middle.custom_minimum_size.x=314; body.add_child(middle)
 var middle_header=HBoxContainer.new(); middle.add_child(middle_header)
 _right_title=_label("出战背包",21); _right_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; middle_header.add_child(_right_title)
 _sort_button=_button("整理",65,44); middle_header.add_child(_sort_button)
 _sort_button.pressed.connect(func(): sort_requested.emit(_target_id if _profile.get("containers",{}).get(_target_id,{}).get("kind")=="grid" else _source_id))
 _right_scroll=ScrollContainer.new(); _right_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; middle.add_child(_right_scroll)
 _right_grid=InventoryGrid.new(); _right_grid.cell_size=48; _right_scroll.add_child(_right_grid)
 _right_grid.item_selected.connect(_select_item); _right_grid.cell_selected.connect(_select_cell)
 _right_pager=HBoxContainer.new(); middle.add_child(_right_pager)
 for amount in [-210,210]:
  var scroll_button=_button("上移" if amount<0 else "下移",80,44); scroll_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _right_pager.add_child(scroll_button)
  scroll_button.pressed.connect(func(): _right_scroll.scroll_vertical+=amount)
 _equipment_title=_label("装备栏",19); middle.add_child(_equipment_title)
 _equipment_grid=InventoryGrid.new(); middle.add_child(_equipment_grid)
 _equipment_grid.item_selected.connect(_select_item); _equipment_grid.cell_selected.connect(_select_cell)
 var inspector=VBoxContainer.new(); inspector.custom_minimum_size.x=290; inspector.size_flags_horizontal=Control.SIZE_EXPAND_FILL; body.add_child(inspector)
 inspector.add_child(_label("物品详情",21))
 var details_scroll=ScrollContainer.new(); details_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; inspector.add_child(details_scroll)
 _details=_label("选择一件物品查看详情",18); _details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _details.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _details.custom_minimum_size.x=268; details_scroll.add_child(_details)
 var amount_row=HBoxContainer.new(); inspector.add_child(amount_row)
 var minus=_button("−",48,44); amount_row.add_child(minus); minus.pressed.connect(func(): _set_quantity(_quantity-1))
 _quantity_label=_label("数量 1",18); _quantity_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _quantity_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; amount_row.add_child(_quantity_label)
 var plus=_button("+",48,44); amount_row.add_child(plus); plus.pressed.connect(func(): _set_quantity(_quantity+1))
 var all=_button("全部",65,44); amount_row.add_child(all); all.pressed.connect(func(): _set_quantity(999999))
 _rotate_button=_button("旋转 90°",0,44); inspector.add_child(_rotate_button); _rotate_button.pressed.connect(_rotate)
 _transfer_button=_button("自动转移",0,44); inspector.add_child(_transfer_button); _transfer_button.pressed.connect(_transfer)
 _place_button=_button("放置到预览位置",0,44); inspector.add_child(_place_button); _place_button.pressed.connect(_place)
 _equip_button=_button("装备",0,44); inspector.add_child(_equip_button); _equip_button.pressed.connect(_equip)
 _sell_button=_button("出售所选数量",0,44); inspector.add_child(_sell_button); _sell_button.pressed.connect(func(): sell.emit(_selected_id,_quantity))
 var footer=HBoxContainer.new(); footer.add_theme_constant_override("separation",8); stack.add_child(footer)
 _quick_button=_button("快速配装",140,48); footer.add_child(_quick_button); _quick_button.pressed.connect(func(): quick_equip.emit())
 _med_button=_button("药包 ×3 · 240",170,48); footer.add_child(_med_button); _med_button.pressed.connect(func(): purchase.emit("medkit_basic"))
 _ammo_button=_button("弹药 ×60 · 120",180,48); footer.add_child(_ammo_button); _ammo_button.pressed.connect(func(): purchase.emit("ammo_rifle"))
 _abandon_button=_button("放弃上局",140,48); footer.add_child(_abandon_button); _abandon_button.pressed.connect(func(): abandon_raid.emit())
 _save_button=_button("保存并回营地",200,48); footer.add_child(_save_button); _save_button.pressed.connect(func(): save_and_return.emit())
 var spacer=Control.new(); spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL; spacer.mouse_filter=Control.MOUSE_FILTER_IGNORE; footer.add_child(spacer)
 _depart_button=_button("进入封锁区",200,48); footer.add_child(_depart_button)
 _depart_button.pressed.connect(func():
  if _has_active_raid(): resume_raid.emit()
  else: depart.emit()
 )
 var close_button=_button("关闭",110,48); footer.add_child(close_button); close_button.pressed.connect(func(): closed.emit())

func _refresh_grids():
 var display_target=_equipment_id if _source_id==_target_id else _target_id
 _left_title.text=_container_title(_source_id)
 _right_title.text=_container_title(display_target)
 _left_grid.render(_profile,_source_id,_catalog,_selected_id,_context=="search",_revealed)
 _right_grid.cell_size=42 if display_target=="stash_main" else 48
 _middle.custom_minimum_size.x=432 if display_target=="stash_main" else 314
 _right_grid.render(_profile,display_target,_catalog,_selected_id,false,[])
 _right_pager.visible=display_target=="stash_main"
 _equipment_grid.render(_profile,_equipment_id,_catalog,_selected_id,false,[])
 _equipment_grid.visible=display_target!=_equipment_id
 _equipment_title.visible=_equipment_grid.visible
 _equipment_title.text="装备栏" if _context=="camp" else "装备栏 · 行动中锁定"
 if display_target==_equipment_id and _context!="camp": _right_title.text+=" · 锁定"
 _overflow_button.text="返回仓库" if _overflow_active else "收件区 (%d)" % _profile.get("containers",{}).get("overflow",{}).get("placements",[]).size()

func _refresh_actions():
 var camp=_context=="camp"
 for button in [_quick_button,_med_button,_ammo_button,_depart_button,_overflow_button]: button.visible=camp
 for button in [_quick_button,_med_button,_ammo_button]: button.disabled=_read_only
 _depart_button.text="继续上局" if _has_active_raid() else "进入封锁区"
 _abandon_button.visible=camp and _has_active_raid()
 _save_button.visible=_context=="bag"
 _take_all_button.visible=_context=="search" or _source_id=="overflow"
 _take_all_button.text="收回仓库" if _source_id=="overflow" else "全部拾取"
 _take_all_button.disabled=_read_only
 _sell_button.visible=camp
 _sort_button.disabled=_read_only

func _refresh_details():
 var item: Dictionary=_profile.get("items",{}).get(_selected_id,{})
 var selected=not item.is_empty()
 var definition=_catalog.get_definition(String(item.get("definition_id",""))) if selected and _catalog!=null else null
 if not selected:
  _details.text="选择物品查看详情。\n\n自动转移会优先堆叠并寻找空位。\n\n也可点击目标空格，预览后确认放置。"
 else:
  var name=String(definition.display_name) if definition!=null else "未知物品"
  var text=name+"\n\n数量  %d\n" % int(item.get("quantity",1))
  if definition!=null:
   text+="尺寸  %d × %d 格\n单件重量  %.2f kg\n单件价值  %d\n" % [definition.height if _rotated else definition.width,definition.width if _rotated else definition.height,definition.unit_weight,definition.value]
  if item.get("durability")!=null: text+="当前耐久  %.1f\n" % float(item.durability)
  if item.get("runtime",{}).has("ammo"): text+="弹匣  %d 发\n" % int(item.runtime.ammo)
  _details.text=text+"\n所在："+_container_title(_selected_container)
 _quantity_label.text="数量 %d" % _quantity
 _rotate_button.text="方向：横向 / 再次旋转" if _rotated else "旋转 90°"
 _rotate_button.disabled=not selected or _read_only or definition==null or definition.width==definition.height or (_context!="camp" and _selected_container==_equipment_id)
 _transfer_button.disabled=not selected or _read_only or (_context!="camp" and _selected_container==_equipment_id)
 _place_button.visible=not _placement.is_empty()
 _place_button.disabled=not bool(_placement.get("valid",false)) or _read_only
 var equippable=definition!=null and not String(definition.equipment_slot).is_empty()
 _equip_button.visible=equippable
 _equip_button.text="行动中无法更换装备" if _context!="camp" else ("卸下到背包" if _selected_container==_equipment_id else "装备到对应部位")
 _equip_button.disabled=_read_only or not selected or _context!="camp"
 _sell_button.disabled=not selected or _read_only or not (_selected_container=="stash_main" or _selected_container=="overflow")
 _transfer_button.text="移入仓库" if _selected_container==_target_id and _context=="camp" else "自动转移"

func _select_item(item_id: String,container_id: String):
 if _read_only: return
 if _context=="search" and container_id==_source_id and not _revealed.has(item_id): return
 _selected_id=item_id
 _selected_container=container_id
 _quantity=int(_profile.get("items",{}).get(item_id,{}).get("quantity",1))
 _placement={}
 _rotated=false
 for placement in _profile.get("containers",{}).get(container_id,{}).get("placements",[]):
  if placement.get("item_id")==item_id: _rotated=bool(placement.get("rotated",false))
 _refresh_grids(); _refresh_details()

func _set_quantity(value: int):
 if _selected_id.is_empty(): return
 _quantity=clampi(value,1,int(_profile.get("items",{}).get(_selected_id,{}).get("quantity",1)))
 if not _placement.is_empty(): _refresh_preview()
 _refresh_details()

func _rotate():
 _rotated=not _rotated
 if not _placement.is_empty(): _select_cell(_placement.to,_placement.x,_placement.y,_placement.slot)
 _refresh_details()

func _select_cell(container_id: String,x: int,y: int,slot: String):
 if _selected_id.is_empty() or _read_only: return
 if _context!="camp" and (container_id==_equipment_id or _selected_container==_equipment_id):
  set_notice("行动中无法更换装备；可在营地配装。",true)
  return
 var item: Dictionary=_profile.items[_selected_id]
 var definition=_catalog.get_definition(String(item.definition_id))
 if definition==null: return
 var footprint: Vector2i=definition.footprint(_rotated)
 var valid=_fits(container_id,x,y,footprint,slot,definition)
 _placement={"to":container_id,"x":x,"y":y,"slot":slot,"valid":valid}
 for grid in [_left_grid,_right_grid,_equipment_grid]:
  grid.clear_preview()
  if grid.container_id==container_id and slot.is_empty(): grid.preview(x,y,footprint,valid)
 set_notice("预览可放置；点击“放置到预览位置”确认。" if valid else "该位置空间不足、被占用或部位不匹配。",not valid)
 _refresh_details()

func _refresh_preview():
 var item: Dictionary=_profile.get("items",{}).get(_selected_id,{})
 var definition=_catalog.get_definition(String(item.get("definition_id","")))
 if definition==null: _placement={}; return
 var footprint: Vector2i=definition.footprint(_rotated)
 _placement.valid=_fits(_placement.to,_placement.x,_placement.y,footprint,_placement.slot,definition)
 for grid in [_left_grid,_right_grid,_equipment_grid]:
  grid.clear_preview()
  if grid.container_id==_placement.to and String(_placement.slot).is_empty(): grid.preview(_placement.x,_placement.y,footprint,_placement.valid)

func _fits(cid: String,x: int,y: int,footprint: Vector2i,slot: String,definition) -> bool:
 var container: Dictionary=_profile.get("containers",{}).get(cid,{})
 if container.is_empty(): return false
 if cid!=_selected_container and float(container.get("weight_limit",0.0))>0.0:
  var weight=float(definition.unit_weight)*_quantity
  for placement in container.get("placements",[]):
   var stored: Dictionary=_profile.get("items",{}).get(placement.get("item_id"),{})
   var stored_definition=_catalog.get_definition(String(stored.get("definition_id","")))
   if stored_definition!=null: weight+=stored_definition.unit_weight*int(stored.get("quantity",1))
  if weight>float(container.weight_limit)+0.000001: return false
 if container.get("kind")=="list": return true
 if container.get("kind")=="slots":
  if slot!=String(definition.equipment_slot): return false
  for placement in container.get("placements",[]):
   if placement.get("slot")==slot and placement.get("item_id")!=_selected_id: return false
  return true
 if x<0 or y<0 or x+footprint.x>int(container.get("width",0)) or y+footprint.y>int(container.get("height",0)): return false
 var target=Rect2i(x,y,footprint.x,footprint.y)
 for placement in container.get("placements",[]):
  if placement.get("item_id")==_selected_id and _selected_container==cid and _quantity==int(_profile.items[_selected_id].quantity): continue
  var other: Dictionary=_profile.get("items",{}).get(placement.get("item_id"),{})
  var def=_catalog.get_definition(String(other.get("definition_id","")))
  if def==null: return false
  var extent: Vector2i=def.footprint(bool(placement.get("rotated",false)))
  if target.intersects(Rect2i(int(placement.get("x",0)),int(placement.get("y",0)),extent.x,extent.y)): return false
 return true

func _transfer():
 if _selected_id.is_empty() or _read_only: return
 var destination=_target_id if _selected_container==_source_id else _source_id
 if _source_id=="overflow": destination="stash_main"
 if _selected_container==_equipment_id: destination="loadout_pack" if _context=="camp" else "raid_pack"
 _send_transfer(destination,-1,-1,"")

func _place():
 if _placement.is_empty() or not _placement.get("valid",false): return
 _send_transfer(_placement.to,_placement.x,_placement.y,_placement.slot)

func _equip():
 if _selected_id.is_empty() or _context!="camp": return
 if _selected_container==_equipment_id:
  _send_transfer("loadout_pack" if _context=="camp" else "raid_pack",-1,-1,"")
 else:
  var definition=_catalog.get_definition(String(_profile.items[_selected_id].definition_id))
  if definition!=null: _send_transfer(_equipment_id,-1,-1,String(definition.equipment_slot))

func _send_transfer(destination: String,x: int,y: int,slot: String):
 if _read_only or _selected_id.is_empty(): return
 if _context!="camp" and (destination==_equipment_id or _selected_container==_equipment_id): return
 command_requested.emit({"item_id":_selected_id,"quantity":_quantity,"from":_selected_container,"to":destination,"x":x,"y":y,"rotated":_rotated,"slot":slot})

func _toggle_overflow():
 _overflow_active=not _overflow_active
 _source_id="overflow" if _overflow_active else "stash_main"
 _target_id="stash_main" if _overflow_active else "loadout_pack"
 _selected_id=""; _placement={}
 _refresh_grids(); _refresh_actions(); _refresh_details()

func _has_active_raid() -> bool:
 var active=_profile.get("active_raid",{})
 return active is Dictionary and not active.is_empty()

func _owner(item_id: String) -> String:
 for cid in _profile.get("containers",{}):
  for placement in _profile.containers[cid].get("placements",[]):
   if placement.get("item_id")==item_id: return String(cid)
 return ""

func _container_title(cid: String) -> String:
 var title={"stash_main":"仓库","loadout_pack":"出战背包","raid_pack":"行动背包","loadout_equipment":"出战装备","raid_equipment":"当前装备","overflow":"待收取物品"}.get(cid,"补给容器")
 var container: Dictionary=_profile.get("containers",{}).get(cid,{})
 if container.get("kind")=="grid":
  var weight=0.0
  for placement in container.get("placements",[]):
   var item: Dictionary=_profile.get("items",{}).get(placement.get("item_id"),{})
   var definition=_catalog.get_definition(String(item.get("definition_id",""))) if _catalog!=null else null
   if definition!=null: weight+=definition.unit_weight*int(item.get("quantity",1))
  title+="  %.1f kg" % weight
 return title

func _label(text: String,font_size: int) -> Label:
 var label=Label.new(); label.text=text; label.mouse_filter=Control.MOUSE_FILTER_IGNORE; label.add_theme_font_size_override("font_size",font_size); label.add_theme_color_override("font_color",Color("ecebd9")); return label

func _button(text: String,width: float,height: float) -> Button:
 var button=Button.new(); button.text=text; button.custom_minimum_size=Vector2(width,height); button.focus_mode=Control.FOCUS_NONE; button.add_theme_font_size_override("font_size",18)
 var style=StyleBoxFlat.new(); style.bg_color=Color("35433b"); style.border_color=Color("647262"); style.set_border_width_all(1); style.set_corner_radius_all(4); style.content_margin_left=8; style.content_margin_right=8
 button.add_theme_stylebox_override("normal",style)
 var hover=style.duplicate(); hover.bg_color=Color("52604b"); button.add_theme_stylebox_override("hover",hover)
 var pressed=style.duplicate(); pressed.bg_color=Color("6b7253"); button.add_theme_stylebox_override("pressed",pressed)
 return button
