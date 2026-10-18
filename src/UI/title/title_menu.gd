class_name TitleMenu
extends Control

@onready var _new_game: Button = $Center/Panel/Margin/Content/NewGame
@onready var _quit: Button = $Center/Panel/Margin/Content/Quit
@onready var _error: Label = $Center/Panel/Margin/Content/Error
@onready var _music: TitleMusic = $TitleMusic
var _starting := false

func _ready() -> void:
	DebugRuntime.apply_release_policy(get_tree())
	var audio: AudioManager = preload("res://src/core/audio/audio_manager.tscn").instantiate()
	add_child(audio)
	var sounds: InteractionAudio = preload("res://src/core/audio/interaction_audio.tscn").instantiate()
	add_child(sounds)
	for message in sounds.configure(audio):
		push_warning(message)
	var feedback := UIAudioFeedback.new()
	add_child(feedback)
	feedback.configure(sounds.play_sound, [self])
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
	await _music.fade_out()
	var error := GameEntry.start_new_game(get_tree())
	if error != OK:
		_music.play_from_start()
		push_warning("New game navigation failed: %s" % error_string(error))
		_error.text = "正在处理上一项操作，请稍后重试。" if error == ERR_BUSY else "暂时无法开始游戏，请重试。"
		_error.show()
		_set_busy(false)
		_new_game.grab_focus()

func _request_quit() -> void:
	if _starting:
		return
	_set_busy(true)
	_quit_after_fade.call_deferred()

func _quit_after_fade() -> void:
	await _music.fade_out()
	get_tree().quit()

func _set_busy(value: bool) -> void:
	_starting = value
	_new_game.disabled = value
	_quit.disabled = value
