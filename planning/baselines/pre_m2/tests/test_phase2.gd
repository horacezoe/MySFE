extends SceneTree
## Phase-two integration through the real game loop. Synthetic duel positions
## isolate the shared shot/health contract; AI navigation has a separate suite.

class PhysicsTask:
 extends Node
 signal completed
 var pending: Callable
 func run(callback: Callable):
  pending=callback
  await completed
 func _physics_process(_delta):
  if pending.is_valid():
   var task=pending
   pending=Callable()
   task.call()
   completed.emit()

var game
var tick: PhysicsTask
var checks := 0
var failures := 0
var saved_before := ""
var save_existed := false

func _initialize():
 call_deferred("run_tests")

func check(condition: bool, description: String):
 checks+=1
 if not condition:
  failures+=1
  printerr("FAIL: "+description)

func frames(count: int):
 for i in range(count):
  await tick.run(func(): game._physics_process(1.0/60.0))

func run_tests():
 create_timer(60).timeout.connect(func(): printerr("FAIL: phase-two game test timeout"); quit(1))
 save_existed=FileAccess.file_exists("user://progress.json")
 if save_existed: saved_before=FileAccess.get_file_as_string("user://progress.json")
 game=load("res://main.tscn").instantiate()
 game.test_mode=true
 root.add_child(game)
 game.set_physics_process(false)
 tick=PhysicsTask.new()
 root.add_child(tick)
 await test_drill_patrol()
 await test_guard_shots_and_death()
 await test_search_freeze()
 await test_reset_lifecycle()
 check(FileAccess.file_exists("user://progress.json")==save_existed,"tests do not create or remove a personal save")
 if save_existed:
  check(FileAccess.get_file_as_string("user://progress.json")==saved_before,"tests leave existing save bytes unchanged")
 game.free()
 tick.queue_free()
 await process_frame
 print("Phase-two game checks: %d passed / %d total" % [checks-failures,checks])
 quit(1 if failures else 0)

func test_drill_patrol():
 await tick.run(func(): game._reset(true,true))
 await frames(8)
 check(game.training_mode and game.combat_drill and game.enemies.size()==2,"combat drill creates exactly two live guards")
 check(game.drill_navigation.ready(),"drill navigation is synchronized")
 check(game.drill_navigation.map!=game.world_navigation.map,"drill owns an independent navigation map")
 var visible_results: Array=[]
 await tick.run(func():
  for enemy in game.enemies:
   visible_results.append(game.aim_resolver.visible(enemy.node,enemy.node.position+Vector3(0,1.5,0),game.player,game.player.position+Vector3(0,1.05,0)))
 )
 check(not visible_results.has(true),"initial central cover blocks both guard-to-player sightlines")
 var origins: Array[Vector3]=[]
 for enemy in game.enemies: origins.append(enemy.node.global_position)
 var penetrated := false
 for frame in range(150):
  await frames(1)
  for enemy in game.enemies:
   var p: Vector3=enemy.node.global_position
   if p.x>212.55 and p.x<227.45 and p.z>7.25 and p.z<8.75: penetrated=true
 var moved := false
 for i in range(game.enemies.size()):
  if origins[i].distance_to(game.enemies[i].node.global_position)>0.5: moved=true
 check(moved,"real game-loop guards patrol before player engagement")
 check(not penetrated,"patrolling guards do not enter central cover")
 check(game.hp==100 and game.last_enemy_shot.is_empty(),"protected deployment has no invisible opening damage")

