extends RefCounted
## JSON-only checkpoint adapter. Navigation paths are rebuilt, never persisted.
const BRAIN_FIELDS=["state_elapsed","has_memory","_route_index","_waypoint_pause","_reaction_remaining","_burst_remaining","_shot_wait","_search_yaw"]

func vector(v: Vector3) -> Array: return [v.x,v.y,v.z]
func vec(a: Array) -> Vector3: return Vector3(float(a[0]),float(a[1]),float(a[2]))

func weapon(w) -> Dictionary:
 return {"ammo":w.ammo,"reserve":w.reserve,"reload_remaining":w.reload_remaining,"cooldown":w.cooldown,"shots_fired":w.shots_fired,"rng_state":str(w.rng.state)}

func restore_weapon(w,data: Dictionary):
 for key in ["ammo","reserve","reload_remaining","cooldown","shots_fired"]:
  if data.has(key): w.set(key,data[key])
 w.disabled=false
 if data.has("rng_state"): w.rng.state=int(data.rng_state)

func health(h) -> Dictionary: return {"hp":h.hp,"head_armor":h.head_armor,"body_armor":h.body_armor}
func restore_health(h,data: Dictionary):
 for key in ["hp","head_armor","body_armor"]: h.set(key,float(data.get(key,h.get(key))))

func capture(game) -> Dictionary:
 var guards=[]
 for enemy in game.enemies:
  var brain={"state":String(enemy.brain.state),"last_known":vector(enemy.brain.last_known),"aim_point":vector(enemy.brain.aim_point),"rng_state":str(enemy.brain._rng.state)}
  for key in BRAIN_FIELDS: brain[key]=enemy.brain.get(key)
  guards.append({"position":vector(enemy.node.position),"rotation_y":enemy.node.rotation.y,"health":health(enemy.health),"weapon":weapon(enemy.weapon),"brain":brain})
 return {"player":{"position":vector(game.player.position),"velocity":vector(game.player.velocity),"yaw":game.rig.yaw,"pitch":game.rig.pitch,"third_person":game.rig.third_person,"crouching":game.motor.crouching,"health":health(game.player_health),"weapon":weapon(game.weapon_runtime),"healing_remaining":game.healing_remaining},"enemies":guards,"remaining":maxf(0.0,game.remaining),"extract_time":maxf(0.0,game.extract_time),"kills":game.kills,"deployment_grace":game.deployment_grace}

func apply(game,data: Dictionary):
 if data.is_empty(): return
 var p=data.player
 game.player.position=vec(p.position)
 game.player.velocity=vec(p.get("velocity",[0,0,0]))
 game.rig.yaw=float(p.yaw); game.rig.pitch=float(p.pitch); game.rig.third_person=p.third_person
 game.motor.crouching=p.crouching
 game.motor.eye_height=0.96 if p.crouching else 1.55
 game.player.get_node("BodyCollider").shape.height=1.05 if p.crouching else 1.7
 game.player.get_node("BodyCollider").position.y=0.575 if p.crouching else 0.9
 game.player.get_node("Visual").scale.y=0.62 if p.crouching else 1.0
 game.combat.set_crouched(game.player,p.crouching)
 game.player.get_node("Hitboxes").scale.y=game.player.get_node("Visual").scale.y
 restore_health(game.player_health,p.health)
 restore_weapon(game.weapon_runtime,p.weapon)
 game.healing_remaining=float(p.get("healing_remaining",0))
 for key in ["remaining","extract_time","kills","deployment_grace"]: game.set(key,data.get(key,game.get(key)))
 for index in range(mini(game.enemies.size(),data.get("enemies",[]).size())):
  var saved=data.enemies[index]; var enemy=game.enemies[index]
  enemy.node.position=vec(saved.position); enemy.node.rotation.y=float(saved.rotation_y)
  restore_health(enemy.health,saved.health); restore_weapon(enemy.weapon,saved.weapon)
  enemy.brain.state=StringName(saved.brain.state)
  enemy.brain.last_known=vec(saved.brain.last_known); enemy.brain.aim_point=vec(saved.brain.aim_point)
  for key in BRAIN_FIELDS:
   if saved.brain.has(key): enemy.brain.set(key,saved.brain[key])
  enemy.brain._rng.state=int(saved.brain.rng_state)
  enemy.sensor.reset()
  if enemy.health.hp<=0:
   enemy.brain.die(); enemy.weapon.disable()
   enemy.node.collision_layer=0; enemy.node.collision_mask=0
   for hitbox in enemy.node.get_node("Hitboxes").get_children(): hitbox.collision_layer=0
   enemy.node.get_node("Visual").rotation.z=PI*0.5
   enemy.label.visible=false
 game._apply_view()
