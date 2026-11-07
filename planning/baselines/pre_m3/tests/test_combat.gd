extends SceneTree
## Shared weapon/damage tests. All space queries run during a physics callback.

const HealthState=preload("res://scripts/combat/health_state.gd")
const WeaponController=preload("res://scripts/combat/weapon_controller.gd")
const CombatResolver=preload("res://scripts/combat/combat_resolver.gd")
const PLAYER=preload("res://data/weapons/player_rifle.tres")
const GUARD=preload("res://data/weapons/guard_rifle.tres")
const ARMOR=preload("res://data/armor/player_light.tres")

class Probe extends Node3D:
 signal tick
 var count=0
 func _physics_process(_delta):
  count+=1
  if count>1800: push_error("Combat tests timed out"); get_tree().quit(1)
  tick.emit()

var probe: Probe
var checks=0
var failures=0
var resolver=CombatResolver.new()
var shooter: CharacterBody3D
var target: CharacterBody3D
var health=HealthState.new(100.0,0.0,0.0)
var shooter_health=HealthState.new(100.0,0.0,0.0)
var weapon=WeaponController.new()

func _initialize(): call_deferred("run_tests")

func check(condition: bool,label: String):
 checks+=1
 if not condition:
  failures+=1
  push_error("FAIL: "+label)

func close(a: float,b: float) -> bool: return absf(a-b)<0.001

func sync():
 await probe.tick
 await probe.tick

func actor(position: Vector3,state: RefCounted,team: StringName) -> CharacterBody3D:
 var body=CharacterBody3D.new()
 var collision=CollisionShape3D.new()
 var shape=CapsuleShape3D.new()
 shape.radius=0.48; shape.height=1.7
 collision.shape=shape; collision.position.y=0.9
 body.add_child(collision)
 probe.add_child(body)
 body.position=position
 resolver.attach_actor(body,state,team)
 return body

func wall(position: Vector3,size: Vector3) -> StaticBody3D:
 var body=StaticBody3D.new()
 var collision=CollisionShape3D.new()
 var shape=BoxShape3D.new(); shape.size=size
 collision.shape=shape; body.add_child(collision)
 probe.add_child(body); body.position=position
 return body

func solution(origin:=Vector3(0,1.03,-1),direction:=Vector3.FORWARD) -> Dictionary:
 return {"blocked":false,"origin":origin,"direction":direction,"target":origin+direction*60.0}

func ready_weapon(tuning: Resource=PLAYER):
 weapon.configure(tuning,73)
 health.reset(); shooter_health.reset()

func run_tests():
 probe=Probe.new(); root.add_child(probe)
 test_health()
 test_tuning()
 test_ammunition()
 shooter=actor(Vector3.ZERO,shooter_health,&"player")
 target=actor(Vector3(0,0,-10),health,&"guard")
 await sync()
 test_zones()
 await test_distance()
 await test_world_and_teams()
 await test_crouched_hitboxes()
 test_rejections_and_ids()
 test_spread()
 probe.queue_free()
 await process_frame
 print("Combat checks: %d passed / %d total" % [checks-failures,checks])
 quit(1 if failures else 0)

func test_health():
 var state=HealthState.new(100.0,20.0,40.0)
 var hit=state.apply_damage(32.0,&"torso",0.35)
 check(close(hit.armor_damage,13.52) and close(hit.health_damage,18.48),"torso damage splits into actual armor and health")
 check(close(state.body_armor,26.48) and close(state.hp,81.52),"durability and health are authoritative")
 state.reset()
 hit=state.apply_damage(64.0,&"head",0.35)
 check(close(hit.armor_damage,20.0) and close(hit.health_damage,44.0),"helmet exhaustion passes unabsorbed damage")
 check(state.head_armor==0 and state.body_armor==40,"helmet and vest durability are separate")
 hit=state.apply_damage(64.0,&"head",0.35)
 check(hit.killed and close(hit.health_damage,56.0),"overkill reports only actual remaining health")
 check(state.apply_damage(32,&"torso").health_damage==0,"dead actor cannot take a second damage event")
 check(state.heal(50)==0,"healing does not resurrect a dead actor")
 state.reset()
 hit=state.apply_damage(20.8,&"limbs",0.35)
 check(close(hit.health_damage,20.8) and hit.armor_damage==0,"limbs do not consume torso armor")
 state.reset()
 hit=state.apply_damage(32,&"torso",1.0)
 check(hit.health_damage==32 and hit.armor_damage==0,"full configured penetration bypasses armor")
 check(state.apply_damage(-1,&"torso").health_damage==0,"negative damage rejected")
 state.configure_armor(ARMOR)
 check(state.head_armor==20 and state.body_armor==40,"armor resource configures durability")

