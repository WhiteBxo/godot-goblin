extends Node
## F6-only harness, no production scene or story dependencies.

const TRANSITION := preload("res://src/UI/screen_transition/screen_transition.tscn")
var _transition: ScreenTransition
var _layer: CanvasLayer
var _status: Label
var _clock: Label
var _elapsed := 0.0

func _ready() -> void:
	if not OS.has_feature("debug"):
		set_process(false)
		return
	# Keep third-party runtime polling out of this standalone demo.
	var probe := get_node_or_null("/root/MCPRuntimeProbe")
	if probe != null:
		probe.process_mode = Node.PROCESS_MODE_DISABLED
	var backdrop := CanvasLayer.new()
	backdrop.layer = 10
	add_child(backdrop)
	var background := ColorRect.new()
	background.color = Color("244b64")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(background)
	var text := Label.new()
	text.text = "SCREEN TRANSITION\n独立视觉背景 · 黑场遮住这里\nDebug 面板位于转场层之上"
	text.add_theme_font_override("font", preload("res://assets/fonts/fusion_pixel/fusion-pixel-12px-monospaced-zh_hans.otf.woff2"))
	text.add_theme_font_size_override("font_size", 12)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(text)
	_layer = CanvasLayer.new()
	_layer.name = "TransitionLayer"
	_layer.layer = 40
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_layer.follow_viewport_enabled = false
	add_child(_layer)
	_rebuild()
	var debug := CanvasLayer.new()
	debug.layer = 50
	add_child(debug)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	var theme := Theme.new()
	theme.default_font = preload("res://assets/fonts/fusion_pixel/fusion-pixel-12px-monospaced-zh_hans.otf.woff2")
	theme.default_font_size = 12
	panel.theme = theme
	debug.add_child(panel)
	var content := VBoxContainer.new()
	panel.add_child(content)
	var title := Label.new()
	title.text = "ScreenTransition · F6 独立 Demo · 时长单位：秒"
	content.add_child(title)
	var effects := HBoxContainer.new()
	content.add_child(effects)
	_button(effects, "黑场 1s", func() -> void: _transition.fade_out(1.0))
	_button(effects, "揭幕 1s", func() -> void: _transition.fade_in(1.0))
	_button(effects, "闪白", func() -> void: _transition.flash_white(0.4))
	_button(effects, "零时长黑场", func() -> void: _transition.fade_out(0.0))
	var bars := HBoxContainer.new()
	content.add_child(bars)
	_button(bars, "打开遮幕", func() -> void: _transition.letterbox(true))
	_button(bars, "关闭遮幕", func() -> void: _transition.letterbox(false))
	_button(bars, "替换请求", func() -> void:
		_transition.fade_out(2.0)
		_transition.fade_in(0.8))
	var lifecycle := HBoxContainer.new()
	content.add_child(lifecycle)
	_button(lifecycle, "暂停 / 恢复", func() -> void: get_tree().paused = not get_tree().paused)
	_button(lifecycle, "取消 / 清屏", func() -> void: _transition.cancel_all())
	_button(lifecycle, "退出 / 重建模块", _rebuild)
	_status = Label.new()
	_status.text = "就绪 · 暂停时按钮和转场仍然工作"
	content.add_child(_status)
	_clock = Label.new()
	content.add_child(_clock)

func _process(delta: float) -> void:
	_elapsed += delta
	if _clock != null:
		_clock.text = "Demo %.1fs · paused=%s · busy=%s" % [_elapsed, get_tree().paused, _transition.is_busy()]

func _exit_tree() -> void:
	if OS.has_feature("debug"):
		get_tree().paused = false

func _rebuild() -> void:
	if is_instance_valid(_transition):
		_layer.remove_child(_transition)
		_transition.queue_free()
	_transition = TRANSITION.instantiate()
	_layer.add_child(_transition)
	_transition.completed.connect(func(action: TransitionAction) -> void: _report(action))
	_transition.cancelled.connect(func(action: TransitionAction) -> void: _report(action))

func _report(action: TransitionAction) -> void:
	if _status != null:
		_status.text = "#%d %s · %s · %s" % [action.id, action.effect, TransitionAction.Result.keys()[action.result], action.reason]

func _button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
