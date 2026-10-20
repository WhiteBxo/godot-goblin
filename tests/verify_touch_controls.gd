extends SceneTree
## Touch HUD contract: pads feed the same InputMap actions the keyboard uses,
## and a blocked HUD never steals a tap from the modal underneath.

var checks := 0
var failures: Array[String] = []
var controls: TouchControls


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)


func _tap(index: int, position: Vector2) -> void:
	controls.apply_touch(index, position, true)
	controls.apply_touch(index, position, false)
	await process_frame


func _clear_actions() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down",
			&"player_run", &"player_sneak", &"interact", &"player_throw", &"pause_game"]:
		Input.action_release(action)


func _run() -> void:
	var scene: PackedScene = load("res://src/UI/touch/touch_controls.tscn")
	check(scene != null, "Touch controls scene loads")
	if scene == null:
		quit(1)
		return
	controls = scene.instantiate()
	root.add_child(controls)
	await process_frame

	check(controls.size.x >= 320.0 and controls.size.y >= 180.0, "Touch controls cover the viewport")
	check(controls.get_theme_default_font() != null, "Touch controls use the shared theme font")
	check(controls.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Touch HUD lets taps reach the HUD beneath it")

	# --- Stick feeds the movement axes ---
	var stick := controls.get_stick_center()
	controls.apply_touch(0, stick, true)
	controls.apply_touch(0, stick + Vector2(-70.0, 0.0), true)
	check(Input.is_action_pressed("move_left"), "Stick left presses move_left")
	check(not Input.is_action_pressed("move_right"), "Stick left does not press move_right")
	controls.apply_touch(0, stick + Vector2(70.0, 0.0), true)
	check(Input.is_action_pressed("move_right"), "Dragging across the stick reverses the axis")
	controls.apply_touch(0, stick, false)
	check(not Input.is_action_pressed("move_left") and not Input.is_action_pressed("move_right"),
		"Releasing the stick clears movement")
	controls.apply_touch(1, stick + Vector2(0.0, -60.0), true)
	check(Input.is_action_pressed("move_up"), "Stick up presses move_up")
	controls.apply_touch(1, stick, false)
	_clear_actions()

	# --- Action pads drive real actions ---
	await _tap(2, controls.get_pad_center(&"interact"))
	check(not Input.is_action_pressed("interact"), "Interact pad releases after the tap")
	controls.apply_touch(3, controls.get_pad_center(&"interact"), true)
	await process_frame
	check(Input.is_action_pressed("interact"), "Interact pad presses the interact action")
	controls.apply_touch(3, controls.get_pad_center(&"interact"), false)
	await process_frame
	check(not Input.is_action_pressed("interact"), "Lifting the finger releases interact")
	_clear_actions()

	controls.apply_touch(4, controls.get_pad_center(&"run"), true)
	controls.apply_touch(4, controls.get_pad_center(&"run"), false)
	check(Input.is_action_pressed("player_run"), "Run pad latches on")
	controls.apply_touch(5, controls.get_pad_center(&"sneak"), true)
	controls.apply_touch(5, controls.get_pad_center(&"sneak"), false)
	check(Input.is_action_pressed("player_sneak"), "Sneak pad latches on")
	check(not Input.is_action_pressed("player_run"), "Sneak releases run")
	controls.apply_touch(6, controls.get_pad_center(&"sneak"), true)
	controls.apply_touch(6, controls.get_pad_center(&"sneak"), false)
	check(not Input.is_action_pressed("player_sneak"), "Tapping sneak again latches it off")
	_clear_actions()

	# --- Throw only exists where the chapter needs it ---
	var throw_center := controls.get_pad_center(&"throw")
	controls.apply_touch(7, throw_center, true)
	await process_frame
	check(not Input.is_action_pressed("player_throw"), "Throw pad is inactive outside the stealth chapter")
	controls.apply_touch(7, throw_center, false)
	controls.set_action_available(&"throw", true)
	controls.apply_touch(8, throw_center, true)
	await process_frame
	check(Input.is_action_pressed("player_throw"), "Throw pad works once the chapter enables it")
	controls.apply_touch(8, throw_center, false)
	await process_frame
	_clear_actions()

	# --- Pause is always reachable, modals still win ---
	controls.apply_touch(9, controls.get_pad_center(TouchControls.PAUSE_ID), true)
	await process_frame
	check(Input.is_action_pressed("pause_game"), "Pause pad presses pause_game")
	controls.apply_touch(9, controls.get_pad_center(TouchControls.PAUSE_ID), false)
	await process_frame
	_clear_actions()

	controls.set_blocked(true)
	check(not controls.visible, "Blocked touch HUD hides itself")
	controls.apply_touch(10, controls.get_pad_center(&"interact"), true)
	await process_frame
	check(not Input.is_action_pressed("interact"), "Blocked touch HUD ignores pads")
	controls.set_blocked(false)
	check(controls.visible, "Unblocking restores the touch HUD")

	# --- Movement locks keep the interact pad usable for dialogue advance ---
	controls.set_movement_available(false)
	controls.apply_touch(11, controls.get_stick_center(), true)
	controls.apply_touch(11, controls.get_stick_center() + Vector2(-70.0, 0.0), true)
	check(not Input.is_action_pressed("move_left"), "Locked movement ignores the stick")
	controls.apply_touch(11, controls.get_stick_center(), false)
	controls.set_movement_available(true)

	print("TOUCH_CONTROLS: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
