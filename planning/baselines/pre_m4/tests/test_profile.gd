extends SceneTree
const ProfileService = preload("res://scripts/raid/profile_service.gd")
var checks = 0
var failures = 0
var fixture_root = "res://tests/.profile-fixtures-" + str(OS.get_process_id())
var durable_services: Array = []

class PhysicsTask:
	extends Node
	signal completed
	var pending: Callable
	func run(callback: Callable):
		pending = callback
		await completed
	func _physics_process(_delta):
		if pending.is_valid():
			var callback = pending
			pending = Callable()
			callback.call()
			completed.emit()

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func memory() -> RefCounted:
	var service = ProfileService.new()
	service.initialize(true)
	return service

func durable(name: String, legacy_path: String = "") -> RefCounted:
	var service = ProfileService.new()
	service.initialize(false, fixture_root.path_join(name), legacy_path)
	durable_services.append(service)
	return service

func encoded(service: RefCounted) -> String:
	return service.saves.canonical_json(service.profile)

func reveal(service: RefCounted, cid: String, count: int = 1) -> Dictionary:
	var candidate = service.profile.duplicate(true)
	candidate.active_raid.search[cid].opened = true
	candidate.active_raid.search[cid].revealed = mini(count, candidate.active_raid.search[cid].order.size())
	candidate.active_raid.search[cid].elapsed = float(count)
	return service.commit(candidate)

func first_id(service: RefCounted, cid: String, definition_id: String = "") -> String:
	for item in service.inventory.contents(service.profile, cid):
		if definition_id.is_empty() or item.definition_id == definition_id:
			return item.instance_id
	return ""

func transfer(service: RefCounted, id: String, from: String, to: String, quantity: int = 1) -> Dictionary:
	return service.execute({"action": "move", "item_id": id, "quantity": quantity, "from": from, "to": to})

