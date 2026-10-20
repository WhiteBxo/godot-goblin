class_name TouchControls
extends Control
## Floating stick and action pads for touch devices.
##
## The pads never call gameplay directly: they feed the same InputMap actions the
## keyboard uses, so movement, interaction, dialogue and menus keep one code path.
## Drag the left pad to move; tap the right pads to act.

## The HUD layout is authored against the 640x360 design resolution and then
## pinned to the closest physical edge, because phones are wider than 16:9.
const REFERENCE_SIZE := Vector2(640.0, 360.0)
const STICK_ORIGIN := Vector2(76.0, 288.0)
const STICK_RADIUS := 44.0
const STICK_HOT_RADIUS := 68.0
const STICK_KNOB_RADIUS := 20.0
const STICK_DEAD_ZONE := 0.16
## A pad accepts a touch slightly outside its rim so missed taps still land.
const PAD_HIT_SLOP := 6.0
## Top centre: the right edge belongs to the wallet, map and menu buttons, and
## the business HUD's balance line sits just below them. Kept as a small offset
## from the viewport centre so it stays centred on wider-than-16:9 screens.
const PAUSE_ORIGIN := Vector2(352.0, 26.0)
const PAUSE_RADIUS := 20.0
const PAUSE_ID := &"pause"
## While a dialogue locks movement the pad lifts above the text box, so it never
## covers the line the player is reading.
const DIALOGUE_INTERACT_ORIGIN := Vector2(600.0, 116.0)
## Pointer id used for the desktop playtest mouse; real touches are 0..n.
const MOUSE_POINTER := 999

## id, label, authored centre and radius in reference pixels.
const ACTION_PADS := [
	{"id": &"interact", "label": "交互", "origin": Vector2(578.0, 300.0), "radius": 33.0},
	{"id": &"throw", "label": "投掷", "origin": Vector2(578.0, 226.0), "radius": 25.0},
	{"id": &"run", "label": "跑", "origin": Vector2(516.0, 268.0), "radius": 25.0},
	{"id": &"sneak", "label": "蹲", "origin": Vector2(492.0, 322.0), "radius": 23.0},
]
const LOCOMOTION_PADS := [&"run", &"sneak"]
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]

var _stick_touch := -1
var _stick_vector := Vector2.ZERO
## touch index -> pad id, so lifting the right finger releases the right pad.
var _touches: Dictionary = {}
var _held_pads: Dictionary = {}
## Run and sneak latch on touch instead of requiring a held second finger.
var _toggled: Dictionary = {}
var _hidden_pads: Dictionary = {}
var _movement_available := true
var _blocked := false
var _accepts_mouse := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hidden_pads[&"throw"] = true
	# Mouse fallback exists only for desktop playtesting of this HUD; on a real
	# touch device the emulated mouse would double-fire every pad.
	_accepts_mouse = not DisplayServer.is_touchscreen_available()
	resized.connect(queue_redraw)


## Story scenes hide the throw pad until the stealth chapter needs it.
func set_action_available(id: StringName, available: bool) -> void:
	if available:
		_hidden_pads.erase(id)
	else:
		_hidden_pads[id] = true
	queue_redraw()


## Movement locks (dialogue, performances, scene travel) hide the stick and the
## locomotion pads while leaving the interact pad usable for dialogue advance.
func set_movement_available(available: bool) -> void:
	if _movement_available == available:
		return
	_movement_available = available
	if not available:
		_release_stick()
		_clear_locomotion()
	queue_redraw()


## Modals own the frame; the whole touch HUD steps aside instead of swallowing
## taps that belong to the popup underneath.
func set_blocked(blocked: bool) -> void:
	if _blocked == blocked:
		return
	_blocked = blocked
	if blocked:
		_release_all()
	visible = not blocked
	queue_redraw()


func is_blocked() -> bool:
	return _blocked


## Feeds one pointer sample. [param position] is local to this control, which
## keeps the touch maths identical for screen touches and desktop test clicks.
## Repeated presses for an active stick sample move the knob.
func apply_touch(index: int, position: Vector2, pressed: bool) -> void:
	if _blocked:
		return
	if not pressed:
		_release(index)
		return
	if index == _stick_touch:
		_update_stick(position)
		return
	_press(index, position)


## Screen-space (control-local) centre of the stick, for tests and automation.
func get_stick_center() -> Vector2:
	return _place(STICK_ORIGIN)


