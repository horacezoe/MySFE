extends SceneTree
## Genuine scene -> JSON slots -> fresh scene roundtrips in a disposable fixture.
## _ready always uses test_mode before explicitly configuring this isolated path.
const ProfileService=preload("res://scripts/raid/profile_service.gd")

class PhysicsTask:
 extends Node
 signal completed
 var pending: Callable
 func run(callback: Callable):
  pending=callback
  await completed
 func _physics_process(_delta):
  if pending.is_valid():
   var callback=pending; pending=Callable()
   callback.call(); completed.emit()

var game
var tick: PhysicsTask
var fixture_root="res://tests/.phase3-disk-%s-%s" % [OS.get_process_id(),Time.get_ticks_usec()]
var checks=0
var failures=0

func _initialize(): call_deferred("run_tests")

func check(condition: bool,label: String):
 checks+=1
 if not condition:
  failures+=1
  push_error("PHASE3 DISK: "+label)

func encoded(value) -> String: return game.profiles.saves.canonical_json(value)
func pack_quantity(id: String) -> int: return game.profiles.inventory.quantity(game.profiles.profile,"raid_pack",id)

func frames(count: int):
 for index in range(count):
  await tick.run(func(): game._physics_process(1.0/60.0))

func free_game():
 if is_instance_valid(game):
  game.profiles.saves.configure(fixture_root) # Release its bound validator cycle.
  game.free()
 game=null

func boot() -> bool:
 free_game()
 await process_frame
 game=load("res://main.tscn").instantiate()
 game.test_mode=true
 game.save_path_override=fixture_root
 root.add_child(game) # initialize(true): no disk or legacy read here.
 game.set_physics_process(false); game.set_process(false)
 var loaded=game.profiles.initialize(false,fixture_root,"")
 check(loaded.ok and not game.profiles.blocked,"fresh scene loads only its isolated disk profile: "+str(loaded.get("reason","")))
 if not loaded.ok: return false
 await tick.run(func(): game._reset(); game.deployment_grace=1000)
 check(game.playing and not game.save_failed and not game.profiles.memory_only,"real scene checkpoint commits to disk: "+game.profiles.last_error)
 return game.playing and not game.save_failed

func run_tests():
 create_timer(65).timeout.connect(func(): push_error("Phase3 disk timeout"); finish(false))
 tick=PhysicsTask.new(); root.add_child(tick)
 if not await boot(): finish(); return
 await frames(5)
 if not await test_pickup_restart(): finish(); return
 if not await test_reload_parked(): finish(); return
 if not await test_heal_parked(): finish(); return
 if not await test_practice_restart(): finish(); return
 await test_write_failure()
 check(game.profiles.inventory.validate(game.profiles.profile).ok,"durable final inventory invariant")
 finish()

