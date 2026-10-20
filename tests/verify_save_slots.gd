extends SceneTree
## Fixed-slot isolation, real paused actions and old-save compatibility.

var checks := 0
var failures: Array[String] = []
var directory := "user://verification/save_slots_%d" % OS.get_process_id()
var state: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count: int = 12) -> void:
	for frame in range(count):
		await process_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame

func click(button: Button) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/save_slots_work/screenshots")
	check(root.get_texture().get_image().save_png("res://.godot/save_slots_work/screenshots/" + name + ".png") == OK, "Capture actual save browser")

func wait_ready() -> MainGame:
	for frame in range(300):
		await process_frame
		if current_scene is MainGame and not current_scene.is_session_initializing():
			await frames()
			return current_scene as MainGame
	check(false, "Reconstructed session becomes ready")
	quit(1)
	return null

func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void: quit(1))
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	state = root.get_node("GameState")
	var fixture: Node = preload("res://src/core/game_state.gd").new()
	fixture.select_business_profile("day1")
	var snapshot: Dictionary = fixture.to_dict()
	fixture.free()
	var library := SaveLibrary.new(directory)
	check(library.get_entries().size() == 9 and not library.has_files(), "Nine empty slots without touching player saves")
	check(library.get_store("../escape") == null, "Unrecognized slot IDs cannot choose filesystem paths")
	var store := library.get_store("auto")
	check(store.directory == directory, "Legacy autosave and backup retain their original paths")
	var legacy := {"format_version": 1, "game_state": snapshot, "checkpoint_id": "day1.initial.shop", "saved_at": 99}
	DirAccess.make_dir_recursive_absolute(directory)
	check(store.validate_document(legacy) == OK and store._write_file(directory.path_join("autosave.dat"), legacy) == OK and store.load_save().data.format_version == 1, "Original format-one documents load at their existing path")
	for number in range(1, 5):
		snapshot.variables["save_test.marker"] = number
		check(library.save_automatic(store, snapshot, "day1.initial.shop", 100 + number) == OK, "Commit rotating automatic save")
	for index in range(3):
		var loaded := library.get_store(SaveLibrary.AUTOMATIC_IDS[index]).load_save()
		check(loaded.error == OK and loaded.data.game_state.variables["save_test.marker"] == 4 - index, "Automatic history retains the latest three complete snapshots")
	var automatic_before := FileAccess.get_file_as_bytes(directory.path_join("autosave.dat"))
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid.story_stage = "save_test.unpublished"
	check(library.save_automatic(store, invalid, "day1.initial.shop", 105) == ERR_INVALID_DATA and FileAccess.get_file_as_bytes(directory.path_join("autosave.dat")) == automatic_before, "Invalid snapshots cannot alter the automatic primary")
	var blocked_archive := library.get_store("auto_3").directory.path_join("autosave.bak.tmp")
	DirAccess.make_dir_recursive_absolute(blocked_archive)
	check(library.save_automatic(store, snapshot, "day1.initial.shop", 105) != OK and FileAccess.get_file_as_bytes(directory.path_join("autosave.dat")) == automatic_before, "An archive write failure preserves the most recent automatic checkpoint")
	DirAccess.remove_absolute(blocked_archive)
	for index in range(6):
		snapshot.variables["save_test.marker"] = index
		check(library.save_manual(SaveLibrary.MANUAL_IDS[index], snapshot, "day1.initial.shop", false, 200 + index) == OK, "Every manual slot is independently writable")
	check(library.save_manual("auto", snapshot, "day1.initial.shop") == ERR_INVALID_PARAMETER, "Manual save cannot target automatic history")
	check(library.save_manual("manual_1", snapshot, "day1.initial.shop") == ERR_ALREADY_EXISTS, "Occupied slot requires explicit overwrite")
	check(library.newest_valid_id() == "manual_6", "Continue can select the newest manual save")
	check(library.save_manual("manual_1", snapshot, "day1.initial.shop", true, 300) == OK, "Confirmed overwrite commits with a slot-local backup")
	var manual := library.get_store("manual_1")
	var broken := FileAccess.open(manual.directory.path_join("autosave.dat"), FileAccess.WRITE)
	broken.store_string("broken primary")
	broken.close()
	var backup := manual.load_save()
	check(backup.error == OK and backup.used_backup and backup.data.saved_at == 200, "Corrupt manual primary falls back only to its own backup")
	var entries := library.get_entries()
	check(entries[3].valid and entries[3].used_backup and entries[3].saved_at == 200, "Slot metadata describes the actual backup being loaded")
	broken = FileAccess.open(manual.directory.path_join("autosave.bak"), FileAccess.WRITE)
	broken.store_string("broken backup")
	broken.close()
	check(not library.get_entries()[3].valid and library.get_entries()[4].valid, "A wholly broken slot cannot disable its neighbors")
	check(library.save_automatic(store, snapshot, "day1.initial.shop", 400) == OK and library.get_store("manual_6").load_save().data.saved_at == 205, "Automatic commits never overwrite manual saves")
	check(library.save_manual("manual_6", snapshot, "day1.initial.shop", true, 400) == OK and library.newest_valid_id() == "manual_6", "Continue resolves saves made within the same second in actual write order")
	# Actual title and pause controls use a separate fresh session directory.
	ProjectSettings.set_setting("persistence/save_directory", directory.path_join("session"))
	check(GameEntry.start_new_game(self) == OK, "Start a formal save-enabled session")
	var game := await wait_ready()
	check(state.get_business_profile() == "day1" and state.get_variable("visuals.appearance_seed") is int, "First formal session selects its business profile before persisting the appearance seed")
	check(not game.can_save_manual(), "Opening playback blocks manual saving")
	game.get_story_director().cancel_event("Save slots fixture")
	var waiting: Dictionary = state.to_dict()
	waiting.story_stage = "day1.wait_human"
	waiting.completed_events = ["day1.opening"]
	waiting.flags["day1.human_open"] = true
	check(state.restore_state(waiting) == OK, "Prepare the real first-customer checkpoint")
	await frames(24)
	var ui := game.get_ui_manager()
	ui.set_paused(true)
	check(paused and game.can_save_manual(), "Paused safe checkpoint permits a manual save")
	var panel := game.get_node("PauseLayer/SaveSlotsPanel") as SaveSlotsPanel
	panel.open_mode(true)
	check(ui.open_screen(ScreenIds.SAVES) == OK, "Save browser opens above pause")
	var page: Control = panel.get_node("ModalShell").get_content()
	var action := page.get_node("Actions/Action") as Button
	check(not action.disabled, "First empty manual slot is selected and writable")
	await key(KEY_ENTER)
	var saved := GameEntry.create_save_store("manual_1").load_save()
	check(saved.error == OK and saved.data.game_state == state.to_dict(), "Pause save stores the complete current safe state")
	await capture("pause_save")
	var before := FileAccess.get_file_as_bytes(GameEntry.create_save_store("manual_1").directory.path_join("autosave.dat"))
	await click(action)
	check(page.get_node("Confirmation").visible, "Manual overwrite asks for confirmation")
	await capture("overwrite")
	await key(KEY_ESCAPE)
	check(panel.is_visible_in_tree() and not page.get_node("Confirmation").visible, "Escape first cancels the overwrite without closing the browser")
	check(FileAccess.get_file_as_bytes(GameEntry.create_save_store("manual_1").directory.path_join("autosave.dat")) == before, "Cancelled overwrite leaves disk bytes unchanged")
	state.set_flag("save_test.unsaved_progress")
	panel.open_mode(false)
	var list := page.get_node("Slots") as ItemList
	list.select(3)
	list.item_selected.emit(3)
	action.pressed.emit()
	check(page.get_node("Confirmation").visible, "Loading warns before abandoning unsaved progress")
	page.get_node("Confirmation/Confirm").pressed.emit()
	game = await wait_ready()
	check(not paused and not state.get_flag("save_test.unsaved_progress"), "Loading a manual slot from pause replaces the whole session and releases pause")
	check(game.get_player().movement_enabled and not game.get_ui_manager().has_modal(), "Loaded session releases input and modal locks")
	check(state.to_dict() == saved.data.game_state, "Manual reconstruction preserves the exact saved snapshot")
	check(GameEntry.return_to_title(self) == OK, "Leave the old session before starting another game")
	await scene_changed
	await frames()
	check(GameEntry.start_new_game(self) == OK, "Start another real session before testing interrupted dialogue")
	game = await wait_ready()
	check(GameEntry.create_save_store("manual_1").load_save().data == saved.data, "New game preserves the previous session's manual slot")
	var dialogue_deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < dialogue_deadline:
		await process_frame
		if game.get_dialogue_manager().is_active():
			break
	check(game.get_dialogue_manager().is_active(), "Fresh session reaches its real opening dialogue")
	game.get_ui_manager().set_paused(true)
	check(game.save_manual("manual_2") == ERR_BUSY, "Pause cannot save over an active dialogue")
	check(GameEntry.continue_game(self, "manual_1") == OK, "An explicitly selected save can replace a paused dialogue")
	game = await wait_ready()
	check(state.to_dict() == saved.data.game_state and not state.get_flag("test.after_cancel") and not paused, "Cancelled old-scene callbacks cannot contaminate the restored snapshot")
	check(GameEntry.return_to_title(self) == OK, "Return to actual title")
	await scene_changed
	await frames()
	var title := current_scene as TitleMenu
	title.get_node("Center/Panel/Margin/Content/LoadGame").pressed.emit()
	await frames(2)
	check(title.get_node("SaveSlotsPanel").is_visible_in_tree(), "Title exposes the same readable slot browser")
	await capture("title_load")
	title.get_node("SaveSlotsPanel")._close()
	check(title.get_node("Center").visible, "Closing the title browser returns to the title controls")
	print("SAVE_SLOTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
