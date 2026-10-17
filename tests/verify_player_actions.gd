extends SceneTree

var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)

func _frames(count: int = 2) -> void:
	for index in range(count):
		await physics_frame
	await process_frame

func _throw_key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F
	event.keycode = KEY_F
	event.unicode = 102
	event.pressed = pressed
	Input.parse_input_event(event)

func _run() -> void:
	for action: String in {"player_run": KEY_SHIFT, "player_sneak": KEY_CTRL, "player_throw": KEY_F}:
		var key := InputEventKey.new()
		key.physical_keycode = {"player_run": KEY_SHIFT, "player_sneak": KEY_CTRL, "player_throw": KEY_F}[action]
		_check(InputMap.action_has_event(action, key), "Physical binding: " + action)
	for path in ["res://src/gameplay/player/player.tscn", "res://src/gameplay/player/shop_player.tscn"]:
		var player: PlayerController = load(path).instantiate()
		root.add_child(player)
		await _frames()
		var sprite := player.animated_sprite
		var events := {"started": 0, "triggered": 0, "finished": 0, "cancelled": 0, "direction": Vector2.ZERO}
		player.action_started.connect(func(_action: StringName, _direction: Vector2) -> void: events.started += 1)
		player.action_triggered.connect(func(_action: StringName, direction: Vector2) -> void:
			events.triggered += 1
			events.direction = direction)
		player.action_finished.connect(func(_action: StringName, cancelled: bool) -> void:
			events.finished += 1
			if cancelled:
				events.cancelled += 1)
		for action: String in ["idle", "walk", "run", "sneak", "crouch_idle", "throw"]:
			for direction: String in ["down", "left", "right", "up"]:
				var animation := action + "_" + direction
				_check(sprite.sprite_frames.has_animation(animation), "Animation exists: " + animation)
				_check(sprite.sprite_frames.get_animation_loop(animation) == (action != "throw"), "Only throw is a one-shot: " + animation)
		Input.action_press("move_right")
		await _frames(20)
		_check(sprite.animation == &"walk_right", "Default input walks")
		Input.action_press("player_run")
		await _frames(20)
		_check(sprite.animation == &"run_right" and is_equal_approx(player.velocity.length(), player.speed * 1.6), "Shift runs at configured speed")
		Input.action_press("player_sneak")
		await _frames(20)
		_check(sprite.animation == &"sneak_right" and is_equal_approx(player.velocity.length(), player.speed * 0.5), "Ctrl sneaks, taking priority over Shift")
		Input.action_release("move_right")
		await _frames(20)
		_check(sprite.animation == &"crouch_idle_right", "Holding Ctrl at rest crouches")
		Input.action_release("player_run")
		Input.action_release("player_sneak")
		await _frames()
		_check(sprite.animation == &"idle_right", "Releasing modifiers restores standing idle")
		player.animation_speed = 4.0
		for direction in range(4):
			player.face_direction(direction)
			var before: int = events.triggered
			var ended: int = events.finished
			_check(player.request_action(&"throw"), "Four-facing throw starts")
			_check(not player.request_action(&"throw"), "Repeated action is rejected while busy")
			var position := player.position
			Input.action_press("move_right")
			await _frames(4)
			_check(player.position.is_equal_approx(position), "Throw holds position and facing")
			Input.action_release("move_right")
			await _frames(25)
			_check(events.triggered == before + 1 and events.direction == player.get_facing_vector(), "Exactly one release with the captured facing")
			_check(events.finished == ended + 1 and player.get_active_action().is_empty(), "Non-looping throw completes once")
			_check(String(sprite.animation).begins_with("idle_"), "Completion restores locomotion animation")
		_check(not player.request_action(&"unknown"), "Unsupported gameplay action is rejected")
		player.animation_speed = 1.0
		player.request_action(&"throw")
		var released_before: int = events.triggered
		player.set_movement_enabled(false)
		await _frames(60)
		_check(events.triggered == released_before and events.cancelled == 1, "Movement lock cancels before release")
		_check(not player.movement_enabled and not player.request_action(&"throw"), "Action completion never unlocks a modal lock")
		player.set_movement_enabled(true)
		player.request_action(&"throw")
		var owner := Node.new()
		root.add_child(owner)
		_check(player.claim_performance_control(owner), "Performance can take control during an action")
		_check(events.cancelled == 2 and not player.request_action(&"throw"), "Performance cancels and rejects player actions")
		Input.action_press("player_run")
		Input.action_press("player_sneak")
		await _frames()
		_check(player.locomotion_mode == PlayerController.Locomotion.WALK, "Performance ignores held stance input")
		player.release_performance_control(owner)
		Input.action_release("player_run")
		Input.action_release("player_sneak")
		owner.queue_free()
		player.request_action(&"throw")
		player.teleport_to(Vector2(10, 10))
		_check(player.get_active_action().is_empty() and events.cancelled == 3, "Teleport cancels action state")
		# Actual unhandled key events must respect NPC input opt-out and GUI consumption.
		player.accepts_player_input = false
		_throw_key(true)
		await _frames()
		_throw_key(false)
		_check(player.get_active_action().is_empty(), "NPC opt-out ignores the throw key")
		player.accepts_player_input = true
		var edit := LineEdit.new()
		root.add_child(edit)
		edit.grab_focus()
		_throw_key(true)
		await _frames()
		_throw_key(false)
		_check(player.get_active_action().is_empty(), "Focused text input consumes F without throwing")
		edit.queue_free()
		await _frames()
		_throw_key(true)
		await _frames()
		_throw_key(false)
		_check(player.get_active_action() == &"throw", "Unhandled F starts the action")
		player.cancel_action()
		player.queue_free()
		await process_frame
	print("PLAYER_ACTIONS: ", "PASS" if _failures.is_empty() else "FAIL", " (", _checks, " checks, two scenes, stances, four throws, cancellation, GUI and NPC boundaries)")
	quit(0 if _failures.is_empty() else 1)