func test_pickup_restart() -> bool:
 var crate=game.crates[0]
 var candidate=game.profiles.profile.duplicate(true)
 var added=game.profiles.inventory.add_item(candidate,"ammo_rifle",7,crate.cid)
 check(added.ok,"fixture adds an ammunition pickup")
 if not added.ok: return false
 var ammo_id=added.item_ids[0]
 candidate.active_raid.search[crate.cid].order.append(ammo_id)
 var committed=game.profiles.commit(candidate)
 check(committed.ok,"fixture crate remains a durable valid profile")
 if not committed.ok: return false
 game._sync_crates()
 await tick.run(func(): game.player.position=crate.node.position+Vector3(0,-0.4,1.4))
 await frames(2)
 await tick.run(func(): game._interact())
 check(game.searching,"durable scene opens real crate")
 if not game.searching: return false
 game._advance_search(10.0)
 var loot=crate.items[0].duplicate(true)
 var raid_id=game.profiles.profile.active_raid.raid_id
 game._take_item(loot)
 var before_ammo=pack_quantity("ammo_rifle")
 var ammo_item={}
 for item in crate.items:
  if item.instance_id==ammo_id: ammo_item=item
 game._take_item(ammo_item)
 check(game.reserve==before_ammo+7 and pack_quantity("ammo_rifle")==game.reserve,"pickup publishes ammunition to runtime and pack")
 var expected_reserve=game.reserve
 var expected_loot=pack_quantity(loot.definition_id)
 var expected_search=encoded(game.profiles.profile.active_raid.search)
 var generation=game.profiles.saves.generation
 check(generation>3 and FileAccess.file_exists(fixture_root.path_join("profile_A.json")) and FileAccess.file_exists(fixture_root.path_join("profile_B.json")),"real play writes alternating JSON slots")
 # Deliberately no close-search/checkpoint: the pickup transaction itself must
 # be sufficient. Reconstruct the entire world and service from disk now.
 if not await boot(): return false
 check(game.profiles.profile.active_raid.raid_id==raid_id,"fresh scene resumes original raid")
 check(pack_quantity("ammo_rifle")==expected_reserve and game.reserve==expected_reserve,"immediate disk restart cannot lose freshly picked ammunition")
 check(pack_quantity(loot.definition_id)==expected_loot and game.profiles.inventory.owner_of(game.profiles.profile,loot.instance_id)=="raid_pack","picked collectible survives complete scene reconstruction")
 check(encoded(game.profiles.profile.active_raid.search)==expected_search,"fixed loot and search progress survive disk roundtrip")
 check(game.profiles.saves.generation>generation,"resumed checkpoint advances loaded generation")
 return true

func test_reload_parked() -> bool:
 game.ammo=10
 game.fire_delay=0
 check(game._checkpoint(),"partly empty magazine saved before reload")
 var reserve_before=pack_quantity("ammo_rifle")
 game._reload()
 await frames(8)
 var remaining=game.reload_time
 check(remaining>0,"reload has in-flight progress to preserve")
 game._save_and_return()
 var saved=encoded(game.profiles.profile)
 game._close_inventory() # Menu presentation disables the old runtime weapon.
 game._checkpoint() # Same checkpoint path as closing the app from camp.
 check(encoded(game.profiles.profile)==saved,"camp menu cannot overwrite parked reload with disabled weapon runtime")
 if not await boot(): return false
 check(is_equal_approx(game.reload_time,remaining) and game.ammo==10,"fresh scene restores parked reload duration and loaded rounds")
 check(game.reserve==reserve_before and pack_quantity("ammo_rifle")==reserve_before,"unfinished reload has not consumed ammunition")
 await frames(int(ceil(remaining*60))+2)
 check(game.ammo==24 and game.reserve==reserve_before-14 and pack_quantity("ammo_rifle")==reserve_before-14,"resumed reload consumes exactly fourteen real rounds")
 var total=game.ammo+game.reserve
 if not await boot(): return false
 check(game.ammo==24 and game.ammo+game.reserve==total and game.reserve==pack_quantity("ammo_rifle"),"completed reload disk restart preserves ammunition conservation")
 return true

func test_heal_parked() -> bool:
 var medicine=pack_quantity("medkit_basic")
 game.hp=55
 game._heal()
 await frames(8)
 var remaining=game.healing_remaining
 check(remaining>0,"healing has in-flight progress to preserve")
 game._save_and_return()
 var saved=encoded(game.profiles.profile)
 game._close_inventory()
 game._checkpoint()
 check(encoded(game.profiles.profile)==saved,"camp menu cannot erase parked healing progress")
 if not await boot(): return false
 check(game.hp==55 and is_equal_approx(game.healing_remaining,remaining),"fresh scene restores partial healing and health")
 check(game.meds==medicine and pack_quantity("medkit_basic")==medicine,"unfinished healing has not consumed a medkit")
 await frames(int(ceil(remaining*60))+2)
 check(game.hp==100 and game.meds==medicine-1 and pack_quantity("medkit_basic")==medicine-1,"resumed healing consumes one real medkit")
 if not await boot(): return false
 check(game.hp==100 and game.meds==medicine-1 and pack_quantity("medkit_basic")==medicine-1,"completed healing survives disk restart without refund or double consumption")
 return true

