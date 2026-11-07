extends SceneTree

const InventoryService=preload("res://scripts/inventory/inventory_service.gd")
var inventory=InventoryService.new()
var checks=0
var failures=0
var command_seq=0

func check(condition: bool,label: String):
 checks+=1
 if not condition:
  failures+=1
  push_error("INVENTORY: "+label)

func snapshot(state: Dictionary) -> String:
 return JSON.stringify(state,"",true)

func first_id(state: Dictionary,cid: String,definition_id: String) -> String:
 for item in inventory.contents(state,cid):
  if item.definition_id==definition_id: return item.instance_id
 return ""

func command(state: Dictionary,id: String,from: String,to: String,amount := -1) -> Dictionary:
 command_seq+=1
 return {"command_id":"test_%d" % command_seq,"item_id":id,"quantity":int(state.items[id].quantity) if amount<0 else amount,"from":from,"to":to,"source_revision":int(state.containers[from].revision),"target_revision":int(state.containers[to].revision),"x":-1,"y":-1,"rotated":false,"slot":""}

func reject_unchanged(state: Dictionary,request: Dictionary,reason: String):
 var before=snapshot(state)
 var result=inventory.preview_transfer(state,request)
 check(not result.ok and result.reason==reason,"reject "+reason+": "+str(result))
 check(snapshot(state)==before,"rejected transfer leaves original unchanged")

func _initialize():
 test_definitions_and_initialization()
 test_transfer_stack_and_split()
 test_geometry_and_slots()
 test_weight_and_batch()
 test_validation()
 test_consumption_and_sort()
 test_idempotence_and_eviction()
 print("Inventory tests: %d checks; %d failures" % [checks,failures])
 quit(1 if failures else 0)

func test_definitions_and_initialization():
 var state=inventory.new_state()
 check(inventory.validate(state).ok,"empty state valid")
 check(state.containers.stash_main.width==10 and state.containers.stash_main.height==12,"stash dimensions")
 check(state.containers.loadout_pack.width==6 and state.containers.loadout_pack.height==5 and state.containers.loadout_pack.weight_limit==25.0,"pack dimensions/weight")
 check(inventory.catalog.ids().size()==14,"14 stable item definitions including depot pass")
 check(inventory.catalog.get_definition("rifle_basic").footprint()==Vector2i(2,3),"rifle footprint")
 check(inventory.catalog.get_definition("medkit_basic").max_stack==3 and inventory.catalog.get_definition("ammo_rifle").max_stack==60,"stack limits")
 state.currency=1234; state.settings={"difficulty":"exploration"}; state.active_raid={"search":{"crate":2}}
 var result=inventory.add_item(state,"ammo_rifle",130,"stash_main")
 check(result.ok and state.items.size()==3,"large initialization splits into stacks")
 check(inventory.quantity(state,"stash_main","ammo_rifle")==130,"initial quantity conserved")
 check(state.currency==1234 and state.active_raid.search.crate==2,"profile fields preserved by initialization")
 var before=snapshot(state)
 check(not inventory.add_item(state,"missing_definition",1,"stash_main").ok,"unknown definition rejected")
 check(snapshot(state)==before,"unknown definition does not mutate")
 check(not inventory.add_item(state,"ammo_rifle",1.5,"stash_main").ok and snapshot(state)==before,"fractional initialization rejected unchanged")
 state.containers.tiny=inventory.make_grid(1,1)
 before=snapshot(state)
 check(not inventory.add_item(state,"rifle_basic",1,"tiny").ok and snapshot(state)==before,"failed initialization is atomic")
 check(inventory.validate(JSON.parse_string(before)).ok,"JSON roundtrip valid with integral numeric values")

