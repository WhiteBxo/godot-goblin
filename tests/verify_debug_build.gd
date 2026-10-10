extends SceneTree

# 导出验收时复制到临时项目 verification/ 中，正式导出继续排除 tests/。
func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var game: MainGame = load("res://src/core/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var debug_build := OS.has_feature("debug")
	var player := game.get_player()
	var failures: Array[String] = []
	if (game.get_debug_tools() != null) != debug_build:
		failures.append("Developer tools build boundary")
	if (game.get_demo_tools() != null) != debug_build:
		failures.append("Cave demo build boundary")
	if not player.can_stand_at(player.global_position):
		failures.append("Release-independent spawn")
	if debug_build:
		game.get_debug_tools().set_player_speed_multiplier(8.0)
		if player.get_speed_multiplier() != 8.0:
			failures.append("Debug speed controls")
	else:
		if game.get_node("DebugLayer").get_child_count() != 0 or game.get_node("Systems").get_child_count() != 0:
			failures.append("Release instantiated debug nodes")
		var probe := root.get_node_or_null("MCPRuntimeProbe")
		if probe != null and probe.is_processing():
			failures.append("Release MCP polling")
		for action: StringName in [&"debug_cycle_walls", &"debug_toggle_overview"]:
			var event := InputEventAction.new()
			event.action = action
			event.pressed = true
			Input.parse_input_event(event)
			Input.flush_buffered_events()
		if player.overview_enabled or game.get_active_level().wall_mode != CaveMap.WallMode.TEXTURED:
			failures.append("Release handled debug input")
		if player.get_speed_multiplier() != 1.0 or game.get_active_level().walkable_cells.size() != 6309:
			failures.append("Release accepted debug layout or speed")
	var before := player.global_position
	Input.action_press("move_right")
	for frame in range(4):
		await physics_frame
	Input.action_release("move_right")
	if player.global_position.x <= before.x:
		failures.append("Build player movement")
	for failure: String in failures:
		printerr("FAIL: ", failure)
	print("BUILD_BOUNDARY debug=%s failures=%d" % [debug_build, failures.size()])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
