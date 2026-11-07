extends RefCounted
## Pure candidate transactions. The caller saves candidate successfully BEFORE
## publishing it. Extra profile fields and instance metadata are preserved.

const ItemCatalog=preload("res://scripts/inventory/item_catalog.gd")
const COMMAND_LIMIT=256
var catalog=ItemCatalog.new()

func new_state() -> Dictionary:
 return {"items":{},"containers":{
  "stash_main":make_grid(10,12),
  "loadout_pack":make_grid(6,5,25.0),
  "loadout_equipment":make_slots(["weapon","helmet","vest"]),
  "overflow":make_list(),
 },"next_item_seq":1,"processed_commands":{"order":[],"results":{}}}

func make_grid(width: int,height: int,weight_limit := 0.0) -> Dictionary:
 return {"kind":"grid","width":width,"height":height,"weight_limit":weight_limit,"revision":0,"placements":[]}

func make_slots(slots: Array) -> Dictionary:
 return {"kind":"slots","slots":slots.duplicate(),"revision":0,"placements":[]}

func make_list() -> Dictionary:
 return {"kind":"list","revision":0,"placements":[]}

func _whole(value,minimum := 0) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and value>=minimum

func _text(value) -> bool:
 # GDScript's dictionary dot syntax creates StringName keys; JSON uses String.
 return value is String or value is StringName

func _reject(reason: String,detail := "") -> Dictionary:
 return {"ok":false,"reason":reason,"detail":detail}

func validate(state: Dictionary) -> Dictionary:
 if not state.get("items") is Dictionary or not state.get("containers") is Dictionary: return _reject("invalid_state")
 if not _whole(state.get("next_item_seq"),1): return _reject("invalid_sequence")
 if state.items.size()>4096: return _reject("too_many_items")
 for id in state.items:
  var item=state.items[id]
  if not _text(id) or not item is Dictionary or item.get("instance_id")!=id: return _reject("invalid_instance",str(id))
  if not _text(item.get("definition_id")): return _reject("invalid_definition",id)
  var definition=catalog.get_definition(item.definition_id)
  if definition==null: return {"ok":false,"reason":"unknown_definition","item_id":id,"definition_id":item.definition_id}
  if not _whole(item.get("quantity"),1) or item.quantity>definition.max_stack: return _reject("invalid_quantity",id)
  if item.has("runtime") and not item.runtime is Dictionary: return _reject("invalid_runtime",id)
  if item.get("durability")!=null:
   var durability=item.durability
   if not (durability is int or durability is float) or not is_finite(float(durability)) or durability<0: return _reject("invalid_durability",id)
 var owners: Dictionary={}
 for cid in state.containers:
  var container=state.containers[cid]
  if not _text(cid) or not container is Dictionary: return _reject("invalid_container",str(cid))
  if not _whole(container.get("revision")) or not container.get("placements") is Array: return _reject("invalid_container",cid)
  var kind=container.get("kind","")
  if kind=="grid":
   if not _whole(container.get("width"),1) or not _whole(container.get("height"),1) or container.width>128 or container.height>128: return _reject("invalid_dimensions",cid)
  elif kind=="slots":
   if not container.get("slots") is Array or container.slots.is_empty(): return _reject("invalid_slots",cid)
   var slot_names={}
   for slot in container.slots:
    if not _text(slot) or slot.is_empty() or slot_names.has(slot): return _reject("invalid_slots",cid)
    slot_names[slot]=true
  elif kind!="list": return _reject("invalid_container_kind",cid)
  var limit=container.get("weight_limit",0.0)
  if not (limit is int or limit is float) or not is_finite(float(limit)) or limit<0: return _reject("invalid_weight_limit",cid)
  var occupied: Dictionary={}
  for placement in container.placements:
   if not placement is Dictionary or not _text(placement.get("item_id")): return _reject("invalid_placement",cid)
   var id=placement.item_id
   if not state.items.has(id): return _reject("missing_item",id)
   if owners.has(id): return _reject("duplicate_owner",id)
   owners[id]=cid
   var definition=catalog.get_definition(state.items[id].definition_id)
   if kind=="grid":
    if not _whole(placement.get("x")) or not _whole(placement.get("y")) or not placement.get("rotated",false) is bool: return _reject("invalid_position",id)
    var footprint=definition.footprint(placement.get("rotated",false))
    if placement.x+footprint.x>container.width or placement.y+footprint.y>container.height: return _reject("out_of_bounds",id)
    for y in range(int(placement.y),int(placement.y)+footprint.y):
     for x in range(int(placement.x),int(placement.x)+footprint.x):
      var cell=Vector2i(x,y)
      if occupied.has(cell): return _reject("overlap",id)
      occupied[cell]=id
   elif kind=="slots":
    var slot=placement.get("slot","")
    if not container.slots.has(slot) or String(definition.equipment_slot)!=slot: return _reject("wrong_slot",id)
    if occupied.has(slot): return _reject("slot_occupied",id)
    occupied[slot]=id
  if limit>0 and weight(state,cid)>float(limit)+0.000001: return _reject("overweight",cid)
 if owners.size()!=state.items.size(): return _reject("orphan_item")
 var ledger=state.get("processed_commands")
 if not ledger is Dictionary or not ledger.get("order") is Array or not ledger.get("results") is Dictionary: return _reject("invalid_command_ledger")
 if ledger.order.size()>COMMAND_LIMIT or ledger.order.size()!=ledger.results.size(): return _reject("invalid_command_ledger")
 var recorded={}
 for id in ledger.order:
  if not _text(id) or recorded.has(id) or not ledger.results.has(id) or not ledger.results[id] is Dictionary: return _reject("invalid_command_ledger")
  if not ledger.results[id].get("fingerprint") is String: return _reject("invalid_command_ledger")
  recorded[id]=true
 return {"ok":true,"reason":"valid"}

