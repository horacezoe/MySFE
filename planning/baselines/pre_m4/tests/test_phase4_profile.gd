extends SceneTree
## Campaign transactions use process-owned fixtures only, never user_data.
const ProfileService=preload("res://scripts/raid/profile_service.gd")
const SaveService=preload("res://scripts/save/save_service.gd")
var checks=0
var failures=0
var fixture_root="res://tests/.phase4-profile-"+str(OS.get_process_id())
var durable_services=[]

func _initialize(): call_deferred("run_tests")
func check(condition: bool,label: String):
 checks+=1
 if not condition:
  failures+=1; push_error("CAMPAIGN: "+label)

func memory() -> RefCounted:
 var service=ProfileService.new(); service.initialize(true); return service

func disk(name: String) -> RefCounted:
 var service=ProfileService.new(); service.initialize(false,fixture_root.path_join(name),"")
 durable_services.append(service)
 return service

func text_of(service) -> String: return service.saves.canonical_json(service.profile)

func add(service,id: String,amount: int,cid := "stash_main",extra: Dictionary={}) -> Dictionary:
 var candidate=service.profile.duplicate(true)
 var added=service.inventory.add_item(candidate,id,amount,cid,extra)
 if not added.ok: return added
 return service.commit(candidate)

func run_tests():
 test_rules_and_loot()
 test_collection()
 test_field_missions()
 test_loss_rules()
 test_atomic_failures()
 test_migration()
 test_invalid_campaign()
 for service in durable_services: service.saves.configure(service.saves.root_path)
 durable_services.clear()
 remove_fixture(fixture_root)
 print("PHASE4 PROFILE: %d/%d checks passed" % [checks-failures,checks])
 quit(1 if failures else 0)

func test_rules_and_loot():
 var service=memory()
 check(service.profile.profile_version==2 and service.profile.settings.difficulty=="comfort","new profile defaults to comfort campaign schema")
 check(service.missions.definitions().size()==3 and service.profile.missions.size()==3,"three stable mission definitions and states")
 var comfort=service.rules.get_rule("comfort"); var standard=service.rules.get_rule("standard")
 check(comfort.duration==600 and comfort.enemy_damage_scale<standard.enemy_damage_scale and comfort.enemy_reaction_time>standard.enemy_reaction_time,"comfort grants time and lowers enemy pressure")
 check(comfort.death_keep_equipment and not standard.death_keep_equipment,"loss rules are explicit frozen data")
 check(service.set_difficulty("standard").ok and service.profile.settings.difficulty=="standard","camp difficulty selection commits")
 var before=text_of(service)
 check(not service.set_difficulty("unknown").ok and text_of(service)==before,"unknown difficulty cannot mutate profile")
 check(service.begin_raid(541).ok,"campaign deployment commits")
 var active=service.profile.active_raid
 check(active.map_id=="depot_v1" and active.rule_id=="standard" and active.rule_version=="rules_1","deployment freezes map and rule identity")
 check(not service.set_difficulty("comfort").ok and service.profile.active_raid.rule_id=="standard","difficulty cannot change an active raid")
 check(service.inventory.quantity(service.profile,"loot_06","depot_pass")==1,"guarded archive contains one guaranteed freight pass")
 check(service.inventory.quantity(service.profile,"loot_00","loot_medical")>=1 and service.inventory.quantity(service.profile,"loot_05","loot_medical")>=1,"two low-risk containers guarantee collect mission supplies")
 for index in range(15):
  var cid="loot_%02d" % index
  var allowed=["loot_chip","loot_watch","loot_alloy","depot_pass"]
  if index in [0,1,5,10]: allowed=["loot_medical","loot_ration","loot_parts"]
  elif index in [2,3,4,7,11,12]: allowed=["loot_battery","loot_electronics","loot_parts"]
  var correct=true
  for item in service.inventory.contents(service.profile,cid):
   if not allowed.has(item.definition_id): correct=false
  check(correct,"loot pool matches zone risk: "+cid)
 var twin=memory(); twin.set_difficulty("standard"); twin.begin_raid(541)
 check(service.saves.canonical_json(service.profile.items)==twin.saves.canonical_json(twin.profile.items),"fixed seed yields identical physical loot")

