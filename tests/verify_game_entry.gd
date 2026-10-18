extends SceneTree

const StateData = preload("res://src/core/game_state.gd")
const RECIPE: Array[String] = ["black_tea", "creamer", "pearl", "syrup"]
var _checks := 0
var _failures: Array[String] = []
var _state: StateData
var _capture := false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames() -> void:
	for index in range(3):
		await process_frame

func _button(menu: Control, name: String) -> Button:
	return menu.get_node("Center/Panel/Margin/Content/" + name) as Button

func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame

func _click(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func _wait_for_scene(path: String) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if current_scene != null and current_scene.scene_file_path == path:
			await _frames()
			return true
		await process_frame
	_check(false, "Navigation reaches " + path)
	return false

func _snapshot(name: String) -> void:
	if not _capture:
		return
	await RenderingServer.frame_post_draw
	var directory := "res://.godot/game_entry"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_check(root.get_texture().get_image().save_png(directory + "/" + name + ".png") == OK, "Capture " + name)

func _check_layout(menu: Control, name: String) -> void:
	var panel := menu.get_node("Center/Panel") as Control
	_check(root.get_visible_rect().encloses(panel.get_global_rect()), name + " fits the viewport")
	for button_name: String in (["NewGame", "Quit"] if menu is TitleMenu else ["Resume", "ReturnTitle"]):
		_check(panel.get_global_rect().encloses(_button(menu, button_name).get_global_rect()), name + " contains " + button_name)

func _is_fresh_day1(defaults: Dictionary) -> bool:
	var snapshot := _state.to_dict()
	return (snapshot.business.profile_id == "day1" and snapshot.current_day == 1
		and snapshot.economy == defaults.economy
		and snapshot.business.production == defaults.business.production
		and not _state.get_flag("entry.old_run") and not _state.get_flag("entry.keep_on_reload")
		and not _state.is_event_completed("entry.completed"))

func _run() -> void:
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/game_entry_%d" % OS.get_process_id())
	_capture = "--capture" in OS.get_cmdline_user_args()
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	_state = root.get_node("GameState")
	_state.start_new_game()
	var defaults := _state.to_dict()
	_check(ProjectSettings.get_setting("application/run/main_scene") == GameEntry.TITLE_SCENE, "F5 starts at title")
	_check(change_scene_to_file(GameEntry.TITLE_SCENE) == OK, "Load real title scene")
	await scene_changed
	await _frames()
	var title := current_scene as TitleMenu
	_check(title != null and root.gui_get_focus_owner() == _button(title, "NewGame"), "Title defaults to new game focus")
	_check(_state.to_dict() == defaults and not paused, "Title does not mutate the session or pause")
	if "--verify-quit" in OS.get_cmdline_user_args():
		_button(title, "Quit").pressed.emit()
		_check(_state.to_dict() == defaults, "Quit does not reset session")
		print("GAME_ENTRY_QUIT: requested via actual quit button")
		return
	if not OS.has_feature("debug"):
		var probe := root.get_node_or_null("MCPRuntimeProbe")
		_check(probe == null or not probe.is_processing(), "Release title stops runtime probe polling")
	await _key(KEY_TAB)
	_check(root.gui_get_focus_owner() == _button(title, "Quit"), "Native Tab reaches quit")
	await _key(KEY_TAB)
	_check(root.gui_get_focus_owner() == _button(title, "NewGame"), "Native Tab wraps to new game")
	for window_size: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		root.size = window_size
		await _frames()
		_check_layout(title, "Title %s" % window_size)
		await _snapshot("title_%dx%d" % [window_size.x, window_size.y])
	# A reset refusal must preserve the title, focus and all data, then allow retry.
	_state.set_flag("entry.old_run")
	var before := _state.to_dict()
	_check(_state.begin_business_transaction(), "Hold existing session transaction")
	_button(title, "NewGame").pressed.emit()
	_button(title, "NewGame").pressed.emit()
	_check(_button(title, "NewGame").disabled and _button(title, "Quit").disabled, "Pending start disables both buttons")
	await create_timer(0.6).timeout
	await _frames()
	_check(current_scene == title and _state.to_dict() == before, "Busy reset leaves scene and session intact")
	_check(not _button(title, "NewGame").disabled and title.get_node("Center/Panel/Margin/Content/Error").visible, "Start failure is visible and retry enabled")
	_check(root.gui_get_focus_owner() == _button(title, "NewGame"), "Failure restores keyboard focus")
	_state.end_business_transaction()
	_check(GameEntry.start_new_game(null) == ERR_INVALID_PARAMETER, "Missing SceneTree rejects")
	_check(GameEntry._navigate(self, "res://src/core/missing_entry.tscn", true) == ERR_FILE_NOT_FOUND, "Missing target rejects before reset")
	_check(_state.to_dict() == before and current_scene == title, "Bad target never resets or leaves title")
	_check(GameEntry._navigate(self, "res://src/resources/ui/game_theme.tres", true) != OK, "Non-scene target rejects")
	_check(_state.to_dict() == before, "Invalid resource leaves state untouched")
	var reset_count: Array[int] = [0]
	var reentries: Array[int] = []
	var observer := func() -> void:
		reset_count[0] += 1
		reentries.append(GameEntry.start_new_game(self))
	_state.state_reset.connect(observer)
	# Real keyboard confirmation, not a direct call to the navigation service.
	await _key(KEY_ENTER)
	await _wait_for_scene(GameEntry.GAME_SCENE)
	_state.state_reset.disconnect(observer)
	_check(reset_count == [1] and reentries == [ERR_BUSY], "One start rejects reset-listener navigation reentry")
	var game := current_scene as MainGame
	var state_connections := _state.state_changed.get_connections().size()
	_check(game != null, "New game uses existing MainGame")
	_check(_is_fresh_day1(defaults), "New game clears the prior session and selects the Day 1 business profile")
	_check(game.get_player().global_position.is_equal_approx(game.get_active_level().get_spawn_position()), "New game uses shop spawn")
	_check(not game.get_player().movement_enabled and not game.get("_shop_interaction").is_input_enabled(), "Day 1 opening retains its input lock")
	_check(game.get_day1_controller() != null and game.get_story_director().is_busy(), "New game starts the real Day 1 opening")
	_check(not game.get_gameplay_bridge().get("_links").is_empty(), "Day 1 gameplay phases load at the formal entry")
	# Restore a valid gameplay checkpoint; the full cinematic is exercised separately.
	var checkpoint := _state.to_dict()
	checkpoint.completed_events = ["day1.opening"]
	checkpoint.story_stage = "day1.wait_human"
	checkpoint.flags["day1.human_open"] = true
	_check(_state.restore_state(checkpoint) == OK, "Restore the Day 1 first-customer checkpoint")
	await _frames()
	_check(game.get_task_delivery().accept_order("day1_human") == OK, "Accept a real Day 1 order")
	_check(game.get_tea_production().make_drink(RECIPE, "day1_human").ok, "Craft real product")
	_check(game.get_task_delivery().deliver_to("human_customer").ok, "Create a real delivery and payment receipt")
	_check(game.get_warehouse_inventory().add_ingredient("coconut_milk_tea", 1), "Carry another product for new-game reset coverage")
	_check(game.get_transactions().add_money(25, "entry.income").ok, "Create balance and transaction receipt")
	var journal := game.get_chronicle_journal()
	_check(journal.unlock_entry("entry.place", "测试地点") == OK, "Unlock chronicle")
	journal.append_record("entry.place", "entry.record", "测试记录")
	journal.mark_read("entry.place")
	_state.set_current_day(2)
	_state.set_story_stage("entry.old_stage")
	_state.complete_event("entry.completed")
	var old_run := _state.to_dict()
	var old_game: WeakRef = weakref(game)
	# Exercise exit while real dialogue, audio and an underlying modal are active.
	game.get_gameplay_bridge().stop(true)
	game.get_story_director().cancel_event("Entry cancellation fixture")
	game.get_audio_manager().register_sound("entry.music", load("res://assets/audio/music/daily_milk_tea.ogg"))
	_check(game.get_audio_manager().play_bgm("entry.music", 0.0) == OK, "Play scene audio")
	_check(game.get_dialogue_manager().load_dialogues("res://src/resources/dialogue/day1_scene01.json") == OK, "Load cancellation dialogue fixture")
	_check(game.get_story_director().load_events("res://src/resources/story/day1_scene01.json") == OK, "Load cancellation story fixture")
	_check(game.get_story_director().request_event("day1.scene01") == OK, "Start real story before pause")
	await _frames()
	_check(game.get_dialogue_manager().is_active(), "Story reaches real dialogue")
	game.get_ui_manager().set_paused(true)
	await _frames()
	var pause := game.get_node("PauseLayer/PauseMenu") as PauseMenu
	_check(paused and pause.visible and not game.get_player().movement_enabled, "Pause covers active dialogue")
	for window_size: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		root.size = window_size
		await _frames()
		_check_layout(pause, "Pause %s" % window_size)
		await _snapshot("pause_%dx%d" % [window_size.x, window_size.y])
	var old_audio: WeakRef = weakref(game.get_audio_manager())
	var old_dialogue: WeakRef = weakref(game.get_dialogue_manager())
	var old_ui: WeakRef = weakref(game.get_ui_manager())
	# Mouse dispatch through the actual pause button.
	await _click(_button(pause, "ReturnTitle"))
	if not await _wait_for_scene(GameEntry.TITLE_SCENE):
		quit(1)
		return
	_check(not paused and old_game.get_ref() == null, "Return disposes game and releases pause")
	_check(old_audio.get_ref() == null and old_dialogue.get_ref() == null and old_ui.get_ref() == null, "Scene audio, dialogue and UI are freed")
	_check(_state.to_dict() == old_run, "Return to title preserves session until explicit new game")
	title = current_scene as TitleMenu
	_check(root.gui_get_focus_owner() == _button(title, "Continue"), "Returned title focuses the persisted game")
	# Synthetic duplicate presses also cover code paths beyond native disabled GUI.
	_button(title, "NewGame").pressed.emit()
	_button(title, "NewGame").pressed.emit()
	title.get_node("Center/Panel/Margin/Content/Confirmation/Confirm").pressed.emit()
	await _wait_for_scene(GameEntry.GAME_SCENE)
	game = current_scene as MainGame
	_check(_is_fresh_day1(defaults), "Second new game clears stock, cups, queue, money, receipts, tasks and journal")
	_check(game.get_chronicle_journal().get_entries().is_empty(), "New game clears chronicle read state")
	_check(_state.state_changed.get_connections().size() == state_connections, "No accumulated scene subscriptions")
	# Direct F6-like instantiation and F3-style reload keep the same run.
	_state.set_flag("entry.keep_on_reload")
	before = _state.to_dict()
	_check(reload_current_scene() == OK, "Reload existing shop")
	await scene_changed
	await _frames()
	_check(_state.to_dict() == before, "Scene reload never starts a new game")
	_check(change_scene_to_file("res://src/core/settlement.tscn") == OK, "Direct settlement entry remains available")
	await scene_changed
	await _frames()
	_check(_state.to_dict() == before, "Direct scene entry preserves session")
	await _test_paused_return_failure()
	await _key(KEY_P)
	_check(paused, "P opens pause after failure recovery")
	await _key(KEY_TAB)
	await _key(KEY_ENTER)
	if not await _wait_for_scene(GameEntry.TITLE_SCENE):
		quit(1)
		return
	_check(not paused, "Keyboard return releases pause")
	await _click(_button(current_scene as TitleMenu, "NewGame"))
	await _click(current_scene.get_node("Center/Panel/Margin/Content/Confirmation/Confirm"))
	if not await _wait_for_scene(GameEntry.GAME_SCENE):
		quit(1)
		return
	_check(_is_fresh_day1(defaults), "Mouse new game also resets the Day 1 session")
	print("GAME_ENTRY: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_paused_return_failure() -> void:
	var game := current_scene as MainGame
	game.get_ui_manager().set_paused(true)
	await _frames()
	var pause := game.get_node("PauseLayer/PauseMenu") as PauseMenu
	# Reserve the shared navigation slot to exercise a real ERR_BUSY response.
	GameEntry._changing_scene = true
	_button(pause, "ReturnTitle").pressed.emit()
	_button(pause, "ReturnTitle").pressed.emit()
	await _frames()
	_check(current_scene == game and paused, "Failed return keeps paused game")
	_check(not _button(pause, "ReturnTitle").disabled and not _button(pause, "Resume").disabled, "Failed return restores both buttons")
	_check(pause.get_node("Center/Panel/Margin/Content/Error").visible, "Failed return displays an error")
	GameEntry._changing_scene = false
	_button(pause, "Resume").pressed.emit()
	_check(not paused and game.get_player().movement_enabled, "Continue still works after failed return")
