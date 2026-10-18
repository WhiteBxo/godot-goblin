extends SceneTree

const StateData = preload("res://src/core/game_state.gd")
const STORY := "res://src/debug/characters/demo_story.json"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func frames(count: int = 3) -> void:
	for index in range(count):
		await process_frame

func tap(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	var state: StateData = root.get_node("GameState")
	state.reset_state()
	var journal := CharacterJournal.new()
	check(journal.unlock_character("test.first", "人物") == ERR_UNCONFIGURED, "Unconfigured service rejects writes")
	check(journal.configure(state) == OK, "Service supports pre-tree configuration")
	check(journal.get_characters().is_empty() and journal.get_character("test.hidden").is_empty(), "Locked characters are absent")
	check(journal.append_record("test.first", "test.record", "内容") == ERR_DOES_NOT_EXIST, "Append cannot unlock unknown people")
	check(journal.unlock_character("bad", "人物") == ERR_INVALID_PARAMETER and journal.unlock_character("test.first", " ") == ERR_INVALID_PARAMETER, "Invalid ID and empty name rejected")
	check(journal.unlock_character("test.first", "人物") == OK and journal.get_unread_count() == 1, "Pre-tree unlock is immediately visible and unread")
	root.add_child(journal)
	var notifications: Array[bool] = []
	journal.changed.connect(func() -> void: notifications.append(true))
	journal.mark_read("test.first")
	var count := notifications.size()
	check(journal.mark_read("test.first") == OK and notifications.size() == count, "Repeated read has no notification")
	check(journal.unlock_character("test.first", "改名") == OK and journal.get_character("test.first").title == "人物" and journal.get_unread_count() == 0, "Duplicate unlock preserves name and read state")
	check(journal.append_record("test.first", "test.record", "身份——测试 [b]原文[/b]") == OK and journal.get_unread_count() == 1, "New knowledge is unread")
	journal.mark_read("test.first")
	count = notifications.size()
	check(journal.append_record("test.first", "test.record", "不能覆盖") == OK and notifications.size() == count and journal.get_character("test.first").is_read, "Retry preserves first content and read state")
	journal.unlock_character("test.second", "另一位人物")
	check(journal.append_record("test.second", "test.record", "冲突") == ERR_ALREADY_EXISTS, "Record IDs are globally unique")
	check(journal.append_record("test.first", "bad", "内容") == ERR_INVALID_PARAMETER and journal.append_record("test.first", "test.empty", " ") == ERR_INVALID_PARAMETER, "Invalid records rejected")
	check(journal.mark_read("test.hidden") == ERR_DOES_NOT_EXIST, "Unknown person cannot be read")
	var exposed := journal.get_characters()
	exposed[0].records.clear()
	check(journal.get_character("test.first").records.size() == 1, "Returned data cannot mutate progress")
	count = notifications.size()
	state.set_flag("test.unrelated")
	check(notifications.size() == count and state.get_variable(ChronicleJournal.STATE_KEY, {}).is_empty(), "Unrelated facts and chronicle stay independent")
	var snapshot := state.to_dict()
	var path := "user://verify_character_records.bin"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(snapshot)
	file.close()
	state.reset_state()
	check(journal.get_characters().is_empty(), "Reset clears all people")
	file = FileAccess.open(path, FileAccess.READ)
	check(state.restore_state(file.get_var()) == OK, "Existing snapshot supports disk round trip")
	file.close()
	DirAccess.remove_absolute(path)
	check(journal.get_character("test.first").is_read and journal.get_unread_count() == 1, "Restore retains knowledge and mixed read states")
	root.remove_child(journal)
	state.reset_state()
	root.add_child(journal)
	check(journal.get_characters().is_empty(), "Reentry recomputes changes missed outside tree")
	journal.configure(state)
	journal.configure(state)
	count = 0
	for connection: Dictionary in state.state_changed.get_connections():
		if connection.callable.get_object() == journal:
			count += 1
	check(count == 1, "Reconfiguration keeps one state subscription")
	state.set_variable(CharacterJournal.STATE_KEY, "broken")
	check(journal.get_characters().is_empty() and journal.unlock_character("test.valid", "人物") == ERR_INVALID_DATA, "Invalid reserved data is hidden and preserved")
	check(journal.configure(state) == ERR_INVALID_DATA, "Invalid reconfiguration is rejected")
	state.restore_state(snapshot)
	check(journal.get_characters().size() == 2, "Valid restore repairs projection")
	journal.free()
	state.reset_state()

	var library := StoryLibrary.new()
	check(library.load_file(STORY) == OK, "Actual story loader accepts character commands")
	for step: Dictionary in [
		{"command": "character_unlock", "character_id": "bad", "name": "人物"},
		{"command": "character_unlock", "character_id": "test.first", "name": " "},
		{"command": "character_unlock", "character_id": "test.first", "name": "人物", "unknown": true},
		{"command": "character_append", "character_id": "test.first", "record_id": "bad", "content": "正文"},
		{"command": "character_append", "character_id": "test.first", "record_id": "test.record", "content": ""}]:
		check(library.load_json(JSON.stringify({"version": 1, "events": {"test.invalid": {"steps": [step]}}})) == ERR_INVALID_DATA, "Malformed character command rejected")

	var game: MainGame = load("res://src/debug/story/legacy_shop.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	journal = game.get_character_journal()
	var ui := game.get_ui_manager()
	var book: HandbookPanel = game.get_node("PopupLayer/HandbookPanel")
	var panel := book.get_characters_page()
	var list := panel.get_entries()
	var text := panel.get_detail_text()
	var hud: HandbookHUD = game.get_node("HudLayer/HandbookHUD")
	var player := game.get_player() as PlayerController
	check(not hud.visible and book.get_pages().is_tab_hidden(3) and game.open_characters() == ERR_UNAVAILABLE, "Locked character page and entry are hidden")
	check(ui.open_screen(ScreenIds.CHARACTERS) == ERR_UNAVAILABLE and not ui.has_modal(), "Locked alias cannot reserve modal")
	var director := game.get_story_director()
	director.load_events(STORY)
	director.set_character_journal(null)
	director.request_event("character_test.discover")
	await frames(12)
	check(not director.is_busy() and director.last_error.contains("CharacterJournal unavailable") and journal.get_characters().is_empty(), "Missing service fails at actual dispatch")
	director.set_character_journal(journal)
	director.request_event("character_test.append")
	await frames(12)
	check(not director.is_busy() and not director.last_error.is_empty() and journal.get_characters().is_empty(), "Appending before unlock fails without progress")
	check(director.request_event("character_test.discover") == OK, "Real story event starts")
	await frames(20)
	check(not director.is_busy() and director.last_error.is_empty() and journal.get_character("characters.drunken_guard").records.size() == 3, "Story unlocks guard with known identity, traits and encounter")
	check(game.get_chronicle_journal().get_entries().is_empty(), "Character commands never create chronicle entries")
	check(hud.visible and hud.get_node("Unread").visible and hud.tooltip_text.contains("人物记录 1"), "Character-only unlock enables handbook and unread badge")
	check(game.open_characters() == OK and book.get_pages().current_tab == 3 and not player.movement_enabled, "Public entry opens the shared character tab and locks movement")
	check(journal.get_unread_count() == 1 and root.gui_get_focus_owner() == list, "Opening focuses list without marking read")
	await tap(KEY_DOWN)
	await tap(KEY_ENTER)
	check(journal.get_unread_count() == 0 and text.text.contains("哥布林守卫") and not text.text.contains("利用价值"), "Native keyboard reads only already acquired knowledge")
	await tap(KEY_P)
	check(paused and not panel.can_process(), "Pause covers and freezes the page")
	journal.append_record("characters.drunken_guard", "test.covered", "暂停期间新增的情报")
	list.item_selected.emit(0)
	check(journal.get_unread_count() == 1, "Covered selection cannot consume unread knowledge")
	await tap(KEY_ESCAPE)
	check(not paused and ui.is_open(ScreenIds.CHARACTERS), "Resume retains the same modal")
	list.item_selected.emit(0)
	check(journal.get_unread_count() == 0 and text.text.contains("暂停期间新增"), "Reselect reads newly displayed knowledge")
	await tap(KEY_ESCAPE)
	check(not ui.has_modal() and player.movement_enabled and not list.is_anything_selected(), "Esc clears selection and restores world input")
	director.request_event("character_test.append")
	await frames(12)
	check(journal.get_unread_count() == 1 and journal.get_character("characters.drunken_guard").records.size() == 5, "Story update appends judgment and restores unread badge")
	director.request_event("character_test.append")
	await frames(12)
	check(journal.get_character("characters.drunken_guard").records.size() == 5, "Actual story replay is idempotent")
	list.item_selected.emit(0)
	check(journal.get_unread_count() == 1, "Hidden page cannot consume unread knowledge")
	game.get_chronicle_journal().unlock_entry("test.other", "异闻")
	game.open_chronicle()
	list.item_selected.emit(0)
	check(journal.get_unread_count() == 1, "Another visible tab cannot consume character unread")
	check(game.open_characters() == OK and ui.is_open(ScreenIds.CHRONICLE) and not player.movement_enabled, "Switching aliases retains one shared modal")
	list.item_selected.emit(0)
	check(hud.get_node("Unread").visible and not hud.tooltip_text.contains("人物记录 1") and hud.tooltip_text.contains("异闻录 1"), "Reading a person preserves chronicle unread")
	journal.unlock_character("test.second", "测试人物（仅预览）")
	check(journal.get_unread_count() == 1 and list.item_count == 2, "Second person unlocks independently")
	ui.close_screen(ScreenIds.HANDBOOK)
	player.set_movement_enabled(false)
	game.open_characters()
	ui.close_screen(ScreenIds.CHARACTERS)
	check(not player.movement_enabled, "Closing preserves an earlier movement lock")
	player.set_movement_enabled(true)
	game.get_dialogue_manager().start_dialogue("demo.greeting")
	check(game.open_characters() == ERR_BUSY, "Dialogue keeps modal exclusivity")
	game.get_dialogue_manager().end_dialogue(false)
	snapshot = state.to_dict()
	state.reset_state()
	check(list.item_count == 0 and not hud.visible, "Reset refreshes character UI and access")
	state.restore_state(snapshot)
	check(list.item_count == 2 and journal.get_unread_count() == 1, "Restore refreshes UI without story replay")

	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		journal.append_record("characters.drunken_guard", "test.long", "长正文与原文标签 [b]保留[/b]。\n".repeat(50))
		# Exercise the maximum tab width as well as long detail scrolling.
		state.set_flag("task.shop.first_order.active")
		state.get_warehouse_inventory().add_ingredient("goblin_firebrew", 1)
		check(state.get_tea_production().craft_formula(["goblin_firebrew"]).ok, "A real crafted drink reveals the fourth handbook tab")
		game.open_characters()
		list.item_selected.emit(0)
		check(not book.get_pages().is_tab_hidden(2), "All four tabs remain available after selection refresh")
		DirAccess.make_dir_recursive_absolute("res://.godot/character-records")
		for dimensions: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
			root.size = dimensions
			await frames(8)
			await RenderingServer.frame_post_draw
			check(text.get_global_rect().end.x <= panel.get_global_rect().end.x and text.get_global_rect().end.y <= panel.get_global_rect().end.y, "Long details stay within modal")
			check(text.get_v_scroll_bar().max_value > text.get_v_scroll_bar().page, "Long character knowledge scrolls")
			root.get_texture().get_image().save_png("res://.godot/character-records/characters-%dx%d.png" % [dimensions.x, dimensions.y])
		ui.close_screen(ScreenIds.HANDBOOK)
		state.restore_state(snapshot)
	game.free()
	await frames()
	game = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	check(state.to_dict() == snapshot and game.get_character_journal().get_characters().size() == 2 and game.open_characters() == OK, "Rebuilt settlement retains progress and access without rewriting state")
	game.free()
	await frames()
	state.reset_state()
	state.set_flag("test.preview_preserved")
	var demo: Node = load("res://src/debug/characters/character_records_demo.tscn").instantiate()
	root.add_child(demo)
	await frames()
	check(not state.get_flag("test.preview_preserved") and demo.get_preview_game().get_character_journal().get_characters().is_empty(), "F6 preview starts isolated and locked")
	demo.free()
	await frames()
	check(state.get_flag("test.preview_preserved"), "F6 preview restores original state on exit")
	state.reset_state()
	print("CHARACTER RECORDS: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
