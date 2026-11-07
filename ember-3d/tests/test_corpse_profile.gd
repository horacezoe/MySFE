extends SceneTree
## Corpse search transactions only use memory or a process-owned disk fixture.
const ProfileService=preload("res://scripts/raid/profile_service.gd")
const CID="loot_guard_00"
var checks=0
var failures=0
var fixture_root="res://tests/.corpse-profile-%s-%s" % [OS.get_process_id(),Time.get_ticks_usec()]
var disk_services=[]

func _initialize(): call_deferred("run")
func check(value: bool,label: String):
 checks+=1
 if not value: failures+=1; push_error("CORPSE PROFILE: "+label)

func memory(seed_value := 427) -> RefCounted:
 var service=ProfileService.new()
 service.initialize(true)
 service.begin_raid(seed_value)
 return service

func disk(path: String) -> RefCounted:
 var service=ProfileService.new()
 var result=service.initialize(false,path,"")
 check(result.ok,"isolated disk fixture initializes: "+str(result.get("reason","")))
 disk_services.append(service)
 return service

func json(value) -> String: return JSON.stringify(value,"",true)

func snapshot() -> Dictionary:
 var player_weapon={"ammo":9,"reserve":90,"reload_remaining":0.0,"cooldown":0.0,"shots_fired":12,"rng_state":"427"}
 var guards=[]
 for index in range(9):
  var weapon={"ammo":7,"reserve":72,"reload_remaining":0.0,"cooldown":0.0,"shots_fired":5,"rng_state":"528"}
  var brain={"state":"Patrol","last_known":[0,0,0],"aim_point":[0,1,0],"rng_state":"628","state_elapsed":0.0,"has_memory":false,"_route_index":0,"_waypoint_pause":0.0,"_reaction_remaining":0.0,"_burst_remaining":0,"_shot_wait":0.0,"_search_yaw":0.0}
  guards.append({"position":[index,0,0],"rotation_y":0.0,"health":{"hp":75.0,"head_armor":15.0,"body_armor":30.0},"weapon":weapon,"brain":brain})
 return {"player":{"position":[0,0,2],"velocity":[0,0,0],"yaw":0.0,"pitch":0.0,"third_person":true,"crouching":false,"health":{"hp":100.0,"head_armor":20.0,"body_armor":40.0},"weapon":player_weapon,"healing_remaining":0.0},"enemies":guards,"remaining":500.0,"extract_time":0.0,"extraction":{"exit_id":"","remaining":0.0},"kills":0,"deployment_grace":1.0}

func dead_candidate(service,indices: Array=[0]) -> Dictionary:
 var result=service.profile.duplicate(true)
 if result.active_raid.snapshot.is_empty(): result.active_raid.snapshot=snapshot()
 for index in indices:
  result.active_raid.snapshot.enemies[index].health.hp=0.0
  result.active_raid.snapshot.enemies[index].brain.state="Dead"
  result.active_raid.snapshot.enemies[index].weapon.reload_remaining=0.0
 return result

func find_item(service,cid: String,definition: String) -> Dictionary:
 for item in service.inventory.contents(service.profile,cid):
  if item.definition_id==definition: return service.profile.items[item.instance_id]
 return {}

func reveal_all(service,cid := CID):
 var candidate=service.profile.duplicate(true)
 candidate.active_raid.search[cid].opened=true
 candidate.active_raid.search[cid].revealed=candidate.active_raid.search[cid].order.size()
 candidate.active_raid.search[cid].elapsed=0.25
 check(service.commit(candidate).ok,"corpse reveal commits")

func transfer(service,item_id: String,command_id := "corpse-transfer") -> Dictionary:
 return {"command_id":command_id,"from":CID,"to":"raid_pack","item_id":item_id,"quantity":service.profile.items[item_id].quantity,"source_revision":service.profile.containers[CID].revision,"target_revision":service.profile.containers.raid_pack.revision}

