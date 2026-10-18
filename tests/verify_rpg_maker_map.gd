extends SceneTree
## Saved source fidelity, edit persistence, directional passages and real player motion.

const MAP_RUNTIME := preload("res://src/levels/rpg_maker/rpg_maker_map.gd")
const PLAYER_SCENE := preload("res://src/gameplay/player/rpg_player.tscn")
const CATALOG := "res://assets/map/rpg_maker/catalog.json"
const ROUNDTRIP := "res://.godot/rpg_maker_verification/edited_map.tscn"

var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)

func _settle(frames: int = 3) -> void:
	for frame in range(frames):
		await physics_frame

func _run() -> void:
	var probe := root.get_node_or_null("MCPRuntimeProbe")
	if probe != null:
		probe.process_mode = Node.PROCESS_MODE_DISABLED
	await _verify_directional_fixture()
	if "--fixture-only" not in OS.get_cmdline_user_args():
		await _verify_saved_maps()
		await _verify_preview()
	print("RPG_MAKER_MAP: %d checks; %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _make_fixture() -> Node2D:
	var map: Node2D = MAP_RUNTIME.new()
	map.name = "DirectionalFixture"
	map.map_size = Vector2i(5, 4)
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(48, 48)
	for layer in [["rpg_tile_id", TYPE_INT], ["passage", TYPE_INT], ["star", TYPE_BOOL]]:
		tiles.add_custom_data_layer()
		var index := tiles.get_custom_data_layers_count() - 1
		tiles.set_custom_data_layer_name(index, layer[0])
		tiles.set_custom_data_layer_type(index, layer[1])
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(Image.create_empty(240, 48, false, Image.FORMAT_RGBA8))
	atlas.texture_region_size = Vector2i(48, 48)
	tiles.add_source(atlas, 0)
	# Open, right blocked, solid, transparent B0, and star-overlaid solid flags.
	for index in range(5):
		var coords := Vector2i(index, 0)
		atlas.create_tile(coords)
		var data := atlas.get_tile_data(coords, 0)
		data.set_custom_data("rpg_tile_id", [2048, 2049, 2050, 0, 7][index])
		data.set_custom_data("passage", [0, 4, 15, 0, 15][index])
		data.set_custom_data("star", index == 4)
	for index in range(4):
		var ground := TileMapLayer.new()
		ground.name = "Ground%d" % index
		ground.tile_set = tiles
		map.add_child(ground)
		ground.owner = map
	var floor_layer: TileMapLayer = map.get_node("Ground0")
	for y in range(4):
		for x in range(5):
			floor_layer.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	floor_layer.set_cell(Vector2i(3, 1), 0, Vector2i(2, 0))
	map.get_node("Ground2").set_cell(Vector2i(1, 1), 0, Vector2i(1, 0))
	map.get_node("Ground3").set_cell(Vector2i(1, 1), 0, Vector2i(3, 0))
	map.get_node("Ground3").set_cell(Vector2i(2, 1), 0, Vector2i(4, 0))
	var spawn := Marker2D.new()
	spawn.name = "Spawn"
	spawn.position = Vector2(72, 72)
	map.add_child(spawn)
	spawn.owner = map
	return map

func _verify_directional_fixture() -> void:
	var map := _make_fixture()
	root.add_child(map)
	await _settle()
	_check(map.get_cell_direction_mask(Vector2i(1, 1)) == 11, "Transparent B0 must reveal the directional tile below")
	_check(map.get_cell_direction_mask(Vector2i(2, 1)) == 15, "Star tile must not override the floor's passage")
	_check(map.can_stand_at(Vector2(72, 72), Vector2(17, 10)), "A partial directional tile must remain occupiable")
	_check(not map.can_stand_at(Vector2(168, 72), Vector2(17, 10)), "Four-direction blocked tile must reject the real footprint")
	_check(not map.can_cross_edge(Vector2i(1, 1), Vector2i.RIGHT), "Right-blocked tile rejects leaving through the right edge")
	_check(not map.can_cross_edge(Vector2i(2, 1), Vector2i.LEFT), "Neighbor destination passage also rejects entry through its right edge")
	_check(map.can_cross_edge(Vector2i(1, 1), Vector2i.DOWN), "Other edges of the same partial tile stay open")
	_check(not map.can_stand_at(Vector2(4, 72), Vector2(17, 10)), "Footprint cannot extend outside the map")
	var player := PLAYER_SCENE.instantiate() as FloorAwareShopPlayer
	root.add_child(player)
	player.set_floor_query(map.can_stand_at)
	player.configure_camera(map.get_camera_bounds())
	player.teleport_to(map.get_spawn_position())
	await _settle()
	await _move(&"move_right", 30)
	_check(absf(player.global_position.x - (96.0 - player.footprint_half_size.x)) < 1.0, "Real foot capsule stops at the partial tile's right boundary")
	player.teleport_to(Vector2(120, 72))
	await _move(&"move_left", 30)
	_check(absf(player.global_position.x - (96.0 + player.footprint_half_size.x)) < 1.0, "Physical boundary also blocks reverse entry")
	player.teleport_to(map.get_spawn_position())
	await _move(&"move_down", 50)
	_check(player.global_position.y > 130, "The real player can leave the same partial tile through an allowed edge: " + str(player.global_position))
	player.teleport_to(Vector2(24, 120))
	await _move(&"move_left", 30)
	_check(absf(player.global_position.x - player.footprint_half_size.x) < 1.0, "Real player remains inside the outer map boundary")
	var overlay: TileMapLayer = map.get_node("Ground2")
	overlay.erase_cell(Vector2i(1, 1))
	map.rebuild_passability()
	await _settle()
	_check(map.can_cross_edge(Vector2i(1, 1), Vector2i.RIGHT), "Erasing a directional tile and rebuilding removes its edge collision")
	player.teleport_to(map.get_spawn_position())
	await _move(&"move_right", 50)
	_check(player.global_position.x > 120, "Real movement crosses the edited boundary after rebuild")
	player.queue_free()
	map.queue_free()
	await _settle()

func _move(action: StringName, frames: int) -> void:
	Input.action_press(action)
	await _settle(frames)
	Input.action_release(action)
	await _settle(3)

func _verify_saved_maps() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	for definition: Dictionary in catalog.maps:
		var scene_path := "res://src/levels/rpg_maker/map_%03d.tscn" % int(definition.id)
		var packed := load(scene_path) as PackedScene
		_check(packed != null, "Saved map scene exists: " + scene_path)
		if packed == null:
			continue
		var map: Node2D = packed.instantiate()
		var shared_tiles: TileSet = map.get_node("Ground0").tile_set
		_check(shared_tiles.resource_path == "res://src/resources/tilesets/rpg_maker/tileset_%03d.tres" % int(definition.tileset_id)
			and map.get_node("Shadows").tile_set.resource_path == "res://src/resources/tilesets/rpg_maker/shadows.tres",
			"Map %d references shared external TileSets rather than embedded copies" % int(definition.id))
		var expected_tiles: Dictionary = {}
		for definition_tileset: Dictionary in catalog.tilesets:
			if int(definition_tileset.id) == int(definition.tileset_id):
				for tile: Dictionary in definition_tileset.tiles:
					expected_tiles[int(tile.id)] = tile
		var animation_matches := true
		for tile: Dictionary in expected_tiles.values():
			var atlas: TileSetAtlasSource = shared_tiles.get_source(int(tile.source_id))
			var coordinate := Vector2i(int(tile.x), int(tile.y))
			animation_matches = animation_matches and atlas.get_tile_animation_frames_count(coordinate) == int(tile.frames)
			if int(tile.frames) > 1:
				animation_matches = animation_matches and is_equal_approx(atlas.get_tile_animation_speed(coordinate), 2.0)
		_check(animation_matches, "Map %d palette preserves all native animation frame counts and speeds" % int(definition.id))
		var auxiliary_matches := true
		var shadows: TileMapLayer = map.get_node("Shadows")
		var edges: TileMapLayer = map.get_node("TableEdges")
		var regions: Dictionary = map.get_meta("regions")
		auxiliary_matches = shadows.get_used_cells().size() == definition.shadows.size() and edges.get_used_cells().size() == definition.table_edges.size() and regions.size() == definition.regions.size()
		for entry: Array in definition.shadows:
			auxiliary_matches = auxiliary_matches and shadows.get_cell_atlas_coords(Vector2i(entry[0], entry[1])) == Vector2i(entry[2], 0)
		for entry: Array in definition.table_edges:
			var data := edges.get_cell_tile_data(Vector2i(entry[0], entry[1]))
			auxiliary_matches = auxiliary_matches and data != null and int(data.get_custom_data("rpg_tile_id")) == int(entry[2])
		for entry: Array in definition.regions:
			auxiliary_matches = auxiliary_matches and regions.get(Vector2i(entry[0], entry[1]), -1) == int(entry[2])
		_check(auxiliary_matches, "Map %d preserves shadows, table edges and region IDs" % int(definition.id))
		var source_matches := true
		var before: Dictionary[String, PackedByteArray] = {}
		for index in range(4):
			var expected_count := 0
			for entry: Array in definition.layers[index]:
				var tile: Dictionary = expected_tiles[int(entry[2])]
				var prefix := "Upper" if bool(tile.star) else "Ground"
				var layer: TileMapLayer = map.get_node(prefix + str(index))
				var data := layer.get_cell_tile_data(Vector2i(entry[0], entry[1]))
				source_matches = source_matches and data != null
				if data != null:
					source_matches = source_matches and int(data.get_custom_data("rpg_tile_id")) == int(entry[2]) and int(data.get_custom_data("passage")) == int(tile.passage) and bool(data.get_custom_data("star")) == bool(tile.star)
				expected_count += 1
			var ground: TileMapLayer = map.get_node("Ground%d" % index)
			var upper: TileMapLayer = map.get_node("Upper%d" % index)
			source_matches = source_matches and ground.get_used_cells().size() + upper.get_used_cells().size() == expected_count
			before[str(ground.name)] = ground.tile_map_data
			before[str(upper.name)] = upper.tile_map_data
		_check(source_matches, "Every saved tile and star split matches source map %d" % int(definition.id))
		root.add_child(map)
		await _settle()
		var unchanged := true
		for layer_name: String in before:
			unchanged = unchanged and map.get_node(layer_name).tile_map_data == before[layer_name]
		_check(unchanged, "Runtime preserves all saved map %d cells" % int(definition.id))
		_check(map.can_stand_at(map.get_spawn_position(), Vector2(17, 10)), "Real player footprint fits map %d spawn" % int(definition.id))
		_check(map.get_camera_bounds().size == Vector2(definition.width, definition.height) * 48, "Map %d bounds preserve source dimensions" % int(definition.id))
		map.queue_free()
		await _settle()
	await _verify_edit_roundtrip()

func _verify_edit_roundtrip() -> void:
	var map: Node2D = load("res://src/levels/rpg_maker/map_001.tscn").instantiate()
	var erased: Vector2i = map.world_to_cell(map.get_spawn_position())
	for index in range(4):
		map.get_node("Ground%d" % index).erase_cell(erased)
		map.get_node("Upper%d" % index).erase_cell(erased)
	root.add_child(map)
	await _settle()
	_check(not map.is_cell_walkable(erased), "Startup preserves a source floor cell erased before initialization")
	DirAccess.make_dir_recursive_absolute(ROUNDTRIP.get_base_dir())
	var packed := PackedScene.new()
	_check(packed.pack(map) == OK and ResourceSaver.save(packed, ROUNDTRIP) == OK, "Edited static map can be saved independently")
	map.queue_free()
	await _settle()
	var reopened: Node2D = ResourceLoader.load(ROUNDTRIP, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	root.add_child(reopened)
	await _settle()
	_check(not reopened.is_cell_walkable(erased), "Erased floor survives save, reopen and runtime initialization")
	reopened.queue_free()
	await _settle()

func _verify_preview() -> void:
	var preview: Node = load("res://src/debug/rpg_maker/rpg_maker_preview.tscn").instantiate()
	root.add_child(preview)
	await _settle()
	var player: FloorAwareShopPlayer = preview.get_player()
	var camera_id := player.camera.get_instance_id()
	var player_id := player.get_instance_id()
	_check(player.scale == Vector2.ONE and player.speed == 120.0 and player.z_index == 0, "Preview uses the RPG player movement profile and lets star tiles cover it")
	_check(player.camera.get_directed_zoom() == 2.0, "Preview doubles the previous 1x view to retain character screen size")
	for id in [1, 4, 5, 6]:
		preview.show_map(id)
		await _settle()
		_check(preview.get_active_level().map_id == id and preview.get_player().get_instance_id() == player_id, "Map switch preserves the same actual player: %d" % id)
		preview.set_overview(true)
		_check(player.camera.get_instance_id() == camera_id and not player.movement_enabled, "Overview uses the same camera and locks movement: %d" % id)
		preview.set_overview(false)
		_check(player.camera.get_instance_id() == camera_id and player.movement_enabled, "Follow restores the same camera and movement: %d" % id)
	preview.queue_free()
	await _settle()
	_check(not InputMap.has_action(&"rpg_preview_overview"), "Standalone debug actions are removed on exit")