func test_transfer_stack_and_split():
 var state=inventory.new_state()
 inventory.add_item(state,"ammo_rifle",60,"stash_main")
 inventory.add_item(state,"ammo_rifle",45,"loadout_pack")
 var original=first_id(state,"stash_main","ammo_rifle")
 var target=first_id(state,"loadout_pack","ammo_rifle")
 var request=command(state,original,"stash_main","loadout_pack",20)
 var before=snapshot(state)
 var result=inventory.preview_transfer(state,request)
 check(result.ok,"partial transfer succeeds")
 check(snapshot(state)==before,"successful preview leaves original unchanged")
 if not result.ok: return
 state=result.candidate
 check(state.items[original].quantity==40,"source split decreases")
 check(state.items[target].quantity==60,"destination stack filled first")
 check(inventory.quantity(state,"loadout_pack","ammo_rifle")==65 and state.items.size()==3,"split remainder gets separate identity")
 check(result.item_ids.size()==2 and result.item_ids[1]!=original,"new identity for split")
 check(inventory.validate(state).ok,"split ownership valid")
 var original_revision=state.containers.loadout_pack.revision
 var split_id=result.item_ids[1]
 var split_request=command(state,split_id,"loadout_pack","loadout_pack",2)
 split_request.x=5; split_request.y=4
 result=inventory.preview_transfer(state,split_request)
 check(result.ok,"same-container split succeeds")
 if result.ok:
  state=result.candidate
  check(state.containers.loadout_pack.revision==original_revision+1,"same-container revision increment once")
  check(state.items[split_id].quantity==3 and state.items[result.item_ids[0]].quantity==2,"same-container split conserved")
 var bound_state=inventory.new_state()
 inventory.add_item(bound_state,"medkit_basic",2,"stash_main",{"bound":true})
 inventory.add_item(bound_state,"medkit_basic",1,"loadout_pack")
 result=inventory.preview_transfer(bound_state,command(bound_state,first_id(bound_state,"stash_main","medkit_basic"),"stash_main","loadout_pack"))
 check(result.ok and inventory.contents(result.candidate,"loadout_pack").size()==2,"bound items never merge into saleable stack")
 var merge_state=inventory.new_state()
 inventory.add_item(merge_state,"ammo_rifle",10,"stash_main")
 inventory.add_item(merge_state,"ammo_rifle",20,"loadout_pack")
 var merge_id=first_id(merge_state,"stash_main","ammo_rifle")
 result=inventory.preview_transfer(merge_state,command(merge_state,merge_id,"stash_main","loadout_pack"))
 check(result.ok and not result.candidate.items.has(merge_id) and result.candidate.items.size()==1,"full merge removes empty source identity")

func test_geometry_and_slots():
 var state=inventory.new_state()
 inventory.add_item(state,"rifle_basic",1,"stash_main",{"runtime":{"ammo":17,"cooldown":0.2,"reload_remaining":0.0}})
 inventory.add_item(state,"helmet_light",1,"loadout_pack",{"durability":55})
 var rifle=first_id(state,"stash_main","rifle_basic")
 var request=command(state,rifle,"stash_main","loadout_pack")
 request.x=0; request.y=0
 reject_unchanged(state,request,"no_space")
 request=command(state,rifle,"stash_main","loadout_pack"); request.x=5; request.y=4
 reject_unchanged(state,request,"no_space")
 state.containers.narrow=inventory.make_grid(3,2)
 request=command(state,rifle,"stash_main","narrow"); request.x=0; request.y=0
 reject_unchanged(state,request,"no_space")
 request=command(state,rifle,"stash_main","narrow"); request.x=0; request.y=0; request.rotated=true
 var result=inventory.preview_transfer(state,request)
 check(result.ok and result.candidate.containers.narrow.placements[0].rotated,"explicit rotation fits narrow grid")
 if result.ok:
  state=result.candidate
  check(state.items[rifle].runtime.ammo==17 and state.items[rifle].runtime.cooldown==0.2,"weapon runtime survives transfer")
  request=command(state,rifle,"narrow","loadout_equipment"); request.slot="helmet"
  reject_unchanged(state,request,"wrong_slot")
  request=command(state,rifle,"narrow","loadout_equipment"); request.slot="weapon"
  result=inventory.preview_transfer(state,request)
  check(result.ok and inventory.owner_of(result.candidate,rifle)=="loadout_equipment","weapon equipment slot")
  if result.ok: state=result.candidate
 inventory.add_item(state,"rifle_basic",1,"stash_main")
 var second=first_id(state,"stash_main","rifle_basic")
 reject_unchanged(state,command(state,second,"stash_main","loadout_equipment"),"slot_occupied")
 request=command(state,second,"stash_main","loadout_pack"); request.x=0.5
 reject_unchanged(state,request,"invalid_position")
 request=command(state,second,"stash_main","loadout_pack"); request.quantity=0
 reject_unchanged(state,request,"invalid_quantity")
 request=command(state,second,"stash_main","loadout_pack"); request.quantity=0.5
 reject_unchanged(state,request,"invalid_quantity")
 request=command(state,second,"stash_main","loadout_pack"); request.slot=[]
 reject_unchanged(state,request,"wrong_slot")