func contents(state: Dictionary,cid: String) -> Array[Dictionary]:
 var result: Array[Dictionary]=[]
 if not state.get("containers",{}).has(cid): return result
 for placement in state.containers[cid].placements:
  if not state.items.has(placement.item_id): continue
  var item: Dictionary=state.items[placement.item_id].duplicate(true)
  var definition=catalog.get_definition(item.definition_id)
  item.placement=placement.duplicate(true)
  item.definition=definition
  item.name=definition.display_name if definition!=null else item.definition_id
  item.value=definition.value if definition!=null else 0
  item.total_value=item.value*int(item.quantity)
  item.weight=definition.unit_weight*int(item.quantity) if definition!=null else 0.0
  result.append(item)
 return result

func quantity(state: Dictionary,cid: String,definition_id: String) -> int:
 var total=0
 if not state.get("containers",{}).has(cid): return total
 for placement in state.containers[cid].placements:
  var item=state.items.get(placement.item_id,{})
  if item.get("definition_id")==definition_id: total+=int(item.quantity)
 return total

func weight(state: Dictionary,cid: String) -> float:
 var total=0.0
 if not state.get("containers",{}).has(cid): return total
 for placement in state.containers[cid].placements:
  var item=state.items.get(placement.item_id,{})
  var definition=catalog.get_definition(item.get("definition_id",""))
  if definition!=null: total+=definition.unit_weight*int(item.get("quantity",0))
 return total

func owner_of(state: Dictionary,item_id: String) -> String:
 for cid in state.containers:
  if _placement(state,cid,item_id)!=null: return cid
 return ""

func _placement(state: Dictionary,cid: String,item_id: String):
 for placement in state.containers[cid].placements:
  if placement.item_id==item_id: return placement
 return null

func _allocate_id(state: Dictionary) -> String:
 var id="item_%08d" % int(state.next_item_seq)
 while state.items.has(id):
  state.next_item_seq=int(state.next_item_seq)+1
  id="item_%08d" % int(state.next_item_seq)
 state.next_item_seq=int(state.next_item_seq)+1
 return id

func _signature(item: Dictionary) -> String:
 var data=item.duplicate(true)
 data.erase("instance_id"); data.erase("quantity")
 return JSON.stringify(data,"",true)

func _can_place(state: Dictionary,cid: String,definition: Resource,x: int,y: int,rotated: bool) -> bool:
 var container=state.containers[cid]
 var dimensions=definition.footprint(rotated)
 var requested=Rect2i(x,y,dimensions.x,dimensions.y)
 if x<0 or y<0 or requested.end.x>container.width or requested.end.y>container.height: return false
 for existing in container.placements:
  var other=catalog.get_definition(state.items[existing.item_id].definition_id)
  var size=other.footprint(existing.get("rotated",false))
  if requested.intersects(Rect2i(int(existing.x),int(existing.y),size.x,size.y)): return false
 return true

