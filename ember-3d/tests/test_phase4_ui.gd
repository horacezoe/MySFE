extends SceneTree

const OperationPanel=preload("res://scripts/ui/operation_panel.gd")
const MissionCatalog=preload("res://scripts/raid/mission_catalog.gd")
const RaidRules=preload("res://scripts/raid/raid_rules.gd")
const InventoryService=preload("res://scripts/inventory/inventory_service.gd")
const InventoryPanel=preload("res://scripts/ui/inventory_panel.gd")
var checks=0
var failures=0
var signals_seen: Array=[]
var panel
var missions=MissionCatalog.new()
var rules=RaidRules.new()
var inventory=InventoryService.new()

func _initialize(): call_deferred("run")

func check(condition: bool,label: String):
 checks+=1
 if not condition:
  failures+=1
  push_error("PHASE4 UI: "+label)

func wait_layout():
 for index in range(4): await process_frame

func map_fixture() -> Dictionary:
 return {"id":"depot_v1","name":"灰湾转运站","bounds":Rect2(-30.5,-30.5,61,61),"spawn":Vector3(-26,0,-26),"crates":[Vector3(-22,0,-22),Vector3(12,0,3)],"walls":[Rect2(3,-10,1,5)],"zones":[{"id":"supply","title":"西侧补给区","rect":Rect2(-30,-30,22,24),"risk":"low"},{"id":"signal","title":"通信站","rect":Rect2(12,-10,17,20),"risk":"high"}],"guards":[{"id":"secret_enemy","position":Vector3(8,0,8)}],"survey":{"id":"signal_station","position":Vector3(22,0,0),"radius":3.0},"exits":[{"id":"south_gate","title":"南侧公路","position":Vector3(25,0,25),"wait":5,"radius":3.6,"required_item":""},{"id":"service_gate","title":"维护通道","position":Vector3(-25,0,24),"wait":3,"radius":3.6,"required_item":"depot_pass"}]}

func state_fixture() -> Dictionary:
 var state=inventory.new_state()
 state.currency=1500; state.wins=0; state.active_raid={}
 state.settings={"difficulty":"comfort"}; state.missions=missions.new_state()
 return state

func visible_buttons(node: Node) -> Array:
 var result=[]
 if node is Button and node.is_visible_in_tree(): result.append(node)
 for child in node.get_children(): result.append_array(visible_buttons(child))
 return result

