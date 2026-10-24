extends SceneTree

var _failures: Array[String] = []
var _checks := 0
var _finished: Array[CameraAction] = []
var _game: MainGame
var _director: CameraDirector
var _camera: BoundedFollowCamera
var _bounds: Rect2

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)
		push_error(message)

func _view(message: String) -> void:
	_camera.force_update_scroll()
	var visible: Rect2 = root.canvas_transform.affine_inverse() * root.get_visible_rect()
	_check(_bounds.grow(0.05).encloses(visible), message + ": " + str(visible))

func _frames(count: int = 3) -> void:
	for i in range(count):
		await process_frame

func _wait(action: CameraAction) -> void:
	for i in range(180):
		if action.is_finished():
			break
		await process_frame
	_check(action.is_finished(), "Action settles within bounded time: " + action.command)
	await _frames(2)

func _run() -> void:
	# Headless opens a 64x64 window, which stretches into a square viewport and
	# changes both the fit zoom and the camera limits. Match the shipping 16:9 window.
	root.size = Vector2i(1280, 720)
	await _frames(2)
	_game = load("res://src/debug/story/legacy_shop.tscn").instantiate()
	root.add_child(_game)
	current_scene = _game
	await _frames()
	_director = _game.get_camera_director()
	_camera = (_game.get_player() as ShopPlayer).camera
	_bounds = (_game.get_active_level() as MilkTeaShop).get_world_bounds()
	_director.action_finished.connect(func(action: CameraAction) -> void: _finished.append(action))
	_check(_camera == _director.get_camera() and root.get_camera_2d() == _camera, "Reuse exactly the active player camera")
	_check(_camera.mode == BoundedFollowCamera.Mode.FOLLOW and _camera.global_position.distance_to(_camera.get_follow_position()) < 0.01 and _camera.position_smoothing_enabled, "Original default follow settings")
	var focus := _director.camera_focus(Vector2(1400, 240), 0.2)
	await _wait(focus)
	_check(focus.result == CameraAction.Result.COMPLETED and _camera.mode == BoundedFollowCamera.Mode.CINEMATIC, "Focus completes and holds cinematic mode")
	var fixed := _camera.global_position
	_game.get_player().position += Vector2(30, 0)
	await _frames()
	_check(_camera.global_position == fixed, "Player movement cannot overwrite cinematic position")
	_view("Focus bounds")
	var marker := Marker2D.new()
	_game.get_active_level().add_child(marker)
	# This focus-follow case needs a world target inside the camera limits.
	# The level's 1.25 scale would push these local coordinates past the limit.
	marker.global_position = Vector2(800, 500)
	focus = _director.camera_focus(marker, 0.1)
	await _wait(focus)
	marker.global_position += Vector2(80, 30)
	await _frames()
	# 整间店正好一屏，推镜没有横向余地：镜头停在边界允许的位置，目标仍然在画面里。
	var view_size: Vector2 = _camera.get_viewport_rect().size / _camera.zoom
	var view_rect := Rect2(_camera.get_screen_center_position() - view_size * 0.5, view_size)
	_check(view_rect.has_point(marker.global_position), "Completed focus keeps the live target on screen")
	marker.queue_free()
	await _frames(5)
	_check(_camera.mode == BoundedFollowCamera.Mode.FOLLOW, "Held target deletion restores follow")
	marker = Marker2D.new()
	_game.get_active_level().add_child(marker)
	focus = _director.camera_focus(marker, 2.0)
	var zoom_action := _director.camera_zoom(1.5, 2.0)
	marker.queue_free()
	await _frames(5)
	_check(focus.result == CameraAction.Result.FAILED and zoom_action.result == CameraAction.Result.FAILED, "Mid-action target deletion fails active requests")
	_check(_camera.mode == BoundedFollowCamera.Mode.FOLLOW and is_equal_approx(_camera.get_directed_zoom(), _camera.preferred_zoom), "Target failure resets state")
	var old := _director.camera_move(Vector2(1000, 600), 2.0)
	var replacement := _director.camera_move(Vector2(900, 450), 0.1, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	await _wait(replacement)
	_check(old.result == CameraAction.Result.CANCELLED and replacement.result == CameraAction.Result.COMPLETED, "Position replacement and easing")
	var follow := _director.camera_follow(0.15)
	await _wait(follow)
	_check(_camera.mode == BoundedFollowCamera.Mode.FOLLOW and _camera.global_position.distance_to(_camera.get_follow_position()) < 0.01 and _camera.position_smoothing_enabled, "Smooth follow handoff restores original configuration")
	var hud := _game.get_node("HudLayer").get_child(0) as Control
	var hud_transform := hud.get_global_transform_with_canvas()
	var shake := _director.camera_shake(100.0, 0.25, 1.0)
	var saw_shake := false
	for i in range(25):
		await process_frame
		saw_shake = saw_shake or not _camera.offset.is_zero_approx()
		_check((_camera.offset * _camera.zoom).abs().x <= 6.0 and (_camera.offset * _camera.zoom).abs().y <= 6.0, "Shake intensity cap")
		_view("Shake bounds")
	await _wait(shake)
	_check(saw_shake and _camera.offset == Vector2.ZERO, "Shake visible then automatically clears")
	_check(hud.get_global_transform_with_canvas().is_equal_approx(hud_transform), "HUD remains fixed during world shake")
	shake = _director.camera_shake(3, 2)
	var next_shake := _director.camera_shake(2, 2)
	_check(shake.result == CameraAction.Result.CANCELLED, "Retrigger cancels old shake")
	_director.shake_enabled = false
	_check(next_shake.result == CameraAction.Result.CANCELLED and _camera.offset == Vector2.ZERO, "Reduced motion disables and clears active shake")
	await _wait(_director.camera_shake())
	_check(_camera.offset == Vector2.ZERO, "Disabled shake is a successful no-op")
	_director.shake_enabled = true
	# All corners, concurrent zoom/shake, extreme viewport shapes; validate every tick.
	for corner in [_bounds.position, _bounds.end, Vector2(_bounds.end.x, 0), Vector2(0, _bounds.end.y)]:
		_director.camera_move(corner, 0.0)
		zoom_action = _director.camera_zoom(0.1, 0.15)
		shake = _director.camera_shake(6, 0.3, 0)
		for i in range(30):
			await process_frame
			_view("Cinematic corner / zoom / shake")
		_director.camera_reset()
	for size in [Vector2i(1800, 500), Vector2i(500, 1400), Vector2i(1280, 720)]:
		_director.camera_move(_bounds.end, 0.0)
		root.size = size
		await _frames(4)
		_view("Resize cinematic bounds")
	_director.camera_reset()
	# Native follow smoothing and shake must also remain bounded while moving.
	for corner in [Vector2(140, 180), Vector2(1500, 870)]:
		_game.get_player().global_position = corner
		shake = _director.camera_shake(6, 0.4, 0.5)
		zoom_action = _director.camera_zoom(0.6, 0.25)
		for i in range(35):
			await process_frame
			_view("Follow smoothing / corner / zoom / shake")
		_director.camera_reset()
	# Off-origin maps use exactly the same world-coordinate constraints.
	var level := _game.get_active_level() as MilkTeaShop
	level.position = Vector2(2000, -1200)
	_game.get_player().global_position = level.get_spawn_position()
	_bounds = level.get_world_bounds()
	_camera.configure(_bounds)
	await _wait(_director.camera_move(_bounds.end, 0.1))
	_view("Translated cinematic bounds")
	_director.camera_reset()
	for invalid in ["missing target", null, Vector2(INF, 0)]:
		var action := _director.camera_focus(invalid)
		_check(action.result == CameraAction.Result.FAILED, "Invalid focus rejected")
	_check(_director.camera_zoom(-1).result == CameraAction.Result.FAILED, "Invalid zoom rejected")
	_check(_director.camera_move(Vector2.ZERO, -1).result == CameraAction.Result.FAILED, "Negative duration rejected")
	_check(_director.camera_shake(NAN).result == CameraAction.Result.FAILED, "Non-finite shake rejected")
	old = _director.camera_move(Vector2(1200, 400), 2)
	zoom_action = _director.camera_zoom(1.5, 2)
	shake = _director.camera_shake(3, 2)
	paused = true
	await create_timer(0.08, true).timeout
	_check(not old.is_finished() and not zoom_action.is_finished(), "Camera actions inherit pause")
	_director.cancel_all("Paused cancellation")
	_check(old.result == CameraAction.Result.CANCELLED and zoom_action.result == CameraAction.Result.CANCELLED and shake.result == CameraAction.Result.CANCELLED, "Cancel all works while paused")
	_check(_camera.mode == BoundedFollowCamera.Mode.FOLLOW and _camera.offset == Vector2.ZERO, "Cancel all restores follow and offset")
	paused = false
	# Existing StoryDirector cancellation is wired through the host.
	var story := _game.get_story_director()
	story.load_events("res://tests/fixtures/story_events.json")
	_check(story.request_event("test.wait") == OK, "Start real story sequence for cancellation")
	old = _director.camera_move(Vector2(1200, 300), 2)
	story.cancel_event("Camera integration test")
	_check(old.result == CameraAction.Result.CANCELLED and _camera.mode == BoundedFollowCamera.Mode.FOLLOW, "Story terminal signal restores camera")
	old = _director.camera_move(Vector2(1200, 300), 2)
	_game.get_node("Systems").remove_child(_director)
	_check(old.result == CameraAction.Result.CANCELLED and _camera.mode == BoundedFollowCamera.Mode.FOLLOW, "Director removal cancels tween and restores camera")
	_director.free()
	await _frames()
	# A queued-free Director must still deliver the request's terminal signal.
	_director = CameraDirector.new()
	_game.get_node("Systems").add_child(_director)
	_director.configure(_camera)
	old = _director.camera_move(Vector2(1200, 300), 2)
	var terminal_signals: Array[int] = []
	old.finished.connect(func(_action: CameraAction) -> void: terminal_signals.append(1))
	_game.queue_free()
	await _frames(5)
	_check(old.result == CameraAction.Result.CANCELLED and terminal_signals.size() == 1, "Scene exit settles action exactly once")
	_check(get_processed_tweens().is_empty(), "No camera tweens survive scene exit")
	var demo: Node = load("res://src/debug/camera/camera_demo.tscn").instantiate()
	root.add_child(demo)
	current_scene = demo
	demo.call("_start")
	await create_timer(3.3).timeout
	_check(not demo.get("_running") and demo.get("_phase") == 4, "Demo completes full focus / hold / return / shake / follow sequence")
	demo.call("_start")
	await create_timer(0.08).timeout
	demo.call("_cancel")
	_check(not demo.get("_running") and (demo.get("_director") as CameraDirector).get_camera().mode == BoundedFollowCamera.Mode.FOLLOW, "Demo can repeat and cancel during motion")
	demo.call("_start")
	await create_timer(0.08).timeout
	demo.call("_delete_target")
	await _frames(5)
	_check(not demo.get("_running"), "Demo safely stops on target deletion")
	demo.call("_start")
	await create_timer(0.08).timeout
	demo.call("_rebuild")
	await _frames(5)
	_check((demo.get("_director") as CameraDirector).get_camera().mode == BoundedFollowCamera.Mode.FOLLOW, "Demo exit and rebuild restores default camera")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/camera-demo-follow.png")
		demo.call("_start")
		await create_timer(1.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/camera-demo-entrance.png")
	demo.queue_free()
	await _frames(5)
	print("CAMERA_DIRECTOR: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