func test_tuning():
 check(PLAYER.magazine_size==24 and PLAYER.base_damage==32,"player resource loads")
 check(GUARD.magazine_size==12 and GUARD.base_damage==12 and close(GUARD.fire_interval,0.45),"guard resource loads conservative fire cadence")
 check(close(PLAYER.damage_at(5,&"head"),64),"head multiplier is data driven")
 check(close(PLAYER.damage_at(5,&"limbs"),20.8),"limb multiplier is data driven")
 check(close(PLAYER.damage_at(40,&"torso"),26.4),"distance falloff interpolates")
 check(close(PLAYER.damage_at(100,&"torso"),20.8),"falloff clamps at configured minimum")
 var first=WeaponController.new(); first.configure(PLAYER)
 var second=WeaponController.new(); second.configure(PLAYER)
 first.ammo=1
 check(second.ammo==24 and PLAYER.magazine_size==24,"shared Resource never stores mutable ammo")

func test_ammunition():
 var gun=WeaponController.new(); gun.configure(PLAYER)
 gun.ammo=5; gun.reserve=7
 check(gun.request_reload(),"partial magazine starts reload")
 check(not gun.request_reload(),"duplicate reload does not restart timer")
 gun.tick(0.8)
 check(gun.ammo==5 and gun.reserve==7,"reload transfers nothing before completion")
 gun.cancel_reload()
 gun.tick(2)
 check(gun.ammo==5 and gun.reserve==7 and gun.reload_remaining==0,"canceled reload transfers no ammo")
 gun.request_reload(); gun.tick(2)
 check(gun.ammo==12 and gun.reserve==0,"reload conserves magazine plus reserve")
 gun.tick(20)
 check(gun.ammo==12 and gun.reserve==0,"completion cannot transfer twice")
 check(not gun.request_reload(),"empty reserve rejects reload")
 gun.configure(PLAYER)
 check(not gun.request_reload(),"full magazine rejects reload")
 gun.ammo=0; gun.request_reload(); gun.disable(); gun.tick(20)
 check(gun.ammo==0 and gun.reserve==120 and not gun.can_fire(),"death disables weapon and cancels reload")

func test_zones():
 for entry in [[Vector3(0,1.62,-1),&"head",64.0],[Vector3(0,1.03,-1),&"torso",32.0],[Vector3(-0.2,0.38,-1),&"limbs",20.8]]:
  ready_weapon()
  var hit=weapon.request_fire(shooter,solution(entry[0]),resolver)
  check(hit.accepted and hit.actor==target and hit.zone==entry[1],"ray selects "+str(entry[1])+" hitbox")
  check(close(hit.health_damage,entry[2]) and close(health.hp,100-entry[2]),"reported "+str(entry[1])+" damage matches health")
  check(weapon.ammo==23 and close(weapon.cooldown,0.16),"accepted shot consumes exactly one round")
  var denied=weapon.request_fire(shooter,solution(),resolver)
  check(not denied.accepted and denied.reason=="cooldown" and weapon.ammo==23,"same-tick repeat cannot fire twice")
 ready_weapon()
 var gap=weapon.request_fire(shooter,solution(Vector3(0,0.38,-1)),resolver)
 check(gap.accepted and gap.actor==null and health.hp==100,"body capsule does not fill gap between leg hitboxes")
 ready_weapon()
 var self_origin=weapon.request_fire(shooter,solution(Vector3(0,1.03,0)),resolver)
 check(self_origin.actor==target and shooter_health.hp==100,"all shooter hitboxes are excluded")
 check(resolver.exclusions(shooter).size()==7,"exclusions include body and six hitboxes")

func test_distance():
 for distance in [5.0,15.0,40.0]:
  target.position.z=-distance
  await sync()
  ready_weapon()
  var hit=weapon.request_fire(shooter,solution(),resolver)
  check(hit.actor==target and close(hit.health_damage,PLAYER.damage_at(hit.distance,&"torso")),"actual ray distance drives falloff at %dm" % distance)
 target.position.z=-65
 await sync()
 ready_weapon()
 var miss=weapon.request_fire(shooter,solution(),resolver)
 check(miss.accepted and miss.actor==null and weapon.ammo==23 and health.hp==100,"beyond-range target unharmed, round still spent")
 check(close(miss.origin.distance_to(miss.end_point),PLAYER.max_range),"miss endpoint obeys weapon maximum range")
 target.position.z=-10
 await sync()

