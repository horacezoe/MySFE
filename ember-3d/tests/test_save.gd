extends SceneTree
## Only process-owned fixtures below res://tests are read/written by this suite.
const SaveService = preload("res://scripts/save/save_service.gd")
var checks = 0
var failures = 0
var fixture_root = "res://tests/.save-fixtures-" + str(OS.get_process_id())

func _initialize() -> void:
	var arguments = OS.get_cmdline_user_args()
	if arguments.size() == 2 and arguments[0] == "lock-worker":
		call_deferred("run_lock_worker", arguments[1])
		return
	call_deferred("run_tests")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func service(name: String, validator: Callable = Callable()) -> RefCounted:
	var result = SaveService.new()
	result.configure(fixture_root.path_join(name), validator)
	return result

func payload(currency: int = 42) -> Dictionary:
	return {"profile_id": "test-profile", "currency": currency, "wins": 2,
		"items": {"i_1": {"definition_id": "medicine", "quantity": 2, "position": [1.5, 2, -0.0]}},
		"containers": {}, "active_raid": null, "settled_raids": {},
		"processed_commands": {}, "settings": {"look": 0.1}, "migration": {"legacy_imported": true}}

func write_text(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "fixture is writable")
	file.store_string(contents)
	file.close()

func read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<absent>"

func write_record(saver: RefCounted, name: String, data: Dictionary, next_generation: int) -> void:
	write_text(saver.root_path.path_join(name), saver.canonical_json(saver._make_record(data, next_generation)))

func validate_items(data: Dictionary) -> Dictionary:
	for item in data.get("items", {}).values():
		if item.get("definition_id") != "medicine":
			return {"ok": false, "reason": "unknown_definition"}
	return {"ok": true}

