class_name RpgMakerMap
extends Node2D
## Saved TileMapLayer cells are authoritative. Importing source JSON is an editor tool action.

const PASS_DOWN := 1
const PASS_LEFT := 2
const PASS_RIGHT := 4
const PASS_UP := 8
const ALL_DIRECTIONS := 15
const STAR := 16

@export var map_id: int = 1
@export var map_title: String = ""
@export var map_size: Vector2i = Vector2i(1, 1)
@export_range(1, 512, 1) var tile_size: int = 48
## Map-local corrections for walls and furniture whose source passage flags are open.
## Coordinates are native cells; saved tiles and shared TileSets stay authoritative for art.
@export var solid_regions: Array[Rect2i] = []

var _ground_layers: Array[TileMapLayer] = []
## Set bits indicate permitted movement, using RPG Maker's down/left/right/up bits.
var _directions: Dictionary[Vector2i, int] = {}
var _passage_body: StaticBody2D

func _ready() -> void:
	rebuild_passability()

func get_world_bounds() -> Rect2:
	return global_transform * Rect2(Vector2.ZERO, Vector2(map_size) * tile_size)

func get_camera_bounds() -> Rect2:
	return get_world_bounds()

func get_spawn_position() -> Vector2:
	return $Spawn.global_position

func world_to_cell(world_position: Vector2) -> Vector2i:
	var ground: TileMapLayer = get_node("Ground0")
	return ground.local_to_map(ground.to_local(world_position))

func cell_to_world(cell: Vector2i) -> Vector2:
	var ground: TileMapLayer = get_node("Ground0")
	return ground.to_global(ground.map_to_local(cell))

func get_cell_direction_mask(cell: Vector2i) -> int:
	return _directions.get(cell, 0)

func is_cell_walkable(cell: Vector2i) -> bool:
	return get_cell_direction_mask(cell) != 0

func can_cross_edge(cell: Vector2i, direction: Vector2i) -> bool:
	var outgoing := 0
	var incoming := 0
	match direction:
		Vector2i.DOWN:
			outgoing = PASS_DOWN
			incoming = PASS_UP
		Vector2i.LEFT:
			outgoing = PASS_LEFT
			incoming = PASS_RIGHT
		Vector2i.RIGHT:
			outgoing = PASS_RIGHT
			incoming = PASS_LEFT
		Vector2i.UP:
			outgoing = PASS_UP
			incoming = PASS_DOWN
		_:
			return false
	return (get_cell_direction_mask(cell) & outgoing) != 0 and (get_cell_direction_mask(cell + direction) & incoming) != 0

## The floor query excludes solid cells and map edges. Directional edge collisions
## are enforced by the derived world-layer StaticBody2D, preserving partial tiles.
func can_stand_at(world_position: Vector2, half_size: Vector2) -> bool:
	return is_walkable_at(world_position, half_size)

## Side-effect-free floor query for actors that only plan a step. Subclasses own
## the player-facing variant, which may report the rejected position to the HUD.
func is_walkable_at(world_position: Vector2, half_size: Vector2) -> bool:
	var minimum := Vector2i(2147483647, 2147483647)
	var maximum := Vector2i(-2147483648, -2147483648)
	for corner: Vector2 in [Vector2(-half_size.x, -half_size.y), Vector2(half_size.x, -half_size.y), Vector2(-half_size.x, half_size.y), half_size]:
		var cell := world_to_cell(world_position + corner)
		minimum = minimum.min(cell)
		maximum = maximum.max(cell)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			if not is_cell_walkable(Vector2i(x, y)):
				return false
	return true

## Call explicitly after changing saved tiles during a running editor preview.
## This derives collision only: it never writes, clears, or reloads map cells.
func rebuild_passability() -> void:
	_ground_layers.clear()
	for index in range(4):
		_ground_layers.append(get_node("Ground%d" % index) as TileMapLayer)
	_directions.clear()
	for y in range(map_size.y):
		for x in range(map_size.x):
			var cell := Vector2i(x, y)
			_directions[cell] = _read_cell_directions(cell)
	if is_instance_valid(_passage_body):
		_passage_body.collision_layer = 0
		remove_child(_passage_body)
		_passage_body.queue_free()
	_passage_body = StaticBody2D.new()
	_passage_body.name = "DerivedPassageWalls"
	_passage_body.collision_layer = 1 << (PlayerController.WORLD_LAYER - 1)
	_passage_body.collision_mask = 0
	add_child(_passage_body)
	_build_horizontal_edges()
	_build_vertical_edges()

func _read_cell_directions(cell: Vector2i) -> int:
	for region: Rect2i in solid_regions:
		if region.has_point(cell):
			return 0
	for index in range(3, -1, -1):
		var data: TileData = _ground_layers[index].get_cell_tile_data(cell)
		if data == null:
			# An omitted tile is RPG Maker's transparent B0, whose flag is STAR.
			continue
		var flags := int(data.get_custom_data("passage"))
		if int(data.get_custom_data("rpg_tile_id")) == 0:
			flags = STAR
		if bool(data.get_custom_data("star")) or (flags & STAR) != 0:
			continue
		return (~flags) & ALL_DIRECTIONS
	return 0

func _build_horizontal_edges() -> void:
	for y in range(map_size.y + 1):
		var start := -1
		for x in range(map_size.x + 1):
			var blocked := x < map_size.x and not can_cross_edge(Vector2i(x, y - 1), Vector2i.DOWN)
			if blocked and start < 0:
				start = x
			elif not blocked and start >= 0:
				_add_edge(Vector2(start, y), Vector2(x, y))
				start = -1

func _build_vertical_edges() -> void:
	for x in range(map_size.x + 1):
		var start := -1
		for y in range(map_size.y + 1):
			var blocked := y < map_size.y and not can_cross_edge(Vector2i(x - 1, y), Vector2i.RIGHT)
			if blocked and start < 0:
				start = y
			elif not blocked and start >= 0:
				_add_edge(Vector2(x, start), Vector2(x, y))
				start = -1

func _add_edge(from_grid: Vector2, to_grid: Vector2) -> void:
	var ground := _ground_layers[0]
	var shape := SegmentShape2D.new()
	shape.a = to_local(ground.to_global(from_grid * tile_size))
	shape.b = to_local(ground.to_global(to_grid * tile_size))
	var collision := CollisionShape2D.new()
	collision.shape = shape
	_passage_body.add_child(collision)
