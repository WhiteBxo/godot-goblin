extends SceneTree
## Isolated day/phase + terminal task fixtures. This publishes no Day 2 gameplay.

const StateData = preload("res://src/core/game_state.gd")
var _checks := 0
var _failures: Array[String] = []
var _directory := "user://verification/save_boundaries_%d" % OS.get_process_id()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func frames(count: int = 8) -> void:
	for index in range(count):
		await process_frame

func _catalog() -> SaveCheckpoints:
	var catalog := SaveCheckpoints.new()
	var entries: Array[Dictionary] = []
	for day: int in [1, 2]:
		entries.append({"id": "save_test.day%d" % day, "scene": "res://src/core/main.tscn", "entrance": "", "stage": "save_test.day%d" % day,
			"day": day, "phase": "night" if day == 1 else "day", "after_event": "", "before_event": "", "required_flags": [], "recovery": "chapter"})
	check(catalog.load_data({"version": 1, "checkpoints": entries}) == OK, "Load independent boundary declarations")
	return catalog

func _bind_tasks(state: Node) -> bool:
	var tasks: Array[Dictionary] = []
	for result: String in ["expired", "completed", "failed"]:
		var task := {"id": "save_test." + result, "type": "commission", "title": "测试", "description": "独立存档夹具",
			"activate_when": {"type": "flag", "key": "save_test.active"},
			"complete_when": {"type": "flag", "key": "save_test." + result + "_done"},
			"objectives": [{"id": "goal", "text": "测试", "complete_when": {"type": "flag", "key": "save_test." + result + "_done"}}]}
		if result == "expired":
			task["deadline"] = {"day": 2, "phase": "day", "boundary": "at"}
		if result == "failed":
			task["fail_when"] = {"type": "flag", "key": "save_test.failed_now"}
		tasks.append(task)
	var catalog := TaskCatalog.new()
	check(catalog.load_json(JSON.stringify({"version": 1, "tasks": tasks})) == OK, "Load independent task fixtures")
	check(state.bind_task_catalog(catalog) == OK, "Bind task facts before full-state restoration")
	return true

func _run() -> void:
	var reader := false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--boundary-directory="):
			_directory = argument.trim_prefix("--boundary-directory=")
			reader = true
	var state: Node = StateData.new()
	state.select_business_profile("day1")
	var tasks_supported := _bind_tasks(state)
	var store := SaveStore.new(_directory, _catalog())
	if reader:
		var loaded := store.load_save()
		check(loaded.error == OK and state.restore_state(loaded.data.game_state) == OK, "New process restores the day-two full snapshot")
		check(state.current_day == 2 and DayPhase.get_phase(state) == "day", "Date and phase cross the process boundary together")
		if tasks_supported:
			for status: String in ["expired", "completed", "failed"]:
				check(state.get_task_result("save_test." + status).get("status") == status, "Terminal outcome survives restart: " + status)
		var before: Dictionary = state.to_dict()
		check(state.restore_state(loaded.data.game_state) == OK and state.to_dict() == before, "Repeated full restore does not settle tasks again")
		state.free()
		_finish()
		return
	state.set_flag("save_test.active")
	check(DayPhase.enter_night(state), "Fixture enters first night")
	state.set_story_stage("save_test.day1")
	check(store.save(state.to_dict(), "save_test.day1", 100) == OK, "Save before the cross-day deadline")
	var before: Dictionary = store.load_save().data
	if tasks_supported:
		check(state.get_task_result("save_test.expired").is_empty(), "Deadline has not settled before its boundary")
	var safe: Array[bool] = [false]
	var coordinator := SaveCoordinator.new()
	root.add_child(coordinator)
	GameEntry._save_session_active = true
	coordinator.configure(state, store, func() -> Dictionary: return store.checkpoints.find_checkpoint(state.to_dict(), "res://src/core/main.tscn"), func() -> bool: return safe[0])
	check(DayPhase.enter_day(state) and state.current_day == 2, "Night-to-day atomically advances the day")
	state.set_story_stage("save_test.day2")
	state.set_flag("save_test.completed_done")
	state.set_flag("save_test.failed_now")
	state.get_warehouse_inventory().try_consume({"black_tea": 1})
	await frames()
	check(store.load_save().data == before, "Unsafe transition retains the whole previous-day checkpoint")
	safe[0] = true
	await frames()
	var after := store.load_save()
	check(after.error == OK and after.data.game_state == state.to_dict(), "Next safe boundary commits date, resources and every final outcome together")
	if tasks_supported:
		for status: String in ["expired", "completed", "failed"]:
			check(after.data.game_state.task_results["save_test." + status].status == status, "Saved terminal result: " + status)
	check(not DayPhase.enter_day(state), "Repeating the same phase does not advance time")
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/verify_save_boundaries.gd", "--", "--boundary-directory=" + _directory], output, true)
	check(code == 0 and str(output).contains("SAVE_BOUNDARIES: PASS"), "Separate engine verifies the cross-day snapshot")
	if code != 0:
		print(output)
	coordinator.free()
	# Startup is Always-processing, but pausing must not consume its deadline.
	var initialized: Array[bool] = [false]
	var restoring := SaveCoordinator.new()
	root.add_child(restoring)
	restoring.configure(state, store, func() -> Dictionary: return store.checkpoints.find_checkpoint(state.to_dict(), "res://src/core/main.tscn"), func() -> bool: return true,
		func(error: Error) -> void: initialized[0] = error == OK)
	var previous_file := FileAccess.get_file_as_bytes(_directory.path_join("autosave.dat"))
	paused = true
	await frames(190)
	check(not initialized[0] and restoring._startup_frames == 0, "Pausing startup never consumes the restoration deadline")
	paused = false
	await frames()
	check(initialized[0] and FileAccess.get_file_as_bytes(_directory.path_join("autosave.dat")) == previous_file, "Resume completes restoration without rewriting the checkpoint")
	restoring.free()
	# A file I/O error is visible while retaining the last good checkpoint.
	var blocked := _directory.path_join("blocked")
	var blocker := FileAccess.open(blocked, FileAccess.WRITE)
	blocker.close()
	var failed := SaveCoordinator.new()
	root.add_child(failed)
	failed.configure(state, SaveStore.new(blocked, _catalog()), func() -> Dictionary: return store.checkpoints.find_checkpoint(state.to_dict(), "res://src/core/main.tscn"), func() -> bool: return true)
	await frames()
	check(failed.get_status_text().contains("保存失败") and store.load_save().data.game_state == state.to_dict(), "Write errors surface without changing the valid slot")
	failed.free()
	DirAccess.remove_absolute(blocked)
	state.free()
	for name: String in ["autosave.dat", "autosave.bak", "autosave.tmp", "autosave.bak.tmp"]:
		if FileAccess.file_exists(_directory.path_join(name)):
			DirAccess.remove_absolute(_directory.path_join(name))
	DirAccess.remove_absolute(_directory)
	_finish()

func _finish() -> void:
	print("SAVE_BOUNDARIES: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
