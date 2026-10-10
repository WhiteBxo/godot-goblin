extends SceneTree

const ATLAS := preload("res://src/resources/tilesets/cave_atlas.gd")
const TILE_SIZE := ATLAS.TILE_SIZE
const ATLAS_MARGIN := ATLAS.ATLAS_MARGIN
const ATLAS_SEPARATION := ATLAS.ATLAS_SEPARATION
const VOID_RGB_THRESHOLD := ATLAS.VOID_RGB_THRESHOLD
const MASK_TO_ATLAS := ATLAS.MASK_TO_ATLAS
const SOURCE_PATH := "res://assets/map/cave/cave_floor_atlas.png"
const FLOOR_PATH := "res://assets/map/cave/cave_floor_processed.png"
const RIVER_SOURCE_PATH := "res://assets/map/cave/river_source.png"
const RIVER_PATH := "res://assets/map/cave/river.png"
const PLAYER_PATH := "res://assets/characters/player/goblin.png"

var floor_atlas_source_image: Image
var floor_atlas_processed_image: Image

func _initialize() -> void:
	var floor_image := _process_floor_image()
	var river_image := Image.load_from_file(ProjectSettings.globalize_path(RIVER_SOURCE_PATH))
	if floor_image == null or river_image == null or river_image.is_empty():
		quit(1)
		return
	river_image.resize(TILE_SIZE, TILE_SIZE, Image.INTERPOLATE_NEAREST)
	for output in [[floor_image, FLOOR_PATH], [river_image, RIVER_PATH], [_make_player_image(), PLAYER_PATH]]:
		var error: Error = output[0].save_png(output[1])
		if error != OK:
			printerr("Could not save ", output[1], ": ", error)
			quit(1)
			return
	if _write_tileset("res://src/resources/tilesets/cave_floor.tres", FLOOR_PATH, true) != OK:
		quit(1)
		return
	if _write_tileset("res://src/resources/tilesets/cave_river.tres", RIVER_PATH, false) != OK:
		quit(1)
		return
	print("PASS: cave atlas, river, player sprite and external TileSets prepared")
	quit()

func _write_tileset(path: String, texture_path: String, floor_atlas: bool) -> Error:
	var text := '[gd_resource type="TileSet" load_steps=3 format=3]\n\n'
	text += '[ext_resource type="Texture2D" path="%s" id="1_texture"]\n\n' % texture_path
	text += '[sub_resource type="TileSetAtlasSource" id="Atlas"]\ntexture = ExtResource("1_texture")\n'
	text += "texture_region_size = Vector2i(%d, %d)\n" % [TILE_SIZE, TILE_SIZE]
	if floor_atlas:
		text += "margins = Vector2i(9, 9)\nseparation = Vector2i(9, 9)\nuse_texture_padding = false\n"
	var columns := 4 if floor_atlas else 1
	for y in range(columns):
		for x in range(columns):
			text += "%d:%d/0 = 0\n" % [x, y]
	text += '\n[resource]\ntile_size = Vector2i(%d, %d)\nsources/0 = SubResource("Atlas")\n' % [TILE_SIZE, TILE_SIZE]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Could not save TileSet: ", path)
		return FileAccess.get_open_error()
	file.store_string(text)
	return OK

func _process_floor_image() -> Image:
	floor_atlas_source_image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE_PATH))
	if floor_atlas_source_image == null or floor_atlas_source_image.is_empty():
		push_error("Could not load cave floor atlas image")
		return null
	floor_atlas_source_image.convert(Image.FORMAT_RGBA8)
	floor_atlas_processed_image = floor_atlas_source_image.duplicate()
	var changed_pixels := 0
	for mask in range(16):
		var atlas_cell: Vector2i = MASK_TO_ATLAS[mask]
		var origin := ATLAS_MARGIN + Vector2i(
			atlas_cell.x * (TILE_SIZE + ATLAS_SEPARATION.x),
			atlas_cell.y * (TILE_SIZE + ATLAS_SEPARATION.y)
		)
		if mask == 0:
			for y in range(TILE_SIZE):
				for x in range(TILE_SIZE):
					var pixel_position := origin + Vector2i(x, y)
					if floor_atlas_processed_image.get_pixelv(pixel_position) != Color.BLACK:
						changed_pixels += 1
					floor_atlas_processed_image.set_pixelv(pixel_position, Color.BLACK)
			continue
		for corner_bit in [1, 2, 4, 8]:
			if (mask & corner_bit) != 0:
				continue
			changed_pixels += _blacken_void_region(origin, _corner_seed(corner_bit))
	print("Floor atlas preprocessing: blackened ", changed_pixels, " void pixels; source PNG remains untouched.")
	return floor_atlas_processed_image

func _corner_seed(corner_bit: int) -> Vector2i:
	match corner_bit:
		1:
			return Vector2i.ZERO
		2:
			return Vector2i(TILE_SIZE - 1, 0)
		4:
			return Vector2i(0, TILE_SIZE - 1)
		_:
			return Vector2i(TILE_SIZE - 1, TILE_SIZE - 1)

func _blacken_void_region(tile_origin: Vector2i, seed: Vector2i) -> int:
	var seed_color: Color = floor_atlas_source_image.get_pixelv(tile_origin + seed)
	var queue: Array[Vector2i] = [seed]
	var visited: Dictionary = {}
	var changed := 0
	while not queue.is_empty():
		var pixel: Vector2i = queue.pop_back()
		if pixel.x < 0 or pixel.y < 0 or pixel.x >= TILE_SIZE or pixel.y >= TILE_SIZE:
			continue
		var key: int = pixel.y * TILE_SIZE + pixel.x
		if visited.has(key):
			continue
		visited[key] = true
		var source_color: Color = floor_atlas_source_image.get_pixelv(tile_origin + pixel)
		var difference := Vector3(source_color.r - seed_color.r, source_color.g - seed_color.g, source_color.b - seed_color.b)
		if difference.length_squared() > VOID_RGB_THRESHOLD * VOID_RGB_THRESHOLD:
			continue
		var current_color: Color = floor_atlas_processed_image.get_pixelv(tile_origin + pixel)
		if current_color != Color.BLACK:
			changed += 1
		floor_atlas_processed_image.set_pixelv(tile_origin + pixel, Color.BLACK)
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			queue.append(pixel + direction)
	return changed

func _make_player_image() -> Image:
	var image := Image.create(20, 26, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_draw_rect(image, Rect2i(5, 3, 10, 8), Color("26332c"))
	_draw_rect(image, Rect2i(4, 5, 12, 8), Color("76a45f"))
	_draw_rect(image, Rect2i(2, 7, 3, 4), Color("64934f"))
	_draw_rect(image, Rect2i(15, 7, 3, 4), Color("64934f"))
	_draw_rect(image, Rect2i(5, 5, 10, 8), Color("8fbd70"))
	_draw_rect(image, Rect2i(6, 9, 2, 2), Color("26332c"))
	_draw_rect(image, Rect2i(12, 9, 2, 2), Color("26332c"))
	_draw_rect(image, Rect2i(7, 15, 6, 7), Color("8b633f"))
	_draw_rect(image, Rect2i(5, 14, 10, 8), Color("c89355"))
	_draw_rect(image, Rect2i(6, 22, 3, 3), Color("3a302b"))
	_draw_rect(image, Rect2i(11, 22, 3, 3), Color("3a302b"))
	_draw_rect(image, Rect2i(7, 15, 6, 2), Color("e1b96e"))
	return image

func _draw_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			image.set_pixel(x, y, color)