func test_weight_and_batch():
 var state=inventory.new_state()
 state.containers.light=inventory.make_grid(6,5,0.6)
 inventory.add_item(state,"ammo_rifle",60,"stash_main")
 var ammo=first_id(state,"stash_main","ammo_rifle")
 reject_unchanged(state,command(state,ammo,"stash_main","light"),"overweight")
 var request=command(state,ammo,"stash_main","light"); request.erase("item_id"); request.erase("quantity")
 var result=inventory.preview_take_all(state,request)
 check(result.ok and result.quantity==50,"batch partly fills exact weight limit")
 if result.ok:
  check(inventory.quantity(result.candidate,"light","ammo_rifle")==50 and inventory.quantity(result.candidate,"stash_main","ammo_rifle")==10,"weight-limited remainder retained")
 state=inventory.new_state()
 state.containers.small=inventory.make_grid(1,1)
 inventory.add_item(state,"ammo_rifle",55,"small")
 inventory.add_item(state,"ammo_rifle",20,"stash_main")
 inventory.add_item(state,"loot_chip",1,"stash_main")
 var ammo_id=first_id(state,"stash_main","ammo_rifle")
 request=command(state,ammo_id,"stash_main","small"); request.erase("item_id"); request.erase("quantity")
 var before=snapshot(state)
 result=inventory.preview_take_all(state,request)
 check(result.ok and result.quantity==5,"full-grid batch still fills existing stack")
 check(snapshot(state)==before,"take-all preview unchanged source")
 if result.ok:
  check(inventory.quantity(result.candidate,"stash_main","ammo_rifle")==15 and inventory.quantity(result.candidate,"stash_main","loot_chip")==1,"full bag retains untransferred items")
  check(result.remaining_item_ids.size()==2,"batch reports remainder identities")
  check(result.candidate.containers.stash_main.revision==state.containers.stash_main.revision+1,"batch single source revision")
 state=inventory.new_state()
 inventory.add_item(state,"loot_chip",1,"stash_main")
 inventory.add_item(state,"loot_watch",1,"stash_main")
 var revealed=first_id(state,"stash_main","loot_chip")
 request=command(state,revealed,"stash_main","loadout_pack"); request.item_ids=[revealed]
 result=inventory.preview_take_all(state,request)
 check(result.ok and inventory.quantity(result.candidate,"stash_main","loot_watch")==1,"take-all only revealed selection")
 var repeat=inventory.preview_take_all(result.candidate,request)
 check(repeat.ok and repeat.reason=="already_applied" and snapshot(repeat.candidate)==snapshot(result.candidate),"take-all repeated request idempotent")

func test_validation():
 var state=inventory.new_state()
 inventory.add_item(state,"loot_chip",1,"stash_main")
 inventory.add_item(state,"loot_watch",1,"stash_main")
 var ids=state.items.keys()
 var damaged=state.duplicate(true)
 damaged.containers.loadout_pack.placements.append(damaged.containers.stash_main.placements[0].duplicate(true))
 check(inventory.validate(damaged).reason=="duplicate_owner","duplicate ownership rejected")
 damaged=state.duplicate(true); damaged.containers.stash_main.placements.pop_back()
 check(inventory.validate(damaged).reason=="orphan_item","orphan rejected")
 damaged=state.duplicate(true); damaged.items.erase(ids[0])
 check(inventory.validate(damaged).reason=="missing_item","dangling placement rejected")
 damaged=state.duplicate(true); damaged.items[ids[0]].definition_id="future_item"
 check(inventory.validate(damaged).reason=="unknown_definition" and damaged.items.has(ids[0]),"unknown definition rejected without deletion")
 damaged=state.duplicate(true); damaged.items[ids[0]].quantity=1.5
 check(inventory.validate(damaged).reason=="invalid_quantity","fractional quantity rejected")
 damaged=state.duplicate(true); damaged.items[ids[0]].quantity=0
 check(inventory.validate(damaged).reason=="invalid_quantity","zero quantity rejected")
 damaged=state.duplicate(true); damaged.containers.stash_main.placements[0].x=100
 check(inventory.validate(damaged).reason=="out_of_bounds","bounds rejected")
 damaged=state.duplicate(true); damaged.containers.stash_main.placements[1].x=damaged.containers.stash_main.placements[0].x
 check(inventory.validate(damaged).reason=="overlap","overlap rejected")
 damaged=state.duplicate(true); damaged.containers.stash_main.weight_limit=0.001
 check(inventory.validate(damaged).reason=="overweight","overweight state rejected")
 damaged=state.duplicate(true); damaged.items[ids[0]].durability=-1
 check(inventory.validate(damaged).reason=="invalid_durability","negative durability rejected")

