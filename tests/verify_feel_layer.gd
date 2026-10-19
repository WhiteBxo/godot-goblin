extends SceneTree
## Focused checks for the feel layer that existing module tests do not cover:
## modal open animation, camera look-ahead, dialogue character ticks and the
## threat overlay pulse.

var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

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

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	await _modal_open_animation()
	await _camera_look_ahead()
	await _dialogue_character_ticks()
	await _threat_overlay_pulse()
	print("FEEL_LAYER: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _modal_open_animation() -> void:
	var shell: ModalShell = load("res://src/UI/components/modal_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	shell.hide()
	await process_frame
	shell.show()
	await process_frame
	_check(shell._panel.modulate.a < 1.0, "Modal panel starts transparent when shown")
	await _frames(14)
	_check(is_equal_approx(shell._panel.modulate.a, 1.0) and shell._panel.scale.is_equal_approx(Vector2.ONE), "Modal panel settles fully visible without a stale scale")
	shell.hide()
	await process_frame
	_check(is_equal_approx(shell._panel.modulate.a, 1.0), "Hiding resets the panel alpha for the next open")
	shell.queue_free()
	await process_frame

func _camera_look_ahead() -> void:
	var player: FloorAwareShopPlayer = load("res://src/gameplay/player/rpg_player.tscn").instantiate()
	root.add_child(player)
	await process_frame
	var camera: BoundedFollowCamera = player.get_node("Camera2D")
	camera.configure(Rect2(-2000, -2000, 4000, 4000))
	player.set_physics_process(false)
	player.velocity = Vector2(120, 0)
	await _frames(20)
	_check(camera.get_follow_position().x > player.global_position.x + 4.0, "RPG follow camera leads in the movement direction")
	player.velocity = Vector2.ZERO
	await _frames(40)
	_check(absf(camera.get_follow_position().x - player.global_position.x) < 1.0, "Stopping removes the look-ahead offset")
	player.queue_free()
	await process_frame

func _dialogue_character_ticks() -> void:
	var ui: DialogueUI = load("res://src/UI/dialogue/dialogue_ui.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	var seen: Array[String] = []
	ui.character_revealed.connect(func(character: String) -> void: seen.append(character))
	ui.characters_per_second = 200.0
	ui.present_line("测试", "abc，def", null, [])
	await _frames(12)
	_check(seen.size() >= 5, "Typewriter emits one character signal per revealed character")
	_check("，" in seen, "The panel emits punctuation too; throttling stays with the host")
	ui.close_dialogue()
	ui.queue_free()
	await process_frame

func _threat_overlay_pulse() -> void:
	var overlay: ThreatOverlay = load("res://src/UI/hud/threat_overlay.tscn").instantiate()
	root.add_child(overlay)
	await process_frame
	overlay.configure(null)
	_check(overlay.get_vignette_alpha() == 0.0 and overlay._vignette.texture != null, "Threat overlay idles clear with a radial texture ready")
	overlay.pulse()
	await _frames(3)
	_check(overlay._flash.color.a > 0.01, "Discovery pulse flashes the screen")
	await _frames(20)
	_check(overlay._flash.color.a < 0.01, "Discovery flash fades back to clear")
	overlay.queue_free()
	await process_frame
