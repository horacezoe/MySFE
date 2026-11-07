extends RefCounted
## One profile owns every item. Durable candidates are published only after save.
const InventoryService=preload("res://scripts/inventory/inventory_service.gd")
const SaveService=preload("res://scripts/save/save_service.gd")
const LOOT=["loot_medical","loot_battery","loot_chip","loot_parts","loot_alloy","loot_ration","loot_watch","loot_electronics"]
var inventory=InventoryService.new()
var saves=SaveService.new()
var profile: Dictionary={}
var memory_only=false
var blocked=false
var last_error=""
var warning=""
var _command_seq=0

func initialize(in_memory := false,path := "",legacy_path := "") -> Dictionary:
 memory_only=in_memory
 if memory_only:
  profile=new_profile()
  return {"ok":true}
 saves.configure(path,validate)
 var loaded=saves.load_profile()
 if not loaded.ok:
  blocked=true; last_error=str(loaded.reason)
  return loaded
 warning=loaded.get("warning","")
 if not loaded.get("needs_initialization",false):
  profile=loaded.payload
  return loaded
 var legacy=saves.read_legacy(legacy_path) if not legacy_path.is_empty() else {"ok":true,"exists":false}
 if not legacy.ok:
  blocked=true; last_error="legacy_invalid"
  return {"ok":false,"reason":last_error}
 if legacy.get("exists",false):
  var backup=saves.backup_legacy(legacy_path)
  if not backup.ok:
   blocked=true; last_error=backup.reason
   return backup
 var initialized=commit(new_profile(legacy))
 if not initialized.ok:
  blocked=true; last_error=str(initialized.reason)
  return initialized
 # Persist the same starter/migration snapshot in both recovery slots. Starter
 # creation happens once; a failed redundant write leaves the first valid save.
 var redundant=commit(profile)
 if not redundant.ok:
  warning="redundancy_pending: "+str(redundant.reason)
  last_error=""
  initialized.warning=warning
  return initialized
 return redundant

func new_profile(legacy: Dictionary={}) -> Dictionary:
 var state=inventory.new_state()
 var imported=legacy.get("exists",false)==true
 state.merge({"profile_version":1,"currency":int(legacy.get("wealth",0)) if imported else 1500,"wins":int(legacy.get("wins",0)) if imported else 0,"next_raid_seq":1,"active_raid":{},"settled_raids":{},"settings":{"sensitivity":1.0},"migration":{"legacy_imported":imported,"starter_granted":true}})
 _starter(state)
 inventory.add_item(state,"ammo_rifle",60,"stash_main")
 inventory.add_item(state,"medkit_basic",3,"stash_main")
 return state

func _starter(state: Dictionary):
 for pair in [["rifle_basic",24],["helmet_light",20],["vest_light",40]]:
  var extra={"bound":true,"durability":100.0 if pair[0]=="rifle_basic" else float(pair[1])}
  if pair[0]=="rifle_basic": extra.runtime={"ammo":24}
  inventory.add_item(state,pair[0],1,"loadout_equipment",extra)
 inventory.add_item(state,"ammo_rifle",90,"loadout_pack",{"bound":true})
 inventory.add_item(state,"medkit_basic",3,"loadout_pack",{"bound":true})

