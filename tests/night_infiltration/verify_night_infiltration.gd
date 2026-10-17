extends SceneTree
## Real movement and physics on the saved reference-coordinate scene.
const STEP := 12
var failures: Array[String] = []
var level: NightInfiltrationMap
var query := PhysicsShapeQueryParameters2D.new()
var reachable: Dictionary[Vector2i, bool] = {}
var free_cells: Dictionary[Vector2i, bool] = {}

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var game: Node = load("res://src/debug/night_infiltration/night_infiltration_demo.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	level = game.get_active_level()
	var player: ShopPlayer = game.get_player()
	query.shape = player.get_node("CollisionShape2D").shape
	query.collision_mask = 1
	for frame in range(6):
		await physics_frame
	check(can_stand(player.global_position), "Spawn must be clear for the actual player feet")
	var ground: TileMapLayer = level.get_node("Ground")
	check(ground.get_used_cells().size() == 405, "405 saved floor cells must survive initialization")
	check(ground.get_cell_atlas_coords(Vector2i(20, 7)) == Vector2i(20, 7), "Ground must preserve original spatial lighting, without repeating a tiny patch")
	check(level.get_node("Objects").get_child_count() == 38, "Reference must be decomposed into 38 independent modules")
	for object: Node2D in level.get_node("Objects").get_children():
		check(object.scale == Vector2.ONE and object.get_node("Visual").scale == Vector2.ONE, "Native art was scaled: " + str(object.name))
	var ports := 0
	for anchor: Node in level.get_node("StoryAnchors").get_children():
		if anchor.get_meta("external_port", false):
			ports += 1
	check(ports == 1, "Exactly one external interface is allowed")
	check(not can_stand(Vector2(1290, 835)), "Southeast gap must be closed physically")
	# Use the entry's right side to pass the standing guard, without passing through him.
	player.global_position = Vector2(286, 850)
	await walk(&"move_up", 62)
	check(player.global_position.y < 630, "Real input must pass the checkpoint through its open space")
	player.global_position = Vector2(500, 355)
	await walk(&"move_up", 35)
	check(player.global_position.y >= 319, "West house must block actual movement")
	player.global_position = Vector2(1260, 497)
	await walk(&"move_up", 25)
	check(player.global_position.y >= 463, "Closed elder door must block movement")
	await action(&"interact")
	for frame in range(3):
		await physics_frame
	check(level.elder_door_open, "E at the door must open it")
	check(level.get_node("Architecture/ElderDoor/Shape").disabled, "Opening must disable the physical door")
	check(level.get_node("Objects/ElderDoorOpen").visible and not level.get_node("Objects/ElderDoorClosed").visible, "Opening must swap local artwork")
	await walk(&"move_up", 45)
	check(player.global_position.y < 330, "Real player must enter the room through the opened doorway")
	flood(level.get_spawn_position())
	for point: InteractionPoint in level.get_interaction_points():
		check(can_stand(point.global_position), "Interaction approach collides: " + str(point.interaction_id))
		check(reachable_near(point.global_position), "Interaction cannot be reached from entry: " + str(point.interaction_id))
	player.global_position = level.get_story_anchor(&"Manuscript").global_position
	player.velocity = Vector2.ZERO
	for frame in range(6):
		await physics_frame
	await action(&"interact")
	check(game.get_interaction_ui().is_open() and not player.movement_enabled, "Inspection must lock walking")
	await action(&"ui_cancel")
	check(not game.get_interaction_ui().is_open() and player.movement_enabled, "Esc must restore walking")
	ground.erase_cell(Vector2i(14, 5))
	check(not level.can_stand_at(Vector2(928, 352), Vector2(17, 10)), "Removing a saved floor cell must change the player's floor query")
	ground.set_cell(Vector2i(14, 5), 0, Vector2i(14, 5))
	print("NIGHT_INFILTRATION: ", "PASS" if failures.is_empty() else "FAIL", " (native composition, saved cells, one port, real input/collision, E door, reachable interior, E/Esc)")
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func walk(id: StringName, frames: int) -> void:
	Input.action_press(id)
	for frame in range(frames):
		await physics_frame
	Input.action_release(id)

func can_stand(at: Vector2) -> bool:
	query.transform = Transform2D(PI * 0.5, at)
	return level.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func cell_free(cell: Vector2i) -> bool:
	if not free_cells.has(cell):
		var at := Vector2(cell) * STEP
		free_cells[cell] = level.can_stand_at(at, Vector2(17, 10)) and can_stand(at)
	return free_cells[cell]

func flood(at: Vector2) -> void:
	var start := Vector2i((at / STEP).round())
	var queue: Array[Vector2i] = [start]
	reachable[start] = true
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + direction
			if next.x < 0 or next.y < 0 or next.x >= 140 or next.y >= 79 or reachable.has(next):
				continue
			if cell_free(next) and can_stand((Vector2(cell) + Vector2(next)) * STEP * 0.5):
				reachable[next] = true
				queue.append(next)

func reachable_near(at: Vector2) -> bool:
	var cell := Vector2i((at / STEP).round())
	for x in range(-1, 2):
		for y in range(-1, 2):
			var candidate := cell + Vector2i(x, y)
			if reachable.has(candidate) and can_stand((Vector2(candidate) * STEP + at) * 0.5):
				return true
	return false

func action(id: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = id
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