func test_guard_shots_and_death():
 var enemy: Dictionary=game.enemies[0]
 var other: Dictionary=game.enemies[1]
 await tick.run(func():
  other.node.free()
  game.enemies.erase(other)
  enemy.node.position=Vector3(205,0,-12)
  enemy.node.rotation.y=0.0
  enemy.brain.route.assign([Vector3(205,0,-12)])
  enemy.brain._route_index=0
  enemy.brain._waypoint_pause=60.0
  enemy.brain._change_state(enemy.brain.PATROL)
  enemy.brain.state_elapsed=0.0
  enemy.sensor.reset()
  enemy.weapon.configure(game.GUARD_WEAPON.duplicate(),77)
  enemy.weapon.definition.aim_spread=0.0
  enemy.weapon.definition.move_spread=0.0
  game.player.position=Vector3(205,0,-20)
  game.player_health.reset()
  game.deployment_grace=0.0
  game.last_enemy_shot={}
 )
 await frames(40)
 check(game.hp==100 and enemy.weapon.shots_fired==0,"confirmed target still has a reaction window without damage")
 var before_hp: float=game.hp
 var damage_sum := 0.0
 var armor_sum := 0.0
 var armor_before: float=game.player_health.body_armor+game.player_health.head_armor
 var ids: Dictionary={}
 for frame in range(100):
  await frames(1)
  var shot: Dictionary=game.last_enemy_shot
  if not shot.is_empty() and not ids.has(shot.shot_id):
   ids[shot.shot_id]=true
   damage_sum+=shot.health_damage
   armor_sum+=shot.armor_damage
 check(enemy.weapon.shots_fired>0 and not ids.is_empty(),"AI emits accepted shared weapon shots with unique IDs")
 check(enemy.weapon.ammo==enemy.weapon.definition.magazine_size-enemy.weapon.shots_fired,"AI consumes one cartridge per accepted shot")
 check(game.hp<before_hp and game.last_enemy_shot.actor==game.player,"real enemy muzzle ray hits player hitboxes")
 check(is_equal_approx(before_hp-game.hp,damage_sum),"player health loss equals actual enemy ShotResult damage")
 check(is_equal_approx(armor_before-game.player_health.body_armor-game.player_health.head_armor,armor_sum),"player armor loss equals actual enemy ShotResult absorption")
 # Freeze a real enemy reload and brain timer through the pause interface.
 enemy.weapon.ammo=2
 check(enemy.weapon.request_reload(),"enemy can begin shared weapon reload")
 var reload_before: float=enemy.weapon.reload_remaining
 var brain_before: float=enemy.brain.state_elapsed
 game._pause_game()
 await frames(30)
 check(enemy.weapon.reload_remaining==reload_before and enemy.brain.state_elapsed==brain_before,"pause freezes enemy weapon and behavior timers")
 game._resume()
 await frames(1)
 check(enemy.weapon.reload_remaining<reload_before,"enemy reload resumes after pause")

 var wall_holder: Array=[]
 await tick.run(func(): wall_holder.append(game.box(game.world,Vector3(5,3,0.12),Vector3(205,1.45,-16),Color.GRAY,true)))
 await frames(2)
 var protected_hp: float=game.hp
 var protected_armor: float=game.player_health.body_armor+game.player_health.head_armor
 await frames(50)
 check(game.hp==protected_hp and game.player_health.body_armor+game.player_health.head_armor==protected_armor,"new physical cover prevents player damage even during cached perception")
 check(enemy.brain.state!=enemy.brain.ENGAGE,"lost visual contact leaves direct engagement")
 # Explicitly submit a valid enemy muzzle shot through the same weapon/resolver:
 # the normal obstacle consumes the bullet but never applies hidden-player damage.
 var obstruction_results: Array=[]
 await tick.run(func():
  var rifle=enemy.node.get_node("Visual/CarriedRifle")
  rifle.look_at(game.player.global_position+Vector3(0,1.03,0),Vector3.UP)
  var solution=game.aim_resolver.solve(enemy.node,enemy.node.global_position+Vector3(0,1.3,0),rifle.get_node("Muzzle").global_position,game.player.global_position+Vector3(0,1.03,0))
  enemy.weapon.cancel_reload()
  enemy.weapon.cooldown=0.0
  obstruction_results.append(enemy.weapon.request_fire(enemy.node,solution,game.combat,0.0))
 )
 var blocked_shot: Dictionary=obstruction_results[0]
 check(blocked_shot.accepted and blocked_shot.get("hit_world",false),"valid enemy shot terminates at nearest thin cover")
 check(blocked_shot.get("actor")==null and blocked_shot.health_damage==0 and game.hp==protected_hp,"covered player takes no health damage from forced valid shot")

 await tick.run(func():
  wall_holder[0].free()
  enemy.node.position=Vector3(205,0,-12)
  enemy.health.hp=1.0
  enemy.weapon.request_reload()
  game.deployment_grace=100.0
  game.weapon_runtime.definition=game.weapon_runtime.definition.duplicate()
  game.weapon_runtime.definition.hip_spread=0.0
  game.weapon_runtime.definition.aim_spread=0.0
  game.weapon_runtime.definition.move_spread=0.0
  game.rig.third_person=false
  game.rig.recoil_pitch=0.0
  game._apply_view()
 )
 for adjustment in range(5):
  await frames(1)
  var direction: Vector3=(enemy.node.global_position+Vector3(0,1.03,0)-game.camera.global_position).normalized()
  game.rig.yaw=atan2(-direction.x,-direction.z)
  game.rig.pitch=asin(direction.y)
 await frames(1)
 await tick.run(func(): game.fire_delay=0.0; game._try_fire())
 check(game.last_shot.get("killed",false) and game.last_shot.get("actor")==enemy.node,"player's shared shot kills the actual guard")
 check(enemy.brain.state==enemy.brain.DEAD and enemy.weapon.disabled and enemy.weapon.reload_remaining==0,"dead guard stops brain and cancels its reload")
 var hitboxes_off := true
 for hitbox in enemy.node.get_node("Hitboxes").get_children():
  if hitbox.collision_layer!=0: hitboxes_off=false
 check(enemy.node.collision_layer==0 and enemy.node.collision_mask==0 and hitboxes_off,"corpse movement and damage colliders are disabled")
 var hp_after_death: float=game.hp
 var shots_after_death: int=enemy.weapon.shots_fired
 await frames(80)
 check(game.hp==hp_after_death and enemy.weapon.shots_fired==shots_after_death,"old corpse cannot keep shooting or damaging the player")
 var rejected: Dictionary=enemy.weapon.request_fire(enemy.node,{},game.combat,0.0)
 check(not rejected.accepted and rejected.reason=="disabled","dead enemy weapon rejects later fire requests")