func validate(state: Dictionary) -> Dictionary:
 var valid=inventory.validate(state)
 if not valid.ok: return valid
 for key in ["currency","wins","next_raid_seq"]:
  var value=state.get(key,-1)
  if not (value is float or value is int) or not is_finite(float(value)) or value<0 or floor(float(value))!=value: return {"ok":false,"reason":"invalid_"+key}
 if not state.get("active_raid") is Dictionary or not state.get("settled_raids") is Dictionary: return {"ok":false,"reason":"invalid_raid_ledger"}
 for cid in ["stash_main","overflow"]:
  if not state.containers.has(cid): return {"ok":false,"reason":"missing_"+cid}
 var active=state.active_raid
 var prefix="loadout" if active.is_empty() else "raid"
 for suffix in ["_pack","_equipment"]:
  if not state.containers.has(prefix+suffix): return {"ok":false,"reason":"missing_"+prefix+suffix}
 if not active.is_empty():
  if not active.get("raid_id") is String or not active.get("search") is Dictionary or not active.get("snapshot") is Dictionary: return {"ok":false,"reason":"invalid_active_raid"}
  if not _valid_snapshot(active.snapshot): return {"ok":false,"reason":"invalid_snapshot"}
  for cid in active.search:
   var search=active.search[cid]
   if not state.containers.has(cid) or not search is Dictionary or not search.get("order") is Array: return {"ok":false,"reason":"invalid_search"}
   var count=search.get("revealed",-1)
   if not (count is float or count is int) or count<0 or count>search.order.size() or floor(count)!=count: return {"ok":false,"reason":"invalid_reveal"}
 return {"ok":true}

func _finite_number(value) -> bool:
 return (value is int or value is float) and is_finite(float(value))

func _nonnegative(value) -> bool:
 return _finite_number(value) and value>=0

func _count(value) -> bool:
 return _nonnegative(value) and value==floor(float(value))

func _vector(value) -> bool:
 if not value is Array or value.size()!=3: return false
 for component in value:
  if not _finite_number(component) or absf(float(component))>100000.0: return false
 return true

func _health(value) -> bool:
 if not value is Dictionary: return false
 for key in ["hp","head_armor","body_armor"]:
  if not _nonnegative(value.get(key)): return false
 return true

func _rng_state(value) -> bool:
 return value is String and value.is_valid_int()

func _weapon(value) -> bool:
 if not value is Dictionary: return false
 for key in ["ammo","reserve","shots_fired"]:
  if not _count(value.get(key)): return false
 for key in ["reload_remaining","cooldown"]:
  if not _nonnegative(value.get(key)): return false
 return _rng_state(value.get("rng_state"))

func _brain(value) -> bool:
 if not value is Dictionary: return false
 if not ["Patrol","Investigate","Alert","Engage","Search","Return","Dead"].has(value.get("state")): return false
 if not _vector(value.get("last_known")) or not _vector(value.get("aim_point")): return false
 if not _rng_state(value.get("rng_state")) or not value.get("has_memory") is bool: return false
 for key in ["state_elapsed","_waypoint_pause","_reaction_remaining","_shot_wait","_search_yaw"]:
  if not _finite_number(value.get(key)): return false
 # Current map guards each use three fixed patrol points. Rejecting a malformed
 # index here prevents array access errors when the restored brain next ticks.
 if not _count(value.get("_route_index")) or value._route_index>=3: return false
 return _count(value.get("_burst_remaining"))

func _valid_snapshot(snapshot: Dictionary) -> bool:
 # A just-created raid has no checkpoint yet; it starts at its deterministic
 # deployment position. A populated checkpoint must be complete and safe to apply.
 if snapshot.is_empty(): return true
 var player=snapshot.get("player")
 if not player is Dictionary: return false
 if not _vector(player.get("position")) or not _vector(player.get("velocity")): return false
 for key in ["yaw","pitch"]:
  if not _finite_number(player.get(key)): return false
 for key in ["third_person","crouching"]:
  if not player.get(key) is bool: return false
 if not _health(player.get("health")) or not _weapon(player.get("weapon")) or not _nonnegative(player.get("healing_remaining")): return false
 for key in ["remaining","extract_time","deployment_grace"]:
  if not _nonnegative(snapshot.get(key)): return false
 if not _count(snapshot.get("kills")): return false
 var enemies=snapshot.get("enemies")
 # This content version has exactly nine guards; partial arrays would silently
 # resurrect omitted guards on resume instead of restoring the saved raid.
 if not enemies is Array or enemies.size()!=9: return false
 for enemy in enemies:
  if not enemy is Dictionary or not _vector(enemy.get("position")) or not _finite_number(enemy.get("rotation_y")): return false
  if not _health(enemy.get("health")) or not _weapon(enemy.get("weapon")) or not _brain(enemy.get("brain")): return false
 return true