func test_practice_restart() -> bool:
 game._save_and_return()
 var saved=encoded(game.profiles.profile)
 var generation=game.profiles.saves.generation
 await tick.run(func(): game._reset(true))
 game.hp=50; game.ammo=1
 game._reload()
 await frames(int(ceil(game.weapon_runtime.definition.reload_duration*60))+2)
 game._heal()
 await frames(134)
 game._save_and_return()
 game._close_inventory()
 game._checkpoint()
 check(encoded(game.profiles.profile)==saved,"practice and its return menu cannot contaminate parked raid snapshot")
 # A safe no-op checkpoint may advance generation, but its payload must remain
 # exactly the parked raid; the next process is the actual durability check.
 check(game.profiles.saves.generation>=generation,"practice never rolls generation backwards")
 if not await boot(): return false
 check(game.hp==100 and game.ammo==24 and game.enemies.size()==9,"disk resume restores raid rather than practice combat state")
 check(game.reserve==pack_quantity("ammo_rifle") and game.meds==pack_quantity("medkit_basic"),"disk resume derives supplies from authoritative inventory")
 return true

func test_write_failure():
 var crate=game.crates[1]
 await tick.run(func(): game.player.position=crate.node.position+Vector3(0,-0.4,1.4))
 await frames(2)
 await tick.run(func(): game._interact())
 check(game.searching,"fault fixture opens a second crate")
 if not game.searching: return
 game._advance_search(10.0)
 var item=crate.items[0].duplicate(true)
 var before_quantity=pack_quantity(item.definition_id)
 var before=encoded(game.profiles.profile)
 var generation=game.profiles.saves.generation
 game.profiles.saves.fault_point="before_replace"
 game._take_item(item)
 check(game.save_failed and game.paused and not game.playing and not game.input_router.enabled,"failed disk pickup pauses gameplay and clears input")
 check(encoded(game.profiles.profile)==before and game.profiles.saves.generation==generation,"failed disk pickup does not publish candidate or generation")
 check(game.profiles.inventory.owner_of(game.profiles.profile,item.instance_id)==crate.cid,"failed disk pickup remains in its original crate")
 var observer=ProfileService.new()
 var loaded=observer.initialize(false,fixture_root,"")
 check(loaded.ok and observer.saves.generation==generation and observer.saves.canonical_json(observer.profile)==before,"fresh disk reader ignores failed temporary candidate")
 observer.saves.configure(fixture_root)
 game.profiles.saves.fault_point=""
 game._resume()
 check(not game.save_failed and game.playing and not game.paused,"clearing disk fault permits explicit save retry and resume")
 await tick.run(func(): game._interact())
 game._take_item(item)
 check(pack_quantity(item.definition_id)==before_quantity+int(item.quantity) and game.profiles.inventory.owner_of(game.profiles.profile,item.instance_id)!=crate.cid,"retry after recovery transfers or merges the item once")
 var expected=pack_quantity(item.definition_id)
 if not await boot(): return
 check(pack_quantity(item.definition_id)==expected,"successful recovery persists exactly one pickup")

func finish(success := true):
 if not success: failures+=1
 free_game()
 if is_instance_valid(tick): tick.queue_free()
 remove_fixture(fixture_root)
 print("PHASE3 DISK: %d/%d checks passed" % [checks-failures,checks])
 quit(1 if failures else 0)

func remove_fixture(path: String):
 var absolute=ProjectSettings.globalize_path(path).replace("\\","/")
 var allowed=ProjectSettings.globalize_path(fixture_root).replace("\\","/")
 var tests_root=ProjectSettings.globalize_path("res://tests").replace("\\","/")
 assert(allowed.begins_with(tests_root+"/.phase3-disk-"))
 assert(absolute==allowed or absolute.begins_with(allowed+"/"))
 var directory=DirAccess.open(path)
 if directory==null: return
 directory.include_hidden=true
 for name in directory.get_files(): DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(name)))
 for name in directory.get_directories(): remove_fixture(path.path_join(name))
 DirAccess.remove_absolute(absolute)
