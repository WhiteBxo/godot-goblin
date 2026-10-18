extends SceneTree

const StateData = preload("res://src/core/game_state.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)

func frames(count: int = 3) -> void:
	for index in range(count):
		await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await frames()

func click(control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = control.get_global_rect().get_center()
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await frames()

func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/map_ui")
	root.get_texture().get_image().save_png("res://.godot/map_ui/" + name + ".png")

func catalog_for(location: String, task_location: String = "") -> TaskCatalog:
	var definition := {"version": 1, "tasks": [{
		"id": "test.map", "type": "main", "title": "地图目标验证", "description": "隔离夹具",
		"activate_when": {"type": "flag", "key": "test.map.active"},
		"complete_when": {"type": "flag", "key": "test.map.done"},
		"objectives": [{"id": "visit", "text": "前往目标地点",
			"reveal_when": {"type": "flag", "key": "test.map.revealed"},
			"complete_when": {"type": "flag", "key": "test.map.done"}}]}]}
	var locations: Array[String] = []
	if not location.is_empty():
		definition.tasks[0].objectives[0]["location_id"] = location
		locations.append(location)
	if not task_location.is_empty():
		definition.tasks[0]["location_id"] = task_location
		if task_location not in locations:
			locations.append(task_location)
	var catalog := TaskCatalog.new()
	check(catalog.load_json(JSON.stringify(definition), {"locations": locations}) == OK, "Location fixture follows existing TaskCatalog schema")
	return catalog

func _run() -> void:
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		root.size = Vector2i(640, 360)
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	var state: StateData = root.get_node("GameState")
	state.reset_state()
	var game: MainGame = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	var ui := game.get_ui_manager()
	var level := game.get_active_level() as SettlementMap
	var player := game.get_player() as ShopPlayer
	var panel: SettlementMapPanel = game.get_node("PopupLayer/SettlementMapPanel")
	var button: Button = game.get_node("HudLayer/MapButton")
	var canvas := panel.get_map_canvas()
	check(not game.has_node("Systems/SettlementPreview"), "Actual settlement host runs with debug tools disabled")
	check(game.open_map() == ERR_UNAVAILABLE and not button.visible, "Locked map rejects public entry and hides button")
	check(ui.open_screen(ScreenIds.MAP) == ERR_DOES_NOT_EXIST, "Locked map cannot be opened through manager")
	await key(KEY_M)
	check(not ui.is_open(ScreenIds.MAP) and player.movement_enabled, "M cannot open or lock movement before unlock")
	check(not panel.is_processing(), "Closed map does not refresh")
	check(not state.get_flag("day1.s04.map_available"), "Installing map capability does not fabricate S04 success")
	check(game.unlock_map() == OK and state.get_flag("day1.s04.map_available") and button.visible, "Explicit host unlock registers real map before availability fact")
	check(not InputMap.action_get_events("open_map")[0].is_match(InputMap.action_get_events("debug_toggle_overview")[0]), "Formal M and debug overview use distinct bindings")
	check(game.unlock_map() == OK, "Host map unlock is idempotent")
	check(not InputMap.action_get_events("debug_cycle_walls")[0].is_match(InputMap.action_get_events("debug_toggle_overview")[0]), "Debug overview also avoids wall inspection binding")
	await click(button)
	check(ui.is_open(ScreenIds.MAP) and not player.movement_enabled, "HUD opens managed modal and locks player")
	check(root.gui_get_focus_owner() == panel.get_default_focus(), "Map gives keyboard focus to close button")
	check(canvas.map_data.regions.size() == 1 and canvas.map_data.regions[0].location_id == "settlement.shop", "Default knowledge contains only established shop exterior")
	check(canvas.player_position.is_equal_approx(player.global_position), "Map player matches actual world position")
	var bounds := level.get_world_bounds()
	var corner := canvas.world_to_map(bounds.position)
	var end := canvas.world_to_map(bounds.end)
	check(canvas.world_to_map(bounds.get_center()).is_equal_approx((corner + end) * 0.5), "World conversion uses shared bounds and centered aspect fit")
	check(is_equal_approx((end.x - corner.x) / (end.y - corner.y), bounds.size.x / bounds.size.y), "Map keeps actual map aspect ratio")
	await capture("known_shop_640")
	var snapshot := state.to_dict()
	await key(KEY_TAB)
	check(root.gui_get_focus_owner() == panel.get_default_focus(), "Tab stays within map modal")
	await key(KEY_P)
	check(paused and ui.is_open(ScreenIds.MAP) and not player.movement_enabled, "Pause covers map without releasing movement")
	await key(KEY_ESCAPE)
	check(not paused and ui.is_open(ScreenIds.MAP), "Esc resumes map from pause")
	await key(KEY_ESCAPE)
	check(not ui.has_modal() and player.movement_enabled and not panel.is_processing(), "Esc closes map and restores movement and refresh lifecycle")
	check(root.gui_get_focus_owner() == button, "Closing restores HUD focus")
	check(state.to_dict() == snapshot, "Viewing map and pausing never alter task or story progress")
	var old_marker := canvas.player_position
	var start := player.global_position
	Input.action_press("move_left")
	for index in range(15):
		await physics_frame
	Input.action_release("move_left")
	await frames()
	check(player.global_position.distance_to(start) > 1, "Actual player moves between map openings")
	check(canvas.player_position == old_marker, "Closed map does not track moving world")
	await key(KEY_M)
	check(ui.is_open(ScreenIds.MAP) and canvas.player_position.is_equal_approx(player.global_position), "M reopens with latest actual player position")
	player.teleport_to(level.get_story_anchor(&"00_shop_entrance").global_position)
	await frames()
	check(canvas.player_position.is_equal_approx(player.global_position), "Visible map updates marker when world position changes")
	var journal := game.get_task_journal()
	check(journal.configure(catalog_for("settlement.tavern"), state) == OK, "Journal uses isolated task projection")
	state.set_flag("test.map.active")
	state.set_flag("test.map.revealed")
	check(canvas.target.is_empty(), "An objective cannot reveal an unknown district")
	state.set_flag("ui.map.known.settlement.tavern")
	check(canvas.target.get("position") == level.get_story_anchor(&"06_tavern_entrance").global_position, "Known objective maps to the real authored tavern entrance")
	check(canvas.target.get("name") == "酒馆", "Target includes a short real location name")
	state.set_flag("ui.map.known.settlement.elder")
	for location in ["settlement.elder_document", "settlement.elder_blood_storage", "settlement.elder_hidden_bookcase", "settlement.ritual_hidden_cover", "test.missing"]:
		journal.configure(catalog_for(location), state)
		check(canvas.target.is_empty(), "Unmapped interior clue or missing location never guesses a coordinate: " + location)
	journal.configure(catalog_for("", "settlement.tavern"), state)
	check(not canvas.target.is_empty(), "Explicit task-level location is used when objective has none")
	journal.configure(catalog_for("test.missing", "settlement.tavern"), state)
	check(canvas.target.is_empty(), "Unknown explicit objective never falls back to misleading task location")
	journal.configure(catalog_for("settlement.elder"), state)
	state.set_flag("test.map.revealed", false)
	check(canvas.target.is_empty(), "Hidden current objective does not leak task location")
	state.set_flag("test.map.revealed")
	check(canvas.target.get("position") == level.get_story_anchor(&"10_elder_entrance").global_position, "Elder objective reveals exterior entrance only")
	var data := level.get_map_data(["settlement.elder", "settlement.elder_document"])
	check(data.regions.size() == 1 and data.regions[0].location_id == "settlement.elder", "Read-only map allowlist excludes private anchors even with arbitrary knowledge IDs")
	data.regions.clear()
	check(level.get_map_data(["settlement.elder"]).regions.size() == 1, "Returned presentation data cannot mutate saved map")
	# Capture every public exterior with explicitly injected knowledge, not story completion.
	for id: String in SettlementMap.MAP_LOCATIONS:
		state.set_flag("ui.map.known." + id)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		check(root.size == Vector2i(640, 360), "Actual game window uses 640 by 360 for narrow acceptance")
	await capture("settlement_640")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 720)
		await frames()
		check(root.size == Vector2i(1280, 720), "Actual game window resized for visual acceptance")
		await capture("settlement_1280")
	await click(panel.get_default_focus())
	check(not ui.is_open(ScreenIds.MAP) and player.movement_enabled, "Mouse close restores player input")
	player.set_movement_enabled(false)
	check(game.open_map() == ERR_BUSY, "Map cannot bypass pre-existing movement lock")
	player.set_movement_enabled(true)
	check(game.open_map() == OK, "Map can reopen normally")
	state.set_flag("day1.s04.map_available", false)
	check(not ui.has_modal() and not button.visible and not panel.is_processing() and player.movement_enabled, "Revoking unlock closes map and restores locks")
	check(game.unlock_map() == OK and game.open_map() == OK, "Re-registering same screen after revoke is safe")
	state.reset_state()
	check(not ui.is_open(ScreenIds.MAP) and game.open_map() == ERR_UNAVAILABLE, "New game reset revokes map and knowledge")
	var saved := state.to_dict()
	game.queue_free()
	await frames()
	state.set_flag("day1.s04.map_available")
	game = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	check(game.open_map() == OK, "Rebuilt normal host restores map from existing availability fact")
	game.queue_free()
	await frames()
	state.restore_state(saved)
	print("MAP_UI: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