func run():
 test_generation()
 test_visibility_and_identity()
 test_capacity()
 test_settlement()
 test_validation()
 test_disk_failure_and_restart()
 for service in disk_services: service.saves.configure(service.saves.root_path)
 disk_services.clear()
 cleanup(fixture_root)
 print("CORPSE PROFILE: %d/%d checks passed" % [checks-failures,checks])
 quit(1 if failures else 0)

func test_generation():
 var service=memory()
 check(not service.profile.containers.has(CID),"living guards have no searchable inventory")
 var before=json(service.profile)
 var candidate=dead_candidate(service,[0,1])
 candidate.active_raid.snapshot.enemies[0].health.head_armor=0.0
 candidate.active_raid.snapshot.enemies[0].health.body_armor=8.5
 candidate.active_raid.snapshot.enemies[0].weapon.ammo=3
 candidate.active_raid.snapshot.enemies[0].weapon.reserve=17
 var result=service.ensure_corpse_loot(candidate)
 check(result.ok and result.changed and result.created==2,"two deaths create two stable containers")
 check(json(service.profile)==before,"ensure never publishes its candidate")
 check(service.commit(candidate).ok,"death snapshot and physical loot commit together")
 check(service.profile.containers[CID].width==6 and service.profile.containers[CID].height==5,"corpse grid keeps standard searchable footprint")
 var search=service.profile.active_raid.search[CID]
 check(search.kind=="corpse" and search.guard_id=="guard_00" and search.revealed==0 and not search.opened,"initial corpse search is hidden and source-bound")
 check(find_item(service,CID,"rifle_basic").runtime.ammo==3,"weapon carries actual remaining magazine")
 check(find_item(service,CID,"helmet_light").durability==0.0 and find_item(service,CID,"vest_light").durability==8.5,"broken helmet and damaged vest retain actual durability")
 check(service.inventory.quantity(service.profile,CID,"ammo_rifle")==17,"remaining reserve is exact, never a fresh stack")
 for item in service.inventory.contents(service.profile,CID): check(not item.bound,"enemy loot is not starter-bound: "+item.definition_id)
 before=json(service.profile)
 check(service.commit(service.profile).ok and json(service.profile)==before,"repeat checkpoint cannot regenerate corpse items")
 var copy=service.profile.duplicate(true)
 check(not service.ensure_corpse_loot(copy).changed and json(copy)==before,"explicit repeated ensure is idempotent")
 var twin=memory()
 var same=dead_candidate(twin,[0,1])
 same.active_raid.snapshot.enemies[0]=candidate.active_raid.snapshot.enemies[0].duplicate(true)
 check(twin.commit(same).ok and json(service.profile.items)==json(twin.profile.items),"same raid seed and death snapshots generate identical inventory")
 var ids=service.profile.active_raid.search[CID].order
 for other in service.profile.active_raid.search.loot_guard_01.order: check(not ids.has(other),"different bodies have unique instance IDs")
 var legacy=memory()
 var old=dead_candidate(legacy)
 old.active_raid.map_id="legacy_v3"
 old.active_raid.snapshot.erase("extraction")
 old.active_raid.snapshot.enemies[0].weapon.reserve=90
 check(legacy.validate(old).ok,"old dead checkpoint without corpse metadata remains readable")
 check(legacy.commit(old).ok and legacy.inventory.quantity(legacy.profile,CID,"ammo_rifle")==90,"first normal checkpoint lazily adds legacy body without losing historical reserve")