func run_tests() -> void:
	var fresh = memory()
	check(fresh.validate(fresh.profile).ok, "starter profile passes ownership, placement and ledger validation")
	check(fresh.profile.currency == 1500 and fresh.profile.wins == 0, "new profile starts with defined currency and wins")
	check(fresh.profile.migration.starter_granted and not fresh.profile.migration.legacy_imported, "starter marker is persisted separately from legacy migration")
	var starter_rifle = fresh.equipment(fresh.profile, "weapon", false)
	check(starter_rifle.definition_id == "rifle_basic" and starter_rifle.bound, "starter rifle occupies weapon slot and is non-sellable")
	check(fresh.inventory.quantity(fresh.profile, "loadout_pack", "ammo_rifle") == 90, "starter combat ammunition is physical inventory")
	check(fresh.inventory.quantity(fresh.profile, "loadout_pack", "medkit_basic") == 3 and fresh.inventory.quantity(fresh.profile, "stash_main", "medkit_basic") == 3, "raid and stash medicines have separate ownership")
	var before = encoded(fresh)
	var invalid = fresh.profile.duplicate(true)
	invalid.currency = -10
	check(not fresh.commit(invalid).ok and encoded(fresh) == before, "invalid profile candidate is never published")
	check(fresh.begin_raid(12345).ok, "equipped profile can deploy")
	check(fresh.profile.active_raid.search.size() == 15, "deployment fixes every search container's contents")
	check(not fresh.profile.containers.has("loadout_pack") and fresh.profile.containers.has("raid_pack"), "deployment transfers loadout ownership to raid")
	check(fresh.equipment(fresh.profile, "weapon").instance_id == starter_rifle.instance_id, "deployment preserves equipment instance identity")
	check(not fresh.begin_raid(12345).ok, "a second deployment cannot overwrite an active raid")
	var twin = memory()
	twin.begin_raid(12345)
	check(twin.saves.canonical_json(twin.profile.active_raid.search) == fresh.saves.canonical_json(fresh.profile.active_raid.search), "same raid seed yields stable container search order")
	for cid in fresh.profile.active_raid.search:
		check(fresh.profile.containers[cid] == twin.profile.containers[cid], "same seed fixes loot placement: " + cid)
	var cid = "loot_00"
	var order = fresh.profile.active_raid.search[cid].order.duplicate()
	var loot_id = order[0]
	var loot_definition = fresh.profile.items[loot_id].definition_id
	before = encoded(fresh)
	var hidden = transfer(fresh, loot_id, cid, "raid_pack")
	check(not hidden.ok and hidden.reason == "not_revealed" and encoded(fresh) == before, "hidden item cannot be picked up or mutate profile")
	check(not fresh.sort_container(cid).ok, "sorting cannot reroll fixed search order")
	check(reveal(fresh, cid).ok and fresh.revealed_ids(cid) == [loot_id], "search reveals only persisted prefix")
	check(fresh.profile.active_raid.search[cid].order == order, "revealing items preserves their original order")
	var forged = {"action": "take_all", "from": cid, "to": "raid_pack", "item_ids": order}
	check(fresh.execute(forged).reason == "not_revealed", "supplied batch selection cannot bypass hidden-item restriction")
	check(transfer(fresh, loot_id, cid, "raid_pack").ok, "revealed collectible can move into the backpack")
	check(fresh.inventory.quantity(fresh.profile, "raid_pack", loot_definition) >= 1, "picked-up item is physically owned by raid backpack")
	check(fresh.profile.currency == 1500, "picking up valuables does not convert them into currency")
	check(not transfer(fresh, starter_rifle.instance_id, "raid_equipment", "raid_pack").ok, "equipped combat weapon cannot be moved during raid")
	check(not transfer(fresh, first_id(fresh, "stash_main"), "stash_main", "raid_pack").ok, "stash cannot teleport supplies into an active raid")
	before = encoded(fresh)
	check(not transfer(fresh, first_id(fresh, "stash_main"), "stash_main", "stash_main").ok and encoded(fresh) == before, "active raid also blocks transfers entirely within camp stash")
	check(fresh.sort_container("stash_main").reason == "active_raid_exists" and encoded(fresh) == before, "active raid blocks camp sorting at service boundary")
	check(fresh.purchase("ammo_rifle").reason == "active_raid_exists" and encoded(fresh) == before, "active raid blocks purchasing at service boundary")
	check(fresh.sell(first_id(fresh, "stash_main"), 1).reason == "active_raid_exists" and encoded(fresh) == before, "active raid blocks selling at service boundary")
	check(fresh.sort_container("raid_pack").ok, "active raid still permits backpack organization")
	var pack_item = first_id(fresh, "raid_pack")
	check(transfer(fresh, pack_item, "raid_pack", "raid_pack").ok, "active raid still permits movement within backpack")
	var raid_id = fresh.profile.active_raid.raid_id
	var stash_before = fresh.inventory.quantity(fresh.profile, "stash_main", loot_definition)
	check(fresh.settle(raid_id, true).ok, "successful extraction settles")
	check(fresh.profile.active_raid.is_empty() and fresh.profile.wins == 1, "successful extraction closes active raid and increments wins")
	check(fresh.inventory.quantity(fresh.profile, "stash_main", loot_definition) == stash_before + 1, "extracted collectible enters stash as an item")
	check(fresh.inventory.owner_of(fresh.profile, starter_rifle.instance_id) == "stash_main", "extraction returns exact weapon instance to stash")
	check(fresh.profile.currency == 1500, "successful extraction does not automatically sell loot")
	check(fresh.profile.containers.loadout_pack.revision > 0 and fresh.profile.containers.loadout_equipment.revision > 0, "settlement does not reset reused container revision numbers")
	before = encoded(fresh)
	check(fresh.settle(raid_id, true).reason == "already_settled" and encoded(fresh) == before, "duplicate extraction cannot duplicate items or wins")
	check(not fresh.settle("missing-raid", true).ok, "unknown raid cannot settle")
	check(fresh.quick_equip().ok and fresh.equipment(fresh.profile, "weapon", false).instance_id == starter_rifle.instance_id, "quick equip reuses recovered rifle rather than minting a new one")
	before = encoded(fresh)
	var quantity_before = fresh.profile.items.size()
	check(fresh.quick_equip().ok and fresh.profile.items.size() == quantity_before, "repeated quick equip cannot duplicate equipment")
	var retried = memory()
	retried.begin_raid(321)
	reveal(retried, "loot_00")
	var retry_id = retried.revealed_ids("loot_00")[0]
	var retry_command = {"action": "move", "item_id": retry_id, "quantity": 1, "from": "loot_00", "to": "raid_pack", "item_ids": [retry_id], "command_id": "retry-original-command", "source_revision": retried.profile.containers.loot_00.revision, "target_revision": retried.profile.containers.raid_pack.revision}
	check(retried.execute(retry_command).ok, "complete command succeeds once")
	reveal(retried, "loot_00", 99)
	before = encoded(retried)
	check(retried.execute(retry_command).reason == "already_applied" and encoded(retried) == before, "complete command retry is idempotent after further search reveals")
	var previous_pack_revision = retried.profile.containers.raid_pack.revision
	var previous_equipment_revision = retried.profile.containers.raid_equipment.revision
	retried.settle(retried.profile.active_raid.raid_id, false)
	check(retried.profile.containers.loadout_pack.revision > previous_pack_revision and retried.profile.containers.loadout_equipment.revision > previous_equipment_revision, "death also advances reused container revisions")
	retried.quick_equip()
	retried.begin_raid(322)
	check(retried.profile.containers.raid_pack.revision > previous_pack_revision and retried.profile.containers.raid_equipment.revision > previous_equipment_revision, "next raid cannot match old container revisions")

	var death = memory()
	death.set_difficulty("standard") # Preserve phase-three full-loss regression.
	var original_stash = death.profile.containers.stash_main.duplicate(true)
	death.begin_raid(8)
	var dead_rifle = death.equipment(death.profile, "weapon").instance_id
	var dead_raid = death.profile.active_raid.raid_id
	check(death.settle(dead_raid, false).ok, "failed raid settles")
	check(not death.profile.items.has(dead_rifle) and death.profile.wins == 0, "death removes carried equipment without awarding a win")
	check(death.profile.containers.stash_main == original_stash, "death preserves pre-existing stash")
	check(death.inventory.contents(death.profile, "loadout_pack").is_empty(), "death empties the combat loadout")
	check(not death.begin_raid(9).ok, "empty loadout cannot deploy without a rifle")
	check(death.quick_equip().ok, "relief kit lets offline player recover after losing all rifles")
	var relief = death.equipment(death.profile, "weapon", false)
	check(relief.bound and relief.instance_id != dead_rifle, "relief weapon has a new identity and cannot be sold")
	check(transfer(death, relief.instance_id, "loadout_equipment", "stash_main").ok, "relief item can be stored normally")
	before = encoded(death)
	check(death.sell(relief.instance_id, 1).reason == "bound_item" and encoded(death) == before, "bound relief items cannot generate currency")
	check(death.quick_equip().ok and death.equipment(death.profile, "weapon", false).instance_id == relief.instance_id, "stored relief weapon is reused")

	var shop = memory()
	var old_ammo = shop.inventory.quantity(shop.profile, "stash_main", "ammo_rifle")
	check(shop.purchase("ammo_rifle").ok and shop.profile.currency == 1380, "buying ammunition debits configured price")
	check(shop.inventory.quantity(shop.profile, "stash_main", "ammo_rifle") == old_ammo + 60, "purchase adds physical stack quantity")
	var ammo_id = first_id(shop, "stash_main", "ammo_rifle")
	check(shop.sell(ammo_id, 10).ok and shop.profile.currency == 1400, "explicit partial sale is the point currency is earned")
	check(shop.inventory.quantity(shop.profile, "stash_main", "ammo_rifle") == old_ammo + 50, "partial sale removes exact quantity")
	before = encoded(shop)
	check(not shop.sell(ammo_id, 1000).ok and encoded(shop) == before, "over-sale is rejected atomically")
	check(not shop.purchase("invalid_definition").ok and encoded(shop) == before, "invalid shop offer changes nothing")
	var poor = shop.profile.duplicate(true)
	poor.currency = 0
	shop.commit(poor)
	before = encoded(shop)
	check(not shop.purchase("rifle_basic").ok and encoded(shop) == before, "insufficient funds cannot create an item")

	var full = memory()
	var tiny = full.profile.duplicate(true)
	full._remove_container(tiny, "stash_main")
	tiny.containers.stash_main = full.inventory.make_grid(1, 1)
	check(full.inventory.add_item(tiny, "loot_watch", 1, "stash_main").ok and full.commit(tiny).ok, "full-stash fixture obeys actual grid constraints")
	full.begin_raid(22)
	var full_raid = full.profile.active_raid.raid_id
	var full_weapon = full.equipment(full.profile, "weapon").instance_id
	check(full.settle(full_raid, true).ok, "full stash cannot block extraction settlement")
	check(full.inventory.owner_of(full.profile, full_weapon) == "overflow", "full-stash extraction retains weapon in overflow")
	check(full.inventory.quantity(full.profile, "overflow", "ammo_rifle") == 90 and full.inventory.quantity(full.profile, "overflow", "medkit_basic") == 3, "overflow retains all return supplies without deletion")
	check(full.validate(full.profile).ok and full.profile.wins == 1, "overflow result preserves profile invariants")
	check(full.quick_equip().ok and full.equipment(full.profile, "weapon", false).instance_id == full_weapon, "quick equip can retrieve items from overflow")

	var disk = durable("disk")
	check(not disk.blocked and disk.saves.generation == 2, "new durable profile initializes both recovery slots")
	check(FileAccess.file_exists(disk.saves.root_path.path_join("profile_A.json")) and FileAccess.file_exists(disk.saves.root_path.path_join("profile_B.json")), "initial starter snapshot has dual-slot redundancy")
	var first_starter_count = disk.profile.items.size()
	var reopen = durable("disk")
	check(reopen.profile.items.size() == first_starter_count and reopen.saves.generation == 2, "restart does not regrant starter kit or write a new generation")
	before = encoded(disk)
	disk.saves.fault_point = "before_write"
	check(not disk.purchase("medkit_basic").ok and encoded(disk) == before and disk.saves.generation == 2, "save failure rolls back purchase and currency together")
	check(not disk.begin_raid(31).ok and encoded(disk) == before, "save failure leaves loadout in camp")
	disk.saves.fault_point = ""
	check(disk.begin_raid(31).ok, "deployment succeeds once saving recovers")
	var disk_raid = disk.profile.active_raid.raid_id
	var disk_order = disk.profile.active_raid.search.loot_00.order.duplicate()
	check(reveal(disk, "loot_00").ok, "search progress saves durably")
	var resumed = durable("disk")
	check(resumed.profile.active_raid.raid_id == disk_raid and resumed.revealed_ids("loot_00") == [disk_order[0]], "restart restores raid identity and revealed prefix")
	check(resumed.profile.active_raid.search.loot_00.order == disk_order, "restart cannot reroll container contents")
	before = encoded(disk)
	disk.saves.fault_point = "after_write"
	check(not transfer(disk, disk_order[0], "loot_00", "raid_pack").ok and encoded(disk) == before, "failed pickup commit publishes neither removal nor deposit")
	check(not disk.settle(disk_raid, true).ok and encoded(disk) == before, "failed settlement commit publishes neither win nor stash items")
	disk.saves.fault_point = ""
	check(disk.settle(disk_raid, true).ok, "settlement retry can commit after fault is cleared")
	var settled = durable("disk")
	before = encoded(settled)
	check(settled.settle(disk_raid, true).reason == "already_settled" and encoded(settled) == before, "restart preserves settlement idempotency ledger")
	check(settled.profile.wins == 1 and settled.profile.currency == 1500, "restart after settlement preserves exactly one win and unchanged cash")
	before = encoded(resumed)
	check(not resumed.settle(disk_raid, false).ok and encoded(resumed) == before, "stale client cannot overwrite successful settlement with a death")
	var durable_retry = durable("command_retry")
	durable_retry.begin_raid(54)
	reveal(durable_retry, "loot_00")
	var durable_retry_id = durable_retry.revealed_ids("loot_00")[0]
	var durable_command = {"action": "move", "item_id": durable_retry_id, "quantity": 1, "from": "loot_00", "to": "raid_pack", "item_ids": [durable_retry_id], "command_id": "durable-retry", "source_revision": durable_retry.profile.containers.loot_00.revision, "target_revision": durable_retry.profile.containers.raid_pack.revision}
	check(durable_retry.execute(durable_command).ok, "complete command and idempotency record commit together")
	var retry_restarted = durable("command_retry")
	before = encoded(retry_restarted)
	var decoded_command = JSON.parse_string(JSON.stringify(durable_command))
	check(retry_restarted.execute(decoded_command).reason == "already_applied" and encoded(retry_restarted) == before, "complete JSON-restored command retry after restart cannot duplicate loot")
	await test_real_scene_snapshot()
	var absent_legacy = durable("absent_legacy", fixture_root.path_join("never_existed/progress.json"))
	check(not absent_legacy.blocked and absent_legacy.profile.currency == 1500 and absent_legacy.profile.wins == 0, "explicit absent legacy path still grants new-profile default currency")
	check(not absent_legacy.profile.migration.legacy_imported, "missing legacy file does not set migration-import marker")
	write_text(fixture_root.path_join("first_write_failure"), "unwritable root fixture")
	var first_write_failure = durable("first_write_failure")
	check(first_write_failure.blocked and first_write_failure.profile.is_empty() and first_write_failure.saves.generation == 0, "failed first commit blocks empty-profile UI instead of exposing an unpublished starter")
	check(first_write_failure.last_error == "directory_unwritable", "failed initialization preserves actionable save error")
	check(FileAccess.get_file_as_string(fixture_root.path_join("first_write_failure")) == "unwritable root fixture", "failed initialization preserves blocking filesystem evidence")

	var legacy_path = fixture_root.path_join("legacy/progress.json")
	write_text(legacy_path, "{\"wealth\":7777,\"wins\":11}")
	var migrated = durable("migration", legacy_path)
	check(not migrated.blocked and migrated.profile.currency == 7777 and migrated.profile.wins == 11, "legacy wealth and wins are imported exactly")
	check(migrated.profile.migration.legacy_imported and migrated.profile.migration.starter_granted, "legacy migration records starter grant in same snapshot")
	check(FileAccess.get_file_as_string(legacy_path) == FileAccess.get_file_as_string(migrated.saves.root_path.path_join("legacy_progress.json")), "migration keeps original and byte-identical backup")
	var migration_count = migrated.profile.items.size()
	write_text(legacy_path, "{\"wealth\":999999,\"wins\":999}")
	var remigrated = durable("migration", legacy_path)
	check(remigrated.profile.currency == 7777 and remigrated.profile.wins == 11 and remigrated.profile.items.size() == migration_count, "existing new profile prevents repeat migration and starter duplication")
	write_text(legacy_path, "invalid legacy")
	var invalid_legacy = durable("bad_migration", legacy_path)
	check(invalid_legacy.blocked and invalid_legacy.profile.is_empty(), "corrupt legacy blocks initialization instead of erasing progress")
	check(not FileAccess.file_exists(invalid_legacy.saves.root_path.path_join("profile_A.json")), "corrupt legacy never produces a replacement starter save")
	for service in durable_services:
		service.saves.configure(service.saves.root_path) # Release bound validator cycles.
	durable_services.clear()
	remove_fixture(fixture_root)
	print("Profile tests: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func test_real_scene_snapshot():
	var game = load("res://main.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	var tick = PhysicsTask.new()
	root.add_child(tick)
	await tick.run(func(): game._reset())
	for i in range(4):
		await tick.run(func(): game._physics_process(1.0 / 60.0))
	game.player_health.hp = 61.0
	game.weapon_runtime.ammo = 7
	game.rig.yaw = 0.731234567890123
	var candidate = game._runtime_candidate()
	check(candidate.active_raid.snapshot.enemies.size() == 9, "real scene snapshot captures every map guard")
	var recorder = durable("real_scene")
	check(recorder.validate(candidate).ok, "real captured player, weapon, health and brain shapes pass validation")
	check(recorder.commit(candidate).ok, "real running 3D scene snapshot commits through dual-slot checksum verification")
	var restored = durable("real_scene")
	check(not restored.blocked and restored.profile.active_raid.snapshot.player.weapon.ammo == 7, "real scene checkpoint reloads from actual disk")
	var checkpoint = restored.profile.active_raid.snapshot
	game.player_health.hp = 99.0
	game.weapon_runtime.ammo = 24
	game.snapshot_codec.apply(game, checkpoint)
	check(game.player_health.hp == 61.0 and game.weapon_runtime.ammo == 7 and absf(game.rig.yaw - 0.731234567890123) < 0.000001, "disk snapshot applies safely to live scene and restores combat state")
	var invalid_snapshots: Array = []
	var invalid = checkpoint.duplicate(true); invalid.erase("player"); invalid_snapshots.append(invalid)
	invalid = checkpoint.duplicate(true); invalid.player.position = [1, 2]; invalid_snapshots.append(invalid)
	invalid = checkpoint.duplicate(true); invalid.player.velocity = "bad"; invalid_snapshots.append(invalid)
	invalid = checkpoint.duplicate(true); invalid.player.health.hp = "bad"; invalid_snapshots.append(invalid)
	invalid = checkpoint.duplicate(true); invalid.player.weapon.cooldown = -1; invalid_snapshots.append(invalid)
	invalid = checkpoint.duplicate(true); invalid.player.weapon.ammo = 1.5; invalid_snapshots.append(invalid)
	invalid = checkpoint.duplicate(true); invalid.player.crouching = "yes"; invalid_snapshots.append(invalid)
	invalid = checkpoint.duplicate(true); invalid.enemies.pop_back(); invalid_snapshots.append(invalid)
	invalid = checkpoint.duplicate(true); invalid.enemies[0].brain._route_index = 99; invalid_snapshots.append(invalid)
	invalid = checkpoint.duplicate(true); invalid.enemies[0].brain.state = "unknown"; invalid_snapshots.append(invalid)
	invalid = checkpoint.duplicate(true); invalid.enemies[0].brain.last_known = [0]; invalid_snapshots.append(invalid)
	invalid = checkpoint.duplicate(true); invalid.enemies[0].brain.rng_state = "broken"; invalid_snapshots.append(invalid)
	var before = encoded(recorder)
	for index in invalid_snapshots.size():
		var malformed = candidate.duplicate(true)
		malformed.active_raid.snapshot = invalid_snapshots[index]
		check(recorder.commit(malformed).get("reason") == "invalid_snapshot" and encoded(recorder) == before, "malformed checkpoint cannot be published: " + str(index))
	var malformed = candidate.duplicate(true)
	malformed.active_raid.snapshot = invalid_snapshots[1]
	var corrupt_path = recorder.saves.root_path.path_join("profile_B.json")
	var corrupted_bytes = recorder.saves.canonical_json(recorder.saves._make_record(malformed, recorder.saves.generation + 1))
	write_text(corrupt_path, corrupted_bytes)
	var isolated = durable("real_scene")
	check(isolated.blocked and isolated.last_error == "quarantine_required" and isolated.profile.is_empty(), "checksum-valid malformed checkpoint is quarantined before scene restoration")
	check(FileAccess.get_file_as_string(corrupt_path) == corrupted_bytes, "checkpoint quarantine preserves corrupt source evidence")
	game.free()
	tick.queue_free()
	await process_frame

func write_text(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(contents)
	file.close()

func remove_fixture(path: String) -> void:
	var absolute = ProjectSettings.globalize_path(path).replace("\\", "/")
	var allowed = ProjectSettings.globalize_path(fixture_root).replace("\\", "/")
	assert(absolute == allowed or absolute.begins_with(allowed + "/"))
	var directory = DirAccess.open(path)
	if directory == null: return
	directory.include_hidden = true
	for name in directory.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(name)))
	for name in directory.get_directories():
		remove_fixture(path.path_join(name))
	DirAccess.remove_absolute(absolute)
