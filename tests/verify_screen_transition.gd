extends SceneTree

const SCENE := preload("res://src/UI/screen_transition/screen_transition.tscn")
var _checks := 0
var _failures: Array[String] = []
var _completed: Array[TransitionAction] = []
var _cancelled: Array[TransitionAction] = []
var _layer: CanvasLayer
var _screen: ScreenTransition

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)
		push_error(message)

func _frames(count: int = 3) -> void:
	for i in range(count):
		await process_frame

func _wait(action: TransitionAction) -> void:
	for i in range(180):
		if action.is_finished():
			break
		await process_frame
	_check(action.is_finished(), "Request settles within deadline: " + action.effect)
	await _frames()

func _run() -> void:
	var probe := root.get_node_or_null("MCPRuntimeProbe")
	if probe != null:
		probe.process_mode = Node.PROCESS_MODE_DISABLED
	_layer = CanvasLayer.new()
	_layer.layer = 40
	root.add_child(_layer)
	_screen = SCENE.instantiate()
	_layer.add_child(_screen)
	_screen.completed.connect(func(action: TransitionAction) -> void: _completed.append(action))
	_screen.cancelled.connect(func(action: TransitionAction) -> void: _cancelled.append(action))
	await _frames()
	_check(not _screen.is_busy() and _screen.get_node("Black").color.a == 0.0, "Initially transparent and idle")
	for control: Control in [_screen] + _screen.get_children():
		_check(control.mouse_filter == Control.MOUSE_FILTER_IGNORE and control.focus_mode == Control.FOCUS_NONE, "Visual controls do not consume input")
	var black := _screen.fade_out(0.12)
	await _frames(3)
	_check(_screen.get_node("Black").color.a > 0.0 and _screen.get_node("Black").color.a < 1.0, "Black opacity interpolates")
	await _wait(black)
	_check(black.result == TransitionAction.Result.COMPLETED and _screen.get_node("Black").color.a == 1.0, "Fade out retains black")
	var reveal := _screen.fade_in(0.08)
	await _wait(reveal)
	_check(_screen.get_node("Black").color.a == 0.0, "Fade in reveals image")
	black = _screen.fade_out(2.0)
	await _frames(3)
	var before: float = _screen.get_node("Black").color.a
	reveal = _screen.fade_in(0.06)
	_check(black.result == TransitionAction.Result.CANCELLED and _screen.get_node("Black").color.a == before, "Replacement cancels and continues from current opacity")
	await _wait(reveal)
	black = _screen.fade_out(0.0)
	var seen: Array[TransitionAction] = []
	black.finished.connect(func(action: TransitionAction) -> void: seen.append(action), CONNECT_ONE_SHOT)
	_check(_screen.get_node("Black").color.a == 1.0, "Zero duration applies visual immediately")
	await _frames()
	_check(seen == [black] and _completed.count(black) == 1, "Zero duration can be awaited after API return, exactly once")
	var flash := _screen.flash_white(0.08)
	var bars := _screen.letterbox(true, 0.08, 0.15)
	_check(_screen.get_node("White").color.a == 1.0, "Flash starts fully white")
	await _wait(flash)
	await _wait(bars)
	_check(_screen.get_node("White").color.a == 0.0 and _screen.get_node("Black").color.a == 1.0, "Flash clears independently over retained black")
	_check(is_equal_approx(_screen.get_node("TopBar").anchor_bottom, 0.15) and is_equal_approx(_screen.get_node("BottomBar").anchor_top, 0.85), "Symmetric relative-height bars")
	var hide := _screen.letterbox(false, 0.0)
	await _wait(hide)
	_check(_screen.get_node("TopBar").size.y == 0.0 and _screen.get_node("BottomBar").size.y == 0.0, "Bars hide completely")
	# Resize the actual viewport and confirm anchors cover it.
	root.size = Vector2i(900, 540)
	await _frames()
	_check(_screen.size == root.get_visible_rect().size and _screen.get_node("Black").size == _screen.size, "Overlay follows viewport resize")
	bars = _screen.letterbox(true, 0.0, 0.2)
	await _wait(bars)
	_check(is_equal_approx(_screen.get_node("TopBar").size.y, _screen.size.y * 0.2), "Bars follow resized viewport")
	paused = true
	Engine.time_scale = 0.0
	reveal = _screen.fade_in(0.06)
	flash = _screen.flash_white(0.06)
	bars = _screen.letterbox(false, 0.06)
	await _wait(reveal)
	await _wait(flash)
	await _wait(bars)
	_check(reveal.result == TransitionAction.Result.COMPLETED and flash.result == TransitionAction.Result.COMPLETED and bars.result == TransitionAction.Result.COMPLETED and paused, "All channels complete during pause and zero time scale without changing pause")
	paused = false
	Engine.time_scale = 1.0
	black = _screen.fade_out(2.0)
	for invalid: TransitionAction in [_screen.fade_in(-1.0), _screen.flash_white(NAN), _screen.letterbox(true, INF), _screen.letterbox(true, 0.0, 0.6), _screen.letterbox(false, 0.0, NAN)]:
		_check(invalid.result == TransitionAction.Result.FAILED, "Reject invalid parameters")
	_check(not black.is_finished(), "Invalid requests preserve active action")
	_screen.cancel(black)
	_check(black.result == TransitionAction.Result.CANCELLED and _screen.get_node("Black").color.a == 0.0, "Targeted cancel clears channel")
	_screen.cancel(black)
	_check(_cancelled.count(black) == 1, "Cancel is idempotent")
	black = _screen.fade_out(0.0)
	reveal = _screen.fade_in(0.0)
	await _wait(reveal)
	_check(black.result == TransitionAction.Result.CANCELLED and _completed.count(black) == 0, "Stale deferred completion cannot finish a replaced action")
	flash = _screen.flash_white(2.0)
	var old_bars := _screen.letterbox(true, 2.0)
	bars = _screen.letterbox(false, 0.0)
	var new_flash := _screen.flash_white(0.0)
	await _wait(bars)
	await _wait(new_flash)
	_check(old_bars.result == TransitionAction.Result.CANCELLED and flash.result == TransitionAction.Result.CANCELLED, "Flash and bars replace only their own channels")
	black = _screen.fade_out(2.0)
	flash = _screen.flash_white(2.0)
	bars = _screen.letterbox(true, 2.0)
	_screen.cancel_all()
	_screen.cancel_all()
	await _frames()
	_check(not _screen.is_busy() and _cancelled.count(black) == 1 and _cancelled.count(flash) == 1 and _cancelled.count(bars) == 1, "Cancel all settles every channel exactly once")
	black = _screen.fade_out(2.0)
	flash = _screen.flash_white(2.0)
	bars = _screen.letterbox(true, 2.0)
	var exited := _screen
	_layer.remove_child(exited)
	_check(black.result == TransitionAction.Result.CANCELLED and flash.result == TransitionAction.Result.CANCELLED and bars.result == TransitionAction.Result.CANCELLED, "Tree removal cancels all pending actions synchronously")
	_check(_cancelled.count(black) == 1 and exited.fade_in().result == TransitionAction.Result.FAILED, "Exit emits cancellation and rejects new work")
	_layer.add_child(exited)
	await _wait(exited.fade_out(0.0))
	_check(exited.get_node("Black").color.a == 1.0, "Removed node can be reattached and reused")
	black = exited.fade_in(2.0)
	var terminal: Array[TransitionAction] = []
	black.finished.connect(func(action: TransitionAction) -> void: terminal.append(action), CONNECT_ONE_SHOT)
	exited.queue_free()
	await _frames()
	_check(terminal == [black] and black.result == TransitionAction.Result.CANCELLED, "Action handle settles even when visual owner is freed")
	var reentrant: ScreenTransition = SCENE.instantiate()
	_layer.add_child(reentrant)
	var pending_black := reentrant.fade_out(2.0)
	var pending_bars := reentrant.letterbox(true, 2.0)
	var removed := [false]
	reentrant.cancelled.connect(func(_action: TransitionAction) -> void:
		if not removed[0]:
			removed[0] = true
			_layer.remove_child(reentrant))
	var abandoned := reentrant.fade_in(0.1)
	_check(pending_black.result == TransitionAction.Result.CANCELLED and pending_bars.result == TransitionAction.Result.CANCELLED and abandoned.result == TransitionAction.Result.CANCELLED, "Signal-triggered exit settles other channels and replacement")
	reentrant.free()
	# Exercise real standalone F6 host without loading production MainGame.
	var demo: Node = load("res://src/debug/screen_transition/screen_transition_demo.tscn").instantiate()
	root.add_child(demo)
	await _frames()
	_screen = demo.get_node("TransitionLayer/ScreenTransition")
	_check(demo.get_node("TransitionLayer").layer == 40 and not demo.get_node("TransitionLayer").follow_viewport_enabled, "Demo reuses TransitionLayer contract")
	await _wait(_screen.fade_out(0.0))
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png("/private/tmp/screen-transition-black.png")
		_check(image.get_pixel(int(image.get_width() * 0.85), int(image.get_height() * 0.5)) == Color.BLACK, "Rendered black covers background")
	await _wait(_screen.fade_in(0.0))
	await _wait(_screen.letterbox(true, 0.0))
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png("/private/tmp/screen-transition-bars.png")
		var x := int(image.get_width() * 0.85)
		_check(image.get_pixel(x, 2) == Color.BLACK and image.get_pixel(x, image.get_height() - 3) == Color.BLACK and image.get_pixel(x, int(image.get_height() * 0.5)) != Color.BLACK, "Rendered bars cover top and bottom, leaving center visible")
		flash = _screen.flash_white(1.0)
		await RenderingServer.frame_post_draw
		image = root.get_texture().get_image()
		image.save_png("/private/tmp/screen-transition-white.png")
		var pixel := image.get_pixel(x, int(image.get_height() * 0.5))
		_check(pixel.r > 0.9 and pixel.g > 0.9 and pixel.b > 0.9, "Rendered flash covers background with white")
	black = _screen.fade_out(2.0)
	demo._rebuild()
	_check(black.result == TransitionAction.Result.CANCELLED, "Demo rebuild settles old module")
	demo.queue_free()
	_layer.queue_free()
	await _frames()
	print("ScreenTransition: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
