extends SceneTree

# 可在真实 Debug / Release export 中通过 --script 运行；tests 需临时纳入验收包。
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_verify")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: ", description)

func _tap(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func _tap_console_key() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_F3
		event.keycode = KEY_F3
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func _make_game(kind: String) -> MainGame:
	var game: MainGame = load("res://src/core/settlement.tscn" if kind == "settlement" else "res://src/debug/story/legacy_shop.tscn").instantiate()
	if kind == "cave":
		var levels := game.get_node("World/LevelRoot")
		levels.get_child(0).free()
		levels.add_child(load("res://src/levels/cave/cave_map.tscn").instantiate())
		var entities := game.get_node("World/EntityRoot")
		entities.get_child(0).free()
		var player: CavePlayer = load("res://src/gameplay/player/player.tscn").instantiate()
		player.name = "Player"
		entities.add_child(player)
	return game

func _verify() -> void:
	for kind: String in ["settlement", "shop", "cave"]:
		await _verify_host(kind)
	# Disabling debug tools is distinct from a true Release executable.
	if OS.has_feature("debug"):
		ProjectSettings.set_setting("debug/developer_tools/enabled", false)
		for kind: String in ["settlement", "shop", "cave"]:
			await _verify_host(kind)
		ProjectSettings.set_setting("debug/developer_tools/enabled", null)
		await _verify_reload()
	print("BUILD_BOUNDARY debug=%s checks=%d failures=%d" % [OS.has_feature("debug"), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _verify_host(kind: String) -> void:
	var game := _make_game(kind)
	var saved_floor_cells: Array[Vector2i] = []
	if kind == "cave":
		saved_floor_cells = game.get_node("World/LevelRoot").get_child(0).get_node("FloorLayer").get_used_cells()
	root.add_child(game)
	current_scene = game
	await process_frame
	var enabled := DebugRuntime.is_enabled()
	var player := game.get_player() as PlayerController
	var tools := game.get_debug_tools()
	check((tools != null) == enabled, "%s: Developer tools build boundary" % kind)
	check((game.get_demo_tools() != null) == (enabled and kind == "cave"), "%s: Cave demo build boundary" % kind)
	check(player.global_position.is_equal_approx(game.get_active_level().get_spawn_position()), "%s: Release-independent spawn" % kind)
	if kind == "cave":
		check(player.can_stand_at(player.global_position), "Cave spawn is walkable")
	if enabled:
		check(not tools.get_panel().visible, "%s: Console defaults collapsed" % kind)
		tools.set_player_speed_multiplier(8.0)
		check(player.get_speed_multiplier() == 8.0, "%s: Debug speed controls" % kind)
		tools.set_player_speed_multiplier(1.0)
		await _verify_modal(game, kind)
	else:
		check(game.get_node("DebugLayer").get_child_count() == 0 and not game.get_node("Systems").has_node("DeveloperTools") and not game.get_node("Systems").has_node("CaveDemoController") and not game.get_node("Systems").has_node("SettlementPreview"), "%s: No debug nodes, production systems remain" % kind)
		var probe := root.get_node_or_null("MCPRuntimeProbe")
		if not OS.has_feature("debug") and probe != null:
			check(not probe.is_processing(), "Release MCP polling stopped")
		# Synthetic actions also test Release when no debug InputMap action was registered.
		_tap(DeveloperTools.TOGGLE_ACTION)
		_tap_console_key()
		for action: StringName in [&"debug_cycle_walls", &"debug_toggle_overview", &"debug_settlement_routes"]:
			_tap(action)
		check(player.get_speed_multiplier() == 1.0, "%s: Release ignores debug speed" % kind)
		if kind == "cave":
			check(not player.overview_enabled and game.get_active_level().wall_mode == CaveMap.WallMode.TEXTURED, "Release ignores cave input")
			# Saved TileMap cells are authoritative; the old 6309 JSON count is obsolete.
			check(game.get_active_level().walkable_cells.size() == saved_floor_cells.size() and game.get_active_level().walkable_cells.has_all(saved_floor_cells), "Release rejects debug layout override and keeps saved floor")
	var before := player.global_position
	Input.action_press("move_right")
	for frame in range(6):
		await physics_frame
	Input.action_release("move_right")
	check(player.global_position.x > before.x, "%s: Build player movement" % kind)
	game.queue_free()
	await process_frame

func _verify_modal(game: MainGame, kind: String) -> void:
	var tools := game.get_debug_tools()
	var panel := tools.get_panel()
	var player := game.get_player() as PlayerController
	var ui := game.get_ui_manager()
	_tap_console_key()
	check(panel.visible and ui.is_open(DeveloperTools.SCREEN_ID), "%s: Shortcut opens console" % kind)
	check(not player.movement_enabled and not paused, "%s: Console locks movement without pausing" % kind)
	var owner := root.gui_get_focus_owner()
	check(owner != null and panel.is_ancestor_of(owner), "%s: Console owns keyboard focus" % kind)
	var before := player.global_position
	Input.action_press("move_right")
	_tap(&"interact")
	_tap(&"pause_game")
	_tap(&"debug_toggle_overview")
	for frame in range(5):
		await physics_frame
	Input.action_release("move_right")
	check(player.global_position.is_equal_approx(before) and not paused and not game.get_dialogue_manager().is_active(), "%s: Open console blocks movement, interaction and pause" % kind)
	if kind == "cave":
		check(not player.overview_enabled, "Console blocks cave overview")
	else:
		check(not game.get_shop_ui().is_open(), "%s: Console blocks shop interaction" % kind)
	_tap(&"ui_cancel")
	check(not panel.visible and player.movement_enabled and not paused and not ui.has_modal(), "%s: Escape closes and restores game" % kind)
	player.set_movement_enabled(false)
	tools.toggle_panel()
	tools.close_panel()
	check(not player.movement_enabled, "%s: Existing movement lock preserved" % kind)
	player.set_movement_enabled(true)
	ui.set_paused(true)
	var focus := root.gui_get_focus_owner()
	tools.toggle_panel()
	check(panel.visible and paused, "%s: Console usable during existing pause" % kind)
	_tap(&"pause_game")
	tools.close_panel()
	check(paused and ui.is_open(&"pause") and root.gui_get_focus_owner() == focus, "%s: Closing preserves pause and restores focus" % kind)
	ui.set_paused(false)
	if kind != "cave":
		game.get_shop_ui().open(game.get_active_level().get_interaction_points()[0])
		if game.get_shop_ui().is_open():
			tools.toggle_panel()
			tools.close_panel()
			check(not player.movement_enabled and ui.has_modal(), "%s: Underlying popup keeps input lock" % kind)
			game.get_shop_ui().close()
	var story := game.get_story_director()
	check(story.load_events("res://tests/fixtures/story_events.json") == OK and story.request_event("test.wait") == OK, "%s: Real story begins before console" % kind)
	tools.toggle_panel()
	check(panel.speed_selector.disabled and panel.get_node("%Respawn").disabled, "%s: Busy story disables character operations" % kind)
	before = player.global_position
	tools.set_player_speed_multiplier(8.0)
	tools.return_to_spawn()
	check(player.get_speed_multiplier() == 1.0 and player.global_position == before, "%s: Guard blocks direct character operations during story" % kind)
	tools.close_panel()
	check(not player.movement_enabled, "%s: Closing console preserves story lock" % kind)
	story.cancel_event("Console lock regression check")
	check(player.movement_enabled, "%s: Story completion releases final lock" % kind)
	player.global_position += Vector2(12, 0)
	tools.return_to_spawn()
	check(player.global_position.is_equal_approx(game.get_active_level().get_spawn_position()), "%s: Public respawn callback" % kind)
	tools.refresh()
	check(panel.status_text.text.contains(game.scene_file_path) and panel.status_text.text.contains("当前天数"), "%s: Live status bound after initialization" % kind)
	if kind == "shop":
		var replacement: DeveloperPanel = load("res://src/debug/developer_tools/developer_panel.tscn").instantiate()
		game.get_node("DebugLayer").add_child(replacement)
		tools.configure(player.set_speed_multiplier, player.get_speed_multiplier, replacement, {"ui_manager": ui})
		tools.toggle_panel()
		check(replacement.visible and not panel.visible and not player.movement_enabled, "Rebinding a new panel preserves modal control")
		panel.queue_free()
		await process_frame
		check(ui.is_open(DeveloperTools.SCREEN_ID), "Old panel exiting cannot unregister its replacement")
		tools.close_panel()
		check(player.movement_enabled, "Rebound panel releases input lock")

func _verify_reload() -> void:
	var state := root.get_node("GameState")
	var snapshot: Dictionary = state.to_dict()
	state.set_flag("console.reload_preserved")
	var game := _make_game("shop")
	root.add_child(game)
	current_scene = game
	await process_frame
	game.get_ui_manager().set_paused(true)
	var tools := game.get_debug_tools()
	tools.toggle_panel()
	var panel := tools.get_panel()
	panel.get_node("%Restart").pressed.emit()
	check(current_scene == game, "Restart prompt does not reload before confirmation")
	panel.get_node("%ConfirmRestart").pressed.emit()
	for frame in range(5):
		await process_frame
	var reloaded := current_scene as MainGame
	check(is_instance_valid(reloaded) and not is_instance_valid(game), "Confirmed restart really reloads current host")
	check(not paused and not reloaded.get_debug_tools().is_open() and reloaded.get_player().movement_enabled, "Reload from paused console leaves no stale pause or control lock")
	check(state.get_flag("console.reload_preserved"), "Scene restart preserves GameState")
	reloaded.queue_free()
	await process_frame
	state.restore_state(snapshot)
