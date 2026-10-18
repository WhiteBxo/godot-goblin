extends SceneTree
## Real hosts, title controls and separate engine processes. Never uses player saves.

var _checks := 0
var _failures: Array[String] = []
var _state: Node
var _directory := "user://verification/save_game_%d" % OS.get_process_id()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func frames(count: int = 10) -> void:
	for index in range(count):
		await process_frame

func _wait_ready() -> MainGame:
	for index in range(240):
		if current_scene is MainGame and not current_scene.is_session_initializing():
			await frames()
			return current_scene as MainGame
		await process_frame
	check(false, "Session initialization finishes within 240 frames")
	quit(1)
	return null

func _wait_saved(checkpoint_id: String = "") -> Dictionary:
	for index in range(120):
		await process_frame
		var result := GameEntry.create_save_store().load_save()
		if result.error == OK and result.data.game_state == _state.to_dict() and (checkpoint_id.is_empty() or result.data.checkpoint_id == checkpoint_id):
			return result.data
	check(false, "Safe state reaches disk within 120 frames")
	return {}

func _human_checkpoint(game: MainGame) -> void:
	game.get_story_director().cancel_event("Save test fixture")
	var snapshot: Dictionary = _state.to_dict()
	snapshot.story_stage = "day1.wait_human"
	snapshot.completed_events = ["day1.opening"]
	snapshot.flags["day1.human_open"] = true
	check(_state.restore_state(snapshot) == OK, "Prepare a published first-customer checkpoint")
	await frames()

func _run() -> void:
	create_timer(100.0).timeout.connect(func() -> void:
		push_error("Save integration timed out")
		quit(1)
	)
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	var mode := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--save-worker="):
			mode = argument.trim_prefix("--save-worker=")
		if argument.begins_with("--save-directory="):
			_directory = argument.trim_prefix("--save-directory=")
	ProjectSettings.set_setting("persistence/save_directory", _directory)
	_state = root.get_node("GameState")
	if not mode.is_empty():
		await _worker(mode)
		_finish()
		return
	check(change_scene_to_file(GameEntry.GAME_SCENE) == OK, "Direct scene run opens the shop")
	await scene_changed
	await frames()
	check(current_scene.get_save_coordinator() == null and not GameEntry.create_save_store().has_files(), "Fresh F6-style scene run never writes player saves")
	check(change_scene_to_file(GameEntry.TITLE_SCENE) == OK, "Open real title without a save")
	await scene_changed
	await frames()
	var title := current_scene as TitleMenu
	check(not title.get_node("Center/Panel/Margin/Content/Continue").visible, "Continue is hidden without valid data")
	check(GameEntry.continue_game(self) == ERR_FILE_NOT_FOUND, "Missing save does not leave title")
	check(GameEntry.start_new_game(self) == OK, "New game starts through the shared navigation lock")
	check(GameEntry.start_new_game(self) == ERR_BUSY, "Duplicate navigation is rejected during initialization")
	var game := await _wait_ready()
	check(game != null and game.get_save_coordinator() != null, "Formal session owns a scene-local coordinator")
	var initial := GameEntry.create_save_store().load_save()
	check(initial.error == OK and initial.data.checkpoint_id == "day1.initial.shop", "Initial checkpoint is written before opening playback")
	check(game.get_story_director().is_busy(), "Opening starts after initial checkpoint is committed")
	await _human_checkpoint(game)
	check(game.get_task_delivery().accept_order("day1_human") == OK, "Accept formal customer order")
	check(game.get_tea_production().make_drink(["black_tea", "creamer", "pearl", "syrup"], "day1_human").ok, "Produce a real inventory item")
	var crafted := await _wait_saved()
	check(not crafted.is_empty() and crafted.checkpoint_id == "day1.wait_human.shop", "Bridge gameplay wait is an autosave boundary")
	var before := FileAccess.get_file_as_bytes(_directory.path_join("autosave.dat"))
	_ui_pause(game, true)
	_state.set_flag("save_test.while_paused")
	await frames()
	check(FileAccess.get_file_as_bytes(_directory.path_join("autosave.dat")) == before, "Pause never commits a pending state")
	check(game.get_node("PauseLayer/PauseMenu/Center/Panel/Margin/Content/SaveStatus").text.contains("最近保存"), "Pause shows latest successful save time")
	await _snapshot("pause")
	_ui_pause(game, false)
	await _wait_saved()
	_state.set_story_stage("day2.unpublished")
	await frames()
	check(GameEntry.create_save_store().load_save().data.game_state.story_stage == "day1.wait_human", "An unpublished stage cannot overwrite a known checkpoint")
	check(GameEntry.return_to_title(self) == OK, "Return to title without unsafe exit save")
	await scene_changed
	await frames()
	title = current_scene as TitleMenu
	var continue_button := title.get_node("Center/Panel/Margin/Content/Continue") as Button
	check(continue_button.visible and root.gui_get_focus_owner() == continue_button, "Valid save defaults keyboard focus to Continue")
	await _snapshot("continue")
	title._request_new_game()
	check(title.get_node("Center/Panel/Margin/Content/Confirmation").visible, "New game requests overwrite confirmation")
	await _snapshot("overwrite")
	title._cancel_new_game()
	check(root.gui_get_focus_owner() == continue_button and FileAccess.get_file_as_bytes(_directory.path_join("autosave.dat")) != PackedByteArray(), "Cancelling overwrite retains the existing save and focus")
	var expected: Dictionary = GameEntry.create_save_store().load_save().data.game_state
	continue_button.pressed.emit()
	game = await _wait_ready()
	check(_state.to_dict() == expected, "Continue replaces the unsafe live session with the disk checkpoint")
	check(game.get_player().movement_enabled and not game.get_story_director().is_busy(), "Recovery releases input at the gameplay boundary")
	check(game.get_tea_production().get_completed_count() == 1 and game.get_warehouse_inventory().get_stock("pearl_milk_tea") == 1, "Crafted progress and product both survive")
	await _test_travel()
	await _test_bad_continue()
	# Distinct processes must recreate all state, not reuse Autoload memory.
	var cross_directory := _directory + "_cross"
	for worker_mode: String in ["craft", "read_craft", "deliver", "read_delivery"]:
		var output: Array = []
		var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/verify_save_game.gd", "--", "--save-worker=" + worker_mode, "--save-directory=" + cross_directory], output, true)
		check(code == 0 and str(output).contains("SAVE_GAME: PASS"), "Separate process round trip: " + worker_mode)
		if code != 0:
			print(output)
	_cleanup(cross_directory)
	_cleanup(_directory)
	_finish()