func test_collection():
 var service=memory()
 check(not service.claim_mission("collect_medical").ok,"cannot claim an unaccepted mission")
 check(service.accept_mission("collect_medical").ok,"collect mission can be accepted")
 var before=text_of(service)
 check(service.accept_mission("collect_medical").reason=="already_accepted" and text_of(service)==before,"repeat accept is a no-op")
 check(not service.claim_mission("collect_medical").ok,"missing materials cannot award currency")
 add(service,"loot_medical",2,"stash_main",{"bound":true})
 check(service.profile.missions.collect_medical.progress==0 and not service.claim_mission("collect_medical").ok,"bound supplies never satisfy collection")
 add(service,"loot_medical",1)
 add(service,"loot_medical",2,"overflow")
 check(service.profile.missions.collect_medical.status=="ready" and service.profile.missions.collect_medical.progress==2,"eligible quantities combine stash and overflow")
 var currency=service.profile.currency
 check(service.claim_mission("collect_medical").ok,"collection delivery commits atomically")
 check(service.profile.currency==currency+400 and service.profile.missions.collect_medical.status=="claimed","collection credits exactly one reward")
 check(service._eligible_quantity(service.profile,"loot_medical")==1,"collection consumes exact required quantity")
 check(service.inventory.quantity(service.profile,"stash_main","loot_medical")==2,"bound copies remain untouched")
 before=text_of(service)
 check(service.claim_mission("collect_medical").reason=="already_claimed" and text_of(service)==before,"repeat collection delivery cannot debit or award twice")
 var selling=memory(); selling.accept_mission("collect_medical"); add(selling,"loot_medical",2)
 var id=""
 for item in selling.inventory.contents(selling.profile,"stash_main"):
  if item.definition_id=="loot_medical": id=item.instance_id
 check(selling.sell(id,1).ok and selling.profile.missions.collect_medical.status=="active" and selling.profile.missions.collect_medical.progress==1,"selling required materials correctly removes readiness")
 before=text_of(selling)
 check(not selling.claim_mission("collect_medical").ok and text_of(selling)==before,"stale ready UI cannot claim sold material")

func test_field_missions():
 var service=memory()
 service.begin_raid(71)
 var candidate=service.profile.duplicate(true)
 check(not service.record_event(candidate,"visit","signal_station").changed,"unaccepted visits do not accumulate")
 check(not service.record_event(candidate,"kill","guard_06").changed,"unaccepted kills do not accumulate")
 check(not service.accept_mission("survey_depot").ok,"cannot accept missions after visiting during a raid")
 service.settle(service.profile.active_raid.raid_id,true)
 check(service.profile.missions.survey_depot.status=="available","old unaccepted event does not become progress")
 service.accept_mission("survey_depot"); service.accept_mission("eliminate_officer"); service.quick_equip(); service.begin_raid(72)
 candidate=service.profile.duplicate(true)
 check(not service.record_event(candidate,"kill","guard_05").changed,"wrong guard cannot advance officer task")
 check(service.record_event(candidate,"visit","signal_station").changed,"accepted visit records one raid event")
 check(service.record_event(candidate,"kill","guard_06").changed,"accepted officer kill records one raid event")
 check(not service.record_event(candidate,"visit","signal_station").changed and not service.record_event(candidate,"kill","guard_06").changed,"duplicate event delivery is idempotent")
 check(service.commit(candidate).ok,"field events can checkpoint")
 check(service.profile.missions.survey_depot.progress==0 and service.profile.missions.eliminate_officer.progress==0,"field events await successful extraction")
 check(not service.claim_mission("survey_depot").ok,"field task cannot be claimed during combat")
 service.settle(service.profile.active_raid.raid_id,false)
 check(service.profile.missions.survey_depot.status=="active" and service.profile.missions.eliminate_officer.status=="active","failure discards field progress")
 service.quick_equip(); service.begin_raid(73)
 candidate=service.profile.duplicate(true)
 service.record_event(candidate,"visit","signal_station"); service.record_event(candidate,"kill","guard_06")
 var raid_id=candidate.active_raid.raid_id
 check(service.settle(raid_id,true,candidate).ok,"field progress and physical extraction settle together")
 check(service.profile.missions.survey_depot.status=="ready" and service.profile.missions.eliminate_officer.status=="ready","successful field tasks become claimable in camp")
 var currency=service.profile.currency
 check(service.claim_mission("survey_depot").ok and service.claim_mission("eliminate_officer").ok,"field task rewards can be delivered")
 check(service.profile.currency==currency+1200,"field rewards are exactly 500 plus 700")
 var before=text_of(service)
 check(service.settle(raid_id,true).reason=="already_settled" and service.claim_mission("survey_depot").reason=="already_claimed" and text_of(service)==before,"duplicate raid and task delivery cannot award again")

