extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	var player: PlayerController = load("res://src/gameplay/player/shop_player.tscn").instantiate()
	root.add_child(player)
	_check(player.animated_sprite.global_scale.is_equal_approx(Vector2.ONE * 0.5), "Shop player restores native pixels from the doubled atlas")
	player.queue_free()
	await process_frame
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 160)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.position = Vector2(64, 80)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.material = load("res://src/gameplay/player/player_sprite_material.tres")
	viewport.add_child(sprite)
	var frames: SpriteFrames = load("res://src/gameplay/player/player_actions_pixel_frames.tres")
	var contact := Image.create(4 * 128, 6 * 160, false, Image.FORMAT_RGBA8)
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
				_check(texture.get_size() == Vector2(128, 160), "Every pose uses the same canvas")
				_check(texture.atlas.resource_path.ends_with("player_actions_pixel_atlas.png"), "All poses use the newly supplied art")
				_check(texture.region not in regions and texture.filter_clip, "Unique clipped source cells")
				_check(frames.get_frame_duration(animation, index) == 1.0, "Uniform frame timing")
				regions.append(texture.region)
				sprite.texture = texture
				await process_frame
				await RenderingServer.frame_post_draw
				var image := viewport.get_texture().get_image()
				var bounds := image.get_used_rect()
				_check(bounds.end.y >= 138 and bounds.end.y <= 157, "Cycle shares a stable ground anchor: " + animation)
				_check(bounds.size.x < 128 and bounds.size.y > 57 and bounds.size.y < 138, "Full pose stays inside its cell: " + animation)
				var partial_alpha := false
				for y in range(bounds.position.y, bounds.end.y):
					for x in range(bounds.position.x, bounds.end.x):
						var alpha := image.get_pixel(x, y).a
						if alpha > 0.001 and alpha < 0.999:
							partial_alpha = true
				_check(not partial_alpha, "No translucent fringes: " + animation)
				var even_pixels := true
				for y in range(0, image.get_height(), 2):
					for x in range(0, image.get_width(), 2):
						var pixel := image.get_pixel(x, y)
						if pixel != image.get_pixel(x + 1, y) or pixel != image.get_pixel(x, y + 1) or pixel != image.get_pixel(x + 1, y + 1):
							even_pixels = false
				_check(even_pixels, "Every source pixel renders as an even 2x2 block: " + animation)
				if index == 0:
					contact.blend_rect(image, Rect2i(0, 0, 128, 160), Vector2i(column * 128, row * 160))
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
