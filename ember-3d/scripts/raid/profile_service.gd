extends RefCounted
## One profile owns every item. Durable candidates are published only after save.
const InventoryService=preload("res://scripts/inventory/inventory_service.gd")
const SaveService=preload("res://scripts/save/save_service.gd")
const MissionCatalog=preload("res://scripts/raid/mission_catalog.gd")
const RaidRules=preload("res://scripts/raid/raid_rules.gd")
const CorpseLoot=preload("res://scripts/raid/corpse_loot.gd")
const LOOT=["loot_medical","loot_battery","loot_chip","loot_parts","loot_alloy","loot_ration","loot_watch","loot_electronics"]
var inventory=InventoryService.new()
var saves=SaveService.new()
var missions=MissionCatalog.new()
var rules=RaidRules.new()
var corpse_loot=CorpseLoot.new()
var profile: Dictionary={}
var memory_only=false
var blocked=false
var last_error=""
var warning=""
var _command_seq=0

func initialize(in_memory := false,path := "",legacy_path := "") -> Dictionary:
 blocked=false; last_error=""; warning=""; profile={}
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
  if int(loaded.payload.get("profile_version",1))==1:
   # Preserve the original checkpoint/search byte-for-byte during schema
   # migration. Corpse containers are added at the first live checkpoint.
   var upgraded=_commit(_upgrade_profile(loaded.payload),false)
   if not upgraded.ok:
    blocked=true; last_error=str(upgraded.reason)
    return upgraded
   warning="phase3_upgraded"
   return {"ok":true,"warning":warning,"payload":profile}
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
 state.merge({"profile_version":2,"currency":int(legacy.get("wealth",0)) if imported else 1500,"wins":int(legacy.get("wins",0)) if imported else 0,"next_raid_seq":1,"active_raid":{},"settled_raids":{},"settings":{"sensitivity":1.0,"difficulty":"standard" if imported else "comfort"},"migration":{"legacy_imported":imported,"starter_granted":true},"missions":missions.new_state(),"mission_version":MissionCatalog.CONTENT_VERSION})
 _starter(state)
 inventory.add_item(state,"ammo_rifle",60,"stash_main")
 inventory.add_item(state,"medkit_basic",3,"stash_main")
 return state

func _upgrade_profile(old: Dictionary) -> Dictionary:
 var candidate=old.duplicate(true)
 candidate.profile_version=2
 candidate.missions=missions.new_state()
 candidate.mission_version=MissionCatalog.CONTENT_VERSION
 if not candidate.get("settings") is Dictionary: candidate.settings={"sensitivity":1.0}
 candidate.settings.difficulty="standard"
 if not candidate.get("migration") is Dictionary: candidate.migration={}
 candidate.migration.phase3_upgraded=true
 if not candidate.active_raid.is_empty():
  candidate.active_raid.map_id="legacy_v3"
  candidate.active_raid.rule_id="standard"
  candidate.active_raid.rule_version=RaidRules.VERSION
  candidate.active_raid.events={"visits":[],"kills":[]}
  candidate.active_raid.mission_ids=[]
 return candidate

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
 if not _count(state.get("profile_version")) or int(state.profile_version) not in [1,2]: return {"ok":false,"reason":"unsupported_profile_version"}
 for key in ["currency","wins","next_raid_seq"]:
  var value=state.get(key,-1)
  if not (value is float or value is int) or not is_finite(float(value)) or value<0 or floor(float(value))!=value: return {"ok":false,"reason":"invalid_"+key}
 if not state.get("active_raid") is Dictionary or not state.get("settled_raids") is Dictionary: return {"ok":false,"reason":"invalid_raid_ledger"}
 if state.profile_version==2:
  var campaign_validation=_validate_campaign(state)
  if not campaign_validation.ok: return campaign_validation
 for cid in ["stash_main","overflow"]:
  if not state.containers.has(cid): return {"ok":false,"reason":"missing_"+cid}
 var active=state.active_raid
 var prefix="loadout" if active.is_empty() else "raid"
 for suffix in ["_pack","_equipment"]:
  if not state.containers.has(prefix+suffix): return {"ok":false,"reason":"missing_"+prefix+suffix}
 if not active.is_empty():
  if not active.get("raid_id") is String or not active.get("search") is Dictionary or not active.get("snapshot") is Dictionary: return {"ok":false,"reason":"invalid_active_raid"}
  if state.profile_version==2 and active.map_id=="depot_v1" and not active.snapshot.is_empty() and not active.snapshot.has("extraction"): return {"ok":false,"reason":"invalid_snapshot"}
  if not _valid_snapshot(active.snapshot): return {"ok":false,"reason":"invalid_snapshot"}
  for cid in active.search:
   var search=active.search[cid]
   if not state.containers.has(cid) or not search is Dictionary or not search.get("order") is Array: return {"ok":false,"reason":"invalid_search"}
   var count=search.get("revealed",-1)
   if not (count is float or count is int) or count<0 or count>search.order.size() or floor(count)!=count: return {"ok":false,"reason":"invalid_reveal"}
 return corpse_loot.validate(state)