func test_world_and_teams():
 var obstruction=wall(Vector3(0,1.0,-9.4),Vector3(2,2,0.12))
 await sync()
 ready_weapon()
 var blocked=weapon.request_fire(shooter,solution(),resolver)
 check(blocked.accepted and blocked.hit_world and health.hp==100 and weapon.ammo==23,"thin wall near target takes shot instead of actor")
 obstruction.free()
 var friend_health=HealthState.new(100.0,0.0,0.0)
 var friend=actor(Vector3(0,0,-5),friend_health,&"player")
 await sync()
 ready_weapon()
 var friendly=weapon.request_fire(shooter,solution(),resolver)
 check(friendly.reason=="friendly_block" and friend_health.hp==100 and health.hp==100,"friendly actor blocks ray without team damage")
 friend.free()
 await sync()
 # Reverse the exact same resolver/controller path: guard shoots player.
 var guard_gun=WeaponController.new(); guard_gun.configure(GUARD,82)
 var incoming=guard_gun.request_fire(target,solution(Vector3(0,1.03,-9),Vector3.BACK),resolver)
 check(incoming.actor==shooter and close(incoming.health_damage,12) and shooter_health.hp==88,"AI uses identical real ray and damage resolver")

func test_crouched_hitboxes():
 resolver.set_crouched(target,true)
 await sync()
 ready_weapon()
 var over=weapon.request_fire(shooter,solution(Vector3(0,1.62,-1)),resolver)
 check(over.actor==null and health.hp==100,"standing head ray passes above crouched hitboxes")
 weapon.tick(1)
 var low=weapon.request_fire(shooter,solution(Vector3(0,1.62*0.62,-1)),resolver)
 check(low.actor==target and low.zone==&"head","crouched head remains hittable at lowered position")
 resolver.set_crouched(target,false)
 await sync()

func test_rejections_and_ids():
 ready_weapon()
 var aim=solution(); aim.blocked=true
 var blocked=weapon.request_fire(shooter,aim,resolver)
 check(not blocked.accepted and blocked.reason=="blocked" and weapon.ammo==24,"invalid muzzle rejects without ammo consumption")
 aim=solution(); aim.direction=Vector3.ZERO
 var invalid=weapon.request_fire(shooter,aim,resolver)
 check(not invalid.accepted and invalid.reason=="invalid_aim" and weapon.ammo==24,"zero direction rejects without ammo consumption")
 shooter_health.hp=0
 var dead=weapon.request_fire(shooter,solution(),resolver)
 check(not dead.accepted and dead.reason=="dead" and weapon.ammo==24,"dead actor cannot fire")
 shooter_health.reset()
 weapon.ammo=5; weapon.request_reload()
 var reload=weapon.request_fire(shooter,solution(),resolver)
 check(not reload.accepted and reload.reason=="reloading" and weapon.ammo==5,"reload blocks firing")
 weapon.cancel_reload(); weapon.ammo=0
 var empty=weapon.request_fire(shooter,solution(),resolver)
 check(not empty.accepted and empty.reason=="no_ammo","empty magazine blocks firing")
 ready_weapon()
 var first=weapon.request_fire(shooter,solution(),resolver)
 var before=health.hp
 var duplicate=resolver.resolve(shooter,solution(),PLAYER,first.shot_id,0.0,weapon.rng)
 check(not duplicate.accepted and duplicate.reason=="duplicate" and health.hp==before,"same shot cannot apply damage twice")
 var initial_id=first.shot_id
 for i in range(270):
  weapon.tick(1); weapon.ammo=24
  weapon.request_fire(shooter,solution(Vector3(10,1.03,-1)),resolver)
 var old_duplicate=resolver.resolve(shooter,solution(),PLAYER,initial_id,0.0,weapon.rng)
 check(not old_duplicate.accepted and health.hp==before,"active-weapon high-water mark rejects evicted old shot")
 check(resolver._recent_shots.size()<=256 and resolver._weapon_sequences.size()<=64,"deduplication memory is bounded")
 weapon.configure(PLAYER)
 var reconfigured=weapon.request_fire(shooter,solution(),resolver)
 check(reconfigured.accepted and reconfigured.shot_id!=initial_id,"reconfigured weapon cannot reuse a previous shot identity")

func test_spread():
 var first=RandomNumberGenerator.new(); first.seed=73
 var second=RandomNumberGenerator.new(); second.seed=73
 var same=true
 var bounded=true
 var varied=false
 for i in range(20):
  var a=resolver._spread(Vector3.FORWARD,0.05,first)
  var b=resolver._spread(Vector3.FORWARD,0.05,second)
  same=same and a.is_equal_approx(b)
  bounded=bounded and a.angle_to(Vector3.FORWARD)<=0.050001
  varied=varied or a.distance_to(Vector3.FORWARD)>0.001
 check(same,"weapon spread replays from isolated RNG seed")
 check(bounded and varied,"spread directions remain within configured cone")
 check(resolver._spread(Vector3.FORWARD,0.0,first)==Vector3.FORWARD,"stationary zero spread remains exact")