func test_loss_rules():
 for difficulty in ["comfort","standard"]:
  var service=memory(); service.set_difficulty(difficulty); service.begin_raid(113)
  var equipment=service.equipment(service.profile,"weapon").instance_id
  var pack_ids=[]
  for item in service.inventory.contents(service.profile,"raid_pack"): pack_ids.append(item.instance_id)
  var result=service.settle(service.profile.active_raid.raid_id,false)
  check(result.ok and service.profile.wins==0,"failure settles without victory: "+difficulty)
  check(service.profile.items.has(equipment)==(difficulty=="comfort"),"correct equipped rifle retention: "+difficulty)
  var pack_gone=true
  for id in pack_ids:
   if service.profile.items.has(id): pack_gone=false
  check(pack_gone,"backpack supplies are lost in both rules: "+difficulty)
  check(service.profile.active_raid.is_empty() and service.validate(service.profile).ok,"loss leaves valid camp ownership: "+difficulty)
  if difficulty=="comfort":
   check(service.inventory.owner_of(service.profile,equipment)=="stash_main","retained equipment returns physically to warehouse")
   service.quick_equip()
   check(service.equipment(service.profile,"weapon",false).instance_id==equipment,"comfort reuses retained rifle instead of duplicating relief")
 var full=memory()
 var candidate=full.profile.duplicate(true)
 full._remove_container(candidate,"stash_main"); candidate.containers.stash_main=full.inventory.make_grid(1,1)
 full.inventory.add_item(candidate,"loot_watch",1,"stash_main"); full.commit(candidate); full.begin_raid(114)
 var rifle=full.equipment(full.profile,"weapon").instance_id
 check(full.settle(full.profile.active_raid.raid_id,false).ok and full.inventory.owner_of(full.profile,rifle)=="overflow","comfort loss cannot delete equipment when warehouse is full")

func test_atomic_failures():
 var service=disk("atomic")
 service.saves.fault_point="before_write"
 var before=text_of(service)
 check(not service.accept_mission("collect_medical").ok and text_of(service)==before,"accept failure does not publish task state")
 check(not service.set_difficulty("standard").ok and text_of(service)==before,"rule selection failure leaves original rule")
 service.saves.fault_point=""; service.accept_mission("collect_medical"); add(service,"loot_medical",2)
 before=text_of(service)
 for fault in ["before_write","after_write","before_replace"]:
  service.saves.fault_point=fault
  check(not service.claim_mission("collect_medical").ok and text_of(service)==before,"reward failure rolls back materials and money: "+fault)
  var restarted=disk("atomic")
  check(text_of(restarted)==before,"restart ignores incomplete reward snapshot: "+fault)
 service.saves.fault_point=""
 check(service.claim_mission("collect_medical").ok,"reward retry succeeds once storage recovers")
 var restarted=disk("atomic"); var currency=restarted.profile.currency
 check(restarted.claim_mission("collect_medical").reason=="already_claimed" and restarted.profile.currency==currency,"reward idempotency survives restart")
 service.accept_mission("survey_depot"); service.begin_raid(512)
 var candidate=service.profile.duplicate(true); service.record_event(candidate,"visit","signal_station"); service.commit(candidate)
 restarted=disk("atomic")
 check(restarted.profile.active_raid.events.visits==["signal_station"],"field event survives true disk restart")
 check(restarted.profile.active_raid.rule_id=="comfort","frozen rule survives disk restart")
 before=text_of(restarted); restarted.saves.fault_point="before_replace"
 check(not restarted.settle(restarted.profile.active_raid.raid_id,true).ok and text_of(restarted)==before,"failed settlement does not publish ready mission")
 restarted.saves.fault_point=""; restarted.settle(restarted.profile.active_raid.raid_id,true)
 var settled=disk("atomic")
 check(settled.profile.missions.survey_depot.status=="ready","successful extraction progress survives restart")