func _find_position(state: Dictionary,cid: String,definition: Resource,rotated: bool) -> Dictionary:
 var container=state.containers[cid]
 for orientation in [rotated,not rotated] if definition.width!=definition.height else [rotated]:
  for y in range(int(container.height)):
   for x in range(int(container.width)):
    if _can_place(state,cid,definition,x,y,orientation): return {"x":x,"y":y,"rotated":orientation}
 return {}

func _deposit(state: Dictionary,cid: String,template: Dictionary,amount: int,options: Dictionary,preferred_id := "",excluded_id := "") -> Dictionary:
 var container=state.containers[cid]
 var definition=catalog.get_definition(template.definition_id)
 var limit=float(container.get("weight_limit",0.0))
 if limit>0 and weight(state,cid)+amount*definition.unit_weight>limit+0.000001: return _reject("overweight")
 var x=int(options.get("x",-1)); var y=int(options.get("y",-1))
 var automatic=x==-1 and y==-1
 if (x<0 or y<0) and not automatic: return _reject("invalid_position")
 var remaining=amount
 var affected: Array[String]=[]
 if container.kind!="slots" and definition.max_stack>1:
  for placement in container.placements:
   if placement.item_id==excluded_id: continue
   if not automatic and container.kind=="grid" and (int(placement.x)!=x or int(placement.y)!=y): continue
   var target=state.items[placement.item_id]
   if _signature(target)!=_signature(template): continue
   var fill=mini(remaining,definition.max_stack-int(target.quantity))
   if fill>0:
    target.quantity=int(target.quantity)+fill
    remaining-=fill; affected.append(placement.item_id)
   if remaining==0: return {"ok":true,"item_ids":affected}
 while remaining>0:
  var placement: Dictionary={}
  if container.kind=="grid":
   if automatic: placement=_find_position(state,cid,definition,options.get("rotated",false))
   elif _can_place(state,cid,definition,x,y,options.get("rotated",false)): placement={"x":x,"y":y,"rotated":options.get("rotated",false)}
   if placement.is_empty(): return _reject("no_space")
  elif container.kind=="slots":
   var slot=String(options.get("slot",""))
   if slot.is_empty(): slot=String(definition.equipment_slot)
   if slot.is_empty() or not container.slots.has(slot) or String(definition.equipment_slot)!=slot: return _reject("wrong_slot")
   for existing in container.placements:
    if existing.slot==slot: return _reject("slot_occupied")
   placement={"slot":slot}
  var id=preferred_id if not preferred_id.is_empty() else _allocate_id(state)
  preferred_id=""
  var item=template.duplicate(true)
  item.instance_id=id; item.quantity=mini(remaining,definition.max_stack)
  remaining-=int(item.quantity)
  state.items[id]=item
  placement.item_id=id
  container.placements.append(placement)
  affected.append(id)
 return {"ok":true,"item_ids":affected}

func add_item(state: Dictionary,definition_id: String,amount,cid: String,extra: Dictionary={}) -> Dictionary:
 var valid=validate(state)
 if not valid.ok: return valid
 if catalog.get_definition(definition_id)==null: return _reject("unknown_definition",definition_id)
 if not _whole(amount,1) or amount>100000: return _reject("invalid_quantity")
 if not state.containers.has(cid): return _reject("invalid_container",cid)
 var candidate=state.duplicate(true)
 var template=extra.duplicate(true)
 template.definition_id=definition_id
 template.quantity=amount
 template.instance_id=""
 if not template.has("durability"): template.durability=null
 if not template.has("runtime"): template.runtime={}
 var result=_deposit(candidate,cid,template,amount,{})
 if not result.ok: return result
 candidate.containers[cid].revision=int(candidate.containers[cid].revision)+1
 valid=validate(candidate)
 if not valid.ok: return valid
 state.clear(); state.merge(candidate,true)
 return {"ok":true,"reason":"added","item_ids":result.item_ids,"quantity":amount}

