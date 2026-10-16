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

func _run() -> void:
	var expected_keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
	}
	for action: String in expected_keys:
		for key: int in expected_keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			_check(InputMap.action_has_event(action, event), "%s must bind %s" % [action, key])
	for path in ["res://src/gameplay/player/player.tscn", "res://src/gameplay/player/shop_player.tscn"]:
		var player: PlayerController = load(path).instantiate()
		root.add_child(player)
		await _frames(2)
		_check(player.motion_mode == CharacterBody2D.MOTION_MODE_FLOATING, "Player uses top-down motion")
		_check(player.collision_layer == 2 and player.collision_mask == 1, "Player detects existing walls and interaction areas")
		var sprite := player.animated_sprite
		for direction in ["down", "left", "right", "up"]:
			_check(sprite.sprite_frames.get_frame_count("idle_" + direction) == 1, "One neutral idle frame: " + direction)
			_check(sprite.sprite_frames.get_frame_count("run_" + direction) == 16, "Sixteen-frame run cycle: " + direction)
		var directions := {"down": "move_down", "left": "move_left", "right": "move_right", "up": "move_up"}
		for direction: String in directions:
			Input.action_press(directions[direction])
			await _frames(1)
			_check(player.velocity.length() > 0.0 and player.velocity.length() < player.speed, "Movement accelerates smoothly")
			_check(sprite.speed_scale < player.animation_speed, "Step cadence slows down during acceleration")
			await _frames(20)
			_check(is_equal_approx(player.velocity.length(), player.speed), "Cardinal reaches configured speed")
			_check(sprite.animation == StringName("run_" + direction), "Movement selects facing animation: " + direction)
			var progress_before := sprite.frame + sprite.frame_progress
			await _frames(4)
			_check(not is_equal_approx(sprite.frame + sprite.frame_progress, progress_before), "Run animation advances")
			Input.action_release(directions[direction])
			await _frames(1)
			_check(player.velocity.length() > 0.0 and player.velocity.length() < player.speed, "Releasing input decelerates smoothly")
			await _frames(20)
			_check(player.velocity.is_zero_approx(), "Releasing input comes to a full stop")
			_check(sprite.animation == StringName("idle_" + direction), "Idle retains the last facing: " + direction)
		for horizontal in ["move_left", "move_right"]:
			for vertical in ["move_up", "move_down"]:
				Input.action_press(horizontal)
				Input.action_press(vertical)
				await _frames(20)
				_check(is_equal_approx(player.velocity.length(), player.speed), "Every diagonal has normalized speed")
				var animation_before := sprite.animation
				await _frames(10)
				_check(sprite.animation == animation_before, "Diagonal facing is stable")
				Input.action_release(horizontal)
				Input.action_release(vertical)
				await _frames(20)
		Input.action_press("move_right")
		await _frames(10)
		sprite.set_frame_and_progress(5, 0.3)
		Input.action_release("move_right")
		Input.action_press("move_up")
		await _frames(1)
		_check(sprite.animation == &"run_up" and sprite.frame >= 5, "Turning keeps the current step phase")
		Input.action_release("move_up")
		Input.action_press("move_right")
		await _frames(1)
		player.set_movement_enabled(false)
		var locked_position := player.global_position
		await _frames(10)
		_check(player.global_position.is_equal_approx(locked_position) and player.velocity.is_zero_approx(), "Movement lock stops immediately")
		_check(sprite.animation == &"idle_right", "Movement lock selects idle")
		Input.action_release("move_right")
		player.set_movement_enabled(true)
		player.queue_free()
		await process_frame
	# The cave still enforces its optional query at maximum developer speed.
	var cave: CavePlayer = load("res://src/gameplay/player/player.tscn").instantiate()
	root.add_child(cave)
	cave.configure(func(point: Vector2, half_size: Vector2) -> bool: return point.x + half_size.x <= 40.0)
	cave.set_speed_multiplier(8.0)
	Input.action_press("move_right")
	await _frames(90)
	_check(cave.position.x <= 33.0 and cave.position.x > 25.0, "Cave query blocks high-speed movement at the footprint")
	_check(cave.animated_sprite.animation == &"idle_right", "Pushing a blocked wall returns to idle")
	Input.action_release("move_right")
	cave.queue_free()
	await process_frame
	print("PLAYER: ", "PASS" if _failures.is_empty() else "FAIL", " (two scenes, eight directions, smoothing, facing, animations, movement lock, cave query)")
	quit(0 if _failures.is_empty() else 1)