func test_consumption_and_sort():
 var state=inventory.new_state()
 inventory.add_item(state,"ammo_rifle",130,"loadout_pack")
 inventory.add_item(state,"medkit_basic",3,"loadout_pack")
 state.settings={"search_pause":true}
 var before=snapshot(state)
 var result=inventory.consume(state,"loadout_pack","ammo_rifle",75)
 check(result.ok and inventory.quantity(result.candidate,"loadout_pack","ammo_rifle")==55,"consume crosses stacks")
 check(snapshot(state)==before,"consume preview immutable")
 if result.ok:
  state=result.candidate
  check(inventory.validate(state).ok,"consume removes empty identities cleanly")
 before=snapshot(state)
 result=inventory.consume(state,"loadout_pack","ammo_rifle",100)
 check(not result.ok and snapshot(state)==before,"insufficient consume unchanged")
 result=inventory.consume(state,"loadout_pack","ammo_rifle",1.5)
 check(not result.ok and snapshot(state)==before,"fractional consume rejected unchanged")
 inventory.add_item(state,"rifle_basic",1,"loadout_pack")
 inventory.add_item(state,"loot_parts",1,"loadout_pack")
 var item_snapshot=snapshot(state.items)
 result=inventory.preview_sort(state,"loadout_pack","sort_once",state.containers.loadout_pack.revision)
 check(result.ok and inventory.validate(result.candidate).ok,"sort valid")
 if result.ok:
  check(snapshot(result.candidate.items)==item_snapshot,"sort preserves identities/quantity/metadata")
  check(result.candidate.settings.search_pause,"sort retains unrelated profile settings")
  var repeated=inventory.preview_sort(result.candidate,"loadout_pack","sort_once",state.containers.loadout_pack.revision)
  check(repeated.ok and repeated.reason=="already_applied","sort idempotent")

func test_idempotence_and_eviction():
 var state=inventory.new_state()
 inventory.add_item(state,"loot_chip",1,"stash_main")
 var id=first_id(state,"stash_main","loot_chip")
 var request=command(state,id,"stash_main","loadout_pack")
 var stale=request.duplicate(true); stale.source_revision-=1
 reject_unchanged(state,stale,"stale_revision")
 var first_request=request.duplicate(true)
 var result=inventory.preview_transfer(state,request)
 check(result.ok,"initial command committed candidate")
 if not result.ok: return
 state=result.candidate
 var before=snapshot(state)
 result=inventory.preview_transfer(state,request)
 check(result.ok and result.reason=="already_applied" and snapshot(result.candidate)==before,"repeat command neither duplicates nor increments revision")
 result=inventory.preview_transfer(JSON.parse_string(before),request)
 check(result.ok and result.reason=="already_applied","idempotence persists through JSON reload")
 result=inventory.preview_transfer(JSON.parse_string(before),JSON.parse_string(snapshot(request)))
 check(result.ok and result.reason=="already_applied","persisted command numeric types do not change identity")
 request.quantity=2
 reject_unchanged(state,request,"command_conflict")
 for index in range(256):
  var from=inventory.owner_of(state,id)
  var to="stash_main" if from=="loadout_pack" else "loadout_pack"
  result=inventory.preview_transfer(state,command(state,id,from,to))
  if not result.ok:
   check(false,"cache stress transfer %d: %s" % [index,str(result)])
   return
  state=result.candidate
 check(state.processed_commands.order.size()==256 and state.processed_commands.results.size()==256,"command ledger bounded to 256")
 check(not state.processed_commands.results.has(first_request.command_id),"old command evicted")
 reject_unchanged(state,first_request,"stale_revision")
 check(state.items.size()==1 and inventory.validate(state).ok,"long repeat sequence preserves one identity")