func test_visibility_and_identity():
 var service=memory()
 service.commit(dead_candidate(service))
 var gun=find_item(service,CID,"rifle_basic")
 var request=transfer(service,gun.instance_id)
 var before=json(service.profile)
 check(service.execute(request).reason=="not_revealed" and json(service.profile)==before,"hidden corpse item cannot be transferred by ID")
 check(service.execute({"action":"take_all","from":CID,"to":"raid_pack","item_ids":[gun.instance_id]}).reason=="not_revealed","caller-supplied take-all selection cannot bypass reveal")
 service.execute({"action":"take_all","from":CID,"to":"raid_pack"})
 check(service.inventory.owner_of(service.profile,gun.instance_id)==CID,"take all only transfers currently revealed items")
 check(service.sort_container(CID).reason=="search_order_fixed","corpse reveal order cannot be sorted")
 reveal_all(service)
 request=transfer(service,gun.instance_id)
 check(service.execute(request).ok and service.inventory.owner_of(service.profile,gun.instance_id)=="raid_pack","revealed rifle enters pack with same identity")
 check(service.profile.items[gun.instance_id].runtime.ammo==7,"pickup never refills the gun")
 before=json(service.profile)
 check(service.execute(request).reason=="already_applied" and json(service.profile)==before,"duplicate item command cannot clone a recovered gun")
 check(service.commit(service.profile).ok and service.inventory.owner_of(service.profile,gun.instance_id)=="raid_pack","later checkpoints never pull transferred loot back")
 # Empty body tombstones remain valid after all items were independently taken.
 var state=service.profile.duplicate(true)
 var original=state.active_raid.search[CID].order.duplicate()
 for placement in state.containers[CID].placements: state.items.erase(placement.item_id)
 state.containers[CID].placements=[]
 check(service.commit(state).ok,"empty corpse state remains valid")
 check(service.commit(service.profile).ok and service.profile.containers[CID].placements.is_empty() and service.profile.active_raid.search[CID].order==original,"empty corpse remains empty on repeated save")

func test_capacity():
 var service=memory()
 service.commit(dead_candidate(service))
 reveal_all(service)
 var candidate=service.profile.duplicate(true)
 for placement in candidate.containers.raid_pack.placements: candidate.items.erase(placement.item_id)
 candidate.containers.raid_pack.placements=[]
 check(service.inventory.add_item(candidate,"loot_watch",60,"raid_pack").ok,"fixture fills all thirty backpack cells")
 check(service.commit(candidate).ok,"full pack fixture commits")
 var remaining=json(service.profile.containers[CID])
 var gun=find_item(service,CID,"rifle_basic")
 check(not service.execute(transfer(service,gun.instance_id)).ok,"full backpack refuses a rifle")
 service.execute({"action":"take_all","from":CID,"to":"raid_pack"})
 check(json(service.profile.containers[CID])==remaining,"failed take-all leaves every corpse item and revision intact")
 check(service.inventory.validate(service.profile).ok,"full-bag failure preserves unique ownership")
 # Check maximal supported reserve and seed variants always fit the grid.
 for seed_value in [0,1,9,73,427,9001]:
  var varied=memory(seed_value)
  var state=dead_candidate(varied)
  state.active_raid.snapshot.enemies[0].weapon.reserve=120
  check(varied.commit(state).ok and varied.inventory.quantity(varied.profile,CID,"ammo_rifle")==120,"max supported reserve fits corpse grid at seed "+str(seed_value))

func test_settlement():
 for success in [true,false]:
  var service=memory()
  service.commit(dead_candidate(service,[0,1]))
  reveal_all(service)
  var gun=find_item(service,CID,"rifle_basic")
  check(service.execute(transfer(service,gun.instance_id)).ok,"settlement fixture recovers enemy weapon")
  var unclaimed=service.profile.active_raid.search.loot_guard_01.order.duplicate()
  var raid_id=service.profile.active_raid.raid_id
  check(service.settle(raid_id,success).ok,"corpse-containing raid settles: "+str(success))
  check(service.profile.active_raid.is_empty() and not service.profile.containers.has(CID) and not service.profile.containers.has("loot_guard_01"),"settlement removes all corpse containers")
  for id in unclaimed: check(not service.profile.items.has(id),"unclaimed corpse item is discarded after raid")
  if success: check(service.inventory.owner_of(service.profile,gun.instance_id)=="stash_main" and service.profile.items[gun.instance_id].runtime.ammo==7,"extracted gun and ammunition survive in stash")
  else: check(not service.profile.items.has(gun.instance_id),"comfort still loses looted backpack weapon on death")
  var before=json(service.profile)
  check(service.settle(raid_id,success).reason=="already_settled" and json(service.profile)==before,"repeated settlement cannot recover corpse loot twice")

