extends SceneTree
## Explicit offline import. Saved TileMapLayer cells remain the runtime authority.
## godot --headless --path . --script tools/map/bake_rpg_maker_maps.gd --
##   --catalog=res://assets/map/rpg_maker/catalog.json
##   --output=res://src/levels/rpg_maker --tilesets=res://src/resources/tilesets/rpg_maker

const MAP_SCRIPT := "res://src/levels/rpg_maker/rpg_maker_map.gd"
const GROUND_Z: Array[int] = [-20, -19, -16, -15]
const CUSTOM_DATA: Dictionary = {
	"rpg_tile_id": TYPE_INT,
	"passage": TYPE_INT,
	"star": TYPE_BOOL,
}

var _catalog: Dictionary = {}
var _options: Dictionary = {}
var _definitions: Dictionary = {}
var _tiles: Dictionary = {}
var _resources: Dictionary = {}
var _shadow_tileset: TileSet
var _map_script: Script
var _tile_size: int = 48
var _saved_files: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--help" in OS.get_cmdline_user_args():
		print("Explicit RPG Maker map bake: --catalog=res://.../catalog.json --output=res://... --tilesets=res://... [--replace]")
		quit(0)
		return
	if not _read_options() or not _read_catalog() or not _validate_catalog():
		quit(1)
		return
	if not _preflight_outputs():
		quit(2)
		return
	for path: String in [str(_options.output), str(_options.tilesets)]:
		var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
		if error != OK:
			_error("Cannot create output directory %s: %s" % [path, error_string(error)])
			quit(1)
			return
	for definition: Dictionary in _catalog.tilesets:
		var tileset := _build_tileset(definition)
		var path := _tileset_path(int(definition.id))
		if not _save_resource(tileset, path):
			quit(1)
			return
		tileset.take_over_path(path)
		_resources[int(definition.id)] = tileset
	_shadow_tileset = _build_shadow_tileset()
	if not _save_resource(_shadow_tileset, _shadow_path()):
		quit(1)
		return
	_shadow_tileset.take_over_path(_shadow_path())
	for definition: Dictionary in _catalog.maps:
		if not _save_map(definition):
			quit(1)
			return
	print("RPG_MAKER_BAKE: saved %d editable maps and %d external TileSets (%d files)." % [
		_catalog.maps.size(), _catalog.tilesets.size() + 1, _saved_files.size()])
	quit(0)


func _read_options() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--replace":
			_options.replace = true
			continue
		var separator := argument.find("=")
		if separator < 0 or not argument.begins_with("--"):
			return _error("Unknown argument: %s. Use --help for explicit input/output options." % argument)
		var key := argument.substr(2, separator - 2)
		if key not in ["catalog", "output", "tilesets"] or _options.has(key):
			return _error("Unknown or duplicate argument: %s" % argument)
		_options[key] = argument.substr(separator + 1).trim_suffix("/")
	for key: String in ["catalog", "output", "tilesets"]:
		var path: String = _options.get(key, "")
		if not path.begins_with("res://") or path == "res:/" or path.simplify_path() != path:
			return _error("--%s must explicitly name a normalized res:// project path." % key)
	if not str(_options.catalog).ends_with(".json"):
		return _error("--catalog must point to a JSON file.")
	if _options.output == _options.tilesets:
		return _error("Scene and TileSet output directories must be separate.")
	return true


