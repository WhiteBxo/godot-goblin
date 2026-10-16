extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _frames(count: int) -> void:
	for index in range(count):
		await physics_frame
	await process_frame
	await process_frame

func _key(physical_key: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = physical_key
	event.keycode = physical_key
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = physical_key
	event.keycode = physical_key
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	var main: MainGame = load("res://src/core/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	var level := main.get_active_level() as MilkTeaShop
	var player := main.get_player() as ShopPlayer
	var ui: ShopUI = main.get_node("HudLayer/ShopUI")
	_check(level != null and player != null, "Main scene must assemble the shop and player")
	_check(InputMap.action_has_event("interact", _e_event()), "E must use the interact InputMap action")
	var spawn := player.global_position
	Input.action_press("move_right")
	await _frames(15)
	_check(player.global_position.x > spawn.x + 45.0, "WASD input must move the player")
	_check(is_equal_approx(player.velocity.length(), player.speed), "Cardinal speed must match speed")
	Input.action_press("move_down")
	await _frames(1)
	_check(is_equal_approx(player.velocity.length(), player.speed), "Diagonal movement must not be faster")
	Input.action_release("move_right")
	Input.action_release("move_down")
	await _frames(1)
	# Every saved obstacle must physically block the actual player's foot shape.
	for collider: CollisionShape2D in level.get_node("WallsAndFurniture").get_children():
		var size: Vector2 = collider.shape.size
		var start := collider.global_position + Vector2(0, size.y * 0.5 + 22)
		_check(player.test_move(Transform2D(0.0, start), Vector2(0, -44)), "Missing collision: " + collider.name)
	# Push into the real counter for one second; the player must stay outside.
	player.global_position = Vector2(800, 620)
	Input.action_press("move_down")
	await _frames(60)
	Input.action_release("move_down")
	_check(player.global_position.y < 643, "Player must not pass through the counter")
	_check(_reachable(level, player), "All three interaction points must be reachable from spawn")
	for point in level.get_interaction_points():
		player.global_position = point.global_position
		await _frames(3)
		_check(point.is_available(), "Point must detect player: " + point.display_name)
		_check(ui.get_node("Prompt").visible, "Approach must display the interaction prompt")
		await _key(KEY_E)
		_check(ui.is_open(), "E must open UI: " + point.display_name)
		_check(main.get_node("PopupLayer/Modal/Center/Panel/Margin/Content/Title").text == point.display_name, "UI title must match point")
		var position_before := player.global_position
		Input.action_press("move_right")
		await _frames(5)
		Input.action_release("move_right")
		_check(player.global_position.is_equal_approx(position_before), "Movement must stop while UI is open")
		await _key(KEY_ESCAPE)
		_check(not ui.is_open() and player.movement_enabled, "Esc must close UI and restore movement")
	player.global_position = spawn
	await _frames(3)
	_check(not ui.get_node("Prompt").visible, "Leaving a point must hide the prompt")
	await _key(KEY_E)
	_check(not ui.is_open(), "E outside interaction range must do nothing")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/milk_tea_verification/shop.png")
		player.global_position = level.get_interaction_points()[0].global_position
		await _frames(3)
		await _key(KEY_E)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/milk_tea_verification/orders.png")
	print("MILK_TEA_SHOP: ", "PASS" if _failures.is_empty() else "FAIL", " (movement, 15 obstacles, reachability, 3 UIs, input and movement lock)")
	quit(0 if _failures.is_empty() else 1)

func _e_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	return event

func _reachable(level: MilkTeaShop, player: ShopPlayer) -> bool:
	# Flood the real physics space with the player's shape, not a second obstacle map.
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = player.get_node("CollisionShape2D").shape
	query.collision_mask = 1
	var space := player.get_world_2d().direct_space_state
	var start := Vector2i(level.get_spawn_position() / 24.0)
	var visited := {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + offset
			if visited.has(next) or next.x < 0 or next.y < 0 or next.x > 69 or next.y > 38:
				continue
			query.transform = Transform2D(0.0, Vector2(next) * 24.0)
			if space.intersect_shape(query, 1).is_empty() and not player.test_move(Transform2D(0.0, Vector2(cell) * 24.0), Vector2(offset) * 24.0):
				visited[next] = true
				queue.append(next)
	for point in level.get_interaction_points():
		var found := false
		for cell: Vector2i in queue:
			if (Vector2(cell) * 24.0).distance_to(point.global_position) < 60.0:
				found = true
				break
		if not found:
			return false
	return true
