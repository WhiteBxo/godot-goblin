class_name TitleMenu
extends Control

@onready var _new_game: Button = $Center/Panel/Margin/Content/NewGame
@onready var _quit: Button = $Center/Panel/Margin/Content/Quit
@onready var _error: Label = $Center/Panel/Margin/Content/Error
var _starting := false

func _ready() -> void:
	DebugRuntime.apply_release_policy(get_tree())
	_new_game.pressed.connect(_request_new_game)
	_quit.pressed.connect(_request_quit)
	_new_game.grab_focus()

func _request_new_game() -> void:
	if _starting:
		return
	_set_busy(true)
	_error.hide()
	_start_new_game.call_deferred()

func _start_new_game() -> void:
	var error := GameEntry.start_new_game(get_tree())
	if error != OK:
		push_warning("New game navigation failed: %s" % error_string(error))
		_error.text = "正在处理上一项操作，请稍后重试。" if error == ERR_BUSY else "暂时无法开始游戏，请重试。"
		_error.show()
		_set_busy(false)
		_new_game.grab_focus()

func _request_quit() -> void:
	if _starting:
		return
	_set_busy(true)
	get_tree().quit.call_deferred()

func _set_busy(value: bool) -> void:
	_starting = value
	_new_game.disabled = value
	_quit.disabled = value
