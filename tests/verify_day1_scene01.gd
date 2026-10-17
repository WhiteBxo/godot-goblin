extends SceneTree

var _failures: Array[String] = []
var _checks := 0
var _host: Node
var _game: MainGame
var _capture := false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames() -> void:
	await process_frame
	await process_frame

func _new_host(autoplay: bool) -> void:
	root.get_node("GameState").reset_state()
	_host = load("res://src/debug/story/day1_scene01_demo.tscn").instantiate()
	_host.autoplay = autoplay
	root.add_child(_host)
	_game = _host.get_story_authoring_game()

func _dispose() -> void:
	_host.queue_free()
	await _frames()

func _snapshot(filename: String) -> void:
	if not _capture:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://.godot/story_previews/day1_scene01/" + filename + ".png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	_check(root.get_texture().get_image().save_png(path) == OK, "Capture " + filename)

func _run() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	_new_host(true)
	var director := _game.get_story_director()
	var manager := _game.get_dialogue_manager()
	var results: Array[bool] = []
	director.event_finished.connect(func(_id: String, ok: bool, reason: String) -> void:
		results.append(ok)
		_check(ok, "Trial execution: " + reason))
	_check(director.is_busy(), "F6 host automatically starts the scene")
	var deadline := Time.get_ticks_msec() + 20000
	var captured_background := false
	var captured_order := false
	var saw_locked := false
	while director.is_busy() and Time.get_ticks_msec() < deadline:
		if not _game.get_player().movement_enabled:
			saw_locked = true
		if manager.is_active():
			if not captured_background:
				await _snapshot("background")
				captured_background = true
			var customer := _game.get_actor_director().get_actor(&"customer")
			if customer != null and not captured_order:
				manager.advance()
				await _snapshot("order")
				captured_order = true
			manager.advance()
		await process_frame
	_check(not director.is_busy() and results == [true], "Full scene completes once")
	_check(saw_locked, "Automatic performance locks movement")
	_check(root.get_node("GameState").is_event_completed("day1.scene01"), "Successful ending records completion")
	_check(_game.get_player().movement_enabled, "Movement restored")
	_check(_game.get_camera_director().get_camera().mode == BoundedFollowCamera.Mode.FOLLOW, "Camera follows player again")
	_check(_game.get("_shop_interaction").is_input_enabled(), "Interaction restored")
	var customer := _game.get_actor_director().get_actor(&"customer")
	_check(customer != null, "Customer remains after the scene")
	if customer != null:
		_check(customer.global_position.distance_to(_game.get_active_level().to_global(Vector2(844, 550))) < 1.0, "Customer reaches order board")
		_check(customer.facing == PlayerController.Facing.UP, "Customer faces the player")
	_check(director.request_event("day1.scene01") == ERR_ALREADY_EXISTS, "Completed event cannot repeat")
	await _snapshot("finished")
	await _dispose()
	_new_host(false)
	director = _game.get_story_director()
	manager = _game.get_dialogue_manager()
	_check(director.request_event("day1.scene01") == OK, "Cancellation fixture starts")
	deadline = Time.get_ticks_msec() + 3000
	while not manager.is_active() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(manager.is_active(), "Cancellation occurs during real dialogue")
	_host.get_node("DemoLayer/Panel/Content/Cancel").pressed.emit()
	await _frames()
	_check(not director.is_busy() and not manager.is_active(), "Cancel ends story and dialogue")
	_check(_game.get_camera_director().get_camera().mode == BoundedFollowCamera.Mode.FOLLOW, "Cancel restores camera follow")
	_check(not root.get_node("GameState").is_event_completed("day1.scene01"), "Cancel does not consume once")
	_check(_game.get_player().movement_enabled and _game.get("_shop_interaction").is_input_enabled(), "Cancel restores controls")
	await _dispose()
	print("DAY1_SCENE01: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
