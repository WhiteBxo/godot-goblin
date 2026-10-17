extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(224, 300)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.position = Vector2(112, 150)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.material = load("res://src/gameplay/player/player_sprite_material.tres")
	viewport.add_child(sprite)
	var frames: SpriteFrames = load("res://src/gameplay/player/player_actions_frames.tres")
	var contact := Image.create(4 * 224, 6 * 300, false, Image.FORMAT_RGBA8)
	contact.fill(Color("39434e"))
	var count := 0
	var row := 0
	for state in ["idle", "walk", "run", "sneak", "crouch_idle", "throw"]:
		var column := 0
		for direction in ["down", "left", "right", "up"]:
			var animation := "%s_%s" % [state, direction]
			var regions: Array[Rect2] = []
			for index in range(frames.get_frame_count(animation)):
				var texture := frames.get_frame_texture(animation, index) as AtlasTexture
				_check(texture.get_size() == Vector2(224, 300), "Every pose uses the same canvas")
				_check(texture.atlas.resource_path.ends_with("player_actions_atlas.png"), "All poses use the newly supplied art")
				_check(texture.region not in regions and texture.filter_clip, "Unique clipped source cells")
				_check(frames.get_frame_duration(animation, index) == 1.0, "Uniform frame timing")
				regions.append(texture.region)
				sprite.texture = texture
				await process_frame
				await RenderingServer.frame_post_draw
				var image := viewport.get_texture().get_image()
				var bounds := image.get_used_rect()
				_check(bounds.end.y >= 260 and bounds.end.y <= 295, "Cycle shares a stable ground anchor: " + animation)
				_check(bounds.size.x < 224 and bounds.size.y > 100 and bounds.size.y < 240, "Full pose stays inside its cell: " + animation)
				var partial_alpha := false
				for y in range(bounds.position.y, bounds.end.y):
					for x in range(bounds.position.x, bounds.end.x):
						var alpha := image.get_pixel(x, y).a
						if alpha > 0.001 and alpha < 0.999:
							partial_alpha = true
				_check(not partial_alpha, "No translucent fringes: " + animation)
				if index == 0:
					contact.blend_rect(image, Rect2i(0, 0, 224, 300), Vector2i(column * 224, row * 300))
				count += 1
			column += 1
		row += 1
	var output := OS.get_environment("TEMP").path_join("player_actions_contact_render.png")
	_check(contact.save_png(output) == OK, "Rendered contact sheet saves")
	print("PLAYER_VISUALS: ", "PASS" if _failures.is_empty() else "FAIL", " (", count, " rendered frames, six actions, four directions, transparency, scale, ground anchor)")
	print("CONTACT: ", output)
	viewport.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)
