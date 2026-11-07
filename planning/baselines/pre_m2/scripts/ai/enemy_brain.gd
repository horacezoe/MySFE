extends RefCounted
## Produces movement and firing intentions, never damage. The only knowledge of
## the player comes from observations or explicit noise/impact events.

const PATROL=&"Patrol"
const INVESTIGATE=&"Investigate"
const ALERT=&"Alert"
const ENGAGE=&"Engage"
const SEARCH=&"Search"
const RETURN=&"Return"
const DEAD=&"Dead"

var body: CharacterBody3D
var agent: NavigationAgent3D
var navigation_map: RID
var state: StringName=PATROL
var state_elapsed := 0.0
var last_known := Vector3.ZERO
var aim_point := Vector3.ZERO
var has_memory := false
var reaction_time := 0.65
var hearing_distance := 26.0
var turn_speed := 2.5
var search_duration := 4.0
var investigate_timeout := 10.0
var route: Array[Vector3]=[]
var _route_index := 0
var _waypoint_pause := 0.0
var _reaction_remaining := 0.0
var _burst_remaining := 0
var _shot_wait := 0.0
var _repath_wait := 0.0
var _path_target := Vector3.INF
var _search_yaw := 0.0
var _nav_initialized := false
var _rng := RandomNumberGenerator.new()

func setup(actor: CharacterBody3D, patrol_route: Array[Vector3], map_rid: RID, seed_value: int) -> void:
 body=actor
 route=patrol_route.duplicate()
 if route.is_empty(): route.append(body.global_position)
 navigation_map=map_rid
 _rng.seed=seed_value
 agent=NavigationAgent3D.new()
 agent.name="GuardNavigation"
 agent.path_desired_distance=0.30
 agent.target_desired_distance=0.55
 agent.path_max_distance=2.0
 agent.radius=0.48
 agent.height=1.8
 agent.max_speed=2.6
 agent.avoidance_enabled=false
 body.add_child(agent)
 agent.set_navigation_map(navigation_map)
 _waypoint_pause=_rng.randf_range(0.3,1.0)

func hear(position: Vector3, strength := 1.0) -> void:
 if state==DEAD or not is_instance_valid(body): return
 if body.global_position.distance_to(position)>hearing_distance*maxf(0.0,strength): return
 if state==ENGAGE or state==ALERT: return
 last_known=position
 aim_point=position+Vector3(0,1.05,0)
 has_memory=true
 _change_state(INVESTIGATE)

func take_hit(source_position: Vector3) -> void:
 if state==DEAD: return
 last_known=source_position
 aim_point=source_position+Vector3(0,1.05,0)
 has_memory=true
 if state!=ENGAGE and state!=ALERT: _change_state(INVESTIGATE)

func die() -> void:
 _change_state(DEAD)
 if is_instance_valid(body): body.velocity=Vector3.ZERO