func _command_value(value):
 # JSON.parse_string returns floats for numbers, including revision 3 and qty 1.
 # Normalize exact JSON integers so a persisted request has the same identity.
 # Outside the IEEE-754 safe integer range, preserve the supplied representation.
 if value is float and is_finite(value) and absf(value)<=9007199254740991.0 and floor(value)==value:
  return int(value)
 if value is Array:
  var normalized=[]
  for entry in value: normalized.append(_command_value(entry))
  return normalized
 if value is Dictionary:
  var normalized={}
  for key in value: normalized[key]=_command_value(value[key])
  return normalized
 return value

func _fingerprint(command: Dictionary) -> String:
 return JSON.stringify(_command_value(command),"",true).sha256_text()

func _cached(state: Dictionary,command: Dictionary) -> Dictionary:
 var id=command.get("command_id","")
 if not _text(id) or id.is_empty(): return _reject("invalid_command_id")
 var results=state.processed_commands.results
 if not results.has(id): return {}
 if results[id].fingerprint!=_fingerprint(command): return _reject("command_conflict")
 var result=results[id].duplicate(true)
 result.erase("fingerprint")
 result.ok=true; result.reason="already_applied"; result.candidate=state.duplicate(true)
 return result

func _record(state: Dictionary,command: Dictionary,result: Dictionary):
 var ledger=state.processed_commands
 var id=command.command_id
 var record=result.duplicate(true)
 record.erase("candidate")
 record.fingerprint=_fingerprint(command)
 ledger.results[id]=record
 ledger.order.append(id)
 # Revisions never reset during a container's lifetime. An evicted transfer
 # cannot apply twice: its source/target revisions are now stale. New raids
 # must use fresh container identities or preserve their increasing revisions.
 while ledger.order.size()>COMMAND_LIMIT:
  ledger.results.erase(ledger.order.pop_front())

func _check_transfer(state: Dictionary,command: Dictionary) -> Dictionary:
 for key in ["from","to"]:
  if not _text(command.get(key)) or not state.containers.has(command[key]): return _reject("invalid_container",str(command.get(key)))
 for pair in [["from","source_revision"],["to","target_revision"]]:
  if not _whole(command.get(pair[1])) or int(command[pair[1]])!=int(state.containers[command[pair[0]]].revision): return _reject("stale_revision")
 for key in ["x","y"]:
  if command.has(key) and (not _whole(command[key],-1)): return _reject("invalid_position")
 if command.has("rotated") and not command.rotated is bool: return _reject("invalid_rotation")
 if command.has("slot") and not _text(command.slot): return _reject("wrong_slot")
 return {"ok":true}

func _move(state: Dictionary,command: Dictionary) -> Dictionary:
 var id=String(command.item_id)
 var source=state.items[id].duplicate(true)
 var amount=int(command.quantity)
 var source_container=state.containers[command.from]
 var full=amount==int(source.quantity)
 if full:
  source_container.placements.erase(_placement(state,command.from,id))
  state.items.erase(id)
 else: state.items[id].quantity=int(source.quantity)-amount
 var result=_deposit(state,command.to,source,amount,command,id if full else "",id)
 if not result.ok: return result
 source_container.revision=int(source_container.revision)+1
 if command.from!=command.to: state.containers[command.to].revision=int(state.containers[command.to].revision)+1
 return {"ok":true,"reason":"transferred","quantity":amount,"item_ids":result.item_ids}

func preview_transfer(state: Dictionary,command: Dictionary) -> Dictionary:
 var valid=validate(state)
 if not valid.ok: return valid
 var cached=_cached(state,command)
 if not cached.is_empty(): return cached
 valid=_check_transfer(state,command)
 if not valid.ok: return valid
 var id=command.get("item_id","")
 if not _text(id) or not state.items.has(id): return _reject("missing_item")
 if _placement(state,command.from,id)==null: return _reject("wrong_source")
 if not _whole(command.get("quantity"),1) or command.quantity>state.items[id].quantity: return _reject("invalid_quantity")
 var candidate=state.duplicate(true)
 var result=_move(candidate,command)
 if not result.ok: return result
 _record(candidate,command,result)
 valid=validate(candidate)
 if not valid.ok: return valid
 result.candidate=candidate
 return result