## Screen-space (control-local) centre of a pad; the pause pad is always there.
func get_pad_center(id: StringName) -> Vector2:
	if id == PAUSE_ID:
		return _place_centered(PAUSE_ORIGIN)
	for pad: Dictionary in ACTION_PADS:
		if pad.id == id:
			return _place(_pad_origin(pad))
	return Vector2.ZERO


## Interact moves above the text box while the dialogue owns the frame.
func _pad_origin(pad: Dictionary) -> Vector2:
	if pad.id == &"interact" and not _movement_available:
		return DIALOGUE_INTERACT_ORIGIN
	return pad.origin


func _input(event: InputEvent) -> void:
	if _blocked:
		return
	if event is InputEventScreenTouch:
		apply_touch(event.index, _to_local_point(event.position), event.pressed)
	elif event is InputEventScreenDrag:
		if event.index == _stick_touch:
			_update_stick(_to_local_point(event.position))
	elif _accepts_mouse and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		apply_touch(MOUSE_POINTER, _to_local_point(event.position), event.pressed)
	elif _accepts_mouse and event is InputEventMouseMotion and _stick_touch == MOUSE_POINTER:
		_update_stick(_to_local_point(event.position))


func _notification(what: int) -> void:
	# Android back is a cancel key, never an app kill.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_inject_action_key(&"ui_cancel", true)
		_inject_action_key(&"ui_cancel", false)


