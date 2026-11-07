extends RefCounted
## Deterministic exit lifecycle. Inventory consumption belongs to atomic settlement.
var exits: Array=[]
var exit_id=""
var remaining=0.0
var completed=false

func configure(definitions: Array):
 exits=definitions.duplicate(true)
 cancel()

func definition(id: String) -> Dictionary:
 for entry in exits:
  if entry.id==id: return entry
 return {}

func nearby(position: Vector3) -> Dictionary:
 var best: Dictionary={}
 var distance=INF
 for entry in exits:
  var d=position.distance_to(entry.position)
  if d<=float(entry.radius) and d<distance: best=entry; distance=d
 return best

func begin(position: Vector3,alive: bool,has_item: Callable) -> Dictionary:
 if not alive: return {"ok":false,"reason":"dead"}
 var entry=nearby(position)
 if entry.is_empty(): return {"ok":false,"reason":"not_at_exit"}
 if not String(entry.get("required_item","")).is_empty() and not has_item.call(entry.required_item): return {"ok":false,"reason":"pass_required","exit":entry}
 if exit_id==entry.id and remaining>0: return {"ok":true,"reason":"already_extracting","exit":entry}
 exit_id=entry.id; remaining=float(entry.wait); completed=false
 return {"ok":true,"reason":"started","exit":entry}

func step(delta: float,position: Vector3,alive: bool,has_item: Callable) -> Dictionary:
 if not alive:
  cancel()
  return {"status":"dead"}
 if exit_id.is_empty() or completed: return {"status":"idle"}
 var entry=definition(exit_id)
 if entry.is_empty() or position.distance_to(entry.position)>float(entry.radius):
  cancel(); return {"status":"cancelled","reason":"left_exit"}
 if not String(entry.get("required_item","")).is_empty() and not has_item.call(entry.required_item):
  cancel(); return {"status":"cancelled","reason":"pass_required"}
 remaining=maxf(0.0,remaining-maxf(0.0,delta))
 if remaining<=0:
  completed=true
  return {"status":"complete","exit":entry}
 return {"status":"extracting","exit":entry}

func cancel():
 exit_id=""; remaining=0.0; completed=false

func snapshot() -> Dictionary:
 return {"exit_id":exit_id,"remaining":maxf(0.0,remaining)}

func restore(data: Dictionary):
 cancel()
 var entry=definition(String(data.get("exit_id","")))
 if entry.is_empty(): return
 var time=float(data.get("remaining",0.0))
 if not is_finite(time) or time<=0: return
 exit_id=entry.id; remaining=minf(time,float(entry.wait))
