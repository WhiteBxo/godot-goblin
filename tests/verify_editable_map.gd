extends SceneTree

const MAP_PATH := "res://src/levels/cave/cave_map.tscn"
const OUTPUT_PATH := "res://.godot/editable_map_verification/edited_roundtrip.tscn"
const GRID := preload("res://src/resources/tilesets/cave_grid.gd")

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_verify")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

func _settle() -> void:
	for frame in range(4):
		await process_frame

func _verify() -> void:
	var map: CaveMap = load(MAP_PATH).instantiate()
	var floor: TileMapLayer = map.get_node("FloorLayer")
	var river: TileMapLayer = map.get_node("RiverLayer")
	var current_layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/levels/cave/cave_layout.json"))
	var expected_cells := cells_from_layout(current_layout)
	var expected_rivers := rivers_from_layout(current_layout, expected_cells)
	check(floor.get_used_cells().size() == expected_cells.size(), "Ground cell count matches current layout")
	check(cells_from_layer(floor) == expected_cells, "Saved scene ground matches current layout coordinates")
	check(cells_from_layer(river) == expected_rivers, "Saved river matches current layout coverage")
	check(map.get_node("BorderLayer").get_used_cells().size() > 0, "Outside edges are saved for editor display")
	check(floor.position == Vector2.ZERO, "Ground uses the same grid as gameplay")
	check(floor.tile_set.get_terrain_sets_count() == 1 and floor.tile_set.get_terrain_name(0, 0) == "StoneFloor", "Ground supports the standard terrain brush")
	var erased := Vector2i(63, 75)
	var added := Vector2i(200, 200)
	check(floor.get_cell_source_id(erased) == 0, "Regression hole starts on existing ground")
	floor.erase_cell(erased)
	floor.set_cell(added, 0, Vector2i(15, 15))
	river.erase_cell(Vector2i(5, 4))
	river.set_cell(added, 0, Vector2i.ZERO)
	root.add_child(map)
	await _settle()
	check(map.load_error == OK, "Edited scene initializes without JSON import")
	check(map.layout_data.is_empty(), "Normal startup does not read archived layout data")
	check(floor.get_cell_source_id(erased) == -1 and not map.walkable_cells.has(erased), "Startup preserves erased ground and removes its walkability")
	check(floor.get_cell_source_id(added) == 0 and map.walkable_cells.has(added), "Startup preserves painted ground and grants walkability")
	check(map.can_stand_at(map.cell_to_world(Vector2(added) + Vector2.ONE * 0.5), Vector2(7, 6)), "Player can stand on painted ground")
	check(not map.can_stand_at(map.cell_to_world(Vector2(erased) + Vector2.ONE * 0.5), Vector2(7, 6)), "Player cannot stand in an erased hole")
	check(river.get_cell_source_id(Vector2i(5, 4)) == -1 and river.get_cell_source_id(added) == 0, "Startup preserves hand-painted river changes")
	check(map.walls.north_edges.has(added), "Walls follow painted ground")
	check(map.get_world_bounds().has_point(map.cell_to_world(Vector2(added) + Vector2.ONE * 0.5)), "Camera bounds include painted ground")
	check(floor.get_cell_atlas_coords(added) == Vector2i.ZERO, "Ground automatically picks the isolated-cell variant")
	check(map.border_layer.get_cell_source_id(added + Vector2i.LEFT) == 0, "Outside edges follow painted ground")
	# Runtime tools refresh explicitly; editor painting is verified through MCP in editor mode.
	var extension := added + Vector2i.RIGHT
	floor.set_cell(extension, 0, Vector2i(15, 15))
	map.refresh_from_tiles()
	await _settle()
	check(map.walkable_cells.has(extension), "Explicit refresh updates runtime walkability")
	check(not map.walls.east_edges.has(added), "Adjacent painting removes the shared wall")
	check(map.border_layer.get_cell_source_id(extension) == -1, "Painting removes obsolete outside-edge decoration")
	floor.erase_cell(extension)
	map.refresh_from_tiles()
	await _settle()
	check(not map.walkable_cells.has(extension) and map.walls.east_edges.has(added), "Erasing restores the boundary wall")
	var before_cells := floor.tile_map_data
	var before_river := river.tile_map_data
	check(map.load_layout("res://missing_cave_layout.json") == ERR_FILE_NOT_FOUND, "Explicit import rejects a missing file")
	check(floor.tile_map_data == before_cells and river.tile_map_data == before_river, "Failed import preserves hand-edited cells")
	DirAccess.make_dir_recursive_absolute("res://.godot/editable_map_verification")
	var packed := PackedScene.new()
	check(packed.pack(map) == OK and ResourceSaver.save(packed, OUTPUT_PATH) == OK, "Edited map can be saved as a scene")
	var reopened: CaveMap = ResourceLoader.load(OUTPUT_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(reopened.get_node("FloorLayer").get_cell_source_id(added) == 0, "Saved ground survives reopening before startup")
	root.add_child(reopened)
	await _settle()
	check(not reopened.walkable_cells.has(erased) and reopened.walkable_cells.has(added), "Saved walkability survives reopening and startup")
	check(reopened.river_layer.get_cell_source_id(added) == 0, "Saved river survives reopening and startup")
	var original_layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/levels/cave/cave_layout_original.json"))
	var original_cells := cells_from_layout(original_layout)
	check(reopened.load_layout("res://src/levels/cave/cave_layout_original.json") == OK and reopened.walkable_cells == original_cells, "Legacy layout remains available through explicit import")
	map.queue_free()
	reopened.queue_free()
	await _settle()
	print("Editable map: %d checks; %d failures" % [checks, failures.size()])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func cells_from_layout(layout: Dictionary) -> Dictionary:
	var cells: Dictionary = {}
	for room: Dictionary in layout.rooms:
		add_rect(cells, [room.x, room.y, room.w, room.h])
	for corridor: Array in layout.corridors:
		add_rect(cells, corridor)
	return cells

func rivers_from_layout(layout: Dictionary, cells: Dictionary) -> Dictionary:
	var rivers: Dictionary = {}
	for river_rect: Array in layout.rivers:
		for y in range(int(river_rect[1]), int(river_rect[1] + river_rect[3])):
			for x in range(int(river_rect[0]), int(river_rect[0] + river_rect[2])):
				var cell := Vector2i(x, y)
				if cells.has(cell):
					rivers[cell] = true
	return rivers

func cells_from_layer(layer: TileMapLayer) -> Dictionary:
	var cells: Dictionary = {}
	for cell: Vector2i in layer.get_used_cells():
		cells[cell] = true
	return cells

func add_rect(cells: Dictionary, rect: Array) -> void:
	for y in range(int(rect[1]), int(rect[1] + rect[3])):
		for x in range(int(rect[0]), int(rect[0] + rect[2])):
			cells[Vector2i(x, y)] = true
