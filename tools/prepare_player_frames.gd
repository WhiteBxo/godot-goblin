extends SceneTree

const ROOT := "res://assets/characters/player/"
const DIRECTIONS := ["down", "left", "right", "up"]
const IDLE_CELLS := [Vector2i(1, 2), Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 0)]
const CANVAS := Vector2i(200, 300)
const FRAMES_PATH := "res://src/gameplay/player/player_run_frames.tres"

func _initialize() -> void:
	if "--pack" in OS.get_cmdline_user_args():
		var atlas := Image.create(3200, 1500, false, Image.FORMAT_RGBA8)
		atlas.fill(Color.TRANSPARENT)
		for direction in range(4):
			var source := Image.load_from_file(ROOT + "player_run_" + DIRECTIONS[direction] + ".png")
			assert(source.get_size() == Vector2i(256, 256))
			for index in range(16):
				_pack(atlas, source, Vector2i(index % 4, index / 4), Vector2i(index * 200, direction * 300))
		var idle := Image.load_from_file(ROOT + "player_idle_sheet.png")
		for direction in range(4):
			_pack(atlas, idle, IDLE_CELLS[direction], Vector2i(direction * 200, 1200), 81)
		var result := atlas.save_png(ROOT + "player_run_atlas.png")
		print("PLAYER_ATLAS: ", error_string(result))
		quit(result)
		return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var atlas := load(ROOT + "player_run_atlas.png") as Texture2D
	for direction in range(4):
		for state in ["idle", "run"]:
			var animation: String = state + "_" + DIRECTIONS[direction]
			frames.add_animation(animation)
			frames.set_animation_speed(animation, 24.0 if state == "run" else 1.0)
			for index in range(16 if state == "run" else 1):
				var texture := AtlasTexture.new()
				texture.atlas = atlas
				texture.region = Rect2(Vector2(index * 200, direction * 300) if state == "run" else Vector2(direction * 200, 1200), Vector2(CANVAS))
				texture.filter_clip = true
				frames.add_frame(animation, texture)
	var result := ResourceSaver.save(frames, FRAMES_PATH)
	print("PLAYER_FRAMES: ", error_string(result), " (four 16-frame run cycles, four idle poses)")
	quit(result)

func _pack(atlas: Image, source: Image, cell: Vector2i, destination: Vector2i, top: int = 77) -> void:
	# Keep fixed grid anchors so the supplied running bounce remains intact.
	var pose := source.get_region(Rect2i(cell * 64, Vector2i(64, 64)))
	pose.resize(224, 224, Image.INTERPOLATE_NEAREST)
	atlas.blit_rect(pose, Rect2i(12, 0, 200, 300 - top), destination + Vector2i(0, top))
