extends Node2D

const PLAYER_SCENE := preload("res://src/gameplay/player/shop_player.tscn")
var _status: Label
var _player: PlayerController

func _ready() -> void:
	if not OS.has_feature("debug"):
		return
	var preview_theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	preview_theme.default_font = font
	var player: PlayerController = PLAYER_SCENE.instantiate()
	_player = player
	add_child(player)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.theme = preview_theme
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(panel)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(text)
	var help := Label.new()
	help.text = "WASD / 方向键：走路   Shift：奔跑\nCtrl：蹲伏 / 潜行   F：投掷\nP：锁定 / 解锁移动（中断动作）"
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(help)
	_status = Label.new()
	_status.text = "动作预览：按 F 观察开始、出手、结束信号"
	text.add_child(_status)
	player.action_started.connect(func(action: StringName, _direction: Vector2) -> void:
		_status.text = "%s：动作开始" % action)
	player.action_triggered.connect(func(action: StringName, direction: Vector2) -> void:
		_status.text = "%s：出手朝向 %s（后续玩法接口）" % [action, direction])
	player.action_finished.connect(func(action: StringName, cancelled: bool) -> void:
		_status.text = "%s：%s" % [action, "已取消" if cancelled else "已完成"])

func _unhandled_input(event: InputEvent) -> void:
	if not OS.has_feature("debug"):
		return
	if event.is_action_pressed(&"pause_game"):
		var player := _player
		player.set_movement_enabled(not player.movement_enabled)
		_status.text = "允许移动：%s" % player.movement_enabled
		get_viewport().set_input_as_handled()

func _draw() -> void:
	draw_rect(Rect2(-4096, -4096, 8192, 8192), Color("39434e"))
	for index in range(-64, 65):
		var coordinate := index * 64.0
		draw_line(Vector2(-4096, coordinate), Vector2(4096, coordinate), Color("465463"))
		draw_line(Vector2(coordinate, -4096), Vector2(coordinate, 4096), Color("465463"))
