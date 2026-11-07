extends SceneTree

const InventoryService=preload("res://scripts/inventory/inventory_service.gd")
const InventoryPanel=preload("res://scripts/ui/inventory_panel.gd")
var service=InventoryService.new()
var panel
var checks=0
var failures=0
var requests: Array=[]

func _initialize():
 call_deferred("run")

func check(condition: bool,label: String):
 checks+=1
 if not condition:
  failures+=1
  push_error("INVENTORY UI: "+label)

func first_id(state: Dictionary,cid: String,definition_id: String) -> String:
 for placement in state.containers[cid].placements:
  if state.items[placement.item_id].definition_id==definition_id: return placement.item_id
 return ""

func wait_layout():
 await process_frame
 await process_frame
 await process_frame

func run():
 var state=service.new_state()
 state.currency=1234; state.wins=2; state.active_raid={}
 service.add_item(state,"ammo_rifle",60,"stash_main")
 service.add_item(state,"rifle_basic",1,"stash_main",{"durability":87.0})
 service.add_item(state,"ammo_rifle",20,"loadout_pack")
 service.add_item(state,"loot_chip",1,"overflow")
 var ammo=first_id(state,"stash_main","ammo_rifle")
 var rifle=first_id(state,"stash_main","rifle_basic")
 var before=JSON.stringify(state,"",true)
 panel=InventoryPanel.new()
 root.add_child(panel)
 panel.setup(service.catalog)
 panel.command_requested.connect(func(request): requests.append(request))
 panel.render(state,"camp","stash_main","loadout_pack")
 await wait_layout()
 check(not panel._read_only and not panel._depart_button.disabled,"empty active raid keeps camp editable")
 panel._left_grid._item_buttons[ammo].pressed.emit()
 panel._set_quantity(17)
 panel._transfer_button.pressed.emit()
 check(requests.size()==1 and requests[0].quantity==17 and requests[0].to=="loadout_pack","selection and split quantity produce transfer intention")
 check(not requests[0].has("command_id"),"caller owns command id and revision allocation")
 panel._select_cell("stash_main",0,0,"")
 check(not panel._placement.valid,"partial split cannot overlap its remaining source stack")
 panel.render(state,"camp","stash_main","loadout_pack")
 check(panel._selected_id==ammo and panel._quantity==17,"refresh preserves selection and quantity")
 panel._left_grid._item_buttons[rifle].pressed.emit()
 panel._select_cell("loadout_pack",0,0,"")
 check(not panel._placement.valid and panel._place_button.disabled,"occupied cells reject preview")
 panel._select_cell("loadout_pack",3,1,"")
 check(panel._placement.valid and panel._right_grid._preview_panel.visible,"free cells show a visible preview above grid buttons")
 state.containers.loadout_pack.weight_limit=1.0
 panel._select_cell("loadout_pack",3,1,"")
 check(not panel._placement.valid,"weight limit invalidates placement preview")
 state.containers.loadout_pack.weight_limit=25.0
 panel._select_cell("loadout_pack",3,1,"")
 panel._rotate_button.pressed.emit()
 check(panel._right_grid._preview.size==Vector2i(3,2),"rotation changes preview footprint")
 panel._place_button.pressed.emit()
 check(requests.back().x==3 and requests.back().y==1 and requests.back().rotated,"manual placement emits selected position and rotation")
 panel._select_cell("loadout_pack",5,4,"")
 check(not panel._placement.valid,"out of bounds preview is rejected")
 panel._equip_button.pressed.emit()
 check(requests.back().to=="loadout_equipment" and requests.back().slot=="weapon","equip emits matching slot")
 check(JSON.stringify(state,"",true)==before,"all UI actions leave authoritative profile untouched")
 panel._toggle_overflow()
 check(panel._source_id=="overflow" and panel._target_id=="stash_main","overflow exposes warehouse destination")
 for viewport_size in [Vector2i(1280,720),Vector2i(1280,960)]:
  root.size=viewport_size
  await wait_layout()
  var visible=root.get_visible_rect()
  check(visible.encloses(panel._depart_button.get_global_rect()),"camp footer fits "+str(viewport_size))
  check(visible.encloses(panel._sell_button.get_global_rect()),"inspector action fits "+str(viewport_size))
  check(panel._left_scroll.size.y>150 and panel._right_scroll.size.y>150,"grids have usable scroll areas "+str(viewport_size))
 panel._toggle_overflow()
 var raid=state.duplicate(true)
 raid.active_raid={"id":"test_raid"}
 raid.containers.raid_pack=service.make_grid(6,5,25.0)
 raid.containers.raid_equipment=service.make_slots(["weapon","helmet","vest"])
 raid.containers.loot_00=service.make_grid(4,4)
 service.add_item(raid,"ammo_rifle",30,"loot_00")
 service.add_item(raid,"loot_chip",1,"loot_00")
 var loot_ammo=first_id(raid,"loot_00","ammo_rifle")
 var loot_chip=first_id(raid,"loot_00","loot_chip")
 panel.render(raid,"search","loot_00","raid_pack",[loot_ammo])
 check(panel._left_grid._item_buttons[loot_chip].disabled and panel._left_grid._item_buttons[loot_chip].text=="?","unrevealed collectibles remain concealed and disabled")
 panel._select_item(loot_chip,"loot_00")
 check(panel._selected_id.is_empty(),"unrevealed items cannot be selected programmatically")
 panel._left_grid._item_buttons[loot_ammo].pressed.emit()
 panel._set_quantity(7)
 panel.render(raid,"search","loot_00","raid_pack",[loot_ammo,loot_chip])
 check(panel._selected_id==loot_ammo and panel._quantity==7,"progressive reveal preserves active selection")
 check(not panel._left_grid._item_buttons[loot_chip].disabled,"new reveal unlocks collectible")
 panel._take_all_button.pressed.emit()
 check(requests.back().action=="take_all" and requests.back().from=="loot_00","take all passes current source")
 service.add_item(raid,"rifle_basic",1,"raid_equipment")
 panel.render(raid,"bag","raid_pack","raid_pack")
 check(panel._right_grid.container_id=="raid_equipment" and not panel._equipment_grid.visible,"bag without return container shows equipment beside pack")
 var equipped=first_id(raid,"raid_equipment","rifle_basic")
 panel._select_item(equipped,"raid_equipment")
 var count_before=requests.size()
 panel._equip(); panel._transfer(); panel._select_cell("raid_pack",0,0,"")
 check(requests.size()==count_before and panel._equip_button.disabled and panel._transfer_button.disabled,"raid equipment is read only")
 panel.render(raid,"camp","stash_main","loadout_pack")
 panel._select_item(ammo,"stash_main"); panel._transfer()
 check(panel._read_only and requests.size()==count_before,"pending raid locks camp transfers")
 check(panel._depart_button.text=="继续上局" and panel._abandon_button.visible,"pending raid offers resume and abandon")
 raid.active_raid={}
 panel.render(raid,"camp","stash_main","loadout_pack")
 check(not panel._read_only and panel._equipment_id=="loadout_equipment","settled raid restores camp equipment")
 panel.free()
 await process_frame
 print("Inventory UI tests: %d checks; %d failures" % [checks,failures])
 quit(1 if failures else 0)