func _validate_campaign(state: Dictionary) -> Dictionary:
 if not state.get("settings") is Dictionary or rules.get_rule(str(state.settings.get("difficulty",""))).is_empty(): return {"ok":false,"reason":"invalid_difficulty"}
 if state.get("mission_version")!=MissionCatalog.CONTENT_VERSION or not state.get("missions") is Dictionary: return {"ok":false,"reason":"unsupported_mission_version"}
 if state.missions.size()!=missions.definitions().size(): return {"ok":false,"reason":"invalid_missions"}
 for definition in missions.definitions():
  var mission=state.missions.get(definition.id)
  if not mission is Dictionary or not ["available","active","ready","claimed"].has(mission.get("status")): return {"ok":false,"reason":"invalid_mission_state"}
  if not _count(mission.get("progress")) or mission.progress>definition.required: return {"ok":false,"reason":"invalid_mission_progress"}
  if mission.status=="available" and mission.progress!=0: return {"ok":false,"reason":"invalid_mission_progress"}
  if mission.status in ["ready","claimed"] and mission.progress!=definition.required: return {"ok":false,"reason":"invalid_mission_progress"}
 var active=state.active_raid
 if active.is_empty(): return {"ok":true}
 if not ["legacy_v3","depot_v1"].has(active.get("map_id")): return {"ok":false,"reason":"unknown_map"}
 if active.get("rule_version")!=RaidRules.VERSION or rules.get_rule(str(active.get("rule_id",""))).is_empty(): return {"ok":false,"reason":"unknown_rules"}
 if not active.get("mission_ids") is Array or not active.get("events") is Dictionary: return {"ok":false,"reason":"invalid_raid_events"}
 var mission_ids={}
 for id in active.mission_ids:
  if not id is String or missions.get_definition(id).is_empty() or mission_ids.has(id) or state.missions[id].status not in ["active","ready"]: return {"ok":false,"reason":"invalid_raid_mission"}
  mission_ids[id]=true
 for kind in ["visits","kills"]:
  var events=active.events.get(kind)
  if not events is Array: return {"ok":false,"reason":"invalid_raid_events"}
  var seen={}
  for target in events:
   if not target is String or seen.has(target): return {"ok":false,"reason":"invalid_raid_events"}
   if kind=="visits" and target!="signal_station": return {"ok":false,"reason":"unknown_event_target"}
   if kind=="kills" and not ["guard_00","guard_01","guard_02","guard_03","guard_04","guard_05","guard_06","guard_07","guard_08"].has(target): return {"ok":false,"reason":"unknown_event_target"}
   seen[target]=true
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
 if snapshot.has("extraction"):
  var extraction=snapshot.extraction
  if not extraction is Dictionary or not ["","south_gate","service_gate"].has(extraction.get("exit_id")) or not _nonnegative(extraction.get("remaining")): return false
  if extraction.exit_id=="" and extraction.remaining!=0: return false
 var enemies=snapshot.get("enemies")
 # This content version has exactly nine guards; partial arrays would silently
 # resurrect omitted guards on resume instead of restoring the saved raid.
 if not enemies is Array or enemies.size()!=9: return false
 for enemy in enemies:
  if not enemy is Dictionary or not _vector(enemy.get("position")) or not _finite_number(enemy.get("rotation_y")): return false
  if not _health(enemy.get("health")) or not _weapon(enemy.get("weapon")) or not _brain(enemy.get("brain")): return false
 return true

func commit(candidate: Dictionary) -> Dictionary:
 return _commit(candidate,true)

