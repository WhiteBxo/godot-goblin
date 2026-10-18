extends SceneTree
## Synchronize derived table edges from saved cells without reimporting source JSON.
## --input=res://.../map_004.tscn --output=res://.../edited_map.tscn [--replace]

const EDGE_ID_OFFSET := 10000

var _options: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--help" in OS.get_cmdline_user_args():
		print("Sync saved table edges: --input=res://...tscn --output=res://...tscn [--replace]")
		quit(0)
		return
	if not _read_options():
		quit(2)
		return
	var source := load(str(_options.input)) as PackedScene
	if source == null:
		_fail("Input must be a loadable PackedScene.")
		return
	# Do not enter the scene tree: runtime collision and gameplay must not run.
	var map := source.instantiate()
	if not _sync_edges(map):
		map.free()
		quit(1)
		return
	var packed := PackedScene.new()
	var error := packed.pack(map)
	map.free()
	if error != OK:
		_fail("Cannot pack updated map: %s" % error_string(error))
		return
	var output := str(_options.output)
	var existing_uid := _read_uid(output)
	error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	if error != OK:
		_fail("Cannot create output directory: %s" % error_string(error))
		return
	error = ResourceSaver.save(packed, output)
	if error != OK:
		_fail("Cannot save %s: %s" % [output, error_string(error)])
		return
	if existing_uid != ResourceUID.INVALID_ID:
		if not _preserve_uid(output, existing_uid):
			_fail("Map saved, but could not preserve its UID.")
			return
	print("RPG_MAKER_TABLE_EDGES: saved %s; source cells, metadata and Spawn preserved." % output)
	quit(0)


func _read_options() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--replace":
			_options.replace = true
			continue
		var separator := argument.find("=")
		if separator < 0 or not argument.begins_with("--"):
			return _error("Unknown argument: %s" % argument)
		var key := argument.substr(2, separator - 2)
		if key not in ["input", "output"] or _options.has(key):
			return _error("Unknown or duplicate argument: %s" % argument)
		_options[key] = argument.substr(separator + 1)
	for key: String in ["input", "output"]:
		var path: String = _options.get(key, "")
		if not path.begins_with("res://") or not path.ends_with(".tscn") or path.simplify_path() != path:
			return _error("--%s must explicitly name a normalized res:// scene path ending in .tscn." % key)
	if not FileAccess.file_exists(_options.input):
		return _error("Input scene does not exist: %s" % _options.input)
	if FileAccess.file_exists(_options.output) and not _options.get("replace", false):
		return _error("Output exists: %s. Explicit --replace is required to overwrite a saved scene." % _options.output)
	if DirAccess.dir_exists_absolute(_options.output):
		return _error("Output path is a directory: %s" % _options.output)
	return true


func _sync_edges(map: Node) -> bool:
	var size: Variant = map.get("map_size")
	if not size is Vector2i or size.x < 1 or size.y < 1:
		return _error("Input map must declare a positive Vector2i map_size.")
	var layers: Dictionary = {}
	for layer_name: String in ["Ground0", "Upper0", "Ground1", "Upper1", "TableEdges"]:
		var layer := map.get_node_or_null(NodePath(layer_name)) as TileMapLayer
		if layer == null or layer.tile_set == null or layer.tile_set.get_custom_data_layer_by_name("rpg_tile_id") < 0:
			return _error("Map requires %s with RPG Maker tile ID custom data." % layer_name)
		layers[layer_name] = layer
	var edges: TileMapLayer = layers.TableEdges
	var lookup := _edge_lookup(edges.tile_set)
	var cells: Dictionary = {}
	# Validate before clearing the derived layer. A source layer holds one tile
	# per coordinate, split between Ground and Upper by the original star flag.
	for y in range(size.y):
		for x in range(size.x):
			var cell := Vector2i(x, y)
			for original_layer in range(2):
				var ground: TileMapLayer = layers["Ground%d" % original_layer]
				var upper: TileMapLayer = layers["Upper%d" % original_layer]
				if ground.get_cell_source_id(cell) != -1 and upper.get_cell_source_id(cell) != -1:
					return _error("Original layer %d has both Ground and Upper tiles at %s; keep only one before syncing." % [original_layer, cell])
			if y == 0:
				continue
			var above := _original_tile_id(layers.Ground1, layers.Upper1, cell + Vector2i.UP)
			var current := _original_tile_id(layers.Ground1, layers.Upper1, cell)
			var base := _original_tile_id(layers.Ground0, layers.Upper0, cell)
			if lookup.has(above) and not lookup.has(current) and not (base >= 4352 and base < 8192):
				cells[cell] = lookup[above]
	edges.clear()
	for cell: Vector2i in cells:
		var tile: Array = cells[cell]
		edges.set_cell(cell, int(tile[0]), tile[1], int(tile[2]))
	print("RPG_MAKER_TABLE_EDGES: rebuilt %d table edges from saved tiles." % cells.size())
	return true


func _edge_lookup(tileset: TileSet) -> Dictionary:
	var result: Dictionary = {}
	for source_index in range(tileset.get_source_count()):
		var source_id := tileset.get_source_id(source_index)
		var atlas := tileset.get_source(source_id) as TileSetAtlasSource
		if atlas == null:
			continue
		for index in range(atlas.get_tiles_count()):
			var coordinate := atlas.get_tile_id(index)
			var data := atlas.get_tile_data(coordinate, 0)
			var tile_id := int(data.get_custom_data("rpg_tile_id"))
			if tile_id >= EDGE_ID_OFFSET:
				result[tile_id - EDGE_ID_OFFSET] = [source_id, coordinate, 0]
	return result


func _original_tile_id(ground: TileMapLayer, upper: TileMapLayer, cell: Vector2i) -> int:
	var data := ground.get_cell_tile_data(cell)
	if data == null:
		data = upper.get_cell_tile_data(cell)
	return int(data.get_custom_data("rpg_tile_id")) if data != null else 0


func _read_uid(path: String) -> int:
	if not FileAccess.file_exists(path):
		return ResourceUID.INVALID_ID
	var pattern := RegEx.new()
	if pattern.compile(' uid="([^"]+)"') != OK:
		return ResourceUID.INVALID_ID
	var found := pattern.search(FileAccess.get_file_as_string(path).get_slice("\n", 0))
	return ResourceUID.text_to_id(found.get_string(1)) if found != null else ResourceUID.INVALID_ID


func _preserve_uid(path: String, uid: int) -> bool:
	# ResourceSaver's runtime path omits UID serialization, even when set_uid()
	# returns OK. Preserve the existing text scene header explicitly offline.
	var text := FileAccess.get_file_as_string(path)
	var line_end := text.find("\n")
	if line_end < 0 or not text.begins_with("[gd_scene "):
		return false
	var header := text.substr(0, line_end)
	var pattern := RegEx.new()
	if pattern.compile(' uid="[^"]+"') != OK:
		return false
	header = pattern.sub(header, "", true).trim_suffix("]")
	header += ' uid="%s"]' % ResourceUID.id_to_text(uid)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(header + text.substr(line_end))
	file.close()
	return FileAccess.get_file_as_string(path).get_slice("\n", 0) == header


func _error(message: String) -> bool:
	push_error("RPG_MAKER_TABLE_EDGES: " + message)
	return false


func _fail(message: String) -> void:
	_error(message)
	quit(1)
