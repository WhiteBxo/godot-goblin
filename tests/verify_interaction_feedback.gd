extends SceneTree

var _failures: Array[String] = []
var _checks := 0
var _successes := 0
var _changes := 0
var _demo: Node

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames(count: int = 3) -> void:
	for index in range(count):
		await physics_frame
		await process_frame
	await process_frame

func _event(pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.keycode = KEY_E
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)

func _run() -> void:
	_demo = load("res://src/debug/interaction/interaction_feedback_demo.tscn").instantiate()
	root.add_child(_demo)
	current_scene = _demo
	await _frames()
	var player: ShopPlayer = _demo.player
	var interaction: ShopInteraction = _demo.interaction
	var ui: ShopUI = _demo.ui
	var audio: AudioManager = _demo.audio
	var feedback: InteractionFeedback = _demo.feedback
	var points: Array[InteractionPoint] = _demo.points
	# 交互提示现在挂在物体上方（WorldPrompt）；底部那条只留数据不再重复显示。
	var prompt: WorldPrompt = _demo.world_prompt
	var bar: PromptBar = ui.get_node("Prompt")
	interaction.interaction_succeeded.connect(func(_point: InteractionPoint) -> void: _successes += 1)
	interaction.target_changed.connect(func(_point: InteractionPoint) -> void: _changes += 1)
	_check(interaction.get_target() == points[1] and prompt.is_prompt_visible() and not bar.visible, "Real Area2D detects initial target and moves the capsule, not the bottom bar")
	_check(prompt.get_key_label().text == "E" and prompt.get_action_text() == "打开仓库" and prompt.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Action capsule says verb and object without intercepting input")
	_check(bar.get_text() == "仓库", "Bottom bar still carries the plain name for hosts that read it")
	_check(prompt.get_text_label().get_theme_font_size("font_size") == 12, "Capsule uses native 12 px pixel font")
	player.position = Vector2(275, 220)
	player.facing = PlayerController.Facing.RIGHT
	await _frames()
	_check(interaction.get_target() == points[1], "Facing right selects right object at equal distance")
	var before_changes := _changes
	for index in range(12):
		player.position.x = 275 + (1 if index % 2 else -1)
		await _frames(1)
	_check(_changes == before_changes, "Boundary jitter does not switch target repeatedly")
	player.facing = PlayerController.Facing.LEFT
	await _frames()
	_check(interaction.get_target() == points[0], "Deliberate facing change overcomes hysteresis")
	for index in range(4):
		player.position = Vector2(60, 285)
		await _frames()
		_check(interaction.get_target() == null and not prompt.is_prompt_visible(), "Exit clears prompt each time")
		player.position = points[0].position + Vector2(0, 40)
		await _frames()
		_check(interaction.get_target() == points[0] and prompt.is_prompt_visible(), "Reentry restores prompt each time")
	interaction.set_input_enabled(false)
	_check(not prompt.is_prompt_visible() and interaction.get_target() == null, "Disable clears feedback synchronously")
	_event(true)
	await _frames()
	_check(_successes == 0 and not ui.is_open(), "Disabled input cannot interact")
	interaction.set_input_enabled(true)
	_event(true, true)
	await _frames()
	_check(_successes == 0, "Held/echo input across unlock does not trigger")
	_event(false)
	await _frames()
	_event(true)
	await _frames(1)
	_check(_successes == 1 and ui.is_open() and not prompt.is_prompt_visible(), "E opens unchanged popup once and hides focus")
	_check(audio.get_active_sound_count() == 1 and feedback._remaining > 0, "Accepted interaction emits visual pulse and optional AudioManager UI sound")
	_event(true, true)
	await _frames(1)
	_check(_successes == 1, "Echo cannot retrigger popup")
	ui.close()
	_event(true)
	await _frames(1)
	_check(_successes == 1 and not ui.is_open(), "Close while held requires a fresh press")
	_event(false)
	await _frames()
	points[0].interaction_enabled = false
	_check(interaction.get_target() != points[0], "Per-object disable clears selected object synchronously")
	points[0].interaction_enabled = true
	await _frames()
	_check(interaction.get_target() == points[0], "Reenable restores existing overlap without a second detector")
	paused = true
	_check(not prompt.is_prompt_visible() and interaction.get_target() == null, "Pause notification hides Always HUD immediately")
	_event(true)
	await _frames()
	_check(_successes == 1 and not ui.is_open(), "Paused E does nothing")
	paused = false
	_event(true, true)
	await _frames()
	_check(_successes == 1, "Unpause while held does not trigger")
	_event(false)
	await _frames()
	_check(prompt.is_prompt_visible(), "Unpause restores target")
	_check(_demo.dialogue.start_dialogue("demo.greeting") == OK, "Real dialogue starts")
	_check(not prompt.is_prompt_visible() and not interaction.is_input_enabled(), "Dialogue hides prompt synchronously")
	_event(true)
	await _frames(1)
	_check(_successes == 1, "Dialogue input does not leak into interaction")
	_event(false)
	_demo.dialogue.end_dialogue(true)
	await _frames()
	_check(prompt.is_prompt_visible() and player.movement_enabled, "Dialogue cancellation restores gameplay feedback")
	_check(_demo.story.request_event("feedback.wait") == OK, "Real story starts")
	_check(not prompt.is_prompt_visible() and not interaction.is_input_enabled(), "Story lock hides prompt before dispatch")
	_demo.story.cancel_event()
	await _frames()
	_check(prompt.is_prompt_visible() and interaction.is_input_enabled(), "Story cancellation restores feedback")
	var owner := RefCounted.new()
	player.claim_performance_control(owner)
	interaction.refresh_target()
	_check(not prompt.is_prompt_visible(), "Actor performance ownership suppresses target")
	player.release_performance_control(owner)
	await _frames()
	_check(prompt.is_prompt_visible(), "Releasing performance control restores target")
	# A consumed rejected route must not look or sound successful.
	interaction.configure(player, ui, points, func(_id: StringName) -> Error: return ERR_BUSY)
	points[0].interact()
	await _frames(1)
	_check(_successes == 1 and not ui.is_open(), "Rejected story route emits no success and does not open fallback")
	interaction.configure(player, ui, points, func(_id: StringName) -> Error: return ERR_DOES_NOT_EXIST)
	points[0].success_sound = "missing.optional"
	points[0].interact()
	await _frames(1)
	_check(_successes == 2 and ui.is_open(), "Missing optional sound does not block fallback interaction")
	ui.close()
	await _frames()
	# A handler may reenter interact synchronously; dispatch guard must stop it.
	interaction.configure(player, ui, points, func(_id: StringName) -> bool:
		points[0].interact()
		return true)
	points[0].sound_bus = "SFX"
	points[0].success_sound = "demo.ui"
	var count_before := audio.get_active_sound_count()
	points[0].interact()
	points[0].interact()
	_check(_successes == 3 and audio.get_active_sound_count() == count_before + 1, "Reentrant and same-frame duplicate dispatch emit once; SFX supported")
	interaction.configure(player, ui, points)
	await _frames()
	var removed := interaction.get_target()
	removed.queue_free()
	interaction.refresh_target()
	_check(interaction.get_target() != removed, "Queued deletion is rejected before next input")
	await _frames()
	_check(not prompt.is_prompt_visible(), "Freed target leaves no stale prompt or invalid reference")
	player.position = points[1].position
	await _frames()
	_check(interaction.get_target() == points[1], "Surviving object remains usable")
	player.queue_free()
	await _frames()
	_check(interaction.get_target() == null and not prompt.is_prompt_visible(), "Deleted player clears active target safely")
	_check(not points[1].is_available(), "Deleted body is pruned from overlap state")
	interaction.queue_free()
	await _frames()
	_check(not prompt.is_prompt_visible(), "Deleting controller clears its HUD")
	_check(feedback._focus == null and feedback._pulse == null, "Feedback safely retires deleted controller")
	_demo._reset_points()
	_demo.free()
	print("INTERACTION_FEEDBACK: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
