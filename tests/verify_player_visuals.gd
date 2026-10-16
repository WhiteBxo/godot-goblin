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
	var frames: SpriteFrames = load("res://src/gameplay/player/player_walk_frames.tres")
	for direction in ["down", "left", "right", "up"]:
		for state in ["idle", "walk"]:
			var animation := "%s_%s" % [state, direction]
			var regions: Array[Rect2] = []
			for index in range(frames.get_frame_count(animation)):
				var texture := frames.get_frame_texture(animation, index) as AtlasTexture
				_check(texture.get_size() == Vector2(200, 300), "Every pose uses the same canvas")
				if state == "walk" and (index == 2 or index == 6):
					_check(texture.atlas.resource_path.ends_with("player_passing_atlas.png"), "Both half-cycles use the verified feet-together pose")
					_check(frames.get_frame_duration(animation, index) == 1.25, "Feet-together phase remains visible")
				else:
					_check(texture.region not in regions, "Non-passing phases use distinct source frames")
				regions.append(texture.region)
				sprite.texture = texture
				await process_frame
				await RenderingServer.frame_post_draw
				var image := viewport.get_texture().get_image()
				var bounds := image.get_used_rect()
				_check(bounds.end.y == 294, "All rendered feet share a fixed baseline: " + animation)
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
	print("PLAYER_VISUALS: ", "PASS" if _failures.is_empty() else "FAIL", " (36 rendered frames, closed-feet phases, hard alpha, baseline, cell isolation)")
	quit(0 if _failures.is_empty() else 1)
