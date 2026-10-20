extends SceneTree
## Read actual rendered pixels: tiles and actors live on different nested
## branches, and a two-cell object must use one shared foot line.

const MAP_SCRIPT := preload("res://src/levels/rpg_maker/rpg_maker_map.gd")
var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("RPG_DEPTH_SORT: requires a rendering display for pixel assertions")
		quit(2)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(240, 240)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node2D.new()
	viewport.add_child(world)
	var level_root := Node2D.new()
	world.add_child(level_root)
	var entities := Node2D.new()
	world.add_child(entities)
	var map = MAP_SCRIPT.new()
	map.map_size = Vector2i(5, 5)
	map.depth_sorted_regions.assign([
		{"layer": "Upper1", "rect": Rect2i(2, 1, 1, 2), "sort_y": 144.0},
		{"layer": "Upper3", "rect": Rect2i(2, 2, 1, 1), "sort_y": 144.0},
		{"layer": "Ground1", "rect": Rect2i(0, 1, 1, 2), "sort_y": 144.0},
		{"layer": "Upper1", "rect": Rect2i(4, 1, 1, 2), "sort_y": 144.0, "z_index": -1},
	])
	var tile_set := _make_tileset()
	for index in range(4):
		var ground := TileMapLayer.new()
		ground.name = "Ground%d" % index
		ground.tile_set = tile_set
		ground.z_index = -20 + index
		if index == 1:
			ground.set_cell(Vector2i(0, 1), 0, Vector2i.ZERO)
			ground.set_cell(Vector2i(0, 2), 0, Vector2i.ZERO)
		map.add_child(ground)
	var upper := TileMapLayer.new()
	upper.name = "Upper1"
	upper.tile_set = tile_set
	upper.z_index = 11
	upper.set_cell(Vector2i(2, 1), 0, Vector2i.ZERO)
	upper.set_cell(Vector2i(2, 2), 0, Vector2i.ZERO)
	upper.set_cell(Vector2i(3, 1), 0, Vector2i.ZERO)
	upper.set_cell(Vector2i(4, 1), 0, Vector2i.ZERO)
	upper.set_cell(Vector2i(4, 2), 0, Vector2i.ZERO)
	map.add_child(upper)
	var upper_detail := TileMapLayer.new()
	upper_detail.name = "Upper3"
	upper_detail.tile_set = _make_tileset(Color.GREEN)
	upper_detail.z_index = 13
	upper_detail.set_cell(Vector2i(2, 2), 0, Vector2i.ZERO)
	map.add_child(upper_detail)
	var saved_cells := upper.tile_map_data.duplicate()
	level_root.add_child(map)
	var actor := Node2D.new()
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([Vector2(-20, -100), Vector2(20, -100), Vector2(20, 0), Vector2(-20, 0)])
	visual.color = Color.RED
	actor.add_child(visual)
	entities.add_child(actor)
	map.configure_depth_sort(entities)
	actor.position = Vector2(120, 140)
	await _draw_frames()
	var image := viewport.get_texture().get_image()
	_check(_is_blue(image.get_pixel(120, 80)), "The upper furniture cell covers the actor behind its foot line")
	_check(_is_green(image.get_pixel(120, 125)), "Multiple furniture layers sharing a foot line preserve their authored drawing order")
	actor.position.y = 150
	await _draw_frames()
	image = viewport.get_texture().get_image()
	_check(_is_red(image.get_pixel(120, 80)) and _is_red(image.get_pixel(120, 125)), "The actor in front covers both furniture cells")
	actor.position = Vector2(168, 150)
	await _draw_frames()
	image = viewport.get_texture().get_image()
	_check(_is_blue(image.get_pixel(168, 80)), "Unconfigured overhead tiles remain above the actor")
	actor.position = Vector2(24, 140)
	await _draw_frames()
	image = viewport.get_texture().get_image()
	_check(_is_blue(image.get_pixel(24, 80)) and _is_blue(image.get_pixel(24, 125)), "Configured ground furniture also covers actors behind its foot line")
	actor.position.y = 150
	await _draw_frames()
	image = viewport.get_texture().get_image()
	_check(_is_red(image.get_pixel(24, 80)) and _is_red(image.get_pixel(24, 125)), "Actors in front cover configured ground furniture")
	actor.position = Vector2(216, 140)
	await _draw_frames()
	image = viewport.get_texture().get_image()
	_check(_is_red(image.get_pixel(216, 80)) and _is_red(image.get_pixel(216, 125)), "Floor decor at Z=-1 stays behind actors on the far side of its foot line")
	_check(upper.tile_map_data == saved_cells, "Runtime depth sorting preserves every saved cell")
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var original := source.get_tile_data(Vector2i.ZERO, 0)
	_check(original.z_index == 0 and original.y_sort_origin == 0, "Runtime sorting leaves the shared TileSet unchanged")
	_check(world.y_sort_enabled and level_root.y_sort_enabled and entities.y_sort_enabled and map.y_sort_enabled, "Map and actor branches share the same sorting space")
	viewport.queue_free()
	await process_frame
	print("RPG_DEPTH_SORT: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _draw_frames() -> void:
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw

func _make_tileset(color := Color.BLUE) -> TileSet:
	var atlas_image := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	atlas_image.fill(color)
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(atlas_image)
	source.texture_region_size = Vector2i(48, 48)
	source.create_tile(Vector2i.ZERO)
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(48, 48)
	tiles.add_source(source, 0)
	for field: String in ["rpg_tile_id", "passage", "star"]:
		var index := tiles.get_custom_data_layers_count()
		tiles.add_custom_data_layer()
		tiles.set_custom_data_layer_name(index, field)
		tiles.set_custom_data_layer_type(index, TYPE_BOOL if field == "star" else TYPE_INT)
	source.get_tile_data(Vector2i.ZERO, 0).set_custom_data("rpg_tile_id", 1)
	return tiles

func _is_red(color: Color) -> bool:
	return color.r > 0.8 and color.b < 0.2

func _is_blue(color: Color) -> bool:
	return color.b > 0.8 and color.r < 0.2

func _is_green(color: Color) -> bool:
	return color.g > 0.8 and color.r < 0.2 and color.b < 0.2
