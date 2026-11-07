extends RefCounted
## Stable search containers derived from the same persisted death snapshot.
## This layer never writes disk or publishes a live profile.

const PREFIX="loot_guard_"
const GUARD_COUNT=9
const PLAYER_WEAPON=preload("res://data/weapons/player_rifle.tres")
const PLAYER_ARMOR=preload("res://data/armor/player_light.tres")
const COLLECTIBLES=["loot_ration","loot_parts","loot_battery","loot_watch"]

func _reject(reason := "invalid_corpse_loot") -> Dictionary:
 return {"ok":false,"reason":reason,"changed":false}

func _whole(value,limit: int) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and value>=0 and value<=limit and floor(float(value))==value

func _durability(value,limit: float) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and value>=0 and value<=limit

func _index(cid: String) -> int:
 for index in GUARD_COUNT:
  if cid==PREFIX+"%02d" % index: return index
 return -1

func validate(state: Dictionary) -> Dictionary:
 var active: Dictionary=state.get("active_raid",{})
 var containers: Dictionary=state.get("containers",{})
 var searches: Dictionary=active.get("search",{})
 var enemies: Array=active.get("snapshot",{}).get("enemies",[])
 for cid in containers:
  if not String(cid).begins_with(PREFIX): continue
  if active.is_empty() or not searches.has(cid) or not containers[cid] is Dictionary: return _reject()
 for cid in searches:
  var search=searches[cid]
  var reserved=String(cid).begins_with(PREFIX)
  if not reserved:
   if search is Dictionary and (search.get("kind")=="corpse" or search.has("guard_id")): return _reject()
   continue
  var index=_index(String(cid))
  if index<0 or not containers.has(cid) or not search is Dictionary: return _reject()
  if enemies.size()!=GUARD_COUNT or not enemies[index] is Dictionary: return _reject()
  var enemy: Dictionary=enemies[index]
  if enemy.get("health",{}).get("hp",-1)!=0 or enemy.get("brain",{}).get("state")!="Dead": return _reject("corpse_source_alive")
  if search.get("kind")!="corpse" or search.get("guard_id")!="guard_%02d" % index: return _reject()
  if not search.get("opened") is bool: return _reject()
  if not search.get("order") is Array or search.order.is_empty() or search.order.size()>8: return _reject()
  if not _whole(search.get("revealed"),search.order.size()): return _reject()
  if not _durability(search.get("elapsed"),0.7): return _reject()
  var container: Dictionary=containers[cid]
  if container.get("kind")!="grid" or container.get("width")!=6 or container.get("height")!=5 or container.get("weight_limit")!=0: return _reject()
  if not container.get("placements") is Array: return _reject()
  var seen={}
  for item_id in search.order:
   if not item_id is String or item_id.is_empty() or seen.has(item_id): return _reject()
   seen[item_id]=true
  # Missing IDs are legitimate tombstones after transfer/stack merge. Current
  # items must still belong to the original reveal order, including an empty body.
  for placement in container.get("placements",[]):
   if not placement is Dictionary or not seen.has(placement.get("item_id")): return _reject()
 return {"ok":true}

func ensure(candidate: Dictionary,inventory) -> Dictionary:
 var valid=validate(candidate)
 if not valid.ok: return valid
 var active: Dictionary=candidate.active_raid
 if active.is_empty() or active.snapshot.is_empty(): return {"ok":true,"changed":false}
 var enemies: Array=active.snapshot.enemies
 var missing: Array[int]=[]
 for index in enemies.size():
  if enemies[index].health.hp>0: continue
  var cid=PREFIX+"%02d" % index
  if not candidate.containers.has(cid): missing.append(index)
 if missing.is_empty(): return {"ok":true,"changed":false}
 var prepared=candidate.duplicate(true)
 for index in missing:
  var enemy: Dictionary=enemies[index]
  if enemy.brain.state!="Dead": return _reject("corpse_source_alive")
  var weapon: Dictionary=enemy.weapon
  var health: Dictionary=enemy.health
  # Historical snapshots could use the player's tuning for a guard. Bound by
  # the supported equipment capacity, preserve its recorded quantity exactly.
  if not _whole(weapon.ammo,PLAYER_WEAPON.magazine_size) or not _whole(weapon.reserve,PLAYER_WEAPON.starting_reserve): return _reject("invalid_corpse_equipment")
  if not _durability(health.head_armor,PLAYER_ARMOR.head_durability) or not _durability(health.body_armor,PLAYER_ARMOR.body_durability): return _reject("invalid_corpse_equipment")
  var cid=PREFIX+"%02d" % index
  prepared.containers[cid]=inventory.make_grid(6,5)
  var items=[
   ["rifle_basic",1,{"bound":false,"durability":100.0,"runtime":{"ammo":int(weapon.ammo)}}],
   ["helmet_light",1,{"bound":false,"durability":float(health.head_armor)}],
   ["vest_light",1,{"bound":false,"durability":float(health.body_armor)}],
  ]
  if weapon.reserve>0: items.append(["ammo_rifle",int(weapon.reserve),{"bound":false}])
  var random=RandomNumberGenerator.new()
  random.seed=(str(active.get("seed",0))+"/corpse/guard_%02d" % index).hash()
  if random.randf()<0.55: items.append(["medkit_basic",1,{"bound":false}])
  items.append([COLLECTIBLES[random.randi_range(0,COLLECTIBLES.size()-1)],1,{"bound":false}])
  for entry in items:
   var added: Dictionary=inventory.add_item(prepared,entry[0],entry[1],cid,entry[2])
   if not added.ok: return {"ok":false,"reason":added.reason,"changed":false}
  var order=[]
  for placement in prepared.containers[cid].placements: order.append(placement.item_id)
  prepared.active_raid.search[cid]={"order":order,"revealed":0,"elapsed":0.0,"opened":false,"kind":"corpse","guard_id":"guard_%02d" % index}
 var generated=validate(prepared)
 if not generated.ok: return generated
 candidate.clear()
 candidate.merge(prepared,true)
 return {"ok":true,"changed":true,"created":missing.size()}