func _ui_pause(game: MainGame, enabled: bool) -> void:
	game.get_ui_manager().set_paused(enabled)

func _test_travel() -> void:
	var snapshot: Dictionary = _state.to_dict()
	snapshot.story_stage = "day1.investigate_coins"
	snapshot.completed_events = ["day1.opening", "day1.first_goblin", "day1.group_arrival", "day1.ending"]
	snapshot.flags["day1.stages_01_02_completed"] = true
	check(_state.restore_state(snapshot) == OK, "Restore the published exploration handoff")
	await frames(16)
	await _wait_saved()
	var game := current_scene as MainGame
	var exit: SceneExit = game.get_active_level().get_scene_exits()[0]
	check(game.get_scene_travel().request_exit(exit) == OK, "Use actual shop-to-settlement navigation")
	await scene_changed
	game = current_scene as MainGame
	for index in range(100):
		await process_frame
		if not game.get_scene_travel().is_busy():
			break
	var saved := await _wait_saved("day1.investigate.settlement")
	check(saved.checkpoint_id == "day1.investigate.settlement", "Arrival saves the destination checkpoint")
	check(GameEntry.return_to_title(self) == OK, "Leave settlement for title")
	await scene_changed
	await frames()
	check(GameEntry.continue_game(self) == OK, "Continue into the saved settlement host")
	game = await _wait_ready()
	check(game.scene_file_path == "res://src/core/settlement.tscn", "Saved host is restored")
	var entrance: SceneEntrance = game.get_active_level().get_scene_entrance(&"shop_door")
	check(entrance != null and game.get_player().global_position.is_equal_approx(entrance.global_position), "Restore uses the authored settlement entrance")
	check(not _state.get_flag("day1.s05.returned_shop"), "Restoration never invents a return-to-shop fact")
	# Exercise the real host's stealth guard while controlling only test timing.
	var stealth := game.get_stealth_service()
	stealth.set_physics_process(false)
	stealth.status = Day1StealthService.Status.RUNNING
	var prior_save: Dictionary = GameEntry.create_save_store().load_save().data
	_state.get_warehouse_inventory().try_consume({"black_tea": 1})
	_state.set_flag("save_test.during_stealth")
	await frames()
	check(not game._can_save_checkpoint() and GameEntry.create_save_store().load_save().data == prior_save, "Active stealth preserves the entire pre-attempt checkpoint")
	check(_state.restore_state(prior_save.game_state) == OK, "Returning to a checkpoint restores inventory and facts together")
	stealth.status = Day1StealthService.Status.IDLE
	stealth.set_physics_process(true)

