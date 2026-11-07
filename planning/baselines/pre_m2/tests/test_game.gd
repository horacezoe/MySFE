extends SceneTree

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

var suite="all"
var game
var tick: PhysicsTask
var failures=0
var checks=0

func _initialize():
 call_deferred("run_tests")

func check(condition: bool, description: String):
 checks+=1
 if not condition:
  failures+=1
  push_error("FAIL: "+description)

func frames(count: int):
 for i in range(count):
  await tick.run(func(): game._physics_process(1.0/60.0))

func run_tests():
 create_timer(35).timeout.connect(func(): push_error("Game test timeout"); quit(1))
 game=load("res://main.tscn").instantiate()
 game.test_mode=true
 root.add_child(game)
 game.set_physics_process(false)
 tick=PhysicsTask.new()
 root.add_child(tick)
 if suite=="all" or suite=="search": await test_raid()
 if suite=="all" or suite=="hit": await test_aim()
 if suite=="all" or suite=="movement": await test_controls()
 if suite=="all": await test_layouts()
 game.free()
 tick.queue_free()
 await process_frame
 print("GAME ",suite,": ",checks-failures,"/",checks," checks passed")
 quit(1 if failures else 0)

func remove_enemies():
 for enemy in game.enemies:
  if is_instance_valid(enemy.node): enemy.node.free()
 game.enemies.clear()

func test_raid():
 # Three full original loops. test_mode forbids personal save reads/writes.
 for raid in range(3):
  await tick.run(func(): game._reset(); remove_enemies())
  await frames(2)
  var crate=game.crates[0]
  var count=crate.items.size()
  await tick.run(func(): game.player.position=crate.node.position+Vector3(0,-0.4,1.4))
  await frames(2)
  await tick.run(func(): game._interact())
  check(game.searching and game.search_ui.visible,"search opens")
  if not game.searching: continue
  game._take_item(crate.items[0])
  check(game.bag.size()==1 and crate.items.size()==count-1,"item moves once")
  game._close_search()
  await tick.run(func(): game._interact())
  check(crate.items.size()==count-1,"reopen preserves remaining loot")
  game._close_search()
  var before=game.wealth
  var value=game.bag[0].value
  await tick.run(func(): game.player.position=game.exit_pos)
  await frames(2)
  await tick.run(func(): game._interact(); game.extract_time=0.02)
  await frames(3)
  check(not game.playing and game.wealth==before+value,"raid extraction settles")
  check(game.menu.visible and not game.input_router.enabled,"results cancel gameplay")

func test_aim():
 await tick.run(func(): game._reset(true))
 # This suite measures geometric aim. Spread distribution is tested separately.
 game.weapon_runtime.definition=game.weapon_runtime.definition.duplicate()
 game.weapon_runtime.definition.hip_spread=0.0
 game.weapon_runtime.definition.aim_spread=0.0
 await frames(3)
 check(game.enemies.size()==3 and game.training_mode,"training targets created")
 for third in [false,true]:
  game.rig.third_person=third
  game._apply_view()
  for target in game.enemies:
   # Put each actual scene target dead ahead at 5/15/40 m, then iterate the
   # camera yaw/pitch to account for shoulder offset, as a player would aim.
   game.rig.yaw=0; game.rig.pitch=0; game.rig.recoil_pitch=0
   for adjustment in range(4):
    await frames(1)
    var direction=(target.node.global_position+Vector3(0,1.05,0)-game.camera.global_position).normalized()
    game.rig.yaw=atan2(-direction.x,-direction.z)
    game.rig.pitch=asin(direction.y)
   await frames(1)
   var before=game.training_hits
   var ammunition=game.ammo
   var health_before=target.health.hp
   await tick.run(func(): game.fire_delay=0; game._try_fire())
   check(game.training_hits==before+1,"real scene gun hits target in view "+str(third))
   check(game.last_shot.get("actor")==target.node and game.last_shot.get("zone")==&"torso","shot resolves intended actor and torso zone")
   check(is_equal_approx(health_before-target.health.hp,game.last_shot.get("health_damage",0.0)),"feedback matches actual health delta")
   check(game.ammo==ammunition-1 and game.hit_marker.visible,"one accepted shot / one ammo / hit marker")
 check(game.hp==100,"range targets never attack")
 # A thin wall between the player and muzzle must refuse a shot and consume 0.
 game.rig.third_person=false; game.rig.yaw=0; game.rig.pitch=0; game.rig.recoil_pitch=0
 await tick.run(func(): game.player.position=Vector3(120,0,10.7))
 await frames(3)
 var before_ammo=game.ammo
 await tick.run(func(): game.fire_delay=0; game._try_fire())
 check(game.aim_solution.blocked and game.ammo==before_ammo,"near-wall rejection keeps ammo")
 # Reload pauses exactly, then completes once.
 game.ammo=8; game.reserve=120
 game._reload()
 game._pause_game()
 var before_reload=game.reload_time
 await frames(5)
 check(game.reload_time==before_reload,"pause freezes reload")
 game._resume()
 await frames(int(ceil(game.weapon_runtime.definition.reload_duration*60))+2)
 check(game.ammo==24 and game.reserve==120,"range reload finishes once")
 await tick.run(func(): game._reset(true))
 await frames(2)
 check(game.enemies.size()==3,"repeat training reset has no stale actors")

