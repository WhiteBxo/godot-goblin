extends SceneTree
## Explicitly add the generated casino art to the existing palette, never repaint maps.

const TILESET_PATH := "res://src/resources/tilesets/rpg_maker/tileset_028.tres"
const ART_PATH := "res://assets/map/rpg_maker/casino_refresh/"
const FIRST_SOURCE := 100
const FIRST_TILE := 30000


func _initialize() -> void:
	var tiles := load(TILESET_PATH) as TileSet
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ART_PATH + "manifest.json"))
	if tiles == null or manifest.get("assets", []).size() != 13:
		push_error("Expected the existing TileSet and 13 casino sprites.")
		quit(1)
		return
	# Preflight all occupied IDs before changing the resource.
	for index in range(manifest.assets.size()):
		if tiles.has_source(FIRST_SOURCE + index):
			push_error("Casino source ID already exists; refusing to overwrite palette edits.")
			quit(1)
			return
	for index in range(manifest.assets.size()):
		var item: Dictionary = manifest.assets[index]
		var source := TileSetAtlasSource.new()
		source.resource_name = "赌场 · " + str(item.label)
		source.texture = load(ART_PATH + str(item.path))
		source.texture_region_size = Vector2i(48, 48)
		var source_id := FIRST_SOURCE + index
		tiles.add_source(source, source_id)
		var pattern := TileMapPattern.new()
		pattern.resource_name = str(item.label)
		var columns := int(item.dimensions_px[0]) / 48
		var rows := int(item.dimensions_px[1]) / 48
		for y in range(rows):
			for x in range(columns):
				var coordinate := Vector2i(x, y)
				source.create_tile(coordinate)
				var data := source.get_tile_data(coordinate, 0)
				# The first row of both table canvases is transparent padding.
				var solid: bool = item.id == "round_stool" or (item.id in ["gambling_table", "boss_desk"] and y > 0)
				data.set_custom_data("rpg_tile_id", FIRST_TILE + index * 16 + y * columns + x)
				data.set_custom_data("passage", 15 if solid else 0)
				data.set_custom_data("star", not solid)
				pattern.set_cell(coordinate, source_id, coordinate, 0)
		tiles.add_pattern(pattern)
	var error := ResourceSaver.save(tiles, TILESET_PATH)
	if error != OK:
		push_error("Could not save casino TileSet: " + str(error))
		quit(1)
		return
	print("Added 13 casino atlas sources and complete-object patterns; map scenes untouched.")
	quit()
