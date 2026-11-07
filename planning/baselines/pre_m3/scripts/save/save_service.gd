extends RefCounted
## Durable, versioned profile snapshots. Callers publish gameplay state only after
## commit_snapshot succeeds. No personal save is read until configure/load is called.

const SCHEMA_VERSION = 1
const CONTENT_VERSION = "phase3_1"
const MAX_SAFE_INTEGER = 9007199254740991
const SLOT_NAMES = ["profile_A.json", "profile_B.json"]
const LOCK_PREFIX = ".commit-lock-"

var generation: int = 0
var fault_point: String = ""
var root_path: String = ""
var _validator: Callable
var _busy: bool = false
var _active_slot: String = ""
var _lock_path: String = ""

func configure(path: String, validator: Callable = Callable()) -> void:
	root_path = path.trim_suffix("/").trim_suffix("\\")
	_validator = validator
	generation = 0
	_active_slot = ""
	fault_point = ""

func load_profile() -> Dictionary:
	if root_path.is_empty():
		return _load_error("not_configured")
	if _busy:
		return _load_error("save_busy")
	var scan = _scan_slots()
	if not scan.ok:
		return scan
	generation = scan.generation
	_active_slot = scan.get("slot", "")
	return scan

func commit_snapshot(payload: Dictionary, expected_generation: int) -> Dictionary:
	if root_path.is_empty():
		return _commit_error("not_configured")
	if _busy:
		return _commit_error("save_busy")
	_busy = true
	var result = _commit_locked(payload, expected_generation)
	_release_lock()
	_busy = false
	return result

func _commit_locked(payload: Dictionary, expected_generation: int) -> Dictionary:
	if expected_generation != generation:
		return _commit_error("stale_generation")
	var encoded = _encode(payload)
	if not encoded.ok:
		return _commit_error("invalid_json_payload: " + encoded.reason)
	var validation = _validate(payload)
	if not validation.ok:
		return _commit_error("quarantine_required", validation.reason)
	var directory_error = DirAccess.make_dir_recursive_absolute(_absolute(root_path))
	if directory_error != OK or not DirAccess.dir_exists_absolute(_absolute(root_path)):
		return _commit_error("directory_unwritable", error_string(directory_error))
	var locked = _acquire_lock()
	if not locked.ok:
		return _commit_error(locked.reason)
	# Reload while holding the writer lock: another service may have committed
	# since this instance loaded. Never use only the in-memory generation.
	var scan = _scan_slots()
	if not scan.ok:
		return _commit_error(scan.reason, scan.get("detail", ""))
	if expected_generation != scan.generation:
		return _commit_error("stale_generation")
	if expected_generation >= MAX_SAFE_INTEGER:
		return _commit_error("generation_exhausted")
	var target = SLOT_NAMES[0] if scan.get("slot", "") != SLOT_NAMES[0] else SLOT_NAMES[1]
	var target_path = root_path.path_join(target)
	var temp_path = target_path + ".tmp"
	var record = _make_record(payload, expected_generation + 1)
	if fault_point == "before_write":
		return _commit_error("injected_before_write")
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _commit_error("write_failed", error_string(FileAccess.get_open_error()))
	file.store_string(_encode(record).text)
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK:
		return _commit_error("write_failed", error_string(write_error))
	if fault_point == "after_write":
		return _commit_error("injected_after_write")
	var verified = _read_slot(temp_path)
	if not verified.ok or verified.get("checksum", "") != record.record_sha256:
		return _commit_error("temporary_verification_failed")
	if fault_point == "before_replace":
		return _commit_error("injected_before_replace")
	# Respect an explicitly protected destination before attempting replacement.
	if FileAccess.file_exists(target_path) and FileAccess.get_read_only_attribute(_absolute(target_path)):
		return _commit_error("replace_failed", "destination_read_only")
	# Godot replaces an existing destination during rename. In particular, do
	# not delete the destination first: a failed rename must preserve both slots.
	var rename_error = DirAccess.rename_absolute(_absolute(temp_path), _absolute(target_path))
	if rename_error != OK:
		return _commit_error("replace_failed", error_string(rename_error))
	var committed = _read_slot(target_path)
	if not committed.ok or committed.get("checksum", "") != record.record_sha256:
		return _commit_error("committed_verification_failed")
	generation = expected_generation + 1
	_active_slot = target
	return {"ok": true, "generation": generation, "reason": "", "warning": scan.warning}