func _test_bad_continue() -> void:
	check(GameEntry.return_to_title(self) == OK, "Return for failed-load checks")
	await scene_changed
	await frames()
	var backup: Dictionary = GameEntry.create_save_store()._read_file(_directory.path_join("autosave.bak")).data
	var file := FileAccess.open(_directory.path_join("autosave.dat"), FileAccess.WRITE)
	file.store_string("broken primary")
	file.close()
	check(GameEntry.return_to_title(self) == OK, "Refresh title after primary damage")
	await scene_changed
	await frames()
	check(current_scene.get_node("Center/Panel/Margin/Content/Error").text.contains("备份"), "Title explains backup recovery")
	check(GameEntry.continue_game(self) == OK, "Continue falls back to a valid backup")
	await _wait_ready()
	check(_state.to_dict() == backup.game_state, "Backup recreates its complete checkpoint")
	check(GameEntry.return_to_title(self) == OK, "Return after backup verification")
	await scene_changed
	await frames()
	var title := current_scene
	var snapshot: Dictionary = _state.to_dict()
	for name: String in ["autosave.dat", "autosave.bak"]:
		file = FileAccess.open(_directory.path_join(name), FileAccess.WRITE)
		file.store_string("broken")
		file.close()
	check(GameEntry.continue_game(self) != OK and current_scene == title and _state.to_dict() == snapshot, "Bad primary and backup preserve the title and previous session")

func _worker(mode: String) -> void:
	if mode == "craft":
		check(GameEntry.start_new_game(self) == OK, "Worker starts a fresh formal game")
		var game := await _wait_ready()
		await _human_checkpoint(game)
		check(game.get_task_delivery().accept_order("day1_human") == OK, "Worker accepts order")
		check(game.get_tea_production().make_drink(["black_tea", "creamer", "pearl", "syrup"], "day1_human").ok, "Worker crafts product")
		_state.set_variable("save_test.numeric", [12, 12.0])
		var saved := await _wait_saved()
		_write_expected(saved.game_state)
		return
	check(GameEntry.continue_game(self) == OK, "Worker continues a previous process save")
	var game := await _wait_ready()
	var file := FileAccess.open(_directory.path_join("expected.dat"), FileAccess.READ)
	var expected: Dictionary = file.get_var(false)
	file.close()
	check(_state.to_dict() == expected, "A fresh process exactly recreates all session facts")
	check(typeof(_state.get_variable("save_test.numeric")[0]) == TYPE_INT and typeof(_state.get_variable("save_test.numeric")[1]) == TYPE_FLOAT, "Native numeric types survive a process restart")
	if mode == "deliver":
		check(game.get_task_delivery().deliver_to("human_customer").ok, "Worker makes a real paid delivery")
		var deadline := Time.get_ticks_msec() + 35000
		while (not _state.is_event_completed("day1.first_goblin") or game.get_story_director().is_busy()) and Time.get_ticks_msec() < deadline:
			if game.get_dialogue_manager().is_active():
				game.get_dialogue_manager().advance()
			await process_frame
		check(_state.is_event_completed("day1.first_goblin"), "Delivery continuation reaches the next recoverable event boundary")
		var saved := await _wait_saved()
		_write_expected(saved.game_state)
	elif mode == "read_delivery":
		var before: Dictionary = _state.to_dict()
		check(not game.get_task_delivery().deliver_to("human_customer").ok and _state.to_dict() == before, "Reopened delivery cannot pay or deduct again")

func _write_expected(snapshot: Dictionary) -> void:
	var file := FileAccess.open(_directory.path_join("expected.dat"), FileAccess.WRITE)
	file.store_var(snapshot, false)
	file.close()

func _snapshot(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/verification/save_system/screenshots")
	root.get_texture().get_image().save_png("res://.godot/verification/save_system/screenshots/" + name + ".png")

func _cleanup(directory: String) -> void:
	for name: String in ["autosave.dat", "autosave.bak", "autosave.tmp", "autosave.bak.tmp", "expected.dat"]:
		if FileAccess.file_exists(directory.path_join(name)):
			DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)

func _finish() -> void:
	print("SAVE_GAME: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
