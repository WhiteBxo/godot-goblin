extends SceneTree

const StateData = preload("res://src/core/game_state.gd")
var _checks := 0
var _failures: Array[String] = []
var _directory := "user://verification/save_store_%d" % OS.get_process_id()

class FailingStore extends SaveStore:
	var fail_write := false
	var fail_replace := false
	func _write_file(path: String, document: Dictionary) -> Error:
		return ERR_FILE_CANT_WRITE if fail_write else super._write_file(path, document)
	func _rename_file(from: String, to: String) -> Error:
		return ERR_FILE_CANT_WRITE if fail_replace and to.ends_with("autosave.dat") else super._rename_file(from, to)

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	var state := StateData.new()
	state.select_business_profile("day1")
	state.complete_event("day1.opening")
	state.set_story_stage("day1.wait_human")
	state.set_variable("save_test.numbers", [7, 7.0, {"nested": [null, true, "中文"]}])
	var snapshot := state.to_dict()
	var store := FailingStore.new(_directory)
	check(store.load_save().error == ERR_FILE_NOT_FOUND, "Empty directory has no save")
	check(state.validate_snapshot(snapshot) == OK and state.can_take_snapshot(), "Public snapshot preflight accepts complete idle state")
	var signals_seen: Array[bool] = []
	state.state_changed.connect(func() -> void: signals_seen.append(true))
	check(state.validate_snapshot(snapshot) == OK and signals_seen.is_empty() and state.to_dict() == snapshot, "Validation neither restores nor publishes state")
	state.begin_business_transaction()
	check(not state.can_take_snapshot(), "In-flight transaction refuses snapshot capture")
	state.end_business_transaction()
	check(store.save(snapshot, "day1.wait_human.shop", 100) == OK, "Write and verify a complete checkpoint")
	var loaded := store.load_save()
	check(loaded.error == OK and not loaded.used_backup and loaded.data.game_state == snapshot, "Complete primary save loads")
	check(typeof(loaded.data.game_state.variables["save_test.numbers"][0]) == TYPE_INT and typeof(loaded.data.game_state.variables["save_test.numbers"][1]) == TYPE_FLOAT, "Binary round trip retains nested numeric types")
	check(state.restore_state(loaded.data.game_state) == OK, "Disk document restores through the existing full-state API")
	check(store.save(snapshot, "unknown", 101) == ERR_INVALID_DATA and store.load_save().data.saved_at == 100, "Unknown checkpoint cannot overwrite valid progress")
	var invalid := snapshot.duplicate(true)
	invalid.economy.inventory.ingredients.syrup.quantity += 1
	check(store.save(invalid, "day1.wait_human.shop") == ERR_INVALID_DATA, "Mismatched duplicate inventory is rejected")
	invalid = snapshot.duplicate(true)
	invalid.schema_version = 999
	check(store.save(invalid, "day1.wait_human.shop") == ERR_INVALID_DATA, "Unknown state schema is rejected")
	invalid = snapshot.duplicate(true)
	invalid.current_day = 2
	check(store.save(invalid, "day1.wait_human.shop") == ERR_INVALID_DATA, "A checkpoint only accepts its declared day and phase")
	invalid = snapshot.duplicate(true)
	invalid.variables["world.phase"] = "night"
	invalid.flags["world.phase.night"] = false
	check(store.save(invalid, "day1.wait_human.shop") == ERR_INVALID_DATA, "Conflicting phase facts cannot become a checkpoint")
	var document: Dictionary = loaded.data.duplicate(true)
	document.format_version = 999
	check(store.validate_document(document) == ERR_INVALID_DATA, "Unknown file format is rejected")
	document = loaded.data.duplicate(true)
	document.game_state.schema_version = 3
	document.game_state.erase("task_results")
	check(store.validate_document(document) == OK, "Explicitly supported older full-state snapshots remain readable")
	store.fail_write = true
	check(store.save(snapshot, "day1.wait_human.shop", 102) != OK and store.load_save().data.saved_at == 100, "Failed temporary write preserves primary")
	store.fail_write = false
	store.fail_replace = true
	check(store.save(snapshot, "day1.wait_human.shop", 103) != OK and store.load_save().data.saved_at == 100, "Failed final rename preserves primary")
	store.fail_replace = false
	check(store.save(snapshot, "day1.wait_human.shop", 104) == OK, "Save can retry after a failed replacement")
	loaded = store.load_save(func(value: Dictionary) -> Error: return ERR_UNCONFIGURED if value.saved_at == 104 else OK)
	check(loaded.error == OK and loaded.used_backup, "Unavailable recovery resources also fall back before navigation")
	var file := FileAccess.open(_directory.path_join("autosave.dat"), FileAccess.WRITE)
	file.store_string("truncated")
	file.close()
	loaded = store.load_save()
	check(loaded.error == OK and loaded.used_backup and loaded.data.saved_at == 100, "Truncated primary falls back to the last verified backup")
	check(store.save(snapshot, "day1.wait_human.shop", 105) == OK, "A valid new primary can replace corruption")
	file = FileAccess.open(_directory.path_join("autosave.dat"), FileAccess.READ_WRITE)
	file.seek(file.get_length() - 1)
	file.store_8(254)
	file.close()
	check(store.load_save().used_backup and store.load_save().data.saved_at == 100, "Checksum detects corruption; corrupt primary never replaces backup")
	# A well-formed but invalid document must also fall back, before touching GameState.
	document = loaded.data.duplicate(true)
	document.checkpoint_id = "missing.content"
	check(store._write_file(_directory.path_join("autosave.dat"), document) == OK and store.load_save().used_backup, "Unknown content checkpoint falls back to backup")
	file = FileAccess.open(_directory.path_join("autosave.bak"), FileAccess.WRITE)
	file.store_string("broken backup")
	file.close()
	check(store.load_save().error != OK and state.to_dict() == snapshot, "Two unusable files never clear the live session")
	var blocked_path := _directory.path_join("blocked")
	file = FileAccess.open(blocked_path, FileAccess.WRITE)
	file.close()
	check(SaveStore.new(blocked_path).save(snapshot, "day1.wait_human.shop") != OK, "Unwritable directory reports failure")
	for name: String in ["autosave.dat", "autosave.bak", "autosave.tmp", "autosave.bak.tmp", "blocked"]:
		DirAccess.remove_absolute(_directory.path_join(name))
	DirAccess.remove_absolute(_directory)
	state.free()
	print("SAVE_STORE: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