func _commit(candidate: Dictionary,prepare_corpses: bool) -> Dictionary:
 if blocked: return {"ok":false,"reason":last_error}
 var prepared=candidate.duplicate(true)
 if prepared.get("profile_version")!=2: return {"ok":false,"reason":"upgrade_required"}
 if prepare_corpses:
  var generated=ensure_corpse_loot(prepared)
  if not generated.ok: last_error=generated.reason; return generated
 _refresh_collect_missions(prepared)
 var valid=validate(prepared)
 if not valid.ok: last_error=valid.reason; return valid
 var result={"ok":true} if memory_only else saves.commit_snapshot(prepared,saves.generation)
 if result.ok:
  profile=prepared
  last_error=""
 else: last_error=str(result.reason)
 return result

func ensure_corpse_loot(candidate: Dictionary) -> Dictionary:
 # Preserve the same durable snapshot, reveal state and physical item identity.
 # Only mutate this supplied candidate; commit() publishes after disk succeeds.
 if not candidate.get("active_raid") is Dictionary or not candidate.get("containers") is Dictionary or not candidate.get("items") is Dictionary: return {"ok":false,"reason":"invalid_state","changed":false}
 var active: Dictionary=candidate.active_raid
 if not active.is_empty():
  if not active.get("search") is Dictionary or not active.get("snapshot") is Dictionary: return {"ok":false,"reason":"invalid_active_raid","changed":false}
  if not _valid_snapshot(active.snapshot): return {"ok":false,"reason":"invalid_snapshot","changed":false}
 return corpse_loot.ensure(candidate,inventory)

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
 var accepted=[]
 for id in candidate.missions:
  if candidate.missions[id].status in ["active","ready"]: accepted.append(id)
 candidate.active_raid={"raid_id":raid_id,"seed":seed_value,"search":{},"snapshot":{},"map_id":"depot_v1","rule_id":candidate.settings.difficulty,"rule_version":RaidRules.VERSION,"mission_ids":accepted,"events":{"visits":[],"kills":[]}}
 var loot_rng=RandomNumberGenerator.new(); loot_rng.seed=seed_value
 for index in range(15):
  var cid="loot_%02d" % index
  candidate.containers[cid]=inventory.make_grid(6,5)
  var pool=["loot_chip","loot_watch","loot_alloy"]
  if index in [0,1,5,10]: pool=["loot_medical","loot_ration","loot_parts"]
  elif index in [2,3,4,7,11,12]: pool=["loot_battery","loot_electronics","loot_parts"]
  for n in range(loot_rng.randi_range(2,4)):
   var definition_id="loot_medical" if n==0 and index in [0,5] else pool[loot_rng.randi_range(0,pool.size()-1)]
   var added=inventory.add_item(candidate,definition_id,1,cid)
   if not added.ok: return added
  if index==6:
   var added=inventory.add_item(candidate,"depot_pass",1,cid)
   if not added.ok: return added
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
 var rule=rules.get_rule(candidate.active_raid.get("rule_id","standard"))
 var retained_equipment=not success and rule.get("death_keep_equipment",false)
 var returned_containers=["raid_pack","raid_equipment"] if success else (["raid_equipment"] if retained_equipment else [])
 if not returned_containers.is_empty():
  for cid in returned_containers:
   for placement in candidate.containers[cid].placements.duplicate(true):
    var item=candidate.items[placement.item_id]
    var command={"command_id":command_id(),"item_id":item.instance_id,"quantity":item.quantity,"from":cid,"to":"stash_main","source_revision":candidate.containers[cid].revision,"target_revision":candidate.containers.stash_main.revision}
    var moved=inventory.preview_transfer(candidate,command)
    if not moved.ok:
     command.to="overflow"; command.target_revision=candidate.containers.overflow.revision
     moved=inventory.preview_transfer(candidate,command)
    if not moved.ok: return moved
    candidate=moved.candidate; returned+=1
 if success:
  candidate.wins=int(candidate.wins)+1
  _advance_settlement_missions(candidate)
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
 candidate.settled_raids[raid_id]={"success":success,"returned_stacks":returned,"kept_equipment":retained_equipment}
 var result=commit(candidate)
 result.returned_stacks=returned
 result.kept_equipment=retained_equipment
 return result

func set_difficulty(id: String) -> Dictionary:
 if blocked: return {"ok":false,"reason":last_error}
 if not profile.active_raid.is_empty(): return {"ok":false,"reason":"active_raid_exists"}
 if rules.get_rule(id).is_empty(): return {"ok":false,"reason":"invalid_difficulty"}
 if profile.settings.difficulty==id: return {"ok":true,"reason":"already_selected"}
 var candidate=profile.duplicate(true)
 candidate.settings.difficulty=id
 return commit(candidate)

