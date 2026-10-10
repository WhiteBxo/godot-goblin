extends SceneTree

const ATLAS := preload("res://src/resources/tilesets/cave_atlas.gd")
const GRID := preload("res://src/resources/tilesets/cave_grid.gd")
const SOURCE_PATH := "res://assets/map/cave/cave_floor_processed.png"

func _initialize() -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE_PATH))
	if source == null or source.is_empty():
		push_error("Prepare the source cave atlas before generating the editable grid")
		quit(1)
		return
	for ground in [true, false]:
		var name := "cave_ground" if ground else "cave_border"
		var texture_path := "res://assets/map/cave/%s.png" % name
		var image := Image.create(512, 512, false, Image.FORMAT_RGBA8)
		for mask in range(256):
			var cells: Dictionary = {}
			if ground:
				cells[Vector2i.ZERO] = true
			for index in range(8):
				if mask & (1 << index):
					cells[GRID.NEIGHBORS[index]] = true
			var destination: Vector2i = GRID.atlas_coords(mask) * ATLAS.TILE_SIZE
			for quadrant in range(4):
				var offset := Vector2i(quadrant % 2, quadrant >> 1)
				var corner_mask: int = ATLAS.corner_mask(offset - Vector2i.ONE, cells)
				var source_origin: Vector2i = ATLAS.ATLAS_MARGIN + ATLAS.MASK_TO_ATLAS[corner_mask] * (Vector2i.ONE * ATLAS.TILE_SIZE + ATLAS.ATLAS_SEPARATION)
				# Reassemble the same pixels on the logical grid instead of a half-tile offset.
				image.blit_rect(source, Rect2i(source_origin + (Vector2i.ONE - offset) * 16, Vector2i(16, 16)), destination + offset * 16)
		var error := image.save_png(texture_path)
		if error == OK:
			error = _write_tileset("res://src/resources/tilesets/%s.tres" % name, texture_path, ground)
		if error != OK:
			push_error("Could not prepare editable cave tiles (error %d)" % error)
			quit(1)
			return
	print("PASS: editable 32x32 cave ground and border TileSets prepared")
	quit()

func _write_tileset(path: String, texture_path: String, ground: bool) -> Error:
	var text := '[gd_resource type="TileSet" load_steps=3 format=3]\n\n'
	text += '[ext_resource type="Texture2D" path="%s" id="1_texture"]\n\n' % texture_path
	text += '[sub_resource type="TileSetAtlasSource" id="Atlas"]\ntexture = ExtResource("1_texture")\n'
	text += 'texture_region_size = Vector2i(32, 32)\nuse_texture_padding = false\n'
	var peering_names := ["top_left_corner", "top_side", "top_right_corner", "left_side", "right_side", "bottom_left_corner", "bottom_side", "bottom_right_corner"]
	for mask in range(256):
		var coords: Vector2i = GRID.atlas_coords(mask)
		var prefix := "%d:%d/0" % [coords.x, coords.y]
		text += prefix + " = 0\n"
		if ground:
			text += prefix + "/terrain_set = 0\n" + prefix + "/terrain = 0\n"
			for index in range(8):
				if mask & (1 << index):
					text += prefix + "/terrains_peering_bit/" + peering_names[index] + " = 0\n"
	text += '\n[resource]\ntile_size = Vector2i(32, 32)\n'
	if ground:
		text += 'terrain_set_0/mode = 0\nterrain_set_0/terrain_0/name = "StoneFloor"\nterrain_set_0/terrain_0/color = Color(0.55, 0.65, 0.4, 1)\n'
	text += 'sources/0 = SubResource("Atlas")\n'
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	return OK
