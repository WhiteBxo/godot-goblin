extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_verify")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

func _verify() -> void:
	var scene: Node = load("res://src/core/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var cave_map: CaveMap = scene.get_active_level()
	var cells: Dictionary = cave_map.walkable_cells
	var player: Node2D = scene.get_player()
	player.set_physics_process(false)
	check(cave_map.walls.conflicts.is_empty(), "Raised walls must not overlap walkable floor")
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/levels/cave/cave_layout_original.json"))
	var revised: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/levels/cave/cave_layout.json"))
	check(original.rooms == revised.rooms, "Room coordinates remain identical")
	check(original.corridors.slice(0, -3) == revised.corridors.slice(0, -3), "Only top bypass changes")
	var original_cells: Dictionary = {}
	for room: Dictionary in original.rooms:
		add_rect(original_cells, [room.x, room.y, room.w, room.h])
	for corridor: Array in original.corridors:
		add_rect(original_cells, corridor)
	var probe: Node2D = load("res://src/levels/cave/wall_outline.gd").new()
	probe.build(original_cells, cave_map.tile_size, revised.wall_prototype)
	check(probe.conflicts.size() == 26, "Original layout reproduces 26 wall conflicts")
	probe.free()
	var queue: Array[Vector2i] = [Vector2i(63, 76)]
	var reached: Dictionary = {Vector2i(63, 76): true}
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor := cell + direction
			if cells.has(neighbor) and not reached.has(neighbor):
				reached[neighbor] = true
				queue.append(neighbor)
	check(reached.size() == cells.size(), "All map cells reachable from spawn")
	for room: Dictionary in revised.rooms:
		check(reached.has(Vector2i(roundi(room.x + room.w / 2), roundi(room.y + room.h / 2))), "Room " + str(room.id) + " connected")
	# Check body clearance through every cell center and shared edge, including water.
	for cell: Vector2i in cells:
		check(player.can_stand_at((Vector2(cell) + Vector2.ONE * 0.5) * 32), "Body cannot stand at " + str(cell))
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			if cells.has(cell + direction):
				check(player.can_stand_at((Vector2(cell) + Vector2.ONE * 0.5 + Vector2(direction) * 0.5) * 32), "Blocked shared edge at " + str(cell))
	# Physically traverse both top turns and the complete one-cell bypass.
	player.position = Vector2(66.5, 2.5) * 32
	for point: Vector2 in [Vector2(66.5, -1.5), Vector2(103.5, -1.5), Vector2(103.5, 2.5)]:
		var target := point * 32
		for step in range(4000):
			var difference: Vector2 = target - player.position
			if difference.length() < 0.1:
				break
			player.move_direction(difference, minf(1.0 / 60.0, difference.length() / 122.0))
		check(player.position.distance_to(target) < 0.1, "Cannot traverse bypass waypoint " + str(point))
	# A solid north wall blocks movement at the floor boundary.
	player.position = Vector2(55.5, 70.5) * 32
	for step in range(120):
		player.move_direction(Vector2.UP, 1.0 / 60.0)
	check(player.position.y >= 70 * 32 + 6, "Player crossed north wall")
	check(player.position.y < 70 * 32 + 9, "Collision stops too far from wall foot")
	check(cave_map.river_layer.get_used_cells().size() == 232, "River remains 232 cells")
	for mode in range(3):
		scene.get_debug_tools().set_wall_mode(mode)
		check(cells == cave_map.walkable_cells, "View toggle changes collision")
	# The map may be placed away from the world origin without changing grid rules.
	var old_map_position := cave_map.position
	cave_map.position = Vector2(20000.0, -5000.0)
	var translated_spawn := cave_map.get_spawn_position()
	check(player.can_stand_at(translated_spawn), "Translated map spawn remains walkable")
	check(cave_map.world_to_cell(translated_spawn) == Vector2i(63, 76), "World/grid conversion respects map transform")
	check(not player.can_stand_at(Vector2(63.5, 76.5) * 32), "Old world coordinates are not used by translated map")
	cave_map.position = old_map_position
	player.global_position = cave_map.get_spawn_position()
	# Overview must release the top-level camera again when returning to follow mode.
	for cycle in range(2):
		scene.get_debug_tools().toggle_overview()
		check(player.overview_enabled and player.camera.top_level, "Overview detaches the camera")
		scene.get_debug_tools().toggle_overview()
		player.move_direction(Vector2.RIGHT, 1.0 / 60.0)
		check(not player.overview_enabled and not player.camera.top_level, "Follow mode restores parent transform")
		check(player.camera.global_position.is_equal_approx(player.global_position), "Camera follows after overview toggle")
	for action in ["move_left", "move_right", "move_up", "move_down", "debug_cycle_walls", "debug_toggle_overview"]:
		check(InputMap.has_action(action), "InputMap action missing: " + action)
	var expected_bindings := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"debug_cycle_walls": [KEY_F2], "debug_toggle_overview": [KEY_M],
	}
	for action: String in expected_bindings:
		var physical_keys: Array[int] = []
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				physical_keys.append(event.physical_keycode)
		for key in expected_bindings[action]:
			check(physical_keys.has(key), "Incorrect key binding for " + action)
	var before_input := player.position
	Input.action_press("move_right")
	player._physics_process(1.0 / 60.0)
	Input.action_release("move_right")
	check(player.position.x > before_input.x, "InputMap drives player movement")
	# Failed reloads keep the existing playable map intact.
	var previous_cells := cave_map.walkable_cells.duplicate()
	check(cave_map.load_layout("res://missing_cave_layout.json") == ERR_FILE_NOT_FOUND, "Missing layout has a useful error")
	check(cave_map.walkable_cells == previous_cells, "Failed reload retains existing geometry")
	var standalone_map: CaveMap = load("res://src/levels/cave/cave_map.tscn").instantiate()
	root.add_child(standalone_map)
	check(standalone_map.load_error == OK and standalone_map.walkable_cells.size() == 6309, "Map scene builds independently")
	standalone_map.queue_free()
	var result := {"checks": checks, "failures": failures, "original_wall_conflicts": 26, "revised_wall_conflicts": cave_map.walls.conflicts.size(), "reachable_cells": reached.size(), "walkable_cells": cells.size(), "rooms": revised.rooms.size(), "river_cells": cave_map.river_layer.get_used_cells().size(), "bypass_movement": "simulated through both corners"}
	DirAccess.make_dir_recursive_absolute("res://.godot/verification")
	var file := FileAccess.open("res://.godot/verification/wall_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func add_rect(cells: Dictionary, rect: Array) -> void:
	for y in range(roundi(rect[1]), roundi(rect[1] + rect[3])):
		for x in range(roundi(rect[0]), roundi(rect[0] + rect[2])):
			cells[Vector2i(x, y)] = true
