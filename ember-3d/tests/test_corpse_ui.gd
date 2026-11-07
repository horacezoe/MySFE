extends SceneTree
## Search-only UI regression; no real profile or disk access.
const InventoryService=preload("res://scripts/inventory/inventory_service.gd")
const InventoryPanel=preload("res://scripts/ui/inventory_panel.gd")
var inventory=InventoryService.new()
var panel
var state: Dictionary
var checks=0
var failures=0
var commands: Array=[]

func _initialize(): call_deferred("run")

func check(condition: bool,label: String):
 checks+=1
 if not condition:
  failures+=1
  push_error("CORPSE UI: "+label)

func frames():
 for i in 3: await process_frame

func add(cid: String,id: String,quantity: int,extra: Dictionary={}) -> String:
 var result=inventory.add_item(state,id,quantity,cid,extra)
 check(result.ok,"fixture adds "+id+" to "+cid)
 return result.item_ids[0] if result.ok else ""

func run():
 root.size=Vector2i(1280,720)
 state=inventory.new_state()
 state.currency=500; state.wins=0
 state.containers.raid_pack=inventory.make_grid(6,5,25.0)
 state.containers.raid_equipment=inventory.make_slots(["weapon","helmet","vest"])
 for cid in ["loot_guard_00","loot_guard_01","loot_guard_02","loot_00"]:
  state.containers[cid]=inventory.make_grid(6,24)
 state.active_raid={"raid_id":"ui_fixture","search":{
  "loot_guard_00":{"kind":"corpse","guard_id":"guard_00"},
  "loot_guard_01":{"kind":"corpse","guard_id":"guard_01","title":"指挥官遗留物资"},
  "loot_guard_02":{"kind":"corpse","guard_id":"guard_02"},
  "loot_00":{},
 }}
 var ammunition=add("loot_guard_00","ammo_rifle",30)
 var rifle=add("loot_guard_00","rifle_basic",1,{"runtime":{"ammo":7},"durability":63.0})
 var chip=add("loot_guard_01","loot_chip",1)
 var box_item=add("loot_00","loot_medical",1)
 var pack_item=add("raid_pack","medkit_basic",1)
 var before=JSON.stringify(state,"",true)
 panel=InventoryPanel.new(); root.add_child(panel); panel.setup(inventory.catalog)
 panel.command_requested.connect(func(command): commands.append(command))
 panel.render(state,"search","loot_guard_00","raid_pack",[])
 await frames()
 check(panel._title.text=="搜索敌人物资","corpse uses enemy-search heading")
 check(panel._left_title.text=="守卫遗留物资  已发现 0.0 kg","hidden loot does not disclose its weight")
 check(panel._left_grid._item_buttons[rifle].text=="?" and panel._left_grid._item_buttons[rifle].tooltip_text=="正在搜索","unrevealed rifle name and magazine are concealed")
 check(panel._left_grid._item_buttons[rifle].disabled and panel._take_all_button.disabled,"unrevealed loot cannot be picked through controls")
 panel._select_item(rifle,"loot_guard_00")
 panel._select_item(rifle,"raid_pack")
 check(panel._selected_id.is_empty() and not panel._details.text.contains("弹匣"),"hidden source or forged owner cannot reveal details")
 panel.render(state,"search","loot_guard_00","raid_pack",[ammunition])
 panel._select_item(ammunition,"loot_guard_00"); panel._set_quantity(7)
 panel._left_scroll.scroll_vertical=160
 await frames()
 var scroll_before=panel._left_scroll.scroll_vertical
 check(scroll_before>0,"long search grid can scroll before a source change")
 panel.render(state,"search","loot_guard_00","raid_pack",[ammunition,rifle])
 await frames()
 check(panel._selected_id==ammunition and panel._quantity==7,"same-source reveal preserves current selection and quantity")
 check(panel._left_scroll.scroll_vertical==scroll_before,"same-source refresh preserves scroll location")
 check(not panel._take_all_button.disabled,"revealed remaining items enable take-all")
 panel._take_all_button.pressed.emit()
 check(commands.size()==1 and commands[0].from=="loot_guard_00" and commands[0].to=="raid_pack","take-all targets the current corpse")
 panel._select_item(rifle,"loot_guard_00")
 check(panel._details.text.contains("弹匣  7 发") and panel._details.text.contains("63.0"),"revealed weapon reports persisted ammunition and durability")
 panel._rotate()
 panel._select_cell("raid_pack",2,1,"")
 check(not panel._placement.is_empty() and panel._rotated,"corpse item can establish a rotated placement preview")
 panel.render(state,"search","loot_guard_01","raid_pack",[chip])
 await frames()
 check(panel._title.text=="搜索敌人物资" and panel._left_title.text.begins_with("指挥官遗留物资"),"provided role title identifies the corpse")
 check(panel._selected_id.is_empty() and panel._selected_container.is_empty() and panel._quantity==1 and not panel._rotated,"new corpse clears all selection state despite identical search context")
 check(panel._placement.is_empty() and not panel._right_grid._preview_panel.visible,"new corpse clears stale placement preview")
 check(panel._left_scroll.scroll_vertical==0 and panel._right_scroll.scroll_vertical==0,"new source starts at the top of both panels")
 check(not panel._details.text.contains("弹匣") and panel._transfer_button.disabled,"new source cannot retain previous rifle details or transfer")
 panel._select_item(chip,"loot_guard_01")
 panel.render(state,"search","loot_guard_01","raid_pack",[])
 check(panel._selected_id.is_empty() and not panel._details.text.contains("解码芯片"),"concealed-on-refresh selection cannot leak old item details")
 panel.render(state,"search","loot_00","raid_pack",[])
 check(panel._title.text=="搜索补给" and panel._left_title.text.begins_with("补给容器"),"ordinary crate keeps supply-search labels")
 check(panel._left_grid._item_buttons[box_item].disabled,"crate reveal gating remains intact")
 panel.render(state,"search","loot_guard_02","raid_pack",[])
 panel.set_notice("物资已取空")
 await frames()
 check(panel._left_grid.container_id=="loot_guard_02" and panel._left_grid._item_buttons.is_empty(),"empty corpse remains a valid searchable grid")
 check(panel._notice.text=="物资已取空" and panel._take_all_button.disabled and panel._transfer_button.disabled,"empty search respects root notice and disables pickup actions")
 check(panel._left_scroll.size.y>150 and panel._right_scroll.size.y>150,"corpse search keeps usable inventory areas")
 panel._select_item(pack_item,"raid_pack")
 panel.render(state,"search","loot_guard_02","raid_pack",[])
 check(panel._selected_id==pack_item,"same-source refresh retains a legitimate player-pack selection")
 panel.render(state,"search","loot_guard_00","raid_pack",[ammunition,rifle])
 check(panel._selected_id.is_empty(),"switching corpses also clears selection from the player pack")
 check(JSON.stringify(state,"",true)==before,"UI never mutates authoritative loot or profile data")
 panel.free()
 await process_frame
 print("Corpse UI: %d checks; %d failures" % [checks,failures])
 quit(1 if failures else 0)
