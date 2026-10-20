extends SceneTree
## Verify physical reachability with the real player's footprint, not visual rectangles.

var _failures: Array[String] = []
var _map: SettlementMap
var _player: ShopPlayer
var _query := PhysicsShapeQueryParameters2D.new()
var _free: Dictionary = {}
var _reachable: Dictionary = {}
const STEP := 32

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	# The formal host (`src/core/settlement.tscn`) now mounts the RPG Maker
	# chapter settlement, not this editable map, so the map is exercised directly
	# here. Host-level UI/input behaviour is covered by the chapter-host tests.
	_map = load("res://src/levels/settlement/settlement_map.tscn").instantiate()
	root.add_child(_map)
	_player = load("res://src/gameplay/player/shop_player.tscn").instantiate()
	_map.add_child(_player)
	await physics_frame
	await physics_frame
	_player.global_position = _map.get_spawn_position()
	_check(_map != null and _player != null, "Editable settlement map must build with a player")
	if _map == null or _player == null:
		quit(1)
		return
	_check(_map.get_node("Districts").get_child_count() == 16, "All 15 reference regions plus the shop must be present")
	_check(_map.get_node("Ground").get_used_cells().size() > 700, "Continuous editable ground must be saved in the scene")
	_query.shape = _player.get_node("CollisionShape2D").shape
	_query.collision_mask = 1
	_query.exclude = [_player.get_rid()]
	_check(_can_stand(_player.global_position), "Spawn must be clear")
	var start := Vector2i((_player.global_position / STEP).round())
	var queue: Array[Vector2i] = [start]
	_reachable[start] = true
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + offset
			if _reachable.has(next) or next.x < 0 or next.y < 0 or next.x > 256 or next.y > 288:
				continue
			if _cell_free(next):
				_reachable[next] = true
				queue.append(next)
	for district: Node2D in _map.get_node("Districts").get_children():
		_check(district.scale.is_equal_approx(Vector2.ONE), "District artwork must not stretch: " + district.name)
		var entry: Marker2D = district.get_node("Entrance")
		_check(_near_reachable(entry.global_position), "Unreachable entrance: " + district.name)
		_check(_can_stand(entry.global_position), "Entrance overlaps physical furniture/wall: " + district.name)
		var interior := entry.global_position + Vector2(0, -170)
		_check(_near_reachable(interior), "Cannot walk through door into district: " + district.name)
	for anchor: Marker2D in _map.get_node("StoryAnchors").get_children():
		if "hidden" in String(anchor.name):
			continue  # Reserved hidden-route clues are not public destinations.
		_check(_can_stand(anchor.global_position), "Story anchor overlaps a solid object: " + anchor.name)
		_check(_near_reachable(anchor.global_position), "Story destination unreachable: " + anchor.name)
	for y in [3328, 5504]:
		for x in range(2080, 2625, 32):
			_check(_can_stand(Vector2(x, y)), "Bridge must be physically crossable")
	_check(not _can_stand(Vector2(2336, 4500)), "River outside bridges must block walking")
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/levels/settlement/settlement_layout.json"))
	for route: String in layout.routes:
		var points: Array = layout.routes[route]
		for index in range(points.size() - 1):
			var from := Vector2(points[index][0], points[index][1])
			var to := Vector2(points[index + 1][0], points[index + 1][1])
			var steps := maxi(1, ceili(from.distance_to(to) / 16.0))
			for step in range(steps + 1):
				var at := from.lerp(to, float(step) / steps)
				if not _can_stand(at):
					_check(false, "Route %s intersects a solid at %s" % [route, at])
					break
	var initial := _player.global_position
	Input.action_press("move_down")
	for index in range(20):
		await physics_frame
	Input.action_release("move_down")
	_check(_player.global_position.y > initial.y + 30, "Actual input must move the player out of the shop")
	# Push against a known solid front wall with the real physics controller.
	_player.global_position = Vector2(3200, 4830)
	_player.velocity = Vector2.ZERO
	Input.action_press("move_up")
	for index in range(50):
		await physics_frame
	Input.action_release("move_up")
	_check(_player.global_position.y > 4730, "Actual player must not cross the tavern front wall")
	print("Reachable physical samples: %d; checked 16 districts, public story anchors, bridges, real movement and walls." % _reachable.size())
	_map.queue_free()
	await process_frame
	# Keep the production host under test as well: it must still assemble a
	# playable chapter settlement with preview tools disabled.
	var previous_debug: Variant = ProjectSettings.get_setting("debug/developer_tools/enabled", true)
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	var normal: MainGame = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(normal)
	await physics_frame
	await physics_frame
	_check(normal.get_active_level() is RpgChapterMap and normal.get_player() != null, "Production host must assemble the chapter settlement")
	_check(normal.get_node_or_null("Systems/SettlementPreview") == null, "Disabled debug tools must not create map inspection UI")
	normal.queue_free()
	await process_frame
	ProjectSettings.set_setting("debug/developer_tools/enabled", previous_debug)
	if _failures.is_empty():
		print("PASS settlement")
		quit()
	else:
		print("FAIL settlement: ", _failures)
		quit(1)

