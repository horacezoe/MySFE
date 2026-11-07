extends RefCounted
## One ray and one damage commit for every accepted local shot, player or AI.

const WORLD := 1
const ACTOR := 2
const HITBOX := 4
const SHOT_MASK := WORLD|HITBOX
const MAX_REMEMBERED_SHOTS := 256
const MAX_ACTIVE_WEAPONS := 64

var _recent_shots: Dictionary = {}
var _shot_order: Array[String] = []
var _weapon_sequences: Dictionary = {}
var _weapon_order: Array[String] = []

func attach_actor(body: CharacterBody3D, health: RefCounted, team: StringName) -> void:
 body.collision_layer=ACTOR
 body.collision_mask=WORLD|ACTOR
 body.set_meta("combat_health",health)
 body.set_meta("team",team)
 var previous := body.get_node_or_null("Hitboxes")
 if previous!=null: previous.free()
 var hitboxes := Node3D.new()
 hitboxes.name="Hitboxes"
 body.add_child(hitboxes)
 var head := SphereShape3D.new()
 head.radius=0.29
 _area(hitboxes,body,"Head",&"head",Vector3(0,1.62,0),head)
 _box_area(hitboxes,body,"Torso",&"torso",Vector3(0,1.03,0),Vector3(0.70,0.72,0.54))
 _box_area(hitboxes,body,"LeftLeg",&"limbs",Vector3(-0.20,0.38,0),Vector3(0.24,0.62,0.28))
 _box_area(hitboxes,body,"RightLeg",&"limbs",Vector3(0.20,0.38,0),Vector3(0.24,0.62,0.28))
 _box_area(hitboxes,body,"LeftArm",&"limbs",Vector3(-0.42,1.0,0),Vector3(0.22,0.55,0.28))
 _box_area(hitboxes,body,"RightArm",&"limbs",Vector3(0.42,1.0,0),Vector3(0.22,0.55,0.28))

func _box_area(parent: Node3D, actor: CharacterBody3D, name: String, zone: StringName, position: Vector3, size: Vector3) -> void:
 var shape := BoxShape3D.new()
 shape.size=size
 _area(parent,actor,name,zone,position,shape)

func _area(parent: Node3D, actor: CharacterBody3D, name: String, zone: StringName, position: Vector3, shape: Shape3D) -> void:
 var area := Area3D.new()
 area.name=name
 area.position=position
 area.collision_layer=HITBOX
 area.collision_mask=0
 area.monitoring=false
 area.monitorable=false
 area.set_meta("actor",actor)
 area.set_meta("zone",zone)
 var collision := CollisionShape3D.new()
 collision.shape=shape
 area.add_child(collision)
 parent.add_child(area)

func set_crouched(body: CharacterBody3D, crouched: bool) -> void:
 var hitboxes := body.get_node_or_null("Hitboxes") as Node3D
 if hitboxes!=null: hitboxes.scale.y=0.62 if crouched else 1.0

func exclusions(body: CollisionObject3D) -> Array[RID]:
 var result: Array[RID]=[body.get_rid()]
 var hitboxes := body.get_node_or_null("Hitboxes")
 if hitboxes!=null:
  for child in hitboxes.get_children():
   if child is CollisionObject3D: result.append(child.get_rid())
 return result