func step(delta: float, perception: Dictionary) -> Dictionary:
 var result={"fire":false,"aim_point":aim_point,"state":state,"aiming":false,"spread":0.024}
 if state==DEAD or not is_instance_valid(body): return result
 state_elapsed+=delta
 _shot_wait=maxf(0.0,_shot_wait-delta)
 _repath_wait=maxf(0.0,_repath_wait-delta)
 var visible: bool=perception.get("visible",false)
 var confirmed: bool=visible and perception.get("confirmed",false)
 if confirmed:
  last_known=perception.position
  aim_point=perception.get("aim_point",last_known+Vector3(0,1.05,0))
  has_memory=true
  if state!=ALERT and state!=ENGAGE:
   _change_state(ALERT)
   _reaction_remaining=reaction_time
 elif state==ENGAGE or state==ALERT:
  _change_state(INVESTIGATE)

 var destination := body.global_position
 var speed := 0.0
 var face_point := body.global_position-body.global_basis.z
 match state:
  PATROL:
   if _navigation_ready():
    if not _nav_initialized:
     for i in range(route.size()): route[i]=NavigationServer3D.map_get_closest_point(navigation_map,route[i])
     _nav_initialized=true
    destination=route[_route_index]
    if _flat_distance(body.global_position,destination)<0.65:
     _waypoint_pause-=delta
     if _waypoint_pause<=0:
      _route_index=(_route_index+1)%route.size()
      _waypoint_pause=_rng.randf_range(0.7,1.4)
     face_point=body.global_position+Vector3(sin(state_elapsed*0.4),0,-cos(state_elapsed*0.4))
    else: speed=1.45
  INVESTIGATE:
   destination=last_known
   speed=2.5
   if _flat_distance(body.global_position,last_known)<0.9 or state_elapsed>=investigate_timeout:
    _change_state(SEARCH)
    _search_yaw=body.rotation.y
    speed=0.0
  ALERT:
   face_point=last_known
   _reaction_remaining-=delta
   if _reaction_remaining<=0:
    _change_state(ENGAGE)
    _burst_remaining=3
    _shot_wait=0.0
  ENGAGE:
   face_point=last_known
   var target_distance := _flat_distance(body.global_position,last_known)
   if target_distance>12.0:
    destination=last_known
    speed=2.2
   elif target_distance<4.5:
    var away := (body.global_position-last_known).normalized()
    destination=body.global_position+away*3.0
    speed=1.4
   if visible and target_distance<=24.0 and _facing_error(last_known)<deg_to_rad(8.0) and _shot_wait<=0:
    if _burst_remaining<=0: _burst_remaining=3
    result.fire=true
    _burst_remaining-=1
    _shot_wait=0.48 if _burst_remaining>0 else 1.10
  SEARCH:
   var angle := _search_yaw+sin(state_elapsed*1.1)*1.15
   face_point=body.global_position+Vector3(-sin(angle),0,-cos(angle))
   if state_elapsed>=search_duration: _change_state(RETURN)
  RETURN:
   destination=route[0]
   speed=1.8
   if _flat_distance(body.global_position,destination)<0.7:
    has_memory=false
    _change_state(PATROL)

 var movement := _path_direction(destination) if speed>0 else Vector3.ZERO
 if movement.length()>0.01 and state!=ENGAGE: face_point=body.global_position+movement
 _turn_toward(face_point,delta)
 body.velocity.x=movement.x*speed
 body.velocity.z=movement.z*speed
 if not body.is_on_floor(): body.velocity.y-=20.0*delta
 elif body.velocity.y<0: body.velocity.y=-0.1
 body.move_and_slide()
 result.state=state
 result.aim_point=aim_point
 result.aiming=state==ALERT or state==ENGAGE
 result.spread=0.034 if movement.length()>0.1 else 0.024
 return result

func _change_state(next: StringName) -> void:
 if state==next: return
 state=next
 state_elapsed=0.0
 _repath_wait=0.0
 _path_target=Vector3.INF

func _navigation_ready() -> bool:
 return navigation_map.is_valid() and NavigationServer3D.map_get_iteration_id(navigation_map)>0 and NavigationServer3D.map_get_closest_point_owner(navigation_map,body.global_position).is_valid()

func _path_direction(destination: Vector3) -> Vector3:
 if not _navigation_ready(): return Vector3.ZERO
 if _repath_wait<=0 or _path_target.distance_to(destination)>0.7:
  agent.target_position=destination
  _path_target=destination
  _repath_wait=0.45
 var next := agent.get_next_path_position()
 if agent.is_navigation_finished(): return Vector3.ZERO
 var direction := next-body.global_position
 direction.y=0
 return direction.normalized() if direction.length()>0.03 else Vector3.ZERO

func _turn_toward(point: Vector3, delta: float) -> void:
 var direction := point-body.global_position
 if Vector2(direction.x,direction.z).length()<0.01: return
 var desired := atan2(-direction.x,-direction.z)
 body.rotation.y+=clampf(wrapf(desired-body.rotation.y,-PI,PI),-turn_speed*delta,turn_speed*delta)

func _facing_error(point: Vector3) -> float:
 var difference := point-body.global_position
 return absf(wrapf(atan2(-difference.x,-difference.z)-body.rotation.y,-PI,PI))

func _flat_distance(a: Vector3,b: Vector3) -> float:
 return Vector2(a.x-b.x,a.z-b.z).length()