func legacy_profile(active := false) -> Dictionary:
 var service=memory()
 if active: service.begin_raid(901)
 var old=service.profile.duplicate(true)
 old.profile_version=1; old.erase("missions"); old.erase("mission_version"); old.settings.erase("difficulty")
 old.currency=7777; old.wins=9
 if active:
  for key in ["map_id","rule_id","rule_version","events","mission_ids"]: old.active_raid.erase(key)
  old.active_raid.snapshot=legacy_snapshot()
  for placement in old.containers.loot_06.placements.duplicate(true):
   if old.items[placement.item_id].definition_id=="depot_pass":
    old.items.erase(placement.item_id); old.containers.loot_06.placements.erase(placement); old.active_raid.search.loot_06.order.erase(placement.item_id)
 return old

func legacy_snapshot() -> Dictionary:
 var weapon={"ammo":7,"reserve":90,"reload_remaining":0.77,"cooldown":0.0,"shots_fired":17,"rng_state":"-1234567890123456"}
 var health={"hp":61.0,"head_armor":12.0,"body_armor":27.0}
 var guards=[]
 for index in range(9):
  var brain={"state":"Dead" if index==6 else "Investigate","last_known":[-22.5,0,-22.5],"aim_point":[-22.5,1.05,-22.5],"rng_state":"56789012345678","state_elapsed":2.5,"has_memory":true,"_route_index":0,"_waypoint_pause":0.0,"_reaction_remaining":0.2,"_burst_remaining":0,"_shot_wait":0.0,"_search_yaw":0.1}
  guards.append({"position":[-18.0+index,0,-19.0],"rotation_y":1.4,"health":{"hp":0.0 if index==6 else 75.0,"head_armor":15.0,"body_armor":30.0},"weapon":weapon.duplicate(true),"brain":brain})
 return {"player":{"position":[-22.0,0,-23.5],"velocity":[0,0,0],"yaw":-2.35,"pitch":-0.1,"third_person":true,"crouching":true,"health":health,"weapon":weapon,"healing_remaining":0.0},"enemies":guards,"remaining":283.75,"extract_time":2.5,"kills":1,"deployment_grace":0.0}

func write_old(name: String,old: Dictionary,generation := 8) -> Dictionary:
 var saver=SaveService.new(); saver.configure(fixture_root.path_join(name))
 var record={"schema_version":1,"content_version":"phase3_1","generation":generation,"payload":old}
 record.record_sha256=saver.canonical_json(record).sha256_text()
 var raw=saver.canonical_json(record)
 write_text(saver.root_path.path_join("profile_A.json"),raw)
 var second=record.duplicate(true); second.generation=generation-1; second.erase("record_sha256"); second.record_sha256=saver.canonical_json(second).sha256_text()
 var raw_b=saver.canonical_json(second); write_text(saver.root_path.path_join("profile_B.json"),raw_b)
 return {"a":raw,"b":raw_b,"path":saver.root_path}

