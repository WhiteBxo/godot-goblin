extends SceneTree
## Saved furniture footprints and real player access through the elder interior.

const MAP_SCENE := preload("res://src/levels/rpg_maker/chapter_elder_house.tscn")
const PLAYER_SCENE := preload("res://src/gameplay/player/rpg_player.tscn")
const FEET := Vector2(8.5, 5.0)

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for frame in range(4):
		await physics_frame


func _check_route(map: RpgChapterMap, player: FloorAwareShopPlayer, start: Vector2, target: Vector2, label: String) -> void:
	var path := map.get_navigation_path(start, target)
	var same_cell := map.world_to_cell(start) == map.world_to_cell(target)
	_check(same_cell or not path.is_empty(), "Saved passages retain a route to " + label)
	if path.is_empty() and not same_cell:
		return
	path.append(target)
	var previous := start
	var clear := map.is_walkable_at(start, FEET)
	for position: Vector2 in path:
		clear = clear and map.is_walkable_at(position, FEET)
		clear = clear and not player.test_move(Transform2D(0.0, previous), position - previous)
		previous = position
	_check(clear, "The actual foot capsule can traverse every segment to " + label)


func _run() -> void:
	var map := MAP_SCENE.instantiate() as RpgChapterMap
	var player := PLAYER_SCENE.instantiate() as FloorAwareShopPlayer
	_check(map != null and player != null, "Real chapter map and RPG player instantiate")
	if map == null or player == null:
		quit(1)
		return
	player.get_node("Camera2D").enabled = false
	root.add_child(map)
	root.add_child(player)
	player.set_physics_process(false)
	player.set_floor_query(map.can_stand_at)
	await _settle()
	var blocked: Array[Vector2i] = [Vector2i(9, 3), Vector2i(10, 3), Vector2i(12, 3), Vector2i(15, 11)]
	for y in range(4, 8):
		for x in range(12, 14):
			blocked.append(Vector2i(x, y))
	for cell: Vector2i in blocked:
		_check(not map.is_cell_walkable(cell) and not map.is_walkable_at(map.cell_to_world(cell), FEET),
			"Furniture rejects the real foot footprint at " + str(cell))
	for y in range(4, 9):
		_check(map.is_walkable_at(map.cell_to_world(Vector2i(14, y)), FEET),
			"The dining room retains a full-width entrance lane at " + str(Vector2i(14, y)))
	for pair: Array in [
		[Vector2i(8, 3), Vector2i(9, 3)],
		[Vector2i(13, 3), Vector2i(12, 3)],
		[Vector2i(14, 5), Vector2i(13, 5)],
		[Vector2i(14, 11), Vector2i(15, 11)],
	]:
		var from: Vector2 = map.cell_to_world(pair[0])
		var to: Vector2 = map.cell_to_world(pair[1])
		_check(player.test_move(Transform2D(0.0, from), to - from),
			"Derived world collision stops the actual player before " + str(pair[1]))
	var spawn := map.get_spawn_position()
	for node_path: String in ["Interactions/day1_elder_document", "Interactions/day1_blood_storage", "Interactions/SignatureS10", "Exits/Outside"]:
		var point := map.get_node(node_path) as InteractionPoint
		_check_route(map, player, spawn, point.global_position, node_path)
		player.teleport_to(point.global_position)
		await _settle()
		_check(point.get_overlapping_bodies().has(player), "The real player reaches the interaction area for " + node_path)
	_check_route(map, player, spawn, map.cell_to_world(Vector2i(15, 4)), "the far side of the dining room")
	player.queue_free()
	map.queue_free()
	await _settle()
	print("RPG_FURNITURE_COLLISION: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