func commit(candidate: Dictionary) -> Dictionary:
 if blocked: return {"ok":false,"reason":last_error}
 var valid=validate(candidate)
 if not valid.ok: last_error=valid.reason; return valid
 var result={"ok":true} if memory_only else saves.commit_snapshot(candidate,saves.generation)
 if result.ok:
  profile=candidate.duplicate(true)
  last_error=""
 else: last_error=str(result.reason)
 return result

func command_id() -> String:
 _command_seq+=1
 return "%s-%s-%s" % [OS.get_process_id(),Time.get_ticks_usec(),_command_seq]

func equipment(state: Dictionary,slot: String,raid := true) -> Dictionary:
 var cid="raid_equipment" if raid else "loadout_equipment"
 for item in inventory.contents(state,cid):
  if item.placement.get("slot")==slot: return state.items[item.instance_id]
 return {}

func begin_raid(seed_value: int) -> Dictionary:
 if blocked: return {"ok":false,"reason":last_error}
 if not profile.active_raid.is_empty(): return {"ok":false,"reason":"active_raid_exists"}
 if equipment(profile,"weapon",false).is_empty(): return {"ok":false,"reason":"weapon_required"}
 var candidate=profile.duplicate(true)
 candidate.containers.raid_pack=candidate.containers.loadout_pack
 candidate.containers.raid_equipment=candidate.containers.loadout_equipment
 candidate.containers.erase("loadout_pack"); candidate.containers.erase("loadout_equipment")
 var raid_id="raid_%08d" % int(candidate.next_raid_seq)
 candidate.next_raid_seq=int(candidate.next_raid_seq)+1
 candidate.active_raid={"raid_id":raid_id,"seed":seed_value,"search":{},"snapshot":{}}
 var loot_rng=RandomNumberGenerator.new(); loot_rng.seed=seed_value
 for index in range(15):
  var cid="loot_%02d" % index
  candidate.containers[cid]=inventory.make_grid(6,5)
  for n in range(loot_rng.randi_range(2,4)):
   inventory.add_item(candidate,LOOT[loot_rng.randi_range(0,LOOT.size()-1)],1,cid)
  var order=[]
  for placement in candidate.containers[cid].placements: order.append(placement.item_id)
  candidate.active_raid.search[cid]={"order":order,"revealed":0,"elapsed":0.0,"opened":false}
 return commit(candidate)

func revealed_ids(cid: String,state: Dictionary={}) -> Array:
 var source=profile if state.is_empty() else state
 var search=source.get("active_raid",{}).get("search",{}).get(cid,{})
 return search.get("order",[]).slice(0,int(search.get("revealed",0)))

func execute(intent: Dictionary,base: Dictionary={}) -> Dictionary:
 var source=profile if base.is_empty() else base
 var command=intent.duplicate(true)
 var from=String(command.get("from","")); var to=String(command.get("to",""))
 if not source.containers.has(from) or not source.containers.has(to): return {"ok":false,"reason":"invalid_container"}
 var in_raid=not source.active_raid.is_empty()
 # Weapons/armor stay equipped in combat; preparation is done at camp.
 if in_raid and (from=="raid_equipment" or to=="raid_equipment"): return {"ok":false,"reason":"equipment_locked_in_raid"}
 if in_raid:
  var allowed=(from=="raid_pack" and to=="raid_pack") or (source.active_raid.search.has(from) and to=="raid_pack")
  if not allowed: return {"ok":false,"reason":"invalid_transfer_context"}
 else:
  var allowed=["stash_main","overflow","loadout_pack","loadout_equipment"]
  if not allowed.has(from) or not allowed.has(to): return {"ok":false,"reason":"invalid_transfer_context"}
 if from.begins_with("loot_"):
  var revealed=revealed_ids(from,source)
  # Keep the originally selected IDs on retries, even if more items have since
  # been revealed. Never let a supplied selection bypass search visibility.
  if command.has("item_ids"):
   if not command.item_ids is Array: return {"ok":false,"reason":"invalid_selection"}
   for id in command.item_ids:
    if not revealed.has(id): return {"ok":false,"reason":"not_revealed"}
  else: command.item_ids=revealed
  if command.get("action")!="take_all" and not revealed.has(command.get("item_id")): return {"ok":false,"reason":"not_revealed"}
 if not command.has("command_id"): command.command_id=command_id()
 if not command.has("source_revision"): command.source_revision=source.containers[from].revision
 if not command.has("target_revision"): command.target_revision=source.containers[to].revision
 var result=inventory.preview_take_all(source,command) if command.get("action")=="take_all" else inventory.preview_transfer(source,command)
 if not result.ok: return result
 var saved=commit(result.candidate)
 if not saved.ok: return saved
 result.erase("candidate")
 return result

