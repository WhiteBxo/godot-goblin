@tool
class_name CaveWallOutline
extends Node2D

signal settings_changed

# Geometry is anchored at the walkable floor boundary; walls occupy solid space.
var tile_size := 32
@export_range(0, 128, 1) var wall_height := 56:
	set(value):
		if wall_height != value:
			wall_height = value
			settings_changed.emit()
@export_range(0, 32, 1) var cap_size := 4:
	set(value):
		if cap_size != value:
			cap_size = value
			settings_changed.emit()
@export_range(0, 32, 1) var side_size := 6:
	set(value):
		if side_size != value:
			side_size = value
			settings_changed.emit()
@export_range(0, 32, 1) var front_size := 5:
	set(value):
		if front_size != value:
			front_size = value
			settings_changed.emit()
const FACE_COLOR := Color("716c61")
const CAP_COLOR := Color("aaa28b")
const SIDE_COLOR := Color("494b48")
const FOOT_COLOR := Color("353a39")

var cells: Dictionary = {}
var north_edges: Array[Vector2i] = []
var south_edges: Array[Vector2i] = []
var west_edges: Array[Vector2i] = []
var east_edges: Array[Vector2i] = []
var conflicts: Array[Vector2i] = []
var flat_floor := false

func get_settings() -> Dictionary:
	return {"height_pixels": wall_height, "cap_pixels": cap_size, "side_pixels": side_size, "front_pixels": front_size}

func build(walkable: Dictionary, cell_size: int, settings: Dictionary) -> void:
	tile_size = cell_size
	wall_height = int(settings.get("height_pixels", 56))
	cap_size = int(settings.get("cap_pixels", 4))
	side_size = int(settings.get("side_pixels", 6))
	front_size = int(settings.get("front_pixels", 5))
	cells = walkable
	north_edges.clear()
	south_edges.clear()
	west_edges.clear()
	east_edges.clear()
	conflicts.clear()
	for cell: Vector2i in cells:
		if not cells.has(cell + Vector2i.UP):
			north_edges.append(cell)
			for depth in range(1, ceili(float(wall_height + cap_size) / tile_size) + 1):
				if cells.has(cell + Vector2i(0, -depth)):
					conflicts.append(cell)
					break
		if not cells.has(cell + Vector2i.DOWN):
			south_edges.append(cell)
		if not cells.has(cell + Vector2i.LEFT):
			west_edges.append(cell)
		if not cells.has(cell + Vector2i.RIGHT):
			east_edges.append(cell)
	queue_redraw()

func _draw() -> void:
	if flat_floor:
		for cell: Vector2i in cells:
			draw_rect(Rect2(Vector2(cell) * tile_size, Vector2.ONE * tile_size), Color("454f51"))
	# Short lateral and foreground rims remain outside the walking area.
	for cell: Vector2i in west_edges:
		var p := Vector2(cell) * tile_size
		draw_rect(Rect2(p + Vector2(-side_size, 0), Vector2(side_size, tile_size)), SIDE_COLOR)
		draw_line(p, p + Vector2(0, tile_size), CAP_COLOR, 2.0)
	for cell: Vector2i in east_edges:
		var p := Vector2(cell + Vector2i.RIGHT) * tile_size
		draw_rect(Rect2(p, Vector2(side_size, tile_size)), SIDE_COLOR)
		draw_line(p, p + Vector2(0, tile_size), CAP_COLOR, 2.0)
	for cell: Vector2i in south_edges:
		var p := Vector2(cell + Vector2i.DOWN) * tile_size
		draw_rect(Rect2(p, Vector2(tile_size, front_size)), FOOT_COLOR)
		draw_line(p, p + Vector2(tile_size, 0), Color("797967"), 2.0)
	# Draw all faces before caps so contiguous segments have no tile seams.
	for cell: Vector2i in north_edges:
		var p := Vector2(cell) * tile_size
		draw_rect(Rect2(p + Vector2(0, -wall_height), Vector2(tile_size, wall_height)), FACE_COLOR)
		draw_rect(Rect2(p + Vector2(0, -5), Vector2(tile_size, 5)), FOOT_COLOR)
	for cell: Vector2i in north_edges:
		var p := Vector2(cell) * tile_size
		draw_rect(Rect2(p + Vector2(0, -wall_height - cap_size), Vector2(tile_size, cap_size)), CAP_COLOR)
		if not north_edges.has(cell + Vector2i.LEFT):
			draw_rect(Rect2(p + Vector2(0, -wall_height), Vector2(3, wall_height)), SIDE_COLOR)
		if not north_edges.has(cell + Vector2i.RIGHT):
			draw_rect(Rect2(p + Vector2(tile_size - 3, -wall_height), Vector2(3, wall_height)), SIDE_COLOR)
		# End faces connect the raised cap down to the side rim at openings.
		if not cells.has(cell + Vector2i.LEFT):
			draw_rect(Rect2(p + Vector2(-side_size, -wall_height - cap_size), Vector2(side_size, wall_height + cap_size)), SIDE_COLOR)
			draw_line(p + Vector2(-side_size, -wall_height - cap_size), p + Vector2(0, -wall_height - cap_size), CAP_COLOR, 2.0)
		if not cells.has(cell + Vector2i.RIGHT):
			draw_rect(Rect2(p + Vector2(tile_size, -wall_height - cap_size), Vector2(side_size, wall_height + cap_size)), SIDE_COLOR)
			draw_line(p + Vector2(tile_size, -wall_height - cap_size), p + Vector2(tile_size + side_size, -wall_height - cap_size), CAP_COLOR, 2.0)