func _read_catalog() -> bool:
	if not FileAccess.file_exists(_options.catalog):
		return _error("Catalog does not exist: %s" % _options.catalog)
	var json := JSON.new()
	var error := json.parse(FileAccess.get_file_as_string(_options.catalog))
	if error != OK:
		return _error("Catalog JSON line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if not json.data is Dictionary:
		return _error("Catalog must contain an object.")
	_catalog = json.data
	return true


func _validate_catalog() -> bool:
	if not _integer(_catalog.get("tile_size"), 48, 48):
		return _error("Catalog tile_size must be 48 native pixels.")
	_tile_size = int(_catalog.tile_size)
	if not _catalog.get("tilesets") is Array or _catalog.tilesets.is_empty():
		return _error("Catalog must contain a nonempty tilesets array.")
	if not _catalog.get("maps") is Array or _catalog.maps.is_empty():
		return _error("Catalog must contain a nonempty maps array.")
	for definition: Variant in _catalog.tilesets:
		if not definition is Dictionary or not _validate_tileset(definition):
			return _error("Invalid tileset definition; no output was written.")
	var map_ids: Dictionary = {}
	for definition: Variant in _catalog.maps:
		if not definition is Dictionary or not _validate_map(definition):
			return _error("Invalid map definition; no output was written.")
		var map_id := int(definition.id)
		if map_ids.has(map_id):
			return _error("Duplicate map id %d." % map_id)
		map_ids[map_id] = true
	if not ResourceLoader.exists(MAP_SCRIPT):
		return _error("Missing map runtime script: %s" % MAP_SCRIPT)
	_map_script = load(MAP_SCRIPT) as Script
	if _map_script == null or not _map_script.can_instantiate():
		return _error("Map runtime script must parse successfully before baking.")
	var shadow_texture := load(_shadow_texture_path()) as Texture2D
	if shadow_texture == null or shadow_texture.get_size() != Vector2(_tile_size * 16, _tile_size):
		return _error("Shadow texture must contain 16 native-size masks in one row: %s" % _shadow_texture_path())
	return true


func _validate_tileset(definition: Dictionary) -> bool:
	if not _integer(definition.get("id"), 1, 65535):
		return _error("Tileset id must be a positive integer.")
	var tileset_id := int(definition.id)
	if _definitions.has(tileset_id):
		return _error("Duplicate tileset id %d." % tileset_id)
	if not definition.get("pages") is Array or not definition.get("tiles") is Array:
		return _error("Tileset %d requires pages and tiles arrays." % tileset_id)
	var pages: Dictionary = {}
	for page: Variant in definition.pages:
		if not page is Dictionary or not _integer(page.get("source_id"), 0, 65535):
			return _error("Tileset %d contains an invalid atlas page." % tileset_id)
		var source_id := int(page.source_id)
		if pages.has(source_id) or not page.get("texture") is String:
			return _error("Tileset %d has a duplicate page or missing texture." % tileset_id)
		var path := str(page.texture)
		if not path.begins_with("res://") or not ResourceLoader.exists(path):
			return _error("Missing imported atlas texture: %s" % path)
		var texture := load(path) as Texture2D
		if texture == null or texture.get_size() != Vector2(_tile_size * 32, _tile_size * 32):
			return _error("Atlas page must contain 32 by 32 native-size tiles: %s" % path)
		pages[source_id] = texture
	var entries: Dictionary = {}
	var occupied: Dictionary = {}
	for entry: Variant in definition.tiles:
		if not entry is Dictionary:
			return _error("Tileset %d contains a non-object tile." % tileset_id)
		for key: String in ["id", "source_id", "x", "y", "frames", "passage"]:
			if not _integer(entry.get(key), 0, 65535):
				return _error("Tileset %d has an invalid tile field: %s." % [tileset_id, key])
		var tile_id := int(entry.id)
		var source_id := int(entry.source_id)
		var frames := int(entry.frames)
		if entries.has(tile_id) or not pages.has(source_id) or not entry.get("star") is bool:
			return _error("Tileset %d has a duplicate tile, unknown page or invalid star flag." % tileset_id)
		if frames < 1 or int(entry.x) + frames > 32 or int(entry.y) >= 32 or int(entry.passage) > 15:
			return _error("Tileset %d tile %d has invalid frames, coordinates or passage bits." % [tileset_id, tile_id])
		for frame in range(frames):
			var coordinate := Vector3i(source_id, int(entry.x) + frame, int(entry.y))
			if occupied.has(coordinate):
				return _error("Tileset %d has overlapping atlas tile/animation regions." % tileset_id)
			occupied[coordinate] = true
		entries[tile_id] = entry
	_definitions[tileset_id] = definition
	_tiles[tileset_id] = entries
	return true


func _validate_map(definition: Dictionary) -> bool:
	for key: String in ["id", "width", "height", "tileset_id"]:
		if not _integer(definition.get(key), 1, 32767):
			return _error("Map requires a positive integer %s within TileMapLayer coordinate bounds." % key)
	if not definition.get("name") is String or not _tiles.has(int(definition.tileset_id)):
		return _error("Map %d needs a name and a known tileset_id." % int(definition.id))
	if not definition.get("layers") is Array or definition.layers.size() != 4:
		return _error("Map %d must have exactly four tile layers." % int(definition.id))
	for entries: Variant in definition.layers:
		if not _validate_cells(entries, definition, "tiles"):
			return false
	for key: String in ["shadows", "table_edges", "regions"]:
		if not _validate_cells(definition.get(key), definition, key):
			return false
	var spawn: Variant = definition.get("spawn")
	if not spawn is Array or spawn.size() != 2:
		return _error("Map %d requires a spawn cell [x, y]." % int(definition.id))
	if not _integer(spawn[0], 0, int(definition.width) - 1) or not _integer(spawn[1], 0, int(definition.height) - 1):
		return _error("Map %d spawn lies outside the map." % int(definition.id))
	return true


func _validate_cells(entries: Variant, definition: Dictionary, kind: String) -> bool:
	if not entries is Array:
		return _error("Map %d %s must be an array." % [int(definition.id), kind])
	var occupied: Dictionary = {}
	var tiles: Dictionary = _tiles[int(definition.tileset_id)]
	for entry: Variant in entries:
		if not entry is Array or entry.size() != 3:
			return _error("Map %d %s entries must be [x, y, value]." % [int(definition.id), kind])
		if not _integer(entry[0], 0, int(definition.width) - 1) or not _integer(entry[1], 0, int(definition.height) - 1) or not _integer(entry[2], 0, 65535):
			return _error("Map %d %s contains invalid cell coordinates or value." % [int(definition.id), kind])
		var cell := Vector2i(int(entry[0]), int(entry[1]))
		var value := int(entry[2])
		if occupied.has(cell):
			return _error("Map %d %s contains duplicate cell %s." % [int(definition.id), kind, cell])
		occupied[cell] = true
		if kind in ["tiles", "table_edges"] and not tiles.has(value):
			return _error("Map %d references missing tile %d." % [int(definition.id), value])
		if kind == "table_edges" and not bool(tiles[value].get("edge", false)):
			return _error("Map %d table edge %d lacks its edge flag." % [int(definition.id), value])
		if (kind == "shadows" and value > 15) or (kind == "regions" and value > 255):
			return _error("Map %d %s value is out of range." % [int(definition.id), kind])
	return true


func _preflight_outputs() -> bool:
	var paths: Array[String] = [_shadow_path()]
	for definition: Dictionary in _catalog.tilesets:
		paths.append(_tileset_path(int(definition.id)))
	for definition: Dictionary in _catalog.maps:
		paths.append(_map_path(int(definition.id)))
	for path: String in paths:
		if DirAccess.dir_exists_absolute(path):
			return _error("An output file path is already a directory: %s" % path)
		if FileAccess.file_exists(path) and not _options.get("replace", false):
			return _error("Saved output exists: %s. Use --replace only to intentionally overwrite editor changes." % path)
	print("RPG_MAKER_BAKE: input %s; scenes %s; TileSets %s; replace=%s" % [
		_options.catalog, _options.output, _options.tilesets, _options.get("replace", false)])
	return true


func _build_tileset(definition: Dictionary) -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(_tile_size, _tile_size)
	tileset.resource_name = "RPG Maker Tileset %03d" % int(definition.id)
	for key: String in CUSTOM_DATA:
		var index := tileset.get_custom_data_layers_count()
		tileset.add_custom_data_layer()
		tileset.set_custom_data_layer_name(index, key)
		tileset.set_custom_data_layer_type(index, CUSTOM_DATA[key])
	for page: Dictionary in definition.pages:
		var source := TileSetAtlasSource.new()
		source.texture = load(page.texture)
		source.texture_region_size = Vector2i(_tile_size, _tile_size)
		source.use_texture_padding = true
		tileset.add_source(source, int(page.source_id))
	for entry: Dictionary in definition.tiles:
		var source := tileset.get_source(int(entry.source_id)) as TileSetAtlasSource
		var coordinate := Vector2i(int(entry.x), int(entry.y))
		source.create_tile(coordinate)
		var frames := int(entry.frames)
		if frames > 1:
			source.set_tile_animation_columns(coordinate, frames)
			source.set_tile_animation_separation(coordinate, Vector2i.ZERO)
			source.set_tile_animation_frames_count(coordinate, frames)
			source.set_tile_animation_speed(coordinate, 2.0)
			for frame in range(frames):
				source.set_tile_animation_frame_duration(coordinate, frame, 1.0)
		var data := source.get_tile_data(coordinate, 0)
		data.set_custom_data("rpg_tile_id", int(entry.id))
		data.set_custom_data("passage", int(entry.passage))
		data.set_custom_data("star", bool(entry.star))
	return tileset


func _build_shadow_tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(_tile_size, _tile_size)
	tileset.resource_name = "RPG Maker Quarter Shadows"
	var source := TileSetAtlasSource.new()
	source.texture = load(_shadow_texture_path())
	source.texture_region_size = Vector2i(_tile_size, _tile_size)
	source.use_texture_padding = true
	for mask in range(16):
		source.create_tile(Vector2i(mask, 0))
	tileset.add_source(source, 0)
	return tileset


func _save_map(definition: Dictionary) -> bool:
	var map := Node2D.new()
	map.name = "RpgMakerMap%03d" % int(definition.id)
	map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map.set_script(_map_script)
	map.set("map_id", int(definition.id))
	map.set("map_title", str(definition.name))
	map.set("map_size", Vector2i(int(definition.width), int(definition.height)))
	map.set("tile_size", _tile_size)
	map.set_meta("source_tileset_id", int(definition.tileset_id))
	var regions: Dictionary = {}
	for entry: Array in definition.regions:
		regions[Vector2i(int(entry[0]), int(entry[1]))] = int(entry[2])
	map.set_meta("regions", regions)
	var tileset: TileSet = _resources[int(definition.tileset_id)]
	var tiles: Dictionary = _tiles[int(definition.tileset_id)]
	for layer_index in range(4):
		var ground := _layer(map, "Ground%d" % layer_index, GROUND_Z[layer_index], tileset)
		var upper := _layer(map, "Upper%d" % layer_index, 10 + layer_index, tileset)
		for entry: Array in definition.layers[layer_index]:
			var tile: Dictionary = tiles[int(entry[2])]
			var layer := upper if bool(tile.star) else ground
			_set_cell(layer, entry, tile)
	var shadows := _layer(map, "Shadows", -18, _shadow_tileset)
	for entry: Array in definition.shadows:
		if int(entry[2]) != 0:
			shadows.set_cell(Vector2i(int(entry[0]), int(entry[1])), 0, Vector2i(int(entry[2]), 0))
	var table_edges := _layer(map, "TableEdges", -17, tileset)
	for entry: Array in definition.table_edges:
		_set_cell(table_edges, entry, tiles[int(entry[2])])
	var spawn := Marker2D.new()
	spawn.name = "Spawn"
	spawn.position = (Vector2(float(definition.spawn[0]), float(definition.spawn[1])) + Vector2(0.5, 0.5)) * _tile_size
	map.add_child(spawn)
	spawn.owner = map
	var packed := PackedScene.new()
	var error := packed.pack(map)
	map.free()
	if error != OK:
		return _error("Cannot pack map %d: %s" % [int(definition.id), error_string(error)])
	return _save_resource(packed, _map_path(int(definition.id)))


func _layer(map: Node2D, layer_name: String, order: int, tileset: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.z_index = order
	layer.tile_set = tileset
	layer.collision_enabled = false
	layer.navigation_enabled = false
	map.add_child(layer)
	layer.owner = map
	return layer


func _set_cell(layer: TileMapLayer, entry: Array, tile: Dictionary) -> void:
	layer.set_cell(Vector2i(int(entry[0]), int(entry[1])), int(tile.source_id), Vector2i(int(tile.x), int(tile.y)))


func _save_resource(resource: Resource, path: String) -> bool:
	var existing_uid := ""
	var uid_pattern := RegEx.create_from_string('uid="(uid://[^"]+)"')
	if FileAccess.file_exists(path):
		var input := FileAccess.open(path, FileAccess.READ)
		if input == null:
			return _error("Cannot read existing resource UID: " + path)
		var uid_match := uid_pattern.search(input.get_line())
		if uid_match != null:
			existing_uid = uid_match.get_string(1)
		input.close()
	var error := ResourceSaver.save(resource, path, ResourceSaver.FLAG_CHANGE_PATH)
	if error != OK:
		return _error("Cannot save %s: %s. Files already saved: %s" % [path, error_string(error), _saved_files])
	if not existing_uid.is_empty():
		# ResourceSaver.set_uid does not persist text headers in command-line
		# runtime mode. Preserve the existing editor UID in the saved text itself.
		var saved := FileAccess.get_file_as_string(path)
		var newline := saved.find("\n")
		if newline < 0:
			return _error("Saved resource has no text header: " + path)
		var header := saved.left(newline)
		if uid_pattern.search(header) != null:
			header = uid_pattern.sub(header, 'uid="%s"' % existing_uid)
		else:
			header = header.trim_suffix("]") + ' uid="%s"]' % existing_uid
		var output := FileAccess.open(path, FileAccess.WRITE)
		if output == null:
			return _error("Cannot preserve existing resource UID: " + path)
		output.store_string(header + saved.substr(newline))
		output.close()
	_saved_files.append(path)
	return true


func _tileset_path(tileset_id: int) -> String:
	return str(_options.tilesets).path_join("tileset_%03d.tres" % tileset_id)


func _map_path(map_id: int) -> String:
	return str(_options.output).path_join("map_%03d.tscn" % map_id)


func _shadow_path() -> String:
	return str(_options.tilesets).path_join("shadows.tres")


func _shadow_texture_path() -> String:
	return str(_options.catalog).get_base_dir().path_join("shadow_tiles.png")


func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	if not value is int and not value is float:
		return false
	return is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum


func _error(message: String) -> bool:
	push_error("RPG_MAKER_BAKE: " + message)
	return false
