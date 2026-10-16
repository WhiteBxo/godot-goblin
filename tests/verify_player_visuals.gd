extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(200, 300)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.position = Vector2(100, 150)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.material = load("res://src/gameplay/player/player_sprite_material.tres")
	viewport.add_child(sprite)
	var frames: SpriteFrames = load("res://src/gameplay/player/player_run_frames.tres")
	for direction in ["down", "left", "right", "up"]:
		for state in ["idle", "run"]:
			var animation := "%s_%s" % [state, direction]
			var regions: Array[Rect2] = []
			for index in range(frames.get_frame_count(animation)):
				var texture := frames.get_frame_texture(animation, index) as AtlasTexture
				_check(texture.get_size() == Vector2(200, 300), "Every pose uses the same canvas")
				_check(texture.atlas.resource_path.ends_with("player_run_atlas.png"), "All poses use the new supplied art")
				_check(texture.region not in regions, "Every phase uses its own source cell")
				_check(frames.get_frame_duration(animation, index) == 1.0, "Run phases have uniform timing")
				regions.append(texture.region)
				sprite.texture = texture
				await process_frame
				await RenderingServer.frame_post_draw
				var image := viewport.get_texture().get_image()
				var bounds := image.get_used_rect()
				_check(bounds.end.y >= 266 and bounds.end.y <= 295, "Supplied running bounce stays above the ground anchor: " + animation)
				_check(bounds.size.x < 160 and bounds.size.y < 240 and bounds.size.y > 180, "Pose stays in its own cell: " + animation)
				var partial_alpha := false
				for y in range(image.get_height()):
					for x in range(image.get_width()):
						var alpha := image.get_pixel(x, y).a
						if alpha > 0.001 and alpha < 0.999:
							partial_alpha = true
				_check(not partial_alpha, "No translucent fringe or ghost pixels: " + animation)
	viewport.queue_free()
	await process_frame
	print("PLAYER_VISUALS: ", "PASS" if _failures.is_empty() else "FAIL", " (68 rendered frames, new art, uniform timing, hard alpha, running bounce, cell isolation)")
	quit(0 if _failures.is_empty() else 1)