func _scan_slots() -> Dictionary:
	var records: Array = []
	var invalid: Array = []
	var existing_count = 0
	for name in SLOT_NAMES:
		var path = root_path.path_join(name)
		if not FileAccess.file_exists(path):
			continue
		existing_count += 1
		var candidate = _read_slot(path)
		candidate["slot"] = name
		if candidate.get("future_version", false):
			return _load_error("future_schema", "A newer save version exists in " + name)
		if candidate.get("unsupported_content", false):
			return _load_error("unsupported_content", "Unknown content version in " + name)
		if candidate.ok:
			records.append(candidate)
		else:
			invalid.append(name + ": " + candidate.reason)
	if existing_count == 0:
		return {"ok": true, "reason": "", "payload": {}, "generation": 0,
			"warning": "", "needs_initialization": true, "slot": ""}
	if records.is_empty():
		return _load_error("corrupt_profile", "; ".join(invalid))
	records.sort_custom(func(a, b): return a.generation > b.generation)
	var selected = records[0]
	if records.size() > 1 and selected.generation == records[1].generation and selected.checksum != records[1].checksum:
		return _load_error("generation_conflict")
	var validation = _validate(selected.payload)
	if not validation.ok:
		var rejected = _load_error("quarantine_required", validation.reason)
		rejected["quarantine_required"] = true
		rejected["quarantine_payload"] = selected.payload.duplicate(true)
		rejected["quarantine_generation"] = selected.generation
		return rejected
	return {"ok": true, "reason": "", "payload": selected.payload.duplicate(true),
		"generation": selected.generation, "warning": "" if invalid.is_empty() else "recovered_previous_slot: " + "; ".join(invalid),
		"needs_initialization": false, "slot": selected.slot}

func _read_slot(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "read_failed"}
	var source = file.get_as_text()
	file.close()
	var parser = JSON.new()
	if parser.parse(source) != OK or not parser.data is Dictionary:
		return {"ok": false, "reason": "invalid_json"}
	var record: Dictionary = parser.data
	# Preserve evidence from a newer game even when its checksum format differs.
	if _whole_number(record.get("schema_version")) and record.schema_version > SCHEMA_VERSION:
		return {"ok": false, "reason": "future_schema", "future_version": true}
	if not _whole_number(record.get("schema_version")) or record.schema_version != SCHEMA_VERSION:
		return {"ok": false, "reason": "invalid_schema"}
	if record.get("content_version") != CONTENT_VERSION:
		return {"ok": false, "reason": "unsupported_content", "unsupported_content": true}
	if not _whole_number(record.get("generation")) or record.generation < 1:
		return {"ok": false, "reason": "invalid_generation"}
	if not record.get("payload") is Dictionary or not record.get("record_sha256") is String:
		return {"ok": false, "reason": "invalid_record"}
	var checksum: String = record.record_sha256
	var unsigned = record.duplicate(true)
	unsigned.erase("record_sha256")
	var encoded = _encode(unsigned)
	if not encoded.ok or encoded.text.sha256_text() != checksum:
		return {"ok": false, "reason": "checksum_mismatch"}
	return {"ok": true, "reason": "", "payload": record.payload,
		"generation": int(record.generation), "checksum": checksum}

func _make_record(payload: Dictionary, next_generation: int) -> Dictionary:
	var record = {"schema_version": SCHEMA_VERSION, "content_version": CONTENT_VERSION,
		"generation": next_generation, "payload": payload.duplicate(true)}
	record["record_sha256"] = _encode(record).text.sha256_text()
	return record

func _validate(payload: Dictionary) -> Dictionary:
	if not _validator.is_valid():
		return {"ok": true, "reason": ""}
	# Validators receive a copy and cannot mutate the snapshot being committed.
	var result = _validator.call(payload.duplicate(true))
	if result is bool:
		return {"ok": result, "reason": "payload_validation_failed" if not result else ""}
	if result is Dictionary:
		return {"ok": result.get("ok", false) == true, "reason": str(result.get("reason", "payload_validation_failed"))}
	return {"ok": false, "reason": "invalid_validator_result"}

func canonical_json(value: Variant) -> String:
	var result = _encode(value)
	return result.text if result.ok else ""

