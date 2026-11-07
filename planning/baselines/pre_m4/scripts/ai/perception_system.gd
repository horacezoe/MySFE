extends RefCounted
## One sensor instance per observer. Hidden targets are never included in the
## returned observation. Cached visible positions are at most one sample old.

var view_distance := 22.0
var field_of_view := deg_to_rad(100.0)
var sample_period := 0.125
var confirmation_time := 0.30
var _until_sample := 0.0
var _visible_duration := 0.0
var _sample_elapsed := 0.0
var _observation: Dictionary = {"visible":false,"confirmed":false}

func reset() -> void:
 _until_sample=0.0
 _visible_duration=0.0
 _sample_elapsed=0.0
 _observation={"visible":false,"confirmed":false}

func observe(observer: CharacterBody3D, target: CharacterBody3D, delta: float) -> Dictionary:
 _until_sample-=delta
 _sample_elapsed+=delta
 if _until_sample>0: return _observation.duplicate()
 _until_sample=sample_period
 var elapsed := _sample_elapsed
 _sample_elapsed=0.0
 var seen := false
 var sample_point := Vector3.ZERO
 var difference := target.global_position-observer.global_position
 var distance := difference.length()
 var horizontal := Vector3(difference.x,0,difference.z)
 var forward := -observer.global_basis.z
 forward.y=0
 if distance<=view_distance and (horizontal.length()<0.01 or forward.normalized().dot(horizontal.normalized())>=cos(field_of_view*0.5)):
  var origin := observer.global_position+Vector3(0,1.5,0)
  var ignored: Array[RID]=[observer.get_rid()]
  for area in observer.find_children("*","Area3D",true,false): ignored.append(area.get_rid())
  for point in _target_points(target):
   var query := PhysicsRayQueryParameters3D.create(origin,point,1|4)
   query.collide_with_areas=true
   query.exclude=ignored
   var hit := observer.get_world_3d().direct_space_state.intersect_ray(query)
   if not hit.is_empty() and hit.collider.has_meta("actor") and hit.collider.get_meta("actor")==target:
    seen=true
    sample_point=point
    break
 if seen:
  _visible_duration+=elapsed
  _observation={"visible":true,"confirmed":_visible_duration>=confirmation_time,"position":target.global_position,"aim_point":sample_point,"distance":distance}
 else:
  _visible_duration=0.0
  _observation={"visible":false,"confirmed":false}
 return _observation.duplicate()

func _target_points(target: CharacterBody3D) -> Array[Vector3]:
 var points: Array[Vector3]=[]
 # Torso is the default aim point; the head is a visibility sample for cover.
 for zone in [&"torso",&"head"]:
  for area in target.find_children("*","Area3D",true,false):
   if area.get_meta("zone",&"")==zone: points.append(area.global_position)
 if points.is_empty(): points.append(target.global_position+Vector3(0,1.05,0))
 return points