func resolve(shooter: CharacterBody3D, solution: Dictionary, definition: Resource, shot_id: String, spread: float, rng: RandomNumberGenerator) -> Dictionary:
 if _was_seen(shot_id): return {"accepted":false,"reason":"duplicate","shot_id":shot_id}
 if not is_instance_valid(shooter) or not shooter.is_inside_tree(): return _rejected(shot_id,"invalid_shooter")
 var shooter_health=shooter.get_meta("combat_health") if shooter.has_meta("combat_health") else null
 if shooter_health!=null and shooter_health.hp<=0: return _rejected(shot_id,"dead")
 if bool(solution.get("blocked",true)): return _rejected(shot_id,"blocked")
 if not solution.has("origin") or not solution.has("direction"): return _rejected(shot_id,"invalid_aim")
 var origin: Vector3=solution.origin
 var direction: Vector3=solution.direction
 if not origin.is_finite() or not direction.is_finite() or direction.length_squared()<0.000001: return _rejected(shot_id,"invalid_aim")
 direction=_spread(direction.normalized(),maxf(0.0,spread),rng)
 var endpoint: Vector3=origin+direction*maxf(0.001,definition.max_range)
 var query := PhysicsRayQueryParameters3D.create(origin,endpoint,SHOT_MASK)
 query.collide_with_areas=true
 query.collide_with_bodies=true
 query.exclude=exclusions(shooter)
 # Muzzle overlap is already checked by AimResolver. hit_from_inside remains a
 # defensive wall hit if an external caller submits an inaccurate solution.
 query.hit_from_inside=true
 var hit := shooter.get_world_3d().direct_space_state.intersect_ray(query)
 var result := {
  "accepted":true,"reason":"fired","shot_id":shot_id,
  "origin":origin,"direction":direction,"end_point":endpoint,
  "actor":null,"zone":&"","health_damage":0.0,"armor_damage":0.0,
  "killed":false,"hit":false,"hit_world":false,"distance":definition.max_range,
 }
 if not hit.is_empty():
  result.hit=true
  result.end_point=hit.position
  result.normal=hit.normal
  result.distance=origin.distance_to(hit.position)
  var collider: CollisionObject3D=hit.collider
  var actor=collider.get_meta("actor") if collider.has_meta("actor") else null
  if is_instance_valid(actor) and actor is CharacterBody3D:
   var health=actor.get_meta("combat_health") if actor.has_meta("combat_health") else null
   result.actor=actor
   result.zone=StringName(collider.get_meta("zone",&"torso"))
   # Guards obstruct each other's shots. Friendly fire is disabled for this
   # single-player prototype; the same team rule applies to every shooter.
   var same_team=shooter.get_meta("team",&"")==actor.get_meta("team",&"none")
   if health!=null and not same_team:
    var raw_damage: float=definition.damage_at(result.distance,result.zone)
    var damage: Dictionary=health.apply_damage(raw_damage,result.zone,definition.armor_penetration)
    result.merge(damage,true)
   elif same_team: result.reason="friendly_block"
  else: result.hit_world=true
 _remember(shot_id)
 return result

func _spread(direction: Vector3, cone: float, rng: RandomNumberGenerator) -> Vector3:
 if cone<=0.0: return direction
 cone=minf(cone,0.5)
 var helper := Vector3.UP if absf(direction.dot(Vector3.UP))<0.99 else Vector3.RIGHT
 var right := direction.cross(helper).normalized()
 var up := right.cross(direction).normalized()
 var radius := sqrt(rng.randf())*tan(cone)
 var angle := rng.randf()*TAU
 return (direction+right*cos(angle)*radius+up*sin(angle)*radius).normalized()

func _rejected(shot_id: String, reason: String) -> Dictionary:
 return {"accepted":false,"reason":reason,"shot_id":shot_id,"health_damage":0.0,"armor_damage":0.0,"killed":false}

func _remember(shot_id: String) -> void:
 _recent_shots[shot_id]=true
 _shot_order.append(shot_id)
 if _shot_order.size()>MAX_REMEMBERED_SHOTS:
  _recent_shots.erase(_shot_order.pop_front())
 # Keep a high-water mark per active weapon so even an ancient sequence cannot
 # replay after the recent-shot ring has wrapped. Retain at most 64 weapons.
 var parts := shot_id.split(":")
 if parts.size()==3 and parts[2].is_valid_int():
  var source := parts[0]+":"+parts[1]
  _weapon_sequences[source]=int(parts[2])
  _weapon_order.erase(source)
  _weapon_order.append(source)
  if _weapon_order.size()>MAX_ACTIVE_WEAPONS:
   _weapon_sequences.erase(_weapon_order.pop_front())

func _was_seen(shot_id: String) -> bool:
 if _recent_shots.has(shot_id): return true
 var parts := shot_id.split(":")
 if parts.size()==3 and parts[2].is_valid_int():
  var source := parts[0]+":"+parts[1]
  return int(parts[2])<=int(_weapon_sequences.get(source,-1))
 return false
