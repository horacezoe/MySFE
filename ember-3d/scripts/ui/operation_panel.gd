extends Control
## Mission and rule UI sends intentions; only ProfileService changes progress.
signal closed
signal warehouse_requested
signal depart
signal resume_raid
signal mission_accepted(id: String)
signal mission_claimed(id: String)
signal difficulty_changed(id: String)

const TacticalMap=preload("res://scripts/ui/tactical_map.gd")
const TEXT=Color("e0e5d3")
const MUTED=Color("adbaa2")
const AMBER=Color("dfb96f")
var _mission_catalog: RefCounted
var _rule_catalog: RefCounted
var _profile: Dictionary={}
var _map_definition: Dictionary={}
var _in_raid=false
var _built=false
var _mission_rows: Dictionary={}
var _rule_buttons: Dictionary={}
var _title: Label
var _account: Label
var _notice: Label
var _map_title: Label
var _map: Control
var _exit_labels: Array[Label]=[]
var _exit_box: VBoxContainer
var _rules_note: Label
var _mission_scroll: ScrollContainer
var _mission_stack: VBoxContainer
var _warehouse_button: Button
var _depart_button: Button
var _close_button: Button
var _up_button: Button
var _down_button: Button
var _legend: Label
var _rules_row: HBoxContainer

func setup(mission_catalog: RefCounted,rule_catalog: RefCounted):
 _mission_catalog=mission_catalog
 _rule_catalog=rule_catalog
 if not _built: _build()

func _ready():
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 if not _built: _build()

func _active() -> bool:
 return not _profile.get("active_raid",{}).is_empty()

func render(profile: Dictionary,map_definition: Dictionary,in_raid:=false,player_position:=Vector3.ZERO):
 if not _built: _build()
 _profile=profile
 _map_definition=map_definition
 _in_raid=in_raid
 var pending=_active()
 _title.text="行动地图与目标" if in_raid else "营地行动简报"
 _account.text="资产 %d  /  成功撤离 %d 次" % [int(profile.get("currency",0)),int(profile.get("wins",0))]
 _map_title.text=String(map_definition.get("name","灰湾转运站"))
 var rule_id=String(profile.get("active_raid",{}).get("rule_id",profile.get("settings",{}).get("difficulty","comfort")))
 for id in _rule_buttons:
  var button: Button=_rule_buttons[id]
  button.disabled=pending or in_raid
  button.text=("已选 · " if id==rule_id else "")+("舒适" if id=="comfort" else "标准")
  button.add_theme_stylebox_override("normal",_style(Color("485540") if id==rule_id else Color("263a30"),AMBER if id==rule_id else Color("50644f")))
 var rule: Dictionary=_rule_catalog.get_rule(rule_id) if _rule_catalog!=null else {}
 _rules_note.text=("本局已锁定。" if pending else "下次行动规则。")+ ("舒适：敌人压力较低。\n失败保留身上装备，背包丢失。" if rule.get("death_keep_equipment",rule_id=="comfort") else "标准：完整战斗压力。\n失败丢失身上装备与背包。")
 _warehouse_button.visible=not in_raid
 _depart_button.visible=not in_raid
 _depart_button.text="继续上局" if pending else "进入封锁区"
 _close_button.text="返回行动" if in_raid else "返回仓库"
 _refresh_missions()
 _refresh_exits(player_position)
 var access={}
 for exit in map_definition.get("exits",[]): access[exit.id]=_has_requirement(String(exit.get("required_item","")))
 _map.render(map_definition,player_position,in_raid,access)
 set_notice("查看路线与已记录目标；地图中不显示敌人实时位置。" if in_raid else ("上局仍在进行。任务和难度锁定，继续上局完成行动。" if pending else "先接任务、选择规则，再检查仓库装备出发。"))
 visible=true

func set_notice(text: String,is_error:=false):
 if not _built: _build()
 _notice.text=text
 _notice.add_theme_color_override("font_color",Color("edaa90") if is_error else MUTED)

