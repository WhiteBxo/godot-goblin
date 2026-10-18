class_name TitleMenu
extends Control

@onready var _new_game: Button = $Center/Panel/Margin/Content/NewGame
@onready var _continue: Button = $Center/Panel/Margin/Content/Continue
@onready var _quit: Button = $Center/Panel/Margin/Content/Quit
@onready var _error: Label = $Center/Panel/Margin/Content/Error
@onready var _music: TitleMusic = $TitleMusic
var _starting := false
var _confirming := false
var _can_continue := false
@onready var _confirmation: VBoxContainer = $Center/Panel/Margin/Content/Confirmation

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
	_continue.pressed.connect(_request_continue)
	_quit.pressed.connect(_request_quit)
	_confirmation.get_node("Confirm").pressed.connect(_confirm_new_game)
	_confirmation.get_node("Cancel").pressed.connect(_cancel_new_game)
	var store := GameEntry.create_save_store()
	var info := store.load_save(GameEntry.preflight_save)
	_can_continue = info.error == OK
	_continue.visible = _can_continue
	var notice := GameEntry.take_notice()
	if notice.is_empty() and store.has_files():
		notice = store.last_error
	if not notice.is_empty():
		_error.text = notice
		_error.show()
	(_continue if _can_continue else _new_game).grab_focus()

func _request_new_game() -> void:
	if _starting:
		return
	if GameEntry.create_save_store().has_files():
		_confirming = true
		_continue.hide()
		_new_game.hide()
		_quit.hide()
		_confirmation.show()
		_confirmation.get_node("Cancel").grab_focus()
		return
	_confirm_new_game()

func _confirm_new_game() -> void:
	if _starting:
		return
	_set_busy(true)
	_error.hide()
	_start_new_game.call_deferred()

func _cancel_new_game() -> void:
	_confirming = false
	_confirmation.hide()
	_continue.visible = _can_continue
	_new_game.show()
	_quit.show()
	(_continue if _can_continue else _new_game).grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if _confirming and not _starting and event.is_action_pressed("ui_cancel"):
		_cancel_new_game()
		get_viewport().set_input_as_handled()

func _request_continue() -> void:
	if _starting or _confirming or not _can_continue:
		return
	_set_busy(true)
	_error.hide()
	_continue_game.call_deferred()

func _continue_game() -> void:
	await _music.fade_out()
	var error := GameEntry.continue_game(get_tree())
	if error != OK:
		_navigation_failed(error, true)

func _navigation_failed(error: Error, continuing: bool = false) -> void:
	_music.play_from_start()
	push_warning("Entry navigation failed: %s" % error_string(error))
	_error.text = "正在处理上一项操作，请稍后重试。" if error == ERR_BUSY else ("存档无法恢复，原文件已保留。" if continuing else "暂时无法开始游戏，请重试。")
	_error.show()
	_set_busy(false)
	if _confirming:
		_cancel_new_game()
	else:
		(_continue if continuing else _new_game).grab_focus()

func _start_new_game() -> void:
	await _music.fade_out()
	var error := GameEntry.start_new_game(get_tree())
	if error != OK:
		_navigation_failed(error)

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
	_continue.disabled = value
	_quit.disabled = value
	_confirmation.get_node("Confirm").disabled = value
	_confirmation.get_node("Cancel").disabled = value