func run():
 var state=state_fixture()
 var definition=map_fixture()
 panel=OperationPanel.new(); root.add_child(panel); panel.setup(missions,rules)
 panel.mission_accepted.connect(func(id): signals_seen.append(["accept",id]))
 panel.mission_claimed.connect(func(id): signals_seen.append(["claim",id]))
 panel.difficulty_changed.connect(func(id): signals_seen.append(["rule",id]))
 panel.depart.connect(func(): signals_seen.append(["depart"]))
 panel.resume_raid.connect(func(): signals_seen.append(["resume"]))
 panel.warehouse_requested.connect(func(): signals_seen.append(["warehouse"]))
 panel.closed.connect(func(): signals_seen.append(["closed"]))
 panel.render(state,definition)
 await wait_layout()
 check(panel._mission_rows.size()==3,"renders all three mission definitions")
 check(panel._rule_buttons.comfort.text.contains("已选") and not panel._rule_buttons.standard.disabled,"camp shows chosen rule and permits a new choice")
 check(panel._rules_note.text.contains("失败保留身上装备"),"comfort consequences are visible before deployment")
 check(panel._depart_button.text=="进入封锁区","fresh camp offers deployment")
 check(panel._exit_labels.size()==2,"both extraction routes have visible conditions")
 check(panel._exit_labels[1].text.contains("需要携带"),"conditional exit advertises the missing pass")
 check(not panel._map.exit_access.service_gate and panel._map.exit_access.south_gate,"map access colors match exit requirements")
 check(panel._map.markers.all(func(marker): return marker.kind!="enemy"),"tactical map never exposes live guard positions")
 check(panel._map.markers.filter(func(marker): return marker.kind=="supply").size()==2,"only fixed supply points are represented without contents")
 var before=JSON.stringify(state,"",true)
 panel._mission_rows.collect_medical.button.pressed.emit()
 panel._rule_buttons.standard.pressed.emit()
 panel._depart_button.pressed.emit()
 panel._warehouse_button.pressed.emit()
 check(signals_seen==[["accept","collect_medical"],["rule","standard"],["depart"],["warehouse"]],"camp buttons emit only expected intentions")
 check(JSON.stringify(state,"",true)==before,"mission and rule UI never mutates profile")
 state.settings.difficulty="standard"
 panel.render(state,definition)
 check(panel._rules_note.text.contains("丢失身上装备与背包"),"standard loss rule is explicit")
 state.missions.collect_medical.status="active"
 inventory.add_item(state,"loot_medical",1,"stash_main")
 inventory.add_item(state,"loot_medical",1,"overflow")
 inventory.add_item(state,"loot_medical",2,"stash_main",{"bound":true})
 panel.render(state,definition)
 check(panel._mission_rows.collect_medical.ready and not panel._mission_rows.collect_medical.button.disabled,"collect mission counts warehouse and overflow")
 before=JSON.stringify(state,"",true)
 panel._mission_rows.collect_medical.button.pressed.emit()
 check(signals_seen.back()==["claim","collect_medical"] and JSON.stringify(state,"",true)==before,"claim only emits and never consumes items locally")
 state.missions.collect_medical.status="claimed"
 panel.render(state,definition)
 check(panel._mission_rows.collect_medical.button.disabled and panel._mission_rows.collect_medical.progress.text.contains("已领取"),"claimed mission cannot be rewarded again from UI")
 var bound_only=state_fixture(); bound_only.missions.collect_medical.status="active"
 inventory.add_item(bound_only,"loot_medical",2,"stash_main",{"bound":true})
 panel.render(bound_only,definition)
 check(not panel._mission_rows.collect_medical.ready,"relief items do not satisfy collection delivery")
 for viewport_size in [Vector2i(1280,720),Vector2i(1200,900),Vector2i(1280,960)]:
  root.size=viewport_size
  panel.render(state,definition)
  await wait_layout()
  var view=root.get_visible_rect()
  check(view.encloses(panel._depart_button.get_global_rect()) and view.encloses(panel._close_button.get_global_rect()),"footer stays on-screen "+str(viewport_size))
  check(view.encloses(panel._map.get_global_rect()) and panel._map.size.y>=300,"map remains usable "+str(viewport_size))
  check(view.encloses(panel._mission_scroll.get_global_rect()) and panel._mission_scroll.size.y>=180,"mission scroller fits "+str(viewport_size))
  check(view.encloses(panel._rule_buttons.standard.get_global_rect()) and view.encloses(panel._down_button.get_global_rect()),"rule and paging touch controls remain reachable "+str(viewport_size))
  check(visible_buttons(panel).all(func(button): return button.size.y>=44),"all action targets at least 44 pixels "+str(viewport_size))
 root.size=Vector2i(1280,720)
 panel.render(state,definition)
 await wait_layout()
 var original_scroll=panel._mission_scroll.scroll_vertical
 panel._down_button.pressed.emit()
 await wait_layout()
 check(panel._mission_scroll.scroll_vertical>=original_scroll,"missions can be paged without dragging")
 var raid=state.duplicate(true)
 raid.active_raid={"raid_id":"test","map_id":"depot_v1","rule_id":"comfort","events":{"visits":["signal_station"],"kills":["guard_06"]}}
 raid.missions.survey_depot.status="active"; raid.missions.eliminate_officer.status="active"
 raid.containers.raid_pack=inventory.make_grid(6,5,25.0)
 inventory.add_item(raid,"depot_pass",1,"raid_pack")
 panel.render(raid,definition,false)
 check(panel._depart_button.text=="继续上局" and panel._rule_buttons.standard.disabled,"pending raid locks difficulty and resumes")
 check(panel._mission_rows.survey_depot.progress.text.contains("成功撤离后交付"),"local visit is shown pending successful extraction")
 check(panel._mission_rows.eliminate_officer.progress.text.contains("本局已达成"),"named target event is visible without enemy coordinates")
 var signal_count=signals_seen.size()
 panel._request_rule("standard"); panel._request_mission("survey_depot"); panel._request_mission("collect_medical")
 check(signals_seen.size()==signal_count,"direct callbacks cannot bypass active raid rule or mission locks")
 panel._depart_button.pressed.emit()
 check(signals_seen.back()==["resume"],"pending raid emits resume instead of another deployment")
 panel.render(raid,definition,true,Vector3(10,0,0))
 check(not panel._depart_button.visible and not panel._warehouse_button.visible,"in-raid brief hides camp actions")
 check(panel._exit_labels[1].text.contains("通行证已携带") and panel._exit_labels[0].text.contains("米"),"in-raid exits show carried pass and distances")
 check(panel._map.show_player and panel._map.player_position==Vector3(10,0,0),"map marks current player location")
 check(panel._map.exit_access.service_gate,"carried pass unlocks corresponding marker")
 signal_count=signals_seen.size(); panel._request_depart()
 check(signals_seen.size()==signal_count,"in-raid callback cannot start a new raid")
 panel._close_button.pressed.emit()
 check(signals_seen.back()==["closed"] and panel._close_button.text=="返回行动","map close delegates to current gameplay context")
 var inventory_panel=InventoryPanel.new(); root.add_child(inventory_panel); inventory_panel.setup(inventory.catalog)
 inventory_panel.operation_requested.connect(func(): signals_seen.append(["operation"]))
 inventory_panel.render(state,"camp","stash_main","loadout_pack")
 await wait_layout()
 inventory_panel._operation_button.pressed.emit()
 check(signals_seen.back()==["operation"] and root.get_visible_rect().encloses(inventory_panel._operation_button.get_global_rect()),"warehouse provides a visible brief entry")
 inventory_panel.render(raid,"bag","raid_pack","raid_pack")
 check(not inventory_panel._operation_button.visible,"warehouse-only brief entry is hidden inside the bag")
 inventory_panel.free(); panel.free()
 await process_frame
 print("Phase4 UI: %d checks; %d failures" % [checks,failures])
 quit(1 if failures else 0)
