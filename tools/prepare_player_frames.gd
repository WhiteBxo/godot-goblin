extends SceneTree

const SHEET_PATH := "res://assets/characters/player/player_walk_sheet.png"
const FRAMES_PATH := "res://src/gameplay/player/player_walk_frames.tres"
const IDLE_SOURCE_PATH := "res://assets/characters/player/player_idle_source.png"
const IDLE_ATLAS_PATH := "res://assets/characters/player/player_idle_atlas.png"
const DIRECTIONS: Array[String] = ["down", "left", "right", "up"]
const COLUMNS: Array[int] = [0, 220, 410, 590, 778, 960, 1148, 1330, 1536]
const ROWS: Array[int] = [0, 270, 513, 752, 1024]
const CANVAS_SIZE := Vector2(200, 300)
const GROUND_Y := 294.0

func _initialize() -> void:
	if "--prepare-idle" in OS.get_cmdline_user_args():
		_prepare_idle_atlas()
		return
	var image := Image.load_from_file(ProjectSettings.globalize_path(SHEET_PATH))
	if image == null or image.get_size() != Vector2i(1536, 1024):
		push_error("Expected the 1536 x 1024 generated walking sheet")
		quit(1)
		return
	var sheet := load(SHEET_PATH) as Texture2D
	var idle_sheet := load(IDLE_ATLAS_PATH) as Texture2D
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for row in range(4):
		var textures: Array[AtlasTexture] = []
		for column in range(8):
			var cell := Rect2i(COLUMNS[column], ROWS[row], COLUMNS[column + 1] - COLUMNS[column], ROWS[row + 1] - ROWS[row])
			var region := _opaque_bounds(image, cell)
			if region.size.x < 40 or region.size.y < 150 or region.size.x >= 200 or region.size.y >= 294:
				push_error("Invalid sprite region: row %d, column %d: %s" % [row, column, region])
				quit(1)
				return
			var anchor_x := _torso_center(image, region)
			var texture := AtlasTexture.new()
			texture.atlas = sheet
			texture.region = region
			texture.margin = Rect2(Vector2(100.0 - (anchor_x - region.position.x), GROUND_Y - region.size.y), CANVAS_SIZE - Vector2(region.size))
			texture.filter_clip = true
			textures.append(texture)
		var walk := "walk_" + DIRECTIONS[row]
		frames.add_animation(walk)
		frames.set_animation_speed(walk, 12.0)
		for texture in textures:
			frames.add_frame(walk, texture)
		var idle := "idle_" + DIRECTIONS[row]
		frames.add_animation(idle)
		var idle_texture := AtlasTexture.new()
		idle_texture.atlas = idle_sheet
		idle_texture.region = Rect2(row * CANVAS_SIZE.x, 0, CANVAS_SIZE.x, CANVAS_SIZE.y)
		idle_texture.filter_clip = true
		frames.add_frame(idle, idle_texture)
	var error := ResourceSaver.save(frames, FRAMES_PATH)
	print("PLAYER_FRAMES: ", error_string(error), " (32 poses, torso-centered, common foot baseline, no modified source pixels)")
	quit(0 if error == OK else 1)

func _prepare_idle_atlas() -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(IDLE_SOURCE_PATH))
	var atlas := Image.create(800, 300, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	var cell_width := source.get_width() / 4
	for direction in range(4):
		var region := _opaque_bounds(source, Rect2i(direction * cell_width, 0, cell_width, source.get_height()))
		var center := _torso_center(source, region)
		var ratio := 208.0 / region.size.y
		var sprite := source.get_region(region)
		sprite.resize(roundi(region.size.x * ratio), 208, Image.INTERPOLATE_NEAREST)
		var x := direction * 200 + roundi(100.0 - (center - region.position.x) * ratio)
		atlas.blit_rect(sprite, Rect2i(Vector2i.ZERO, sprite.get_size()), Vector2i(x, 86))
	var error := atlas.save_png(ProjectSettings.globalize_path(IDLE_ATLAS_PATH))
	print("PLAYER_IDLE_ATLAS: ", error_string(error), " (four neutral poses, 208px body height, nearest downsampling)")
	quit(0 if error == OK else 1)

func _opaque_bounds(image: Image, cell: Rect2i) -> Rect2i:
	var low := cell.end
	var high := cell.position
	for y in range(cell.position.y, cell.end.y):
		for x in range(cell.position.x, cell.end.x):
			if image.get_pixel(x, y).a >= 0.9:
				low = low.min(Vector2i(x, y))
				high = high.max(Vector2i(x + 1, y + 1))
	return Rect2i(low, high - low)

func _torso_center(image: Image, region: Rect2i) -> float:
	var left := region.end.x
	var right := region.position.x
	for y in range(region.position.y + int(region.size.y * 0.42), region.position.y + int(region.size.y * 0.7)):
		for x in range(region.position.x, region.end.x):
			var color := image.get_pixel(x, y)
			if color.a >= 0.9 and color.r > color.g * 1.2 and color.g > color.b * 1.2:
				left = mini(left, x)
				right = maxi(right, x)
	return roundf((left + right) * 0.5) if left <= right else region.get_center().x