func sort_container(cid: String,base: Dictionary={}) -> Dictionary:
 var source=profile if base.is_empty() else base
 if cid.begins_with("loot_"): return {"ok":false,"reason":"search_order_fixed"}
 if not source.active_raid.is_empty() and cid!="raid_pack": return {"ok":false,"reason":"active_raid_exists"}
 var result=inventory.preview_sort(source,cid,command_id())
 return commit(result.candidate) if result.ok else result

func _remove_container(state: Dictionary,cid: String):
 if not state.containers.has(cid): return
 for placement in state.containers[cid].placements: state.items.erase(placement.item_id)
 state.containers.erase(cid)

func settle(raid_id: String,success: bool,base: Dictionary={}) -> Dictionary:
 var source=profile if base.is_empty() else base
 # Idempotency is checked before active raid identity, including after restart.
 if source.settled_raids.has(raid_id): return {"ok":true,"reason":"already_settled","result":source.settled_raids[raid_id]}
 if source.active_raid.get("raid_id","")!=raid_id: return {"ok":false,"reason":"wrong_raid"}
 var candidate=source.duplicate(true)
 var returned=0
 if success:
  for cid in ["raid_pack","raid_equipment"]:
   for placement in candidate.containers[cid].placements.duplicate(true):
    var item=candidate.items[placement.item_id]
    var command={"command_id":command_id(),"item_id":item.instance_id,"quantity":item.quantity,"from":cid,"to":"stash_main","source_revision":candidate.containers[cid].revision,"target_revision":candidate.containers.stash_main.revision}
    var moved=inventory.preview_transfer(candidate,command)
    if not moved.ok:
     command.to="overflow"; command.target_revision=candidate.containers.overflow.revision
     moved=inventory.preview_transfer(candidate,command)
    if not moved.ok: return moved
    candidate=moved.candidate; returned+=1
  candidate.wins=int(candidate.wins)+1
 # Carry revisions across deployment/settlement. Commands retained by a UI or
 # evicted from the bounded ledger must never match a later raid's containers.
 var pack_revision=int(candidate.containers.raid_pack.revision)+1
 var equipment_revision=int(candidate.containers.raid_equipment.revision)+1
 for cid in candidate.containers.keys():
  if cid.begins_with("raid_") or cid.begins_with("loot_"): _remove_container(candidate,cid)
 candidate.containers.loadout_pack=inventory.make_grid(6,5,25.0)
 candidate.containers.loadout_equipment=inventory.make_slots(["weapon","helmet","vest"])
 candidate.containers.loadout_pack.revision=pack_revision
 candidate.containers.loadout_equipment.revision=equipment_revision
 candidate.active_raid={}
 candidate.settled_raids[raid_id]={"success":success,"returned_stacks":returned}
 var result=commit(candidate)
 result.returned_stacks=returned
 return result