func test_validation():
 var service=memory()
 service.commit(dead_candidate(service))
 var before=json(service.profile)
 var mutations=[
  func(s): s.active_raid.snapshot.enemies[0].health.hp=1,
  func(s): s.active_raid.snapshot.enemies[0].brain.state="Patrol",
  func(s): s.active_raid.search[CID].guard_id="guard_01",
  func(s): s.active_raid.search[CID].kind="crate",
  func(s): s.active_raid.search[CID].order.append(s.active_raid.search[CID].order[0]),
  func(s): s.active_raid.search[CID].order.pop_back(),
  func(s): s.active_raid.search[CID].opened="true",
  func(s): s.active_raid.search[CID].elapsed=-1,
  func(s): s.active_raid.search[CID].revealed=100,
  func(s): s.containers[CID].width=7,
  func(s): s.containers[CID]="broken",
  func(s): s.active_raid.search.erase(CID),
  func(s): s.active_raid.search.loot_00.kind="corpse",
 ]
 for index in mutations.size():
  var candidate=service.profile.duplicate(true)
  mutations[index].call(candidate)
  var original=json(candidate)
  check(not service.ensure_corpse_loot(candidate).ok and json(candidate)==original,"malformed source refuses without candidate mutation: "+str(index))
  check(not service.commit(candidate).ok and json(service.profile)==before,"malformed corpse cannot publish: "+str(index))
 var fresh=memory()
 var bad=dead_candidate(fresh,[0,1])
 bad.active_raid.snapshot.enemies[1].weapon.reserve=121
 var unchanged=json(bad)
 check(not fresh.ensure_corpse_loot(bad).ok and json(bad)==unchanged,"failed second body rolls back first body's partial generation")
 check(not fresh.profile.containers.has(CID),"failed generation never publishes first body")

func test_disk_failure_and_restart():
 var service=disk(fixture_root)
 service.begin_raid(427)
 var candidate=dead_candidate(service)
 var before=json(service.profile)
 service.saves.fault_point="before_replace"
 check(not service.commit(candidate).ok and json(service.profile)==before,"failed disk death commit publishes no corpse or items")
 var restarted=disk(fixture_root)
 check(not restarted.profile.containers.has(CID) and restarted.profile.active_raid.snapshot.is_empty(),"restart after failed commit sees prior live snapshot")
 service.saves.fault_point=""
 check(service.commit(candidate).ok,"retry persists death and loot together")
 restarted=disk(fixture_root)
 check(restarted.profile.active_raid.snapshot.enemies[0].health.hp==0 and restarted.profile.containers.has(CID),"fresh disk reader restores searchable dead body")
 reveal_all(restarted)
 var gun=find_item(restarted,CID,"rifle_basic")
 check(restarted.execute(transfer(restarted,gun.instance_id)).ok,"corpse pickup persists on disk")
 var after=disk(fixture_root)
 check(after.inventory.owner_of(after.profile,gun.instance_id)=="raid_pack","fresh reader preserves transferred corpse item identity")
 check(after.profile.active_raid.search[CID].revealed==after.profile.active_raid.search[CID].order.size() and after.profile.active_raid.search[CID].elapsed==0.25,"restart preserves reveal count and partial timer")
 check(after.commit(after.profile).ok and after.inventory.owner_of(after.profile,gun.instance_id)=="raid_pack","restart and checkpoint cannot respawn looted rifle")

func cleanup(path: String):
 var absolute=ProjectSettings.globalize_path(path).replace("\\","/")
 var expected=ProjectSettings.globalize_path(fixture_root).replace("\\","/")
 if absolute!=expected and not absolute.begins_with(expected+"/"): return
 var directory=DirAccess.open(path)
 if directory==null: return
 for file in directory.get_files(): DirAccess.remove_absolute(path.path_join(file))
 for folder in directory.get_directories(): cleanup(path.path_join(folder))
 DirAccess.remove_absolute(path)
