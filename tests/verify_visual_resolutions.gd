extends SceneTree
## Real windows: scene framing, HUD bounds, small-window dialogue and pixel readback.

const SIZES := [Vector2i(1024, 600), Vector2i(1280, 720), Vector2i(1366, 768),
	Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2400, 1080)]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _frames() -> void:
	for index in range(4):
		await physics_frame
	await process_frame

func _buttons_inside(node: Node, bounds: Rect2) -> void:
	if node is BaseButton and node.is_visible_in_tree():
		check(bounds.grow(1).encloses(node.get_global_rect()), "HUD button stays on screen: " + str(node.get_path()))
	for child in node.get_children():
		_buttons_inside(child, bounds)

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	check(picture.get_size() == root.size, "Renderer uses the complete physical window: " + name)
	if "--capture" in OS.get_cmdline_user_args():
		check(picture.save_png("res://.godot/visual_resolution_check/" + name + ".png") == OK, "Save actual render: " + name)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("VISUAL_RESOLUTIONS: requires a rendering context")
		quit(2)
		return
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	DirAccess.make_dir_recursive_absolute("res://.godot/visual_resolution_check")
	root.mode = Window.MODE_WINDOWED
	var scaling := root.get_node("DisplayScaling")
	for scene_path: String in ["res://src/debug/story/legacy_shop.tscn", "res://src/core/settlement.tscn"]:
		var game: MainGame = load(scene_path).instantiate()
		game.day1_story_enabled = false
		root.add_child(game)
		current_scene = game
		await _frames()
		var shop := game.get_active_level() is MilkTeaShop
		var player := game.get_player() as ShopPlayer
		if not shop:
			var vendor := game.get_actor_director().get_actor(&"market_vendor_1")
			check(vendor != null, "Formal cave registers the updated vendor")
			if vendor != null:
				player.teleport_to(vendor.global_position + Vector2(72, 48))
		for size: Vector2i in SIZES:
			root.size = size
			scaling.apply_to(root, root.size)
			await create_timer(0.25).timeout
			await _frames()
			check(root.size == size, "Operating system accepts the requested physical window: " + str(size))
			player.camera.reset_smoothing()
			await _frames()
			var logical := player.camera.get_viewport_rect().size
			var bounds := Rect2(Vector2.ZERO, logical)
			_buttons_inside(game.get_node("HudLayer"), bounds)
			check(bounds.has_point(player.get_global_transform_with_canvas().origin), "Player remains visible at " + str(size))
			if root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER:
				var factor := player.camera._screen_factor()
				check(is_equal_approx(factor, roundf(factor)), "Camera uses the same integer scale as the window")
			var name := "%s_%dx%d" % ["shop" if shop else "cave", size.x, size.y]
			await _capture(name)
			if size == Vector2i(1024, 600):
				var dialogue := game.get_dialogue_manager()
				check(dialogue.start_lines([{"speaker": "醉酒守卫", "text": "醉酒守卫"}], "resolution_fixture") == OK, "Small-window dialogue opens")
				await create_timer(0.3).timeout
				await _capture(name + "_dialogue")
				dialogue.end_dialogue()
		game.get_audio_manager().stop_bgm(0.0)
		await create_timer(0.05).timeout
		game.queue_free()
		await _frames()
	print("VISUAL_RESOLUTIONS: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
