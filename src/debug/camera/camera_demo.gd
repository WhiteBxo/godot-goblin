extends Node
## Repeatable debug-only sequence. Never injected into the production entry point.

var _game: MainGame
var _director: CameraDirector
var _entrance: Marker2D
var _status: Label
var _timer: Timer
var _running := false
var _phase := 0
var _expected: CameraAction

func _ready() -> void:
	if not OS.has_feature("debug"):
		return
	_timer = Timer.new()
	_timer.one_shot = true
	add_child(_timer)
	_timer.timeout.connect(_return_to_player)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 40)
	panel.size.x = 624
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = preload("res://assets/fonts/fusion_pixel/fusion-pixel-12px-monospaced-zh_hans.otf.woff2")
	theme.default_font_size = 12
	panel.theme = theme
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035, 0.045, 0.065, 0.94)
	background.content_margin_left = 6.0
	background.content_margin_right = 6.0
	background.content_margin_top = 4.0
	background.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", background)
	layer.add_child(panel)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)
	var hint := Label.new()
	hint.text = "Camera Demo · WASD 移动 · 聚焦入口 → 停留 0.5s → 回到玩家 → 轻震 → 跟随"
	content.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(buttons)
	for item in [["播放 / 重播", _start], ["取消 / 重置", _cancel], ["删除聚焦目标", _delete_target], ["退出 / 重建场景", _rebuild], ["开关震动", _toggle_shake]]:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(item[1])
		buttons.add_child(button)
	_status = Label.new()
	content.add_child(_status)
	_rebuild()

func _rebuild() -> void:
	_cancel()
	if is_instance_valid(_game):
		remove_child(_game)
		_game.queue_free()
	_game = preload("res://src/debug/story/legacy_shop.tscn").instantiate()
	add_child(_game)
	_director = _game.get_camera_director()
	_director.action_finished.connect(_on_finished)
	_director.camera_recovered.connect(func(reason: String) -> void: _running = false; _timer.stop(); _status.text = reason)
	_entrance = null
	_status.text = "正常跟随；可移动后播放。退出 / 重建可在任何动作期间触发。"

func _start() -> void:
	_cancel()
	if not is_instance_valid(_entrance):
		_entrance = Marker2D.new()
		_entrance.name = "ShopEntrance"
		_game.get_active_level().add_child(_entrance)
		_entrance.position = Vector2(1500, 240)
	_running = true
	_phase = 0
	_status.text = "聚焦右上方入口……"
	_expected = _director.camera_focus(_entrance, 1.2)

func _on_finished(action: CameraAction) -> void:
	if not _running or action != _expected:
		return
	if action.result != CameraAction.Result.COMPLETED:
		_running = false
		_timer.stop()
		_status.text = "%s · %s" % [CameraAction.Result.keys()[action.result], action.reason]
		return
	match _phase:
		0:
			_phase = 1
			_status.text = "停留 0.5 秒（可删除目标 / 取消）"
			_timer.start(0.5)
		2:
			_phase = 3
			_status.text = "轻微震动；HUD 和此面板保持固定"
			_expected = _director.camera_shake()
		3:
			_phase = 4
			_expected = _director.camera_follow(0.0)
		4:
			_running = false
			_status.text = "完成 · 恢复默认跟随，可再次播放"

func _return_to_player() -> void:
	if _running:
		_phase = 2
		_status.text = "平滑回到玩家……"
		_expected = _director.camera_follow(1.0)

func _cancel() -> void:
	_running = false
	if is_instance_valid(_timer):
		_timer.stop()
	if is_instance_valid(_director):
		_director.camera_reset()
	if is_instance_valid(_status):
		_status.text = "已取消 · 恢复默认跟随 / 缩放 / 偏移"

func _delete_target() -> void:
	if is_instance_valid(_entrance):
		_entrance.queue_free()

func _toggle_shake() -> void:
	_director.shake_enabled = not _director.shake_enabled
	_status.text = "屏幕震动：" + ("开" if _director.shake_enabled else "关")

func _exit_tree() -> void:
	_cancel()
