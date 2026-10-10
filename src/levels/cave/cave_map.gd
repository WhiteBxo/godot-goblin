class_name CaveMap
extends Node2D

const ATLAS := preload("res://src/resources/tilesets/cave_atlas.gd")
const MASK_TO_ATLAS := ATLAS.MASK_TO_ATLAS

enum WallMode { OFF, TEXTURED, FLAT }

@export_file("*.json") var layout_path := "res://src/levels/cave/cave_layout.json"

@onready var floor_layer: TileMapLayer = $FloorLayer
@onready var river_layer: TileMapLayer = $RiverLayer
@onready var walls: CaveWallOutline = $WallOutline

var layout_data: Dictionary = {}
var walkable_cells: Dictionary = {}
var map_bounds := Rect2i()
var tile_size := ATLAS.TILE_SIZE
var wall_mode := WallMode.TEXTURED
var spawn_cell := Vector2i.ZERO
var load_error: Error = OK

func _ready() -> void:
	load_error = load_layout(layout_path)
	if load_error != OK:
		push_error("Could not build cave layout: %s (error %d)" % [layout_path, load_error])

func load_layout(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return ERR_PARSE_ERROR
	var data: Dictionary = json.data
	if not _valid_layout(data):
		return ERR_INVALID_DATA
	var next_cells: Dictionary = {}
	for room: Dictionary in data.rooms:
		_add_rect_cells(next_cells, [room.x, room.y, room.w, room.h])
	for corridor: Array in data.corridors:
		_add_rect_cells(next_cells, corridor)
	var next_spawn := Vector2i(int(data.spawn_cell[0]), int(data.spawn_cell[1]))
	if not next_cells.has(next_spawn):
		return ERR_INVALID_DATA
	layout_data = data
	layout_path = path
	walkable_cells = next_cells
	spawn_cell = next_spawn
	tile_size = int(data.tile_size)
	floor_layer.clear()
	river_layer.clear()
	floor_layer.position = Vector2.ONE * tile_size * 0.5
	var floor_candidates: Dictionary = {}
	for cell: Vector2i in walkable_cells:
		for offset in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.UP, Vector2i(-1, -1)]:
			floor_candidates[cell + offset] = true
	for cell: Vector2i in floor_candidates:
		var mask := corner_mask(cell)
		if mask != 0:
			floor_layer.set_cell(cell, 0, MASK_TO_ATLAS[mask])
	for river: Array in data.rivers:
		for y in range(int(river[1]), int(river[1] + river[3])):
			for x in range(int(river[0]), int(river[0] + river[2])):
				var cell := Vector2i(x, y)
				if walkable_cells.has(cell):
					river_layer.set_cell(cell, 0, Vector2i.ZERO)
	map_bounds = _measure_map_bounds()
	walls.build(walkable_cells, tile_size, data.wall_prototype)
	set_wall_mode(wall_mode)
	load_error = OK
	return OK

func cell_to_world(cell: Vector2) -> Vector2:
	return to_global(cell * tile_size)

func world_to_cell(world_position: Vector2) -> Vector2i:
	var local_position := to_local(world_position)
	return Vector2i(floori(local_position.x / tile_size), floori(local_position.y / tile_size))

func get_spawn_position() -> Vector2:
	return cell_to_world(Vector2(spawn_cell) + Vector2.ONE * 0.5)

func can_stand_at(world_position: Vector2, body_half_size: Vector2) -> bool:
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			var corner := world_position + body_half_size * Vector2(x_sign, y_sign)
			if not walkable_cells.has(world_to_cell(corner)):
				return false
	return true

func corner_mask(cell: Vector2i) -> int:
	return ATLAS.corner_mask(cell, walkable_cells)

func get_world_bounds() -> Rect2:
	var local_bounds := Rect2(Vector2(map_bounds.position) * tile_size, Vector2(map_bounds.size) * tile_size)
	return get_global_transform() * local_bounds

func set_wall_mode(mode: int) -> void:
	wall_mode = clampi(mode, WallMode.OFF, WallMode.FLAT)
	walls.visible = wall_mode != WallMode.OFF
	walls.flat_floor = wall_mode == WallMode.FLAT
	floor_layer.visible = wall_mode != WallMode.FLAT
	river_layer.z_index = -4 if wall_mode == WallMode.FLAT else -8
	walls.queue_redraw()

func get_wall_mode_name() -> String:
	return ["关闭墙体", "墙体 + 石砖地面", "纯色轮廓"][wall_mode]

func _valid_layout(data: Dictionary) -> bool:
	if not data.get("rooms") is Array or not data.get("corridors") is Array:
		return false
	if not data.get("spawn_cell") is Array or data.spawn_cell.size() != 2:
		return false
	if not data.get("rivers") is Array or not data.get("wall_prototype") is Dictionary:
		return false
	if data.get("tile_size") != floor_layer.tile_set.tile_size.x:
		return false
	for value in data.spawn_cell:
		if not _is_integer(value):
			return false
	for room in data.rooms:
		if not room is Dictionary or not room.has_all(["x", "y", "w", "h"]):
			return false
		if not _valid_rect([room.x, room.y, room.w, room.h]):
			return false
	for rect in data.corridors + data.rivers:
		if not _valid_rect(rect):
			return false
	for field in ["height_pixels", "cap_pixels", "side_pixels", "front_pixels"]:
		if not _is_integer(data.wall_prototype.get(field)) or data.wall_prototype[field] < 0:
			return false
	return not data.rooms.is_empty()

func _valid_rect(rect: Variant) -> bool:
	if not rect is Array or rect.size() != 4:
		return false
	for value in rect:
		if not _is_integer(value):
			return false
	return rect[2] > 0 and rect[3] > 0

func _is_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_equal_approx(float(value), roundf(float(value)))

func _add_rect_cells(cells: Dictionary, rect: Array) -> void:
	for y in range(int(rect[1]), int(rect[1] + rect[3])):
		for x in range(int(rect[0]), int(rect[0] + rect[2])):
			cells[Vector2i(x, y)] = true

func _measure_map_bounds() -> Rect2i:
	if not walkable_cells.is_empty():
		var cells: Array = walkable_cells.keys()
		var first_cell: Vector2i = cells[0]
		var min_x: int = first_cell.x
		var min_y: int = first_cell.y
		var max_x: int = first_cell.x
		var max_y: int = first_cell.y
		for cell: Vector2i in cells:
			min_x = mini(min_x, cell.x)
			min_y = mini(min_y, cell.y)
			max_x = maxi(max_x, cell.x)
			max_y = maxi(max_y, cell.y)
		return Rect2i(Vector2i(min_x, min_y), Vector2i(max_x - min_x + 1, max_y - min_y + 1))
	return Rect2i()