func test_controls():
 await tick.run(func(): game._reset(true))
 await frames(10)
 check(game.player.is_on_floor(),"settles on floor")
 game._queue_action(&"crouch")
 await frames(20)
 check(game.motor.crouching and game.motor.eye_height<1.1,"crouch updates capsule and eye")
 game._queue_action(&"jump")
 await frames(5)
 check(not game.motor.crouching and game.player.position.y>0.1,"jump stands and rises")
 await frames(80)
 check(game.player.is_on_floor(),"jump lands")
 game.input_router.set_action(&"move_forward",true)
 game.input_router.set_action(&"sprint",true)
 await frames(2)
 check(Vector2(game.player.velocity.x,game.player.velocity.z).length()>9,"sprint speed")
 game._pause_game()
 game._resume()
 await frames(2)
 check(game.player.velocity.x==0 and game.player.velocity.z==0,"pause/resume cannot revive movement")
 check(not game.input_router.consume_frame().fire,"resume cannot revive firing")
 var original_view=game.rig.third_person
 var key=InputEventKey.new()
 key.device=0; key.physical_keycode=KEY_V; key.keycode=KEY_V; key.pressed=true
 root.push_input(key,true)
 key=key.duplicate(); key.pressed=false
 root.push_input(key,true)
 await frames(2)
 check(game.rig.third_person!=original_view,"native keyboard device routed through viewport")
 # Real viewport GUI routing: independent left move, right look, fire button.
 var fire_button: Button
 for child in game.hud_root.get_children():
  if child is Button and child.text=="开火": fire_button=child
 var button_point=fire_button.get_global_rect().get_center()
 touch(0,Vector2(170,400),true)
 drag(0,Vector2(170,345),Vector2(0,-55))
 touch(1,Vector2(850,280),true)
 drag(1,Vector2(880,280),Vector2(30,0))
 touch(2,button_point,true)
 var frame=game.input_router.consume_frame()
 check(frame.move.y<0 and frame.look.x<0 and frame.fire,"three-finger GUI+move+look")
 touch(2,Vector2(800,100),false)
 check(not game.input_router.consume_frame().fire,"release outside button stops fire")
 game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
 check(game.paused and not game.input_router.enabled and game.touch_buttons.is_empty(),"focus loss cancels all controls")
 game._resume()
 var clean=game.input_router.consume_frame()
 check(clean.move==Vector2.ZERO and clean.look==Vector2.ZERO and not clean.fire,"focus return is neutral")
 touch(0,Vector2(170,345),false)
 touch(1,Vector2(880,280),false)

func touch(id: int, position: Vector2, down: bool):
 var event=InputEventScreenTouch.new()
 event.index=id; event.position=position; event.pressed=down
 root.push_input(event,true)

func test_layouts():
 game._pause_game()
 for size in [Vector2i(1280,720),Vector2i(1200,900),Vector2i(1280,800)]:
  root.size=size
  await process_frame
  await process_frame
  var visible=game.get_viewport().get_visible_rect()
  check(game.crosshair.get_global_rect().get_center().distance_to(visible.get_center())<1,"crosshair exact center "+str(size))
  var contained=true
  for child in game.hud_root.get_children():
   if child is Button and not visible.encloses(child.get_global_rect()): contained=false
  check(contained,"HUD buttons inside viewport "+str(size))
  check(visible.encloses(game.menu.get_child(1).get_global_rect()),"menu inside viewport "+str(size))

func drag(id: int, position: Vector2, relative: Vector2):
 var event=InputEventScreenDrag.new()
 event.index=id; event.position=position; event.relative=relative; event.screen_relative=relative
 root.push_input(event,true)