func accept_mission(id: String) -> Dictionary:
 if blocked: return {"ok":false,"reason":last_error}
 if not profile.active_raid.is_empty(): return {"ok":false,"reason":"active_raid_exists"}
 if missions.get_definition(id).is_empty(): return {"ok":false,"reason":"unknown_mission"}
 if profile.missions[id].status!="available": return {"ok":true,"reason":"already_accepted"}
 var candidate=profile.duplicate(true)
 candidate.missions[id].status="active"
 return commit(candidate)

func _eligible_quantity(state: Dictionary,definition_id: String) -> int:
 var total=0
 for cid in ["stash_main","overflow"]:
  for item in inventory.contents(state,cid):
   if item.definition_id==definition_id and not item.get("bound",false): total+=int(item.quantity)
 return total

func _refresh_collect_missions(state: Dictionary):
 if not state.get("missions") is Dictionary: return
 if not state.get("containers") is Dictionary or not state.get("items") is Dictionary: return
 for definition in missions.definitions():
  var mission=state.missions.get(definition.id)
  if not mission is Dictionary or definition.kind!="collect" or mission.get("status") not in ["active","ready"]: continue
  # Do not let malformed item structures crash validation; validate() will reject.
  if not inventory.validate(state).ok: return
  var count=mini(definition.required,_eligible_quantity(state,definition.target))
  mission.progress=count
  mission.status="ready" if count>=definition.required else "active"

func record_event(state: Dictionary,kind: String,target: String) -> Dictionary:
 if not state.get("active_raid") is Dictionary or state.active_raid.is_empty(): return {"ok":false,"reason":"no_active_raid","changed":false}
 if kind not in ["visit","kill"]: return {"ok":false,"reason":"invalid_event_kind","changed":false}
 var active=state.active_raid
 if not active.get("events") is Dictionary: return {"ok":false,"reason":"invalid_raid_events","changed":false}
 var eligible=false
 for id in active.get("mission_ids",[]):
  var definition=missions.get_definition(id)
  if definition.get("kind")==kind and definition.get("target")==target and state.missions[id].status=="active": eligible=true
 if not eligible: return {"ok":true,"reason":"event_not_required","changed":false}
 var key="visits" if kind=="visit" else "kills"
 if active.events[key].has(target): return {"ok":true,"reason":"already_recorded","changed":false}
 active.events[key].append(target)
 return {"ok":true,"reason":"recorded","changed":true}

func _advance_settlement_missions(state: Dictionary):
 var active=state.active_raid
 for id in active.mission_ids:
  var definition=missions.get_definition(id)
  var mission=state.missions[id]
  if mission.status!="active" or definition.kind=="collect": continue
  var key="visits" if definition.kind=="visit" else "kills"
  if active.events[key].has(definition.target):
   mission.progress=definition.required
   mission.status="ready"

func claim_mission(id: String) -> Dictionary:
 if blocked: return {"ok":false,"reason":last_error}
 if not profile.active_raid.is_empty(): return {"ok":false,"reason":"active_raid_exists"}
 var definition=missions.get_definition(id)
 if definition.is_empty(): return {"ok":false,"reason":"unknown_mission"}
 var mission=profile.missions[id]
 if mission.status=="claimed": return {"ok":true,"reason":"already_claimed"}
 if mission.status not in ["active","ready"]: return {"ok":false,"reason":"mission_not_accepted"}
 var candidate=profile.duplicate(true)
 if definition.kind=="collect":
  if _eligible_quantity(candidate,definition.target)<definition.required: return {"ok":false,"reason":"mission_items_missing"}
  var remaining=int(definition.required)
  for cid in ["stash_main","overflow"]:
   var consumed=false
   for placement in candidate.containers[cid].placements.duplicate(true):
    if remaining<=0: break
    var item=candidate.items[placement.item_id]
    if item.definition_id!=definition.target or item.get("bound",false): continue
    var used=mini(remaining,int(item.quantity))
    item.quantity=int(item.quantity)-used; remaining-=used; consumed=true
    if item.quantity==0:
     candidate.items.erase(placement.item_id)
     candidate.containers[cid].placements.erase(placement)
   if consumed: candidate.containers[cid].revision=int(candidate.containers[cid].revision)+1
 else:
  if mission.status!="ready" or int(mission.progress)<definition.required: return {"ok":false,"reason":"mission_not_ready"}
 candidate.missions[id]={"status":"claimed","progress":definition.required}
 candidate.currency=int(candidate.currency)+int(definition.reward_currency)
 return commit(candidate)

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
