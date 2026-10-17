extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_verify")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _verify() -> void:
	var game: MainGame = _make_cave_game()
	root.add_child(game)
	await process_frame
	var level := game.get_active_level() as CaveMap
	var player := game.get_player() as CavePlayer
	var tools := game.get_debug_tools()
	var demo := game.get_demo_tools()
	var overlay := demo.get_overlay()
	var panel := tools.get_panel()
	var world: Node2D = game.get_node("World")
	check(player.camera.get_screen_center_position().distance_to(player.global_position) < 1.0, "Spawn immediately centers camera even with smoothing enabled")
	check(game.name == "MainGame" and game.get_class() == "Node", "MainGame is a non-spatial root")
	check(level.get_parent() == world.get_node("LevelRoot"), "Level belongs to LevelRoot")
	check(player.get_parent() == world.get_node("EntityRoot"), "Player belongs to EntityRoot")
	check(world.get_node("EffectRoot").get_child_count() == 0, "EffectRoot remains reserved")
	check(tools.get_parent() == game.get_node("Systems"), "Debug controller belongs to Systems")
	check(overlay.get_parent() == game.get_node("DebugLayer"), "Debug display belongs to DebugLayer")
	check(game.process_mode == Node.PROCESS_MODE_ALWAYS, "MainGame always processes")
	check(world.process_mode == Node.PROCESS_MODE_PAUSABLE, "World is pausable")
	check(game.get_node("Systems").process_mode == Node.PROCESS_MODE_PAUSABLE, "Systems is pausable")
	check(tools.process_mode == Node.PROCESS_MODE_ALWAYS, "Debug controller works during pause")
	check(world.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "World preserves nearest filtering")
	var layer_order := {"HudLayer": 10, "PopupLayer": 20, "PauseLayer": 30, "TransitionLayer": 40, "DebugLayer": 50}
	for name: String in layer_order:
		var screen_layer: CanvasLayer = game.get_node(name)
		check(screen_layer.layer == layer_order[name], "Screen layer order: " + name)
		check(not screen_layer.follow_viewport_enabled, "Screen layer stays fixed: " + name)
		var expected_mode := Node.PROCESS_MODE_WHEN_PAUSED if name == "PauseLayer" else Node.PROCESS_MODE_ALWAYS
		check(screen_layer.process_mode == expected_mode, "Screen layer process mode: " + name)
		if name == "HudLayer":
			var task_hud := screen_layer.get_node("TaskHUD") as TaskHUD
			check(task_hud != null and not task_hud.visible, "Shared task HUD remains hidden without an active task")
			check(screen_layer.get_node("ChronicleHUD") is ChronicleHUD and screen_layer.get_node("ChronicleHUD").visible, "Chronicle button belongs to HUD")
		if name == "TransitionLayer":
			check(screen_layer.get_child_count() == 0, "Unused UI layer remains empty: " + name)
	check(game.get_ui_manager() != null, "MainGame exposes scene-local UI manager")
	check(game.get_node("PopupLayer/DialogueUI") != null, "Dialogue belongs to PopupLayer")
	check(game.get_node("PauseLayer/PauseMenu") != null, "Pause menu belongs to PauseLayer")
	check(not game.get_node("PauseLayer").visible, "Pause layer initially hidden")
	check(not game.get_node("TransitionLayer").visible, "Transition layer initially hidden")
	check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Debug overlay does not intercept mouse input")
	check(overlay.hint.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Debug hint does not intercept mouse input")
	check(panel.speed_selector.item_count == 4, "Developer tools offer four speed multipliers")
	check(panel.get_parent() == game.get_node("DebugLayer"), "Generic developer panel belongs to DebugLayer")
	var base_speed := player.speed
	var saved_query := player.walkability_query
	var saved_position := player.global_position
	player.configure(func(_position: Vector2, _half_size: Vector2) -> bool: return true)
	for index in range(4):
		panel.speed_selector.select(index)
		panel.speed_selector.item_selected.emit(index)
		var multiplier := float(panel.speed_selector.get_item_id(index))
		player.global_position = Vector2.ZERO
		# Measure steady speed; acceleration has its own player tests.
		player.velocity = Vector2.RIGHT * player.get_movement_speed()
		player.move_direction(Vector2.RIGHT, 0.1)
		check(is_equal_approx(player.global_position.x, base_speed * multiplier * 0.1), "Selected multiplier changes actual movement: %s" % multiplier)
		check(is_equal_approx(player.speed, base_speed), "Multiplier preserves base speed")
	tools.set_player_speed_multiplier(1.0)
	check(is_equal_approx(player.get_movement_speed(), base_speed), "Returning to 1x restores base speed without accumulation")
	tools.set_player_speed_multiplier(3.0)
	check(is_equal_approx(player.speed_multiplier, 1.0) and panel.speed_selector.selected == 0, "Unsupported multiplier leaves player and UI unchanged")
	tools.set_player_speed_multiplier(8.0)
	player.global_position = Vector2.ZERO
	player.configure(func(position: Vector2, _half_size: Vector2) -> bool: return position.x < 20.0 or position.x > 40.0)
	player.move_direction(Vector2.RIGHT, 0.1)
	check(player.global_position.x < 20.0, "8x movement cannot jump over an unwalkable gap")
	tools.set_player_speed_multiplier(1.0)
	player.configure(saved_query)
	player.global_position = saved_position
	var overlay_origin := overlay.get_global_transform_with_canvas().origin
	world.position = Vector2(300.0, -150.0)
	check(player.global_position.is_equal_approx(level.get_spawn_position()), "World movement keeps player at map spawn")
	check(level.world_to_cell(player.global_position) == level.spawn_cell, "World movement preserves grid conversion")
	check(player.can_stand_at(player.global_position), "Translated World remains walkable")
	check(player.camera.global_position.is_equal_approx(player.global_position), "Camera follows translated World")
	check(overlay.get_global_transform_with_canvas().origin.is_equal_approx(overlay_origin), "World movement does not move screen hints")
	var before_movement := player.global_position
	Input.action_press("move_right")
	for frame in range(4):
		await physics_frame
	check(player.global_position.x > before_movement.x, "World processes player movement before pause")
	paused = true
	var paused_position := player.global_position
	await create_timer(0.06, true).timeout
	check(player.global_position.is_equal_approx(paused_position), "World stops player processing while paused")
	check(not player.can_process(), "Player inherits World pause")
	check(tools.can_process() and overlay.can_process(), "Debug controller and display continue during pause")
	panel.speed_selector.select(2)
	panel.speed_selector.item_selected.emit(2)
	check(is_equal_approx(player.get_movement_speed(), base_speed * 4.0), "Speed tool remains usable while paused")
	tools.set_player_speed_multiplier(1.0)
	var previous_mode := level.wall_mode
	_send_action("debug_cycle_walls", true)
	_send_action("debug_cycle_walls", false)
	await process_frame
	check(level.wall_mode == (previous_mode + 1) % 3, "F2 action is handled by paused debug controller")
	check(overlay.hint.text.contains(level.get_wall_mode_name()), "Debug status updates during pause")
	paused = false
	for frame in range(4):
		await physics_frame
	Input.action_release("move_right")
	check(player.global_position.x > paused_position.x, "World resumes player movement")
	_send_action("debug_toggle_overview", true)
	_send_action("debug_toggle_overview", false)
	await process_frame
	check(player.overview_enabled, "M action switches to overview")
	_send_action("debug_toggle_overview", true)
	_send_action("debug_toggle_overview", false)
	await process_frame
	check(not player.overview_enabled, "M action switches back to follow")
	check(player.camera.global_position.is_equal_approx(player.global_position), "Camera follows after action toggles")
	check(player.camera.get_screen_center_position().distance_to(player.global_position) < 1.0, "Returning from overview immediately resets camera smoothing")
	check(overlay.get_global_transform_with_canvas().origin.is_equal_approx(overlay_origin), "Camera movement does not move screen hints")
	for description: String in failures:
		printerr("FAIL: ", description)
	print("MainGame architecture: %d checks; %d failures" % [checks, failures.size()])
	game.queue_free()
	await process_frame
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	var plain_game: MainGame = _make_cave_game()
	root.add_child(plain_game)
	await process_frame
	check(plain_game.get_debug_tools() == null and plain_game.get_demo_tools() == null, "Game starts without debug components")
	check(plain_game.get_ui_manager() != null and plain_game.get_node("DebugLayer").get_child_count() == 0, "Disabled debug tools preserve game systems without debug display")
	check(plain_game.get_player().can_stand_at(plain_game.get_player().global_position), "Normal level initialization is independent of debug tools")
	_send_action("debug_toggle_overview", true)
	_send_action("debug_toggle_overview", false)
	check(not plain_game.get_player().overview_enabled, "Disabled debug mode ignores overview action")
	var normal_position := plain_game.get_player().global_position
	Input.action_press("move_right")
	for frame in range(4):
		await physics_frame
	Input.action_release("move_right")
	check(plain_game.get_player().global_position.x > normal_position.x, "Player still moves with debug components absent")
	plain_game.queue_free()
	await process_frame
	ProjectSettings.set_setting("debug/developer_tools/enabled", null)
	print("MainGame total: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

# This suite exercises the supported cave host and its developer tools explicitly.
# The default shop host has its own movement/interaction suite.
func _make_cave_game() -> MainGame:
	var game: MainGame = load("res://src/core/main.tscn").instantiate()
	var levels := game.get_node("World/LevelRoot")
	levels.get_child(0).free()
	levels.add_child(load("res://src/levels/cave/cave_map.tscn").instantiate())
	var entities := game.get_node("World/EntityRoot")
	entities.get_child(0).free()
	var player: CavePlayer = load("res://src/gameplay/player/player.tscn").instantiate()
	player.name = "Player"
	entities.add_child(player)
	return game
