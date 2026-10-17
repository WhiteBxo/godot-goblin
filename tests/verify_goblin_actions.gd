extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var manifest: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/goblin_actions/manifest.json"))
	var total := 0
	var sprite := AnimatedSprite2D.new()
	root.add_child(sprite)
	for entry: Dictionary in manifest:
		var frames := load("res://src/gameplay/goblin_actions/%s_frames.tres" % entry.actor) as SpriteFrames
		assert(frames != null)
		var animation := StringName(entry.animation)
		assert(frames.get_frame_count(animation) == int(entry.count))
		assert(frames.get_animation_loop(animation) == bool(entry.loop))
		assert(frames.get_animation_speed(animation) == 12.0)
		var source := Image.new()
		assert(source.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/characters/goblin_actions/" + entry.file)) == OK)
		var covered := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
		for index in range(int(entry.count)):
			var texture := frames.get_frame_texture(animation, index) as AtlasTexture
			var cell := int(entry.cell)
			var expected := Rect2i(index % 6 * int(entry.stride), index / 6 * int(entry.stride), cell, cell)
			assert(texture.region == Rect2(expected))
			assert(texture.filter_clip)
			var frame := source.get_region(expected)
			assert(not frame.is_invisible(), "%s frame %d is blank" % [animation, index])
			covered.blit_rect(frame, Rect2i(0, 0, cell, cell), expected.position)
		# Every opaque pixel must be retained; gaps and unused cells must be transparent.
		for y in range(source.get_height()):
			for x in range(source.get_width()):
				assert(is_equal_approx(source.get_pixel(x, y).a, covered.get_pixel(x, y).a))
		sprite.stop()
		sprite.sprite_frames = frames
		sprite.speed_scale = 20.0
		sprite.play(animation)
		await create_timer((float(entry.count) + 2.0) / 240.0).timeout
		assert(sprite.is_playing() == bool(entry.loop), "Incorrect playback end: " + animation)
		if not bool(entry.loop):
			assert(sprite.frame == int(entry.count) - 1)
		total += int(entry.count)
	sprite.queue_free()
	var preview := load("res://src/debug/goblin_action_preview/goblin_action_preview.tscn").instantiate() as Control
	root.add_child(preview)
	for actor_index in range(4):
		preview.call("_select_actor", actor_index)
		var actions: OptionButton = preview.get("_actions")
		for action_index in range(actions.item_count):
			preview.call("_select_action", action_index)
			preview.call("_step", -1)
			preview.call("_replay")
			var visual: AnimatedSprite2D = preview.get("_sprite")
			assert(visual.frame == 0 and visual.is_playing())
			preview.call("_toggle_play")
			assert(not visual.is_playing())
			var mirror: CheckButton = preview.get("_mirror")
			assert(mirror.disabled == not String(visual.animation).ends_with("_side"))
			if not mirror.disabled:
				mirror.button_pressed = true
				assert(visual.flip_h)
	preview.call("_select_actor", 2)
	preview.call("_select_action", 1)
	preview.call("_step", 3)
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/goblin_action_preview.png")
	preview.queue_free()
	print("GOBLIN_ACTIONS_OK: 15 animations, %d nonblank frames, complete alpha coverage, playback and preview controls" % total)
	quit()