func _to_local_point(screen_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_position


func _press(index: int, position: Vector2) -> void:
	if position.distance_to(_place_centered(PAUSE_ORIGIN)) <= PAUSE_RADIUS + PAD_HIT_SLOP:
		_touches[index] = PAUSE_ID
		_held_pads[PAUSE_ID] = true
		_inject_action_key(&"pause_game", true)
		queue_redraw()
		return
	var pad := _pad_at(position)
	if not pad.is_empty():
		_touches[index] = pad.id
		_held_pads[pad.id] = true
		_on_pad_down(pad.id)
		queue_redraw()
		return
	if _stick_touch == -1 and _movement_available and position.distance_to(_place(STICK_ORIGIN)) <= STICK_HOT_RADIUS:
		_stick_touch = index
		_update_stick(position)


func _release(index: int) -> void:
	if index == _stick_touch:
		_release_stick()
	if not _touches.has(index):
		return
	var id: StringName = _touches[index]
	_touches.erase(index)
	_held_pads.erase(id)
	_on_pad_up(id)
	queue_redraw()


func _on_pad_down(id: StringName) -> void:
	match id:
		&"interact":
			_inject_action_key(&"interact", true)
		&"throw":
			_inject_action_key(&"player_throw", true)
		&"run":
			_toggle_locomotion(&"player_run", &"run", &"player_sneak", &"sneak")
		&"sneak":
			_toggle_locomotion(&"player_sneak", &"sneak", &"player_run", &"run")


func _on_pad_up(id: StringName) -> void:
	match id:
		&"interact":
			_inject_action_key(&"interact", false)
		&"throw":
			_inject_action_key(&"player_throw", false)
		PAUSE_ID:
			_inject_action_key(&"pause_game", false)


## Run and sneak are mutually exclusive, mirroring how two held keys resolve in
## the player controller's locomotion poll.
func _toggle_locomotion(action: StringName, id: StringName, other_action: StringName, other_id: StringName) -> void:
	var enabled := not bool(_toggled.get(id, false))
	_toggled[id] = enabled
	_toggled[other_id] = false
	Input.action_release(other_action)
	if enabled:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _update_stick(position: Vector2) -> void:
	var offset := position - _place(STICK_ORIGIN)
	var strength := clampf(offset.length() / STICK_RADIUS, 0.0, 1.0)
	_stick_vector = offset.normalized() * strength if strength > 0.0 else Vector2.ZERO
	_apply_stick()
	queue_redraw()


func _apply_stick() -> void:
	_set_axis(&"move_left", &"move_right", _stick_vector.x)
	_set_axis(&"move_up", &"move_down", _stick_vector.y)


func _set_axis(negative: StringName, positive: StringName, value: float) -> void:
	if value <= -STICK_DEAD_ZONE:
		Input.action_press(negative, clampf(absf(value), 0.0, 1.0))
		Input.action_release(positive)
	elif value >= STICK_DEAD_ZONE:
		Input.action_press(positive, clampf(value, 0.0, 1.0))
		Input.action_release(negative)
	else:
		Input.action_release(negative)
		Input.action_release(positive)


func _release_stick() -> void:
	_stick_touch = -1
	_stick_vector = Vector2.ZERO
	for action: StringName in MOVE_ACTIONS:
		Input.action_release(action)
	queue_redraw()


func _clear_locomotion() -> void:
	for id: StringName in LOCOMOTION_PADS:
		_toggled[id] = false
	for action: StringName in [&"player_run", &"player_sneak"]:
		Input.action_release(action)


func _release_all() -> void:
	_release_stick()
	for index: int in _touches.keys():
		if _held_pads.has(_touches[index]):
			_on_pad_up(_touches[index])
	_touches.clear()
	_held_pads.clear()
	_clear_locomotion()


## Replays the action's own authored key event, so device id, physical keycode
## and modifiers match InputMap exactly instead of being guessed here.
func _inject_action_key(action: StringName, pressed: bool) -> void:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := (event as InputEventKey).duplicate() as InputEventKey
			key.pressed = pressed
			key.echo = false
			Input.parse_input_event(key)
			# Parsed events sit in the buffer until the engine flushes them; a pad
			# tap must read as pressed on the same frame the finger lands.
			Input.flush_buffered_events()
			return


func _pad_at(position: Vector2) -> Dictionary:
	for pad: Dictionary in ACTION_PADS:
		if _hidden_pads.has(pad.id):
			continue
		# A movement lock leaves only the interact pad, which also advances dialogue.
		if not _movement_available and pad.id != &"interact":
			continue
		if position.distance_to(_place(_pad_origin(pad))) <= float(pad.radius) + PAD_HIT_SLOP:
			return pad
	return {}


## Authored position -> current control space, pinned to the nearest edge.
func _place(origin: Vector2) -> Vector2:
	var offset := Vector2.ZERO
	if origin.x > REFERENCE_SIZE.x * 0.5:
		offset.x = size.x - REFERENCE_SIZE.x
	if origin.y > REFERENCE_SIZE.y * 0.5:
		offset.y = size.y - REFERENCE_SIZE.y
	return origin + offset


## Authored position -> current control space, keeping its offset from the
## viewport centre. `expand` widens the viewport on non-16:9 screens, so a pad
## authored near the middle must follow the centre instead of the right edge.
func _place_centered(origin: Vector2) -> Vector2:
	var placed := _place(origin)
	placed.x = size.x * 0.5 + (origin.x - REFERENCE_SIZE.x * 0.5)
	return placed


func _is_pad_active(id: StringName) -> bool:
	if id in LOCOMOTION_PADS:
		return bool(_toggled.get(id, false))
	return _held_pads.has(id)


func _draw() -> void:
	if _blocked:
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var font_size := get_theme_default_font_size()
	if _movement_available:
		_draw_stick()
	for pad: Dictionary in ACTION_PADS:
		if _hidden_pads.has(pad.id):
			continue
		if not _movement_available and pad.id != &"interact":
			continue
		_draw_pad(_place(_pad_origin(pad)), pad.radius, pad.label, _is_pad_active(pad.id), font, font_size)
	_draw_pad(_place_centered(PAUSE_ORIGIN), PAUSE_RADIUS, "暂停", _held_pads.has(PAUSE_ID), font, font_size)


func _draw_stick() -> void:
	var center := _place(STICK_ORIGIN)
	draw_circle(center, STICK_RADIUS, UITokens.TOUCH_PAD, true, -1.0, true)
	draw_arc(center, STICK_RADIUS, 0.0, TAU, 40, UITokens.TOUCH_PAD_EDGE, 2.0, true)
	var knob := center + _stick_vector * STICK_RADIUS
	var active := not _stick_vector.is_zero_approx()
	draw_circle(knob, STICK_KNOB_RADIUS, UITokens.TOUCH_PAD_ACTIVE if active else UITokens.TOUCH_PAD, true, -1.0, true)
	draw_arc(knob, STICK_KNOB_RADIUS, 0.0, TAU, 28, UITokens.TOUCH_PAD_EDGE, 2.0, true)


func _draw_pad(center: Vector2, radius: float, label: String, active: bool, font: Font, font_size: int) -> void:
	draw_circle(center, radius, UITokens.TOUCH_PAD_ACTIVE if active else UITokens.TOUCH_PAD, true, -1.0, true)
	draw_arc(center, radius, 0.0, TAU, 36, UITokens.TOUCH_PAD_EDGE, 2.0, true)
	var color := UITokens.TOUCH_PAD_TEXT_ACTIVE if active else UITokens.TOUCH_PAD_TEXT
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var baseline := (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, center + Vector2(-text_size.x * 0.5, baseline), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
