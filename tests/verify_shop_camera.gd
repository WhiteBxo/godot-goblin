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
	# Headless opens a 64x64 window, which stretches into a square 640x640 viewport
	# and changes both the fit zoom and the camera limits. Match the shipping 16:9
	# window so every assertion below is evaluated under the real aspect.
	root.size = Vector2i(1280, 720)
	await _frames(2)
	var game: MainGame = load("res://src/debug/story/legacy_shop.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames(3)
	var level := game.get_active_level() as MilkTeaShop
	var player := game.get_player() as ShopPlayer
	var camera := player.camera
	var bounds := level.get_world_bounds()
	var camera_bounds := level.get_camera_bounds()
	_check(bounds.size.is_equal_approx(Vector2(1720, 960)), "Bounds come from the replacement texture")
	# 相机边界现在正好是一屏：1280×720 美术像素 × 节点 1.25 = 1600×900 世界像素，
	# 四边各裁 48/24 个美术像素的外框。整间店因此一屏装下、每像素都在栅格上。
	_check(camera_bounds.position.is_equal_approx(Vector2(60, 30)) and camera_bounds.size.is_equal_approx(Vector2(1600, 900)), "Camera bounds are exactly one 1280x720 screen of room art")
	# Headless renders a square 640x640 viewport while the shipping window is 16:9,
	# so the camera fills the bounds along whichever axis is tightest. Assert the
	# fit rule rather than a fixed 0.5 that only held for the wide window.
	var fit_zoom := maxf(camera.preferred_zoom, maxf(
		camera.get_viewport_rect().size.x / camera_bounds.size.x,
		camera.get_viewport_rect().size.y / camera_bounds.size.y))
	# 相机只接受「整数个屏幕像素 / 美术像素」的倍率：headless 窗口是 1 倍，
	# 所以合法值只能是整数，0.727 这类必然糊的倍率会被向上抬到 1.0。
	# 断言"至少铺满"与"落在屏幕像素栅格上"，而不是某个具体小数。
	var logical := Vector2(root.content_scale_size)
	if logical.x <= 0.0:
		logical = root.get_viewport().get_visible_rect().size
	var screen_factor := maxf(1.0, float(root.size.x) / logical.x)
	_check(camera.zoom.x >= fit_zoom - 0.001 and is_equal_approx(camera.zoom.x, camera.zoom.y),
		"Default zoom fills the camera bounds without exposing the outer frame")
	# 一条美术像素要换整数个屏幕像素：房间密度 1.25 也要乘进去。
	var art_scale: float = camera.art_scale
	var pixels_per_art := camera.zoom.x * screen_factor * art_scale
	_check(is_equal_approx(pixels_per_art, roundf(pixels_per_art)),
		"Default zoom lands on whole screen pixels")
	_check(camera.is_current() and camera.get_parent() == player, "The active camera follows the player")
	_check_view(camera, camera_bounds, "Spawn view excludes the outer frame")
	player.global_position = level.to_global(Vector2(690, 545))
	camera.reset_smoothing()
	await _frames(30)
	var start_center := camera.get_screen_center_position()
	Input.action_press("move_right")
	await _frames(25)
	Input.action_release("move_right")
	# 整间店一屏之后镜头没有可移动的余地（这正是「兼得」的代价）：跟拍退化成
	# 静止，要求房间始终完整留在画面里、小人也在画面里。
	_check(camera.get_screen_center_position().distance_to(start_center) < 0.5,
		"The fixed shop view does not drift while the player walks")
	_check_view(camera, camera_bounds, "Walking keeps the whole shop on screen")
	await _frames(15)
	# Test limits throughout smoothing, including abrupt direction changes at all corners.
	for target in [Vector2(130, 880), Vector2(1540, 880), Vector2(1500, 180), Vector2(130, 180)]:
		player.velocity = Vector2.ZERO
		player.global_position = target
		for frame in range(20):
			await _frames(1)
			_check_view(camera, camera_bounds, "Smoothed corner view excludes the outer frame")
	# There must be no path around either side wall through the bottom floor strip.
	var starts := [level.to_global(Vector2(175, 570)), level.to_global(Vector2(1205, 560)), level.to_global(Vector2(350, 640)), level.to_global(Vector2(850, 320))]
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
	# Camera2D snaps to the pixel grid, so its rendered centre can sit half a pixel
	# past the arithmetic limit; compare the centre and allow that half pixel.
	var allowed_center_y: float = camera_bounds.end.y - camera.get_viewport_rect().size.y / camera.zoom.y * 0.5 + 0.5
	for x in [350.0, 1035.0, 1055.0]:
		player.global_position = level.to_global(Vector2(x, 640))
		player.velocity = Vector2.ZERO
		Input.action_press("move_down")
		await _frames(150)
		var stable_center := camera.get_screen_center_position()
		var stable_transform := root.canvas_transform
		for frame in range(45):
			await process_frame
			_check(camera.get_screen_center_position() == stable_center, "Holding S at the bottom has no smoothing oscillation")
			_check(root.canvas_transform == stable_transform, "Holding S keeps the rendered world transform fixed")
			_check(camera.get_screen_center_position().y <= allowed_center_y, "Follow target itself stays inside camera limits")
		Input.action_release("move_down")
	player.global_position = level.to_global(Vector2(520, 570))
	player.velocity = Vector2.ZERO
	player.configure_camera(camera_bounds)
	Input.action_press("move_up")
	# Walk by physics frames and stop once the player is genuinely clear of the
	# bottom band; a fixed render-frame count moves a different distance at
	# different frame rates, which made this look like a stuck camera.
	var bottom_center_y := stable_bottom_center_y(camera, camera_bounds)
	for frame in range(300):
		await physics_frame
		if player.global_position.y < bottom_center_y - 40.0:
			break
	Input.action_release("move_up")
	await _frames(30)
	var view_size: Vector2 = camera.get_viewport_rect().size / camera.zoom
	var view_rect := Rect2(camera.get_screen_center_position() - view_size * 0.5, view_size)
	_check(view_rect.has_point(player.global_position), "Leaving the bottom keeps the player inside the fixed shop view")
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