func _build():
 _built=true
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var theme=Theme.new(); theme.default_font_size=18; self.theme=theme
 var background=ColorRect.new(); background.color=Color("15251e"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
 var margin=MarginContainer.new(); add_child(margin); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,22)
 var stack=VBoxContainer.new(); stack.add_theme_constant_override("separation",10); margin.add_child(stack)
 var header=HBoxContainer.new(); stack.add_child(header)
 _title=_label("营地行动简报",31); _title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(_title)
 _account=_label("",18,MUTED); header.add_child(_account)
 _notice=_label("",17,MUTED); _notice.clip_text=true; _notice.custom_minimum_size.y=24; stack.add_child(_notice)
 var body=HBoxContainer.new(); body.add_theme_constant_override("separation",22); body.size_flags_vertical=Control.SIZE_EXPAND_FILL; stack.add_child(body)
 var map_column=VBoxContainer.new(); map_column.custom_minimum_size.x=480; map_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; map_column.size_flags_stretch_ratio=1.1; body.add_child(map_column)
 _map_title=_label("灰湾转运站",24); map_column.add_child(_map_title)
 _map=TacticalMap.new(); _map.size_flags_vertical=Control.SIZE_EXPAND_FILL; map_column.add_child(_map)
 _legend=_label("小方块：补给点   十字：调查点   方框：出口",16,MUTED); map_column.add_child(_legend)
 _exit_box=VBoxContainer.new(); _exit_box.add_theme_constant_override("separation",4); map_column.add_child(_exit_box)
 var side=VBoxContainer.new(); side.custom_minimum_size.x=480; side.size_flags_horizontal=Control.SIZE_EXPAND_FILL; side.add_theme_constant_override("separation",8); body.add_child(side)
 _rules_row=HBoxContainer.new(); _rules_row.add_theme_constant_override("separation",8); side.add_child(_rules_row)
 var mode_title=_label("行动规则",21); mode_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _rules_row.add_child(mode_title)
 for id in ["comfort","standard"]:
  var button=_button("舒适" if id=="comfort" else "标准",140)
  _rule_buttons[id]=button; _rules_row.add_child(button)
  button.pressed.connect(func(): _request_rule(id))
 _rules_note=_label("",17,MUTED); _rules_note.clip_text=true; _rules_note.custom_minimum_size.y=48; side.add_child(_rules_note)
 var mission_header=HBoxContainer.new(); side.add_child(mission_header)
 var title=_label("营地委托",23); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; mission_header.add_child(title)
 _up_button=_button("上移",70); _down_button=_button("下移",70); mission_header.add_child(_up_button); mission_header.add_child(_down_button)
 _mission_scroll=ScrollContainer.new(); _mission_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; _mission_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; side.add_child(_mission_scroll)
 _mission_stack=VBoxContainer.new(); _mission_stack.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _mission_stack.add_theme_constant_override("separation",10); _mission_scroll.add_child(_mission_stack)
 _up_button.pressed.connect(func(): _mission_scroll.scroll_vertical-=180)
 _down_button.pressed.connect(func(): _mission_scroll.scroll_vertical+=180)
 var footer=HBoxContainer.new(); footer.add_theme_constant_override("separation",12); stack.add_child(footer)
 _warehouse_button=_button("仓库与配装",190); footer.add_child(_warehouse_button); _warehouse_button.pressed.connect(func(): if not _in_raid: warehouse_requested.emit())
 var hint=_label("E 搜索 / 撤离   B 背包   M 地图与目标",17,MUTED); hint.size_flags_horizontal=Control.SIZE_EXPAND_FILL; footer.add_child(hint)
 _depart_button=_button("进入封锁区",190); footer.add_child(_depart_button); _depart_button.add_theme_stylebox_override("normal",_style(Color("786b42"),AMBER))
 _depart_button.pressed.connect(_request_depart)
 _close_button=_button("返回仓库",140); footer.add_child(_close_button); _close_button.pressed.connect(func(): closed.emit())

func _refresh_missions():
 var definitions: Array=_mission_catalog.definitions() if _mission_catalog!=null else []
 for definition in definitions:
  var id=String(definition.id)
  if not _mission_rows.has(id): _create_mission_row(id)
  var row: Dictionary=_mission_rows[id]
  var state: Dictionary=_profile.get("missions",{}).get(id,{"status":"available","progress":0})
  var status=String(state.get("status","available"))
  var required=int(definition.get("required",1))
  var progress=int(state.get("progress",0))
  var pending_event=false
  var available_count=0
  if String(definition.get("kind",""))=="collect":
   available_count=_item_count(String(definition.get("target","")),["stash_main","overflow"],true)
   if status=="active" or status=="ready": progress=mini(required,available_count)
  elif status=="active" and _active():
   var kind=String(definition.get("kind",""))
   var key="visits" if kind=="visit" else "kills"
   pending_event=_profile.active_raid.get("events",{}).get(key,[]).has(definition.get("target",""))
  var ready=status=="ready" or (status=="active" and String(definition.get("kind",""))=="collect" and progress>=required)
  row.title.text=String(definition.title)
  row.description.text=String(definition.description)
  row.reward.text="奖励 %d 资产" % int(definition.get("reward_currency",0))
  var progress_text="尚未接受"
  if status=="claimed": progress_text="已交付 · 奖励已领取"
  elif pending_event: progress_text="本局已达成 · 成功撤离后交付"
  elif status=="active" or status=="ready": progress_text="进度 %d / %d%s" % [progress,required," · 可交付" if ready else ""]
  row.progress.text=progress_text
  row.progress.add_theme_color_override("font_color",AMBER if ready or pending_event else MUTED)
  row.button.text="接受任务" if status=="available" else ("交付并领奖" if ready else ("已领取" if status=="claimed" else "进行中"))
  row.button.disabled=_active() or _in_raid or not (status=="available" or ready)
  row.ready=ready