func _encode(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_NIL:
			return {"ok": true, "text": "null"}
		TYPE_BOOL:
			return {"ok": true, "text": "true" if value else "false"}
		TYPE_STRING, TYPE_STRING_NAME:
			return {"ok": true, "text": JSON.stringify(str(value))}
		TYPE_INT, TYPE_FLOAT:
			var number = float(value)
			if not is_finite(number) or absf(number) > MAX_SAFE_INTEGER:
				return {"ok": false, "reason": "unsafe_number"}
			# Godot's decimal parser can change the last binary digit of a
			# full-precision float. Fixed six-decimal quantization is stable across
			# write/parse/hash cycles and precise to a micrometer for world vectors.
			# Integer quantities/IDs remain exact; normalize -0 and whole floats.
			var numeric_text = str(int(number)) if floor(number) == number else String.num(number, 6)
			numeric_text = numeric_text.trim_suffix(".0")
			if numeric_text == "-0": numeric_text = "0"
			return {"ok": true, "text": numeric_text}
		TYPE_ARRAY:
			var entries: PackedStringArray = []
			for child in value:
				var encoded = _encode(child)
				if not encoded.ok:
					return encoded
				entries.append(encoded.text)
			return {"ok": true, "text": "[" + ",".join(entries) + "]"}
		TYPE_DICTIONARY:
			var keys: Array = value.keys()
			for key in keys:
				if not key is String and not key is StringName:
					return {"ok": false, "reason": "non_string_key"}
			keys.sort_custom(func(a, b): return str(a) < str(b))
			var entries: PackedStringArray = []
			for key in keys:
				var encoded = _encode(value[key])
				if not encoded.ok:
					return encoded
				entries.append(JSON.stringify(str(key)) + ":" + encoded.text)
			return {"ok": true, "text": "{" + ",".join(entries) + "}"}
	return {"ok": false, "reason": "non_json_value"}

func _whole_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and absf(float(value)) <= MAX_SAFE_INTEGER and float(value) == floor(float(value))

func _acquire_lock() -> Dictionary:
	# PID in the directory name makes lock creation atomic, including crashes
	# before a separate owner file could be written. Two contenders may both
	# return busy; neither can write while the other's live directory exists.
	var own_path = root_path.path_join(LOCK_PREFIX + str(OS.get_process_id()))
	var error = DirAccess.make_dir_absolute(_absolute(own_path))
	if error != OK:
		return {"ok": false, "reason": "save_busy" if error == ERR_ALREADY_EXISTS else "lock_failed"}
	_lock_path = own_path
	var directory = DirAccess.open(root_path)
	if directory == null:
		return {"ok": false, "reason": "lock_failed"}
	directory.include_hidden = true
	for entry in directory.get_directories():
		if not entry.begins_with(LOCK_PREFIX) or entry == own_path.get_file():
			continue
		var owner = entry.trim_prefix(LOCK_PREFIX)
		if not owner.is_valid_int() or int(owner) <= 0 or OS.is_process_running(int(owner)):
			return {"ok": false, "reason": "save_busy"}
		# Dead-process locks are empty directories. Never recurse into arbitrary
		# files or remove another live writer's lock.
		if DirAccess.remove_absolute(_absolute(root_path.path_join(entry))) != OK:
			return {"ok": false, "reason": "stale_lock_unremovable"}
	return {"ok": true, "reason": ""}

func _release_lock() -> void:
	if not _lock_path.is_empty():
		DirAccess.remove_absolute(_absolute(_lock_path))
		_lock_path = ""

func read_legacy(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "exists": false, "wealth": 0, "wins": 0, "reason": ""}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "exists": true, "wealth": 0, "wins": 0, "reason": "legacy_read_failed"}
	var source = file.get_as_text()
	file.close()
	var parser = JSON.new()
	if parser.parse(source) != OK or not parser.data is Dictionary:
		return {"ok": false, "exists": true, "wealth": 0, "wins": 0, "reason": "legacy_invalid_json"}
	var data: Dictionary = parser.data
	if not _whole_number(data.get("wealth")) or not _whole_number(data.get("wins")) or data.wealth < 0 or data.wins < 0:
		return {"ok": false, "exists": true, "wealth": 0, "wins": 0, "reason": "legacy_invalid_values"}
	return {"ok": true, "exists": true, "wealth": int(data.wealth), "wins": int(data.wins), "reason": ""}

func backup_legacy(path: String) -> Dictionary:
	if root_path.is_empty():
		return {"ok": false, "reason": "not_configured"}
	var legacy = read_legacy(path)
	if not legacy.ok or not legacy.exists:
		return {"ok": false, "reason": legacy.reason if not legacy.ok else "legacy_missing"}
	if DirAccess.make_dir_recursive_absolute(_absolute(root_path)) != OK:
		return {"ok": false, "reason": "directory_unwritable"}
	var backup_path = root_path.path_join("legacy_progress.json")
	if FileAccess.file_exists(backup_path):
		if FileAccess.get_sha256(path) == FileAccess.get_sha256(backup_path):
			return {"ok": true, "reason": "", "path": backup_path}
		return {"ok": false, "reason": "legacy_backup_conflict"}
	var error = DirAccess.copy_absolute(_absolute(path), _absolute(backup_path))
	if error != OK or FileAccess.get_sha256(path) != FileAccess.get_sha256(backup_path):
		return {"ok": false, "reason": "legacy_backup_failed"}
	return {"ok": true, "reason": "", "path": backup_path}

func _load_error(reason: String, detail: String = "") -> Dictionary:
	return {"ok": false, "reason": reason, "detail": detail, "payload": {}, "generation": generation,
		"warning": "", "needs_initialization": false}

func _commit_error(reason: String, detail: String = "") -> Dictionary:
	return {"ok": false, "reason": reason, "detail": detail, "generation": generation}

func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path)
