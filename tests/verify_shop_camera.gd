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
	var camera_bounds := level.get_camera_bounds()
	_check(bounds.size == Vector2(1672, 941), "Bounds come from the replacement texture")
	_check(camera_bounds.position == Vector2(100, 80) and camera_bounds.size == Vector2(1480, 861), "Camera excludes the painted outer frame")
	_check(camera.zoom == Vector2(0.5, 0.5), "Default view is 50 percent wider than the old zoom")
	_check(camera.is_current() and camera.get_parent() == player, "The active camera follows the player")
	_check_view(camera, camera_bounds, "Spawn view excludes the outer frame")
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
			_check_view(camera, camera_bounds, "Smoothed corner view excludes the outer frame")
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
		_check_view(camera, camera_bounds, "Boundary view excludes the outer frame")
	# Hold S against the bottom at the center and both corners, sampling render frames.
	for x in [150.0, 800.0, 1520.0]:
		player.global_position = Vector2(x, 900)
		player.velocity = Vector2.ZERO
		Input.action_press("move_down")
		await _frames(150)
		var stable_center := camera.get_screen_center_position()
		var stable_transform := root.canvas_transform
		for frame in range(45):
			await process_frame
			_check(camera.get_screen_center_position() == stable_center, "Holding S at the bottom has no smoothing oscillation")
			_check(root.canvas_transform == stable_transform, "Holding S keeps the rendered world transform fixed")
			_check(camera.global_position.y <= camera_bounds.end.y - camera.get_viewport_rect().size.y / camera.zoom.y * 0.5 + 0.001, "Follow target itself stays inside camera limits")
		Input.action_release("move_down")
	player.global_position = Vector2(300, 900)
	player.velocity = Vector2.ZERO
	player.configure_camera(camera_bounds)
	Input.action_press("move_up")
	await _frames(120)
	Input.action_release("move_up")
	_check(camera.get_screen_center_position().y < stable_bottom_center_y(camera, camera_bounds) - 10.0, "Camera resumes following when leaving the bottom")
	# Viewport resizing must increase zoom when one dimension exceeds the map.
	for window_size in [Vector2i(1800, 500), Vector2i(500, 1400), Vector2i(1280, 720)]:
		root.size = window_size
		await _frames(4)
		_check_view(camera, camera_bounds, "Resized view excludes the outer frame")
	# A translated level uses world coordinates for both limits and collisions.
	level.position = Vector2(2400, -1300)
	player.global_position = level.get_spawn_position()
	player.velocity = Vector2.ZERO
	player.configure_camera(level.get_camera_bounds())
	await _frames(3)
	_check_view(camera, level.get_camera_bounds(), "Translated level keeps the outer frame off screen")
	if "--capture" in OS.get_cmdline_user_args():
		level.position = Vector2.ZERO
		player.global_position = level.get_spawn_position()
		player.configure_camera(level.get_camera_bounds())
		await _frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/milk_tea_verification/follow_camera.png")
	print("SHOP_CAMERA: ", "PASS" if _failures.is_empty() else "FAIL", " (follow, smoothing, four edges, whole sprite, viewport resizing, translated level)")
	quit(0 if _failures.is_empty() else 1)

func stable_bottom_center_y(camera: Camera2D, bounds: Rect2) -> float:
	return bounds.end.y - camera.get_viewport_rect().size.y / camera.zoom.y * 0.5