func _create_mission_row(id: String):
 var panel=PanelContainer.new(); panel.add_theme_stylebox_override("panel",_style(Color("24382c"),Color("4d624e"))); _mission_stack.add_child(panel)
 var contents=VBoxContainer.new(); contents.add_theme_constant_override("separation",5); panel.add_child(contents)
 var title=_label("",21); contents.add_child(title)
 var description=_label("",17,MUTED); description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; description.custom_minimum_size.x=410; contents.add_child(description)
 var bottom=HBoxContainer.new(); bottom.add_theme_constant_override("separation",10); contents.add_child(bottom)
 var details=VBoxContainer.new(); details.size_flags_horizontal=Control.SIZE_EXPAND_FILL; bottom.add_child(details)
 var progress=_label("",16,MUTED); details.add_child(progress)
 var reward=_label("",16,MUTED); details.add_child(reward)
 var button=_button("接受任务",145); bottom.add_child(button)
 button.pressed.connect(func(): _request_mission(id))
 _mission_rows[id]={"panel":panel,"title":title,"description":description,"progress":progress,"reward":reward,"button":button,"ready":false}

func _refresh_exits(player_position: Vector3):
 for label in _exit_labels: label.free()
 _exit_labels.clear()
 for exit in _map_definition.get("exits",[]):
  var requirement=String(exit.get("required_item",""))
  var condition="随时可用" if requirement.is_empty() else ("通行证已携带" if _has_requirement(requirement) else "需要携带转运站通行证")
  var distance="  %d 米" % int(player_position.distance_to(exit.position)) if _in_raid else ""
  var label=_label("%s%s  ·  %s  ·  等待 %d 秒" % [exit.title,distance,condition,int(exit.get("wait",5))],16,AMBER if not _has_requirement(requirement) else TEXT)
  label.clip_text=true
  _exit_box.add_child(label); _exit_labels.append(label)

func _has_requirement(id: String) -> bool:
 if id.is_empty(): return true
 return _item_count(id,["raid_pack"] if _active() else ["loadout_pack"])>0

func _item_count(id: String,containers: Array,exclude_bound:=false) -> int:
 var count=0
 for cid in containers:
  for placement in _profile.get("containers",{}).get(cid,{}).get("placements",[]):
   var item: Dictionary=_profile.get("items",{}).get(placement.get("item_id",""),{})
   if item.get("definition_id","")!=id or (exclude_bound and item.get("bound",false)): continue
   count+=int(item.get("quantity",0))
 return count

func _request_rule(id: String):
 if _active() or _in_raid or not _rule_buttons.has(id): return
 difficulty_changed.emit(id)

func _request_depart():
 if _in_raid: return
 if _active(): resume_raid.emit()
 else: depart.emit()

func _request_mission(id: String):
 if _active() or _in_raid or not _mission_rows.has(id): return
 var state: Dictionary=_profile.get("missions",{}).get(id,{"status":"available"})
 if state.get("status")=="available": mission_accepted.emit(id)
 elif _mission_rows[id].ready: mission_claimed.emit(id)

func _label(text: String,font_size: int,color:=TEXT) -> Label:
 var label=Label.new(); label.text=text; label.add_theme_font_size_override("font_size",font_size); label.add_theme_color_override("font_color",color); label.mouse_filter=Control.MOUSE_FILTER_IGNORE
 return label

func _button(text: String,width: float) -> Button:
 var button=Button.new(); button.text=text; button.custom_minimum_size=Vector2(width,48); button.focus_mode=Control.FOCUS_NONE
 button.add_theme_font_size_override("font_size",19); button.add_theme_color_override("font_color",TEXT)
 button.add_theme_stylebox_override("normal",_style(Color("2c4234"),Color("5e7457")))
 button.add_theme_stylebox_override("hover",_style(Color("405842"),AMBER))
 button.add_theme_stylebox_override("pressed",_style(Color("5b6543"),AMBER))
 button.add_theme_stylebox_override("disabled",_style(Color("26362b"),Color("425342")))
 button.add_theme_color_override("font_disabled_color",Color("87947e"))
 return button

func _style(background: Color,border: Color) -> StyleBoxFlat:
 var style=StyleBoxFlat.new(); style.bg_color=background; style.border_color=border
 style.set_border_width_all(1); style.set_corner_radius_all(3)
 style.content_margin_left=12; style.content_margin_right=12; style.content_margin_top=9; style.content_margin_bottom=9
 return style
