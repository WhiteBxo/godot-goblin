extends SceneTree
## Check editor brush stamping and the RPG directional-passage contract.

const MAP_SCRIPT := preload("res://src/levels/rpg_maker/rpg_maker_map.gd")
const TILESET_PATH := "res://src/resources/tilesets/rpg_maker/tileset_028.tres"
const ART := "res://assets/map/rpg_maker/casino_refresh/"
var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)


func _run() -> void:
	var tiles := load(TILESET_PATH) as TileSet
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ART + "manifest.json"))
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map/rpg_maker/catalog.json"))
	_check(tiles.tile_size == Vector2i(48, 48), "The palette must retain native 48px cells")
	var open_tile: Dictionary = {}
	var blocked_tile: Dictionary = {}
	for definition: Dictionary in catalog.tilesets:
		if int(definition.id) != 28:
			continue
		for tile: Dictionary in definition.tiles:
			var source := tiles.get_source(int(tile.source_id)) as TileSetAtlasSource
			var coordinate := Vector2i(int(tile.x), int(tile.y))
			var data := source.get_tile_data(coordinate, 0)
			_check(int(data.get_custom_data("rpg_tile_id")) == int(tile.id)
				and int(data.get_custom_data("passage")) == int(tile.passage)
				and bool(data.get_custom_data("star")) == bool(tile.star)
				and source.get_tile_animation_frames_count(coordinate) == int(tile.frames),
				"Original tile metadata changed: " + str(tile.id))
			if not tile.star and int(tile.passage) == 0:
				open_tile = tile
			if not tile.star and int(tile.passage) == 15:
				blocked_tile = tile
	_check(not open_tile.is_empty() and not blocked_tile.is_empty(), "Fixture needs open and solid base tiles")
	var fixture: Node2D = MAP_SCRIPT.new()
	fixture.map_size = Vector2i(12, 10)
	for index in range(4):
		var layer := TileMapLayer.new()
		layer.name = "Ground%d" % index
		layer.tile_set = tiles
		fixture.add_child(layer)
	var ground: TileMapLayer = fixture.get_node("Ground0")
	var props: TileMapLayer = fixture.get_node("Ground1")
	for y in range(10):
		for x in range(12):
			ground.set_cell(Vector2i(x, y), int(open_tile.source_id), Vector2i(int(open_tile.x), int(open_tile.y)))
	root.add_child(fixture)
	var origin := Vector2i(4, 4)
	var found_patterns := 0
	for index in range(manifest.assets.size()):
		var item: Dictionary = manifest.assets[index]
		var source_id := 100 + index
		_check(tiles.has_source(source_id), "Missing casino palette source: " + str(item.id))
		var source := tiles.get_source(source_id) as TileSetAtlasSource
		var dimensions := Vector2i(int(item.dimensions_px[0]) / 48, int(item.dimensions_px[1]) / 48)
		_check(source.texture.resource_path == ART + str(item.path)
			and source.texture_region_size == Vector2i(48, 48), "Wrong sprite reference or region size")
		var pattern: TileMapPattern
		for pattern_index in range(tiles.get_patterns_count()):
			var candidate := tiles.get_pattern(pattern_index)
			if candidate.get_cell_source_id(Vector2i.ZERO) == source_id:
				pattern = candidate
				break
		_check(pattern != null, "Missing complete-object brush: " + str(item.id))
		if pattern == null:
			continue
		found_patterns += 1
		_check(pattern.get_size() == dimensions, "Brush dimensions differ from sprite canvas")
		props.clear()
		props.set_pattern(origin, pattern)
		fixture.rebuild_passability()
		_check(props.get_used_cells().size() == dimensions.x * dimensions.y, "Incomplete brush stamp")
		for coordinate: Vector2i in pattern.get_used_cells():
			var cell := origin + coordinate
			_check(props.get_cell_atlas_coords(cell) == coordinate
				and props.get_cell_source_id(cell) == source_id, "Stamp changed atlas coordinates")
			var solid: bool = item.id == "round_stool" or (item.id in ["gambling_table", "boss_desk"] and coordinate.y > 0)
			_check(fixture.get_cell_direction_mask(cell) == (0 if solid else 15), "Unexpected stamped passage: " + str(item.id))
		# Decoration must preserve a solid floor below, not accidentally open it.
		if item.id not in ["gambling_table", "boss_desk", "round_stool"]:
			ground.set_cell(origin, int(blocked_tile.source_id), Vector2i(int(blocked_tile.x), int(blocked_tile.y)))
			fixture.rebuild_passability()
			_check(fixture.get_cell_direction_mask(origin) == 0, "Decoration opened a blocked base cell")
			ground.set_cell(origin, int(open_tile.source_id), Vector2i(int(open_tile.x), int(open_tile.y)))
	_check(found_patterns == 13, "Expected 13 usable complete-object brushes")
	fixture.free()
	print("CASINO_TILES: %d checks; %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
