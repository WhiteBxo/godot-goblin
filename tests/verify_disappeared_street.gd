extends SceneTree
## Real scene, physical player, input dispatch and optional rendered captures.

const STEP := 24
var _failures: Array[String] = []
var _query := PhysicsShapeQueryParameters2D.new()
var _level: DisappearedStreetMap
var _reachable: Dictionary[Vector2i, bool] = {}
var _free: Dictionary[Vector2i, bool] = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	var game: Node = load("res://src/debug/disappeared_street/disappeared_street_demo.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var player: ShopPlayer = game.get_player()
	_level = game.get_active_level()
	var identity := player.get_instance_id()
	_query.shape = player.get_node("CollisionShape2D").shape
	_query.collision_mask = 1
	for frame in range(6):
		await physics_frame
	_check(_can_stand(player.global_position), "Spawn must be physically clear for the actual player capsule")
	_check(_level.get_node("Ground").get_used_cells().size() == 120, "Saved floor cells must survive runtime initialization")
	_flood(player.global_position)
	for point: InteractionPoint in _level.get_interaction_points():
		_check(_can_stand(point.global_position), "Interaction approach intersects scenery: " + str(point.interaction_id))
		_check(_reachable_near(point.global_position), "Interaction is not reachable from shop: " + str(point.interaction_id))
	for object: Node2D in _level.get_node("Objects").get_children():
		_check(object.scale == Vector2.ONE and object.get_node("Visual").scale == Vector2.ONE, "Artwork must keep native proportions: " + str(object.name))
	var start := player.global_position
	Input.action_press("move_down")
	for frame in range(24):
		await physics_frame
	Input.action_release("move_down")
	_check(player.global_position.y > start.y + 35, "Real movement input must leave the shop landing")
	var ground: TileMapLayer = _level.get_node("Ground")
	ground.erase_cell(Vector2i(6, 5))
	player.global_position = Vector2(832, 605)
	player.velocity = Vector2.ZERO
	Input.action_press("move_down")
	for frame in range(35):
		await physics_frame
	Input.action_release("move_down")
	_check(player.global_position.y > 615 and player.global_position.y < 632, "Real movement must stop at a floor cell removed in the editor data")
	ground.set_cell(Vector2i(6, 5), 0, Vector2i(6, 5))
	player.global_position = Vector2(414, 510)
	player.velocity = Vector2.ZERO
	Input.action_press("move_up")
	for frame in range(45):
		await physics_frame
	Input.action_release("move_up")
	_check(player.global_position.y >= 450, "Actual player must stop at the shop facade")
	player.global_position = Vector2(460, 1040)
	player.velocity = Vector2.ZERO
	Input.action_press("move_up")
	for frame in range(40):
		await physics_frame
	Input.action_release("move_up")
	_check(player.global_position.y >= 975, "Actual player must stop against the stall counter")
	if "--captures" in OS.get_cmdline_user_args():
		await _capture_views(game, player)
	player.global_position = Vector2(740, 1065)
	player.velocity = Vector2.ZERO
	for frame in range(5):
		await physics_frame
	await _action(&"interact")
	_check(game.get_interaction_ui().is_open() and not player.movement_enabled, "E must inspect coins and lock walking during the popup")
	await _action(&"ui_cancel")
	_check(not game.get_interaction_ui().is_open() and player.movement_enabled, "Closing inspection must restore walking")
	# Holding the door key through the fade cannot immediately send us back.
	player.global_position = Vector2(414, 505)
	player.velocity = Vector2.ZERO
	for frame in range(5):
		await physics_frame
	await _press(&"interact", true)
	for frame in range(100):
		await physics_frame
	_check(game.is_inside_shop() and not game.is_changing_level(), "Door E must enter the existing shop once, even while held")
	_check(player.get_instance_id() == identity, "Map changes must preserve the same player")
	if "--captures" in OS.get_cmdline_user_args():
		await _capture_root("shop_connection")
	await _press(&"interact", false)
	for frame in range(5):
		await physics_frame
	await _action(&"interact")
	for frame in range(100):
		await physics_frame
	_check(not game.is_inside_shop() and not game.is_changing_level(), "Releasing and pressing E must return to the street")
	_check(player.global_position.distance_to(Vector2(420, 530)) < 1.0, "Return must land safely outside the same shop door")
	print("DISAPPEARED_STREET: ", "PASS" if _failures.is_empty() else "FAIL", " (reachable scenery, real movement/collision, E inspection, held-key-safe door round trip, persistent player)")
	game.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)

func _can_stand(at: Vector2) -> bool:
	_query.transform = Transform2D(PI * .5, at)
	return _level.get_world_2d().direct_space_state.intersect_shape(_query, 1).is_empty()

func _cell_free(cell: Vector2i) -> bool:
	if not _free.has(cell):
		var at := Vector2(cell) * STEP
		_free[cell] = _level.has_floor_at(at) and _can_stand(at)
	return _free[cell]

func _flood(at: Vector2) -> void:
	var start := Vector2i((at / STEP).round())
	var queue: Array[Vector2i] = [start]
	_reachable[start] = true
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + direction
			if next.x < 0 or next.y < 0 or next.x >= 64 or next.y >= 54 or _reachable.has(next):
				continue
			if _cell_free(next) and _can_stand((Vector2(cell) + Vector2(next)) * STEP * .5):
				_reachable[next] = true
				queue.append(next)

func _reachable_near(at: Vector2) -> bool:
	var cell := Vector2i((at / STEP).round())
	for x in range(-1, 2):
		for y in range(-1, 2):
			var candidate := cell + Vector2i(x, y)
			if _reachable.has(candidate) and _can_stand((Vector2(candidate) * STEP + at) * .5):
				return true
	return false

func _press(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func _action(action: StringName) -> void:
	await _press(action, true)
	await _press(action, false)

func _capture_root(label: String) -> void:
	for frame in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/disappeared_street/captures/" + label + ".png")

func _capture_views(game: Node, player: ShopPlayer) -> void:
	# A second real camera renders the live World2D at native map resolution.
	player.global_position = Vector2(414, 515)
	player.velocity = Vector2.ZERO
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1536, 1280)
	viewport.world_2d = root.world_2d
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera2D.new()
	camera.position = Vector2(768, 640)
	viewport.add_child(camera)
	camera.make_current()
	# Keep focus brackets out of the clean whole-map comparison image.
	game.get_node("World/EffectRoot").hide()
	await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://docs/disappeared_street/captures/street_overview.png")
	viewport.queue_free()
	await process_frame
	game.get_node("World/EffectRoot").show()
	player.camera.make_current()
	player.camera.reset_smoothing()
	await _capture_root("shop_scale")
	player.global_position = Vector2(460, 987)
	player.velocity = Vector2.ZERO
	player.camera.reset_smoothing()
	await _capture_root("market_scale")
	player.global_position = Vector2(1380, 360)
	player.velocity = Vector2.ZERO
	player.camera.reset_smoothing()
	await _capture_root("dark_exit")