func test_search_freeze():
 await tick.run(func(): game._reset())
 await frames(5)
 var crate: Dictionary=game.crates[0]
 var enemy: Dictionary=game.enemies[0]
 enemy.weapon.ammo=2
 enemy.weapon.request_reload()
 await tick.run(func(): game.player.position=crate.node.position+Vector3(0,-0.4,1.4))
 await frames(2)
 await tick.run(func(): game._interact())
 check(game.searching and game.search_ui.visible,"real crate interaction enters search context")
 var timer: float=enemy.weapon.reload_remaining
 var elapsed: float=enemy.brain.state_elapsed
 var position: Vector3=enemy.node.global_position
 await frames(30)
 check(enemy.weapon.reload_remaining==timer and enemy.brain.state_elapsed==elapsed and enemy.node.global_position==position,"search freezes enemy reload, state time and movement")
 game._close_search()
 await frames(2)
 check(enemy.weapon.reload_remaining<timer,"closing search resumes enemy weapon time")

func test_reset_lifecycle():
 var before_wealth: int=game.wealth
 var before_wins: int=game.wins
 await tick.run(func(): game._reset(true,true))
 await frames(8)
 var previous_map: RID=game.drill_navigation.map
 var previous_actor=weakref(game.enemies[0].node)
 for iteration in range(2):
  await tick.run(func(): game._reset(true,true))
  await frames(8)
  check(game.drill_navigation.ready() and game.enemies.size()==2,"reopened drill has synchronized navigation and exactly two guards")
  check(game.drill_navigation.map!=previous_map and not NavigationServer3D.get_maps().has(previous_map),"reopening drill disposes its old navigation RID")
  check(previous_actor.get_ref()==null,"reopening drill frees old enemy actors")
  previous_map=game.drill_navigation.map
  previous_actor=weakref(game.enemies[0].node)
 game._finish(true,"测试演练结算")
 check(not game.playing and game.wealth==before_wealth and game.wins==before_wins,"combat drill results never award warehouse progress")
 await tick.run(func(): game._reset(true,false))
 await frames(5)
 check(game.training_mode and not game.combat_drill and game.drill_navigation==null,"switching to target range disposes combat navigation")
 check(game.enemies.size()==3 and game.enemies.all(func(enemy): return enemy.brain==null),"target range contains only harmless practice targets")
 check(game.wealth==before_wealth and game.wins==before_wins,"practice mode changes preserve warehouse progress")