func test_migration():
 for active in [false,true]:
  var name="migration_active" if active else "migration_camp"
  var old=legacy_profile(active); var source=write_old(name,old)
  var service=disk(name)
  check(not service.blocked and service.profile.profile_version==2,"phase3 profile migrates safely: "+name)
  check(service.profile.currency==7777 and service.profile.wins==9,"migration preserves currency and wins: "+name)
  check(service.saves.canonical_json(service.profile.items)==service.saves.canonical_json(old.items),"migration does not regrant or replace physical items: "+name)
  check(service.profile.settings.difficulty=="standard","migration preserves previous loss difficulty")
  check(FileAccess.get_file_as_string(source.path.path_join("phase3_g00000008_profile_A.json"))==source.a and FileAccess.get_file_as_string(source.path.path_join("phase3_g00000008_profile_B.json"))==source.b,"migration keeps byte-identical backups of both old slots")
  if active:
   check(service.profile.active_raid.map_id=="legacy_v3" and service.profile.active_raid.rule_id=="standard","ongoing old raid stays on old layout and rules")
   check(service.saves.canonical_json(service.profile.active_raid.snapshot)==service.saves.canonical_json(old.active_raid.snapshot) and service.saves.canonical_json(service.profile.active_raid.search)==service.saves.canonical_json(old.active_raid.search),"migration preserves checkpoint and already generated loot")
   check(service.profile.active_raid.mission_ids.is_empty(),"migration cannot retroactively accept missions")
   check(service.profile.active_raid.snapshot.player.weapon.reload_remaining==0.77 and service.profile.active_raid.snapshot.enemies[6].health.hp==0 and not service.profile.active_raid.snapshot.has("extraction"),"legacy partial reload, dead guard and old extraction format remain recoverable")
  var before=text_of(service); var generation=service.saves.generation
  var restarted=disk(name)
  check(text_of(restarted)==before and restarted.saves.generation==generation,"migration runs once without later starter or save churn")
 var old=legacy_profile(true); var source=write_old("migration_failure",old)
 # Block the would-be temporary destination. The old files and backups survive.
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(source.path.path_join("profile_B.json.tmp")))
 var failed=disk("migration_failure")
 check(failed.blocked and failed.profile.is_empty(),"failed upgrade is blocked instead of publishing uncommitted schema")
 check(FileAccess.get_file_as_string(source.path.path_join("profile_A.json"))==source.a and FileAccess.get_file_as_string(source.path.path_join("profile_B.json"))==source.b,"failed upgrade preserves both phase3 slots exactly")
 DirAccess.remove_absolute(ProjectSettings.globalize_path(source.path.path_join("profile_B.json.tmp")))
 var recovered=disk("migration_failure")
 check(not recovered.blocked and recovered.profile.profile_version==2,"blocked migration can retry after storage recovers")
 var future=legacy_profile(); future.profile_version=99; write_old("future_profile",future)
 var quarantined=disk("future_profile")
 check(quarantined.blocked and quarantined.profile.is_empty(),"future profile schema cannot be silently downgraded")

func test_invalid_campaign():
 var service=memory(); var baseline=text_of(service)
 var mutations=[
  func(s): s.settings.difficulty="impossible",
  func(s): s.mission_version="missions_99",
  func(s): s.missions.erase("survey_depot"),
  func(s): s.missions.survey_depot.status="claimed",
  func(s): s.missions.survey_depot.progress=0.5,
 ]
 for mutate in mutations:
  var candidate=service.profile.duplicate(true); mutate.call(candidate)
  check(not service.commit(candidate).ok and text_of(service)==baseline,"invalid mission or rule metadata is rejected atomically")
 service.accept_mission("survey_depot"); service.begin_raid(81); baseline=text_of(service)
 mutations=[
  func(s): s.active_raid.map_id="unknown_map",
  func(s): s.active_raid.rule_id="unknown_rule",
  func(s): s.active_raid.rule_version="rules_99",
  func(s): s.active_raid.events.visits=["signal_station","signal_station"],
  func(s): s.active_raid.events.kills=["guard_99"],
  func(s): s.active_raid.mission_ids=["unknown_task"],
 ]
 for mutate in mutations:
  var candidate=service.profile.duplicate(true); mutate.call(candidate)
  check(not service.commit(candidate).ok and text_of(service)==baseline,"invalid active-raid metadata is rejected atomically")

func write_text(path: String,contents: String):
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
 var file=FileAccess.open(path,FileAccess.WRITE); assert(file!=null)
 file.store_string(contents); file.close()

func remove_fixture(path: String):
 var absolute=ProjectSettings.globalize_path(path).replace("\\","/")
 var allowed=ProjectSettings.globalize_path(fixture_root).replace("\\","/")
 assert(absolute==allowed or absolute.begins_with(allowed+"/"))
 var directory=DirAccess.open(path)
 if directory==null: return
 directory.include_hidden=true
 for name in directory.get_files(): DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(name)))
 for name in directory.get_directories(): remove_fixture(path.path_join(name))
 DirAccess.remove_absolute(absolute)
