extends SceneTree

const GRID := preload("res://src/resources/tilesets/cave_grid.gd")
const TILE_SIZE := 32
const ATLAS_MARGIN := Vector2i(9, 9)
const ATLAS_SEPARATION := Vector2i(9, 9)
const EXPECTED_ATLAS_SHA256 := "4eda50dfaee516cf3a3bdd99b3b675fd78573e44a1dfc8e5150c7de2e5824b52"
const EXPECTED_ATLAS_MASKS := [
	[4, 10, 13, 12],
	[9, 14, 15, 7],
	[2, 3, 11, 5],
	[0, 8, 6, 1],
]
const EXPECTED_MAP_MASK_COUNTS := {
	1: 14, 2: 13, 3: 397, 4: 14, 5: 242, 7: 20,
	8: 13, 10: 244, 11: 19, 12: 397, 13: 20, 14: 19, 15: 5593,
}

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var scene: Node = (load("res://src/core/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var cave_map: CaveMap = scene.get_active_level()
	var failures: Array[String] = []
	var original_layout := "--original-layout" in OS.get_cmdline_user_args()
	var expected_count := 6305 if original_layout else 6309
	var expected_masks: Dictionary = EXPECTED_MAP_MASK_COUNTS if original_layout else {1:14,2:13,3:397,4:14,5:246,7:20,8:13,10:248,11:19,12:397,13:20,14:19,15:5593}
	var floor_layer: TileMapLayer = cave_map.floor_layer
	var river_layer: TileMapLayer = cave_map.river_layer
	var script_constants: Dictionary = cave_map.get_script().get_script_constant_map()
	var mask_to_atlas: Dictionary = script_constants["MASK_TO_ATLAS"]
	var legacy_tileset: TileSet = load("res://src/resources/tilesets/cave_floor.tres")
	var floor_source: TileSetAtlasSource = legacy_tileset.get_source(0) as TileSetAtlasSource
	var expected_by_mask: Dictionary = {}
	for y in range(4):
		for x in range(4):
			var mask: int = EXPECTED_ATLAS_MASKS[y][x]
			expected_by_mask[mask] = Vector2i(x, y)
			if mask_to_atlas.get(mask) != Vector2i(x, y):
				failures.append("mask %d should map to atlas (%d,%d)" % [mask, x, y])
			if not floor_source.has_tile(Vector2i(x, y)):
				failures.append("atlas tile (%d,%d) was not added to the TileSet" % [x, y])
	if expected_by_mask.size() != 16:
		failures.append("atlas table must cover all 16 corner masks")
	if floor_layer.position != Vector2.ZERO:
		failures.append("editable floor must use the logical grid origin")
	if floor_source.use_texture_padding:
		failures.append("floor atlas texture padding must be disabled")
	if floor_layer.get_used_cells().size() != expected_count:
		failures.append("unexpected number of editable ground cells")
	if river_layer.get_used_cells().size() != 232:
		failures.append("river should remain 232 cells")
	if FileAccess.get_sha256("res://assets/map/cave/cave_floor_atlas.png").to_lower() != EXPECTED_ATLAS_SHA256:
		failures.append("source atlas PNG changed on disk")
	var source_image: Image = (load("res://assets/map/cave/cave_floor_atlas.png") as Texture2D).get_image()
	var processed_image: Image = (load("res://assets/map/cave/cave_floor_processed.png") as Texture2D).get_image()
	if source_image.get_size() != Vector2i(173, 173) or processed_image.get_size() != source_image.get_size():
		failures.append("runtime atlas images have the wrong dimensions")
	for mask in range(16):
		var atlas_cell: Vector2i = mask_to_atlas[mask]
		var origin := ATLAS_MARGIN + Vector2i(atlas_cell.x * 41, atlas_cell.y * 41)
		for bit in [1, 2, 4, 8]:
			var corner := _corner_seed(bit)
			var original_pixel: Color = source_image.get_pixelv(origin + corner)
			var processed_pixel: Color = processed_image.get_pixelv(origin + corner)
			if mask == 0 or (mask & bit) == 0:
				if processed_pixel != Color.BLACK:
					failures.append("missing corner seed was not blackened for mask %d" % mask)
			else:
				if processed_pixel != original_pixel:
					failures.append("occupied corner changed for mask %d" % mask)
					break
		for y in range(TILE_SIZE):
			for x in range(TILE_SIZE):
				var source_color: Color = source_image.get_pixelv(origin + Vector2i(x, y))
				var output_color: Color = processed_image.get_pixelv(origin + Vector2i(x, y))
				if mask == 0 and output_color != Color.BLACK:
					failures.append("empty atlas tile should be fully black")
					break
				if mask == 15 and output_color != source_color:
					failures.append("full stone tile 15 must remain pixel-identical")
					break
				if output_color != source_color and maxf(source_color.r, maxf(source_color.g, source_color.b)) > 0.32:
					failures.append("bright stone pixel was altered at mask %d" % mask)
					break
	for y in range(4, 62):
		for x in range(5, 9):
			if river_layer.get_cell_source_id(Vector2i(x, y)) < 0:
				failures.append("river disconnected at (%d,%d)" % [x, y])
				break

	var actual_masks: Dictionary = {}
	var actual_mask_counts: Dictionary = {}
	var legacy_candidates: Dictionary = {}
	for cell: Vector2i in cave_map.walkable_cells:
		for offset: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.UP, Vector2i(-1, -1)]:
			legacy_candidates[cell + offset] = true
		if floor_layer.get_cell_atlas_coords(cell) != GRID.atlas_coords(GRID.neighbor_mask(cell, cave_map.walkable_cells)):
			failures.append("wrong editable ground variant at %s" % cell)
	for cell: Vector2i in legacy_candidates:
		var mask: int = cave_map.corner_mask(cell)
		actual_masks[mask] = true
		actual_mask_counts[mask] = int(actual_mask_counts.get(mask, 0)) + 1
	if actual_mask_counts != expected_masks:
		failures.append("actual map mask counts do not match the expected geometry: %s" % [actual_mask_counts])
	# Compare complete raster images against the original half-offset atlas composition.
	# This checks the new tiles and outside-edge decoration independently of their generator.
	var bounds := cave_map.map_bounds.grow(1)
	var size := bounds.size * TILE_SIZE
	var legacy_image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var editable_image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	legacy_image.fill(Color.BLACK)
	editable_image.fill(Color.BLACK)
	for cell: Vector2i in legacy_candidates:
		var atlas_cell: Vector2i = mask_to_atlas[cave_map.corner_mask(cell)]
		var source_origin := ATLAS_MARGIN + atlas_cell * (Vector2i.ONE * TILE_SIZE + ATLAS_SEPARATION)
		legacy_image.blit_rect(processed_image, Rect2i(source_origin, Vector2i.ONE * TILE_SIZE), (cell - bounds.position) * TILE_SIZE + Vector2i(16, 16))
	for layer: TileMapLayer in [floor_layer, cave_map.border_layer]:
		var image: Image = (layer.tile_set.get_source(0) as TileSetAtlasSource).texture.get_image()
		for cell: Vector2i in layer.get_used_cells():
			editable_image.blit_rect(image, Rect2i(layer.get_cell_atlas_coords(cell) * TILE_SIZE, Vector2i.ONE * TILE_SIZE), (cell - bounds.position) * TILE_SIZE)
	if legacy_image.get_data() != editable_image.get_data():
		failures.append("editable map pixels differ from the original atlas composition")

	var original_cells: Dictionary = cave_map.walkable_cells
	for mask in range(16):
		cave_map.walkable_cells = {}
		if (mask & 1) != 0:
			cave_map.walkable_cells[Vector2i.ZERO] = true
		if (mask & 2) != 0:
			cave_map.walkable_cells[Vector2i.RIGHT] = true
		if (mask & 4) != 0:
			cave_map.walkable_cells[Vector2i.DOWN] = true
		if (mask & 8) != 0:
			cave_map.walkable_cells[Vector2i(1, 1)] = true
		if cave_map.corner_mask(Vector2i.ZERO) != mask:
			failures.append("corner sampling failed for mask %d" % mask)
	cave_map.walkable_cells = original_cells

	var player: CharacterBody2D = scene.get_player()
	var camera: Camera2D = scene.get_player().camera
	if not player.can_stand_at(Vector2(90.5, 0.5 if original_layout else -1.5) * 32.0):
		failures.append("one-cell-wide top passage should stay passable")
	if not camera.global_position.is_equal_approx(player.global_position):
		failures.append("camera should remain centered on the player")

	if failures.is_empty():
		var masks: Array = actual_masks.keys()
		masks.sort()
		print("PASS: all 16 atlas masks; actual map mask counts=", actual_mask_counts, "; editable map pixels identical; river=232; narrow passage passable; camera centered.")
		quit()
	else:
		for failure: String in failures:
			printerr("FAIL: ", failure)
		quit(1)

func _corner_seed(bit: int) -> Vector2i:
	match bit:
		1:
			return Vector2i.ZERO
		2:
			return Vector2i(TILE_SIZE - 1, 0)
		4:
			return Vector2i(0, TILE_SIZE - 1)
		_:
			return Vector2i(TILE_SIZE - 1, TILE_SIZE - 1)