func quick_equip() -> Dictionary:
 if not profile.active_raid.is_empty(): return {"ok":false,"reason":"active_raid_exists"}
 var candidate=profile.duplicate(true)
 # When all rifles were lost, a non-sellable relief kit keeps offline play viable.
 var has_rifle=false
 for item in candidate.items.values():
  if item.definition_id=="rifle_basic": has_rifle=true
 if not has_rifle:
  for cid in ["loadout_equipment","loadout_pack"]:
   for placement in candidate.containers[cid].placements.duplicate(true):
    var moved=_auto_move(candidate,placement.item_id,cid,"stash_main")
    if not moved.ok: moved=_auto_move(candidate,placement.item_id,cid,"overflow")
    if not moved.ok: return moved
    candidate=moved.candidate
  _starter(candidate)
 else:
  for slot in ["weapon","helmet","vest"]:
   if not equipment(candidate,slot,false).is_empty(): continue
   for cid in ["stash_main","overflow"]:
    for item in inventory.contents(candidate,cid):
     if String(item.definition.equipment_slot)==slot:
      var moved=_auto_move(candidate,item.instance_id,cid,"loadout_equipment")
      if moved.ok: candidate=moved.candidate
      break
    if not equipment(candidate,slot,false).is_empty(): break
  for pair in [["ammo_rifle",90],["medkit_basic",3]]:
   for cid in ["stash_main","overflow"]:
    for item in inventory.contents(candidate,cid):
     var needed=int(pair[1])-inventory.quantity(candidate,"loadout_pack",pair[0])
     if needed<=0: break
     if item.definition_id!=pair[0]: continue
     var moved=_auto_move(candidate,item.instance_id,cid,"loadout_pack",mini(needed,int(item.quantity)))
     if moved.ok: candidate=moved.candidate
 return commit(candidate)

func _auto_move(state: Dictionary,id: String,from: String,to: String,amount := -1) -> Dictionary:
 return inventory.preview_transfer(state,{"command_id":command_id(),"item_id":id,"quantity":int(state.items[id].quantity) if amount<0 else amount,"from":from,"to":to,"source_revision":state.containers[from].revision,"target_revision":state.containers[to].revision})

func purchase(id: String) -> Dictionary:
 if not profile.active_raid.is_empty(): return {"ok":false,"reason":"active_raid_exists"}
 var offers={"ammo_rifle":[60,120],"medkit_basic":[3,240],"rifle_basic":[1,600],"helmet_light":[1,250],"vest_light":[1,400]}
 if not offers.has(id): return {"ok":false,"reason":"invalid_offer"}
 var offer=offers[id]
 if profile.currency<offer[1]: return {"ok":false,"reason":"insufficient_currency"}
 var candidate=profile.duplicate(true)
 var extra={}
 if id=="rifle_basic": extra={"runtime":{"ammo":24},"durability":100.0}
 if id=="helmet_light": extra={"durability":20.0}
 if id=="vest_light": extra={"durability":40.0}
 var added=inventory.add_item(candidate,id,offer[0],"stash_main",extra)
 if not added.ok: return added
 candidate.currency=int(candidate.currency)-int(offer[1])
 return commit(candidate)

func sell(id: String,amount: int) -> Dictionary:
 if not profile.active_raid.is_empty(): return {"ok":false,"reason":"active_raid_exists"}
 if not profile.items.has(id) or amount<=0: return {"ok":false,"reason":"missing_item"}
 var item=profile.items[id]
 var cid=inventory.owner_of(profile,id)
 if not ["stash_main","overflow"].has(cid): return {"ok":false,"reason":"sell_from_stash"}
 if item.get("bound",false): return {"ok":false,"reason":"bound_item"}
 if amount>item.quantity: return {"ok":false,"reason":"invalid_quantity"}
 var candidate=profile.duplicate(true)
 var definition=inventory.catalog.get_definition(item.definition_id)
 candidate.currency=int(candidate.currency)+definition.value*amount
 candidate.items[id].quantity=int(item.quantity)-amount
 if candidate.items[id].quantity==0:
  candidate.items.erase(id)
  for p in candidate.containers[cid].placements.duplicate(true):
   if p.item_id==id: candidate.containers[cid].placements.erase(p)
 candidate.containers[cid].revision=int(candidate.containers[cid].revision)+1
 return commit(candidate)