func run_tests() -> void:
	var saver = service("normal")
	var initial = saver.load_profile()
	check(initial.ok and initial.needs_initialization and initial.generation == 0, "absent slots explicitly request initialization")
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(saver.root_path)), "read-only load does not create directories")
	check(saver.commit_snapshot(payload(), 0).ok, "first snapshot commits")
	check(saver.generation == 1, "first commit publishes generation only on success")
	var restarted = service("normal")
	var loaded = restarted.load_profile()
	check(loaded.ok and loaded.generation == 1 and not loaded.needs_initialization, "restart loads durable slot")
	check(loaded.payload.currency == 42 and loaded.payload.settings.look == 0.1, "fractional and integer values survive JSON checksum roundtrip")
	check(loaded.payload.items.i_1.quantity == 2, "complete item payload survives")
	check(saver.canonical_json({"b": [1, 1.5, -0.0], "a": 2}) == saver.canonical_json({"a": 2.0, "b": [1.0, 1.5, 0]}), "canonical key order, number types and signed zero agree")
	var snapshot_floats = [0.3672524690628052, 0.9434462785720825, -2.289626359939575, -1.8313987255096436, 0.6390740871429443, 0.0000000003, -0.0000000003]
	var random = RandomNumberGenerator.new()
	random.seed = 875412
	for i in range(2048): snapshot_floats.append(random.randf_range(-1000, 1000))
	var numeric_json = saver.canonical_json(snapshot_floats)
	check(saver.canonical_json(JSON.parse_string(numeric_json)) == numeric_json, "real scene values and 2048 random floats produce stable JSON checksums")
	var float_save = service("float_snapshot")
	check(float_save.commit_snapshot({"snapshot": snapshot_floats}, 0).ok, "realistic fractional snapshot commits to disk")
	check(service("float_snapshot").load_profile().ok, "fractional snapshot verifies after process-style reload")
	check(saver.commit_snapshot(payload(70), 1).ok, "second snapshot commits to other slot")
	check(FileAccess.file_exists(saver.root_path.path_join("profile_A.json")) and FileAccess.file_exists(saver.root_path.path_join("profile_B.json")), "both generations are retained")
	check(saver.commit_snapshot(payload(80), 2).ok, "third commit replaces existing destination on this platform")
	check(service("normal").load_profile().payload.currency == 80, "replacement is durable")
	var slot_a = saver.root_path.path_join("profile_A.json")
	var slot_b = saver.root_path.path_join("profile_B.json")
	for point in ["before_write", "after_write", "before_replace"]:
		var before_a = read_text(slot_a)
		var before_b = read_text(slot_b)
		saver.fault_point = point
		var failure = saver.commit_snapshot(payload(999), 3)
		check(not failure.ok and failure.reason == "injected_" + point, "fault propagates: " + point)
		check(saver.generation == 3, "failed commit retains in-memory generation: " + point)
		check(read_text(slot_a) == before_a and read_text(slot_b) == before_b, "failed commit preserves both formal files: " + point)
		check(service("normal").load_profile().payload.currency == 80, "restart ignores partial transaction: " + point)
	saver.fault_point = ""
	write_text(slot_b + ".tmp", "{\"generation\":999999}")
	check(service("normal").load_profile().generation == 3, "arbitrary newer temporary file cannot become a committed save")
	var stale = service("normal")
	stale.load_profile()
	check(saver.commit_snapshot(payload(90), 3).ok, "new generation commits after faults")
	var stale_result = stale.commit_snapshot(payload(1000), 3)
	check(not stale_result.ok and stale_result.reason == "stale_generation", "second client detects external newer generation")
	check(stale.generation == 3 and service("normal").load_profile().payload.currency == 90, "stale client cannot overwrite newer disk or publish its state")
	check(not saver.commit_snapshot(payload(), 2).ok and saver.generation == 4, "in-memory stale command is rejected")
	var corrupted = JSON.parse_string(read_text(slot_b))
	corrupted.payload.currency = 999999
	write_text(slot_b, JSON.stringify(corrupted))
	var recovered = service("normal").load_profile()
	check(recovered.ok and recovered.generation == 3 and recovered.payload.currency == 80, "checksum-corrupt newest slot falls back to previous complete payload")
	check(not recovered.warning.is_empty(), "recovery is reported to UI")
	write_text(slot_a, "{broken")
	var blocked = service("normal")
	var both_bad = blocked.load_profile()
	check(not both_bad.ok and not both_bad.needs_initialization, "two corrupt slots never request fresh starter kit")
	check(not blocked.commit_snapshot(payload(), 0).ok, "two corrupt slots cannot be silently overwritten")
	check(read_text(slot_a) == "{broken" and read_text(slot_b) == JSON.stringify(corrupted), "corruption evidence remains intact")

	var future = service("future")
	write_record(future, "profile_A.json", payload(42), 1)
	write_text(future.root_path.path_join("profile_B.json"), JSON.stringify({"schema_version": 2, "payload": {"unknown": true}}))
	var future_result = future.load_profile()
	check(not future_result.ok and future_result.reason == "future_schema", "future version blocks even with valid older slot")
	check(not future.commit_snapshot(payload(), 0).ok, "future evidence cannot be overwritten")
	var content = service("future_content")
	var content_record = content._make_record(payload(), 1)
	content_record.content_version = "phase99_1"
	write_text(content.root_path.path_join("profile_A.json"), JSON.stringify(content_record))
	check(content.load_profile().reason == "unsupported_content", "unknown content version also fails closed")

	var quarantine = service("quarantine", validate_items)
	var unknown = payload()
	unknown.items.i_1.definition_id = "future_relic"
	write_record(quarantine, "profile_A.json", payload(), 1)
	write_record(quarantine, "profile_B.json", unknown, 2)
	var quarantine_bytes = read_text(quarantine.root_path.path_join("profile_B.json"))
	var quarantined = quarantine.load_profile()
	check(not quarantined.ok and quarantined.reason == "quarantine_required", "unknown definition is quarantined instead of silently rolled back")
	check(quarantined.quarantine_payload.items.i_1.definition_id == "future_relic", "quarantine reports full evidence for explicit recovery")
	check(not quarantine.commit_snapshot(payload(), 0).ok, "quarantined save cannot be overwritten with starter items")
	check(read_text(quarantine.root_path.path_join("profile_B.json")) == quarantine_bytes, "quarantine preserves exact source bytes")
	var validation = service("validation", validate_items)
	check(not validation.commit_snapshot(unknown, 0).ok and validation.generation == 0, "unknown item rejected before durable write")
	check(not validation.commit_snapshot({"vector": Vector3.ONE}, 0).ok, "non-JSON snapshots are rejected")
	check(not validation.commit_snapshot({"bad": NAN}, 0).ok, "NaN cannot enter canonical save")
	check(not validation.commit_snapshot({"bad": INF}, 0).ok, "infinite value cannot enter canonical save")
	check(not validation.commit_snapshot({1: "bad"}, 0).ok, "non-string dictionary key is rejected")
	check(not validation.commit_snapshot({"bad": 9007199254740992}, 0).ok, "unsafe JSON integer is rejected")

	var tie = service("tie")
	write_record(tie, "profile_A.json", payload(1), 7)
	write_record(tie, "profile_B.json", payload(2), 7)
	check(tie.load_profile().reason == "generation_conflict", "ambiguous equal generations cannot be selected arbitrarily")
	var unconfigured = SaveService.new()
	check(not unconfigured.load_profile().ok and not unconfigured.commit_snapshot({}, 0).ok, "unconfigured service does not access default personal saves")

	var unwritable_path = fixture_root.path_join("not_a_directory")
	write_text(unwritable_path, "blocking fixture")
	var unwritable = SaveService.new()
	unwritable.configure(unwritable_path)
	check(not unwritable.commit_snapshot(payload(), 0).ok and unwritable.generation == 0, "unwritable root returns failure without publishing")
	check(read_text(unwritable_path) == "blocking fixture", "unwritable fixture remains unchanged")
	var write_failure = service("write_failure")
	write_failure.commit_snapshot(payload(), 0)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(write_failure.root_path.path_join("profile_B.json.tmp")))
	var failed_write = write_failure.commit_snapshot(payload(999), 1)
	check(not failed_write.ok and failed_write.reason == "write_failed", "temporary file creation failure is propagated")
	check(write_failure.generation == 1 and service("write_failure").load_profile().payload.currency == 42, "write failure preserves previously committed snapshot")
	if OS.get_name() == "Windows":
		var readonly = service("readonly")
		readonly.commit_snapshot(payload(), 0)
		readonly.commit_snapshot(payload(50), 1)
		var protected_slot = readonly.root_path.path_join("profile_A.json")
		var protected_bytes = read_text(protected_slot)
		var attribute_result = FileAccess.set_read_only_attribute(protected_slot, true)
		check(attribute_result == OK and FileAccess.get_read_only_attribute(protected_slot), "read-only fixture attribute is established")
		var readonly_result = readonly.commit_snapshot(payload(999), 2)
		check(not readonly_result.ok and readonly_result.reason == "replace_failed", "read-only destination propagates replacement failure")
		check(readonly.generation == 2 and read_text(protected_slot) == protected_bytes and service("readonly").load_profile().payload.currency == 50, "failed read-only replacement preserves both durable generations")
		FileAccess.set_read_only_attribute(protected_slot, false)

	var lock_test = service("locks")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(lock_test.root_path))
	var own_lock = lock_test.root_path.path_join(".commit-lock-" + str(OS.get_process_id()))
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(own_lock))
	check(lock_test.commit_snapshot(payload(), 0).reason == "save_busy", "active same-process writer lock prevents concurrent service writes")
	check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(own_lock)), "contender does not release another service's lock")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(own_lock))
	var dead_lock = lock_test.root_path.path_join(".commit-lock-2147483647")
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(dead_lock))
	check(lock_test.commit_snapshot(payload(), 0).ok, "dead-process crash lock is recovered")
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dead_lock)), "recovered stale lock is removed")
	var nested = service("reentrant")
	var recursive_result = {}
	nested.configure(nested.root_path, func(_data):
		recursive_result.merge(nested.commit_snapshot({}, 0), true)
		return true)
	check(nested.commit_snapshot(payload(), 0).ok and recursive_result.reason == "save_busy", "validator reentrancy cannot start a second transaction")
	nested.configure(nested.root_path) # Release the validator's self-reference.
	var concurrent = service("concurrent")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(concurrent.root_path))
	var worker_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", "Godot/save-worker-tests.log", "--script", "res://tests/test_save.gd", "--", "lock-worker", concurrent.root_path])
	check(worker_pid > 0, "independent writer process starts")
	var wait_until = Time.get_ticks_msec() + 10000
	while not FileAccess.file_exists(concurrent.root_path.path_join("ready")) and Time.get_ticks_msec() < wait_until:
		OS.delay_msec(20)
	check(FileAccess.file_exists(concurrent.root_path.path_join("ready")), "independent writer holds its process lock")
	check(concurrent.commit_snapshot(payload(999), 0).reason == "save_busy", "another live process cannot race a held writer lock")
	write_text(concurrent.root_path.path_join("release"), "release")
	wait_until = Time.get_ticks_msec() + 10000
	while OS.is_process_running(worker_pid) and Time.get_ticks_msec() < wait_until:
		OS.delay_msec(20)
	check(not OS.is_process_running(worker_pid), "independent writer exits within deadline")
	if OS.is_process_running(worker_pid):
		OS.kill(worker_pid)
	check(concurrent.commit_snapshot(payload(999), 0).reason == "stale_generation", "old generation cannot overwrite a commit from another process")
	check(concurrent.load_profile().payload.get("currency") == 77, "independent writer's payload remains intact")

	var legacy = service("legacy")
	var legacy_path = fixture_root.path_join("legacy_source/progress.json")
	check(legacy.read_legacy(legacy_path).ok and not legacy.read_legacy(legacy_path).exists, "absent legacy profile is distinguished from corrupt legacy")
	write_text(legacy_path, "{\"wealth\":12000,\"wins\":3}")
	var legacy_read = legacy.read_legacy(legacy_path)
	check(legacy_read.ok and legacy_read.wealth == 12000 and legacy_read.wins == 3, "legacy wealth and wins can be migrated")
	check(legacy.backup_legacy(legacy_path).ok, "valid legacy source is backed up")
	check(read_text(legacy_path) == read_text(legacy.root_path.path_join("legacy_progress.json")), "legacy backup is byte-identical and preserves source")
	check(legacy.backup_legacy(legacy_path).ok, "identical legacy backup is idempotent")
	write_text(legacy_path, "{\"wealth\":12001,\"wins\":3}")
	check(legacy.backup_legacy(legacy_path).reason == "legacy_backup_conflict", "different legacy backup evidence is never overwritten")
	write_text(legacy_path, "{\"wealth\":-1,\"wins\":3}")
	check(not legacy.read_legacy(legacy_path).ok, "invalid negative legacy currency is rejected")
	write_text(legacy_path, "not json")
	var bad_legacy = service("bad_legacy")
	check(not bad_legacy.read_legacy(legacy_path).ok and not bad_legacy.backup_legacy(legacy_path).ok, "malformed legacy data is never migrated or backed up as valid")
	check(not FileAccess.file_exists(bad_legacy.root_path.path_join("legacy_progress.json")), "failed legacy parsing creates no backup")

	remove_fixture(fixture_root)
	print("Save tests: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func run_lock_worker(path: String) -> void:
	var absolute = ProjectSettings.globalize_path(path).replace("\\", "/")
	var test_root = ProjectSettings.globalize_path("res://tests/.save-fixtures-").replace("\\", "/")
	assert(absolute.begins_with(test_root) and absolute.ends_with("/concurrent"))
	var saver = SaveService.new()
	saver.configure(path)
	var result = saver._acquire_lock()
	if not result.ok:
		quit(1)
		return
	write_text(path.path_join("ready"), "ready")
	var wait_until = Time.get_ticks_msec() + 15000
	while not FileAccess.file_exists(path.path_join("release")) and Time.get_ticks_msec() < wait_until:
		OS.delay_msec(20)
	saver._release_lock()
	var committed = saver.commit_snapshot(payload(77), 0)
	quit(0 if committed.ok else 1)

func remove_fixture(path: String) -> void:
	# Every removal is restricted to this process's explicitly named test root.
	var absolute = ProjectSettings.globalize_path(path).replace("\\", "/")
	var allowed = ProjectSettings.globalize_path(fixture_root).replace("\\", "/")
	assert(absolute == allowed or absolute.begins_with(allowed + "/"))
	var directory = DirAccess.open(path)
	if directory == null:
		return
	directory.include_hidden = true
	for name in directory.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(name)))
	for name in directory.get_directories():
		remove_fixture(path.path_join(name))
	DirAccess.remove_absolute(absolute)