func preview_take_all(state: Dictionary,command: Dictionary) -> Dictionary:
 var valid=validate(state)
 if not valid.ok: return valid
 var cached=_cached(state,command)
 if not cached.is_empty(): return cached
 valid=_check_transfer(state,command)
 if not valid.ok: return valid
 if command.from==command.to: return _reject("same_container")
 if command.has("item_ids") and not command.item_ids is Array: return _reject("invalid_selection")
 var candidate=state.duplicate(true)
 var moved=0; var moved_ids: Array=[]; var left_ids: Array=[]
 # Persisted placement order is deterministic and survives closing/reopening UI.
 var placements=state.containers[command.from].placements.duplicate(true)
 for placement in placements:
  var id=placement.item_id
  if command.has("item_ids") and not command.item_ids.has(id): continue
  var available=int(candidate.items[id].quantity)
  var lo=1; var hi=available; var best: Dictionary={}; var best_count=0
  # Find the largest transferable quantity, including a partly fillable stack.
  while lo<=hi:
   var amount=int((lo+hi)/2)
   var attempt=candidate.duplicate(true)
   var move_command={"from":command.from,"to":command.to,"item_id":id,"quantity":amount}
   var result=_move(attempt,move_command)
   if result.ok:
    best=attempt; best_count=amount; lo=amount+1
   else: hi=amount-1
  if best_count>0:
   candidate=best; moved+=best_count; moved_ids.append(id)
  if best_count<available: left_ids.append(id)
 if moved==0: return _reject("no_space")
 # A batch is one transaction, so each affected container advances once.
 candidate.containers[command.from].revision=int(state.containers[command.from].revision)+1
 candidate.containers[command.to].revision=int(state.containers[command.to].revision)+1
 var output={"ok":true,"reason":"transferred","quantity":moved,"moved_item_ids":moved_ids,"remaining_item_ids":left_ids}
 _record(candidate,command,output)
 valid=validate(candidate)
 if not valid.ok: return valid
 output.candidate=candidate
 return output

func consume(state: Dictionary,cid: String,definition_id: String,amount) -> Dictionary:
 var valid=validate(state)
 if not valid.ok: return valid
 if not _whole(amount,1): return _reject("invalid_quantity")
 if not state.containers.has(cid): return _reject("invalid_container")
 if quantity(state,cid,definition_id)<amount: return _reject("insufficient_quantity")
 var candidate=state.duplicate(true)
 var remaining=amount
 for placement in candidate.containers[cid].placements.duplicate(true):
  var item=candidate.items[placement.item_id]
  if item.definition_id!=definition_id: continue
  var used=mini(remaining,int(item.quantity))
  item.quantity=int(item.quantity)-used; remaining-=used
  if item.quantity==0:
   candidate.items.erase(placement.item_id)
   candidate.containers[cid].placements.erase(placement)
  if remaining==0: break
 candidate.containers[cid].revision=int(candidate.containers[cid].revision)+1
 valid=validate(candidate)
 if not valid.ok: return valid
 return {"ok":true,"reason":"consumed","quantity":amount,"candidate":candidate}

func preview_sort(state: Dictionary,cid: String,command_id := "",expected_revision := -1) -> Dictionary:
 var valid=validate(state)
 if not valid.ok: return valid
 if not state.containers.has(cid) or state.containers[cid].kind!="grid": return _reject("invalid_container")
 var command={"command_id":command_id,"operation":"sort","container":cid,"revision":expected_revision}
 if not command_id.is_empty():
  var cached=_cached(state,command)
  if not cached.is_empty(): return cached
 if expected_revision>=0 and int(state.containers[cid].revision)!=expected_revision: return _reject("stale_revision")
 var candidate=state.duplicate(true)
 var items=contents(candidate,cid)
 items.sort_custom(func(a,b):
  var area_a=a.definition.width*a.definition.height
  var area_b=b.definition.width*b.definition.height
  return area_a>area_b if area_a!=area_b else a.instance_id<b.instance_id)
 candidate.containers[cid].placements=[]
 for item in items:
  var placement=_find_position(candidate,cid,item.definition,item.placement.get("rotated",false))
  if placement.is_empty(): return _reject("cannot_repack")
  placement.item_id=item.instance_id
  candidate.containers[cid].placements.append(placement)
 candidate.containers[cid].revision=int(candidate.containers[cid].revision)+1
 var result={"ok":true,"reason":"sorted"}
 if not command_id.is_empty(): _record(candidate,command,result)
 valid=validate(candidate)
 if not valid.ok: return valid
 result.candidate=candidate
 return result
