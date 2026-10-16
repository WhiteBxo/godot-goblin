extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _frames(count: int) -> void:
	for index in range(count):
		await physics_frame
	await process_frame
	await process_frame

func _check_view(camera: Camera2D, bounds: Rect2, message: String) -> void:
	camera.force_update_scroll()
	var visible_world: Rect2 = root.canvas_transform.affine_inverse() * root.get_visible_rect()
	_check(bounds.grow(0.5).encloses(visible_world), message + ": " + str(visible_world))

func _run() -> void:
	var game: MainGame = load("res://src/core/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames(3)
	var level := game.get_active_level() as MilkTeaShop
	var player := game.get_player() as ShopPlayer
	var camera := player.camera
	var bounds := level.get_world_bounds()
	_check(bounds.size == Vector2(1672, 941), "Bounds come from the replacement texture")
	_check(camera.is_current() and camera.get_parent() == player, "The active camera follows the player")
	_check_view(camera, bounds, "Spawn view stays within the background")
	var start_center := camera.get_screen_center_position()
	Input.action_press("move_right")
	await _frames(25)
	Input.action_release("move_right")
	_check(camera.get_screen_center_position().x > start_center.x + 20.0, "The camera scrolls during player movement")
	await _frames(15)
	# Test limits throughout smoothing, including abrupt direction changes at all corners.
	for target in [Vector2(130, 880), Vector2(1540, 880), Vector2(1500, 180), Vector2(130, 180)]:
		player.velocity = Vector2.ZERO
		player.global_position = target
		for frame in range(20):
			await _frames(1)
			_check_view(camera, bounds, "Smoothed corner view stays inside the image")
	# There must be no path around either side wall through the bottom floor strip.
	var starts := [Vector2(150, 870), Vector2(1550, 870), Vector2(300, 870), Vector2(1500, 170)]
	var actions := ["move_left", "move_right", "move_down", "move_up"]
	for index in range(starts.size()):
		player.velocity = Vector2.ZERO
		player.global_position = starts[index]
		Input.action_press(actions[index])
		await _frames(90)
		Input.action_release(actions[index])
		var texture := player.animated_sprite.sprite_frames.get_frame_texture(player.animated_sprite.animation, player.animated_sprite.frame)
		var sprite_rect := Rect2(player.animated_sprite.offset - texture.get_size() * 0.5, texture.get_size())
		var visible_player: Rect2 = player.animated_sprite.global_transform * sprite_rect
		_check(bounds.encloses(visible_player), "The entire character stays inside the background: " + actions[index])
		_check_view(camera, bounds, "Boundary view stays inside the background")
	# Viewport resizing must increase zoom when one dimension exceeds the map.
	for window_size in [Vector2i(1800, 500), Vector2i(500, 1400), Vector2i(1280, 720)]:
		root.size = window_size
		await _frames(4)
		_check_view(camera, bounds, "Resized view stays inside the background")
	# A translated level uses world coordinates for both limits and collisions.
	level.position = Vector2(2400, -1300)
	player.global_position = level.get_spawn_position()
	player.velocity = Vector2.ZERO
	player.configure_camera(level.get_world_bounds())
	await _frames(3)
	_check_view(camera, level.get_world_bounds(), "Translated level keeps the view inside its background")
	if "--capture" in OS.get_cmdline_user_args():
		level.position = Vector2.ZERO
		player.global_position = level.get_spawn_position()
		player.configure_camera(level.get_world_bounds())
		await _frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/milk_tea_verification/follow_camera.png")
	print("SHOP_CAMERA: ", "PASS" if _failures.is_empty() else "FAIL", " (follow, smoothing, four edges, whole sprite, viewport resizing, translated level)")
	quit(0 if _failures.is_empty() else 1)