func _can_stand(at: Vector2) -> bool:
	_query.transform = Transform2D(PI * 0.5, at)
	return _map.get_world_2d().direct_space_state.intersect_shape(_query, 1).is_empty()

func _action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventAction.new()
	event.action = action
	Input.parse_input_event(event)
	await process_frame

func _cell_free(cell: Vector2i) -> bool:
	if not _free.has(cell):
		_free[cell] = _can_stand(Vector2(cell) * STEP)
	return _free[cell]

func _near_reachable(at: Vector2) -> bool:
	var cell := Vector2i((at / STEP).round())
	for y in range(-1, 2):
		for x in range(-1, 2):
			var candidate := cell + Vector2i(x, y)
			if not _reachable.has(candidate):
				continue
			var start := Vector2(candidate) * STEP
			var steps := maxi(1, ceili(start.distance_to(at) / 8.0))
			var clear := true
			for index in range(steps + 1):
				if not _can_stand(start.lerp(at, float(index) / steps)):
					clear = false
					break
			if clear:
				return true
	return false

func _captures(main: MainGame) -> void:
	var dest := ProjectSettings.globalize_path("res://docs/levels/settlement/captures")
	DirAccess.make_dir_recursive_absolute(dest)
	var preview: Node = main.get_node("Systems/SettlementPreview")
	preview.set_overview(true)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dest + "/overview.png")
	# Render the same live World2D into a portrait viewport for a readable whole-map artifact.
	var overview := SubViewport.new()
	overview.size = Vector2i(2048, 2304)
	overview.world_2d = _map.get_world_2d()
	overview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(overview)
	var camera := Camera2D.new()
	camera.position = _map.get_world_bounds().get_center()
	camera.zoom = Vector2(0.235, 0.235)
	overview.add_child(camera)
	camera.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	overview.get_texture().get_image().save_png(dest + "/full_map.png")
	overview.queue_free()
	preview.set_route(1)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dest + "/day1_route.png")
	preview.set_route(2)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dest + "/day2_route.png")
	preview.set_route(0)
	preview.set_overview(false)
	for shot: Array in [["shop", Vector2(5180, 8560)], ["tavern", Vector2(3568, 4430)], ["casino", Vector2(6568, 4470)], ["elder", Vector2(6320, 1370)], ["bridge", Vector2(2336, 5504)], ["front_wall", Vector2(3200, 4710)]]:
		_player.global_position = shot[1]
		_player.velocity = Vector2.ZERO
		_player.set_movement_enabled(false)
		_player.camera.begin_cinematic()
		_player.camera.set_cinematic_position(shot[1] + Vector2(0, -100))
		for frame in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(dest + "/" + shot[0] + ".png")
	print("Captured actual Godot views: ", dest)
