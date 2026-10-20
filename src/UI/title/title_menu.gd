class_name TitleMenu
extends Control

@onready var _new_game: Button = $Center/Panel/Margin/Content/NewGame
@onready var _continue: Button = $Center/Panel/Margin/Content/Continue
@onready var _quit: Button = $Center/Panel/Margin/Content/Quit
@onready var _error: Label = $Center/Panel/Margin/Content/Error
@onready var _music: TitleMusic = $TitleMusic
@onready var _panel: PanelContainer = $Center/Panel
@onready var _backdrop: TextureRect = $Backdrop
var _starting := false
var _confirming := false
var _can_continue := false
var _settings: Control
var _saves: SaveSlotsPanel
var _selected_slot := ""
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
	var motion := UIButtonMotion.new()
	motion.name = "UIButtonMotion"
	add_child(motion)
	motion.configure([self])
	_apply_platform_layout()
	_new_game.pressed.connect(_request_new_game)
	_continue.pressed.connect(_request_continue)
	_quit.pressed.connect(_request_quit)
	_settings = preload("res://src/UI/settings/settings_panel.tscn").instantiate()
	add_child(_settings)
	_settings.hide()
	$Center/Panel/Margin/Content/Settings.pressed.connect(func() -> void:
		if _starting:
			return
		$Center.hide()
		_settings.show()
		_settings.get_default_focus().grab_focus())
	_settings.dismissed.connect(func() -> void:
		$Center.show()
		$Center/Panel/Margin/Content/Settings.grab_focus())
	_saves = preload("res://src/UI/saves/save_slots_panel.tscn").instantiate()
	add_child(_saves)
	_saves.hide()
	$Center/Panel/Margin/Content/LoadGame.pressed.connect(func() -> void:
		if _starting:
			return
		$Center.hide()
		_saves.open_mode(false)
		_saves.show()
		_saves.get_default_focus().grab_focus())
	_saves.dismissed.connect(func() -> void:
		$Center.show()
		$Center/Panel/Margin/Content/LoadGame.grab_focus())
	_saves.load_requested.connect(func(slot_id: String) -> void:
		_selected_slot = slot_id
		_saves.hide()
		$Center.show()
		_set_busy(true)
		_continue_game.call_deferred())
	_confirmation.get_node("Confirm").pressed.connect(_confirm_new_game)
	_confirmation.get_node("Cancel").pressed.connect(_cancel_new_game)
	var library := GameEntry.create_save_library()
	var newest := library.newest_valid_id(GameEntry.preflight_save)
	var store := GameEntry.create_save_store(newest if not newest.is_empty() else "auto")
	var info := store.load_save(GameEntry.preflight_save)
	_can_continue = info.error == OK
	_continue.visible = _can_continue
	var notice := GameEntry.take_notice()
	if notice.is_empty() and store.has_files():
		notice = store.last_error
	if not notice.is_empty():
		_error.text = notice
		_error.show()
	_apply_primary()
	(_continue if _can_continue else _new_game).grab_focus()
	_start_presentation()
	get_viewport().size_changed.connect(_recenter_pivot)

func _recenter_pivot() -> void:
	_backdrop.pivot_offset = _backdrop.size * 0.5
	if _panel.size != Vector2.ZERO:
		_panel.pivot_offset = _panel.size * 0.5

## Phone builds drop desktop-only affordances: the shell owns app exit, key
## hints would name keys that do not exist, and the save list must be draggable.
func _apply_platform_layout() -> void:
	if not MobileSupport.is_touch_ui():
		return
	var scroll := TouchScroll.new()
	scroll.name = "TouchScroll"
	add_child(scroll)
	scroll.configure([self])
	_quit.visible = false
	$Center/Panel/Margin/Content/Keys.visible = false

## Exactly one gold button: the action a returning player wants first.
func _apply_primary() -> void:
	_continue.theme_type_variation = &"PrimaryButton" if _can_continue else &""
	_new_game.theme_type_variation = &"" if _can_continue else &"PrimaryButton"

## The menu settles in over a slowly breathing shop; nothing pops in hard.
func _start_presentation() -> void:
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.96, 0.96)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_panel.pivot_offset = _panel.size * 0.5
	_backdrop.pivot_offset = _backdrop.size * 0.5
	var enter := create_tween().set_parallel(true)
	enter.tween_property(_panel, "modulate:a", 1.0, 0.22).set_delay(0.05)
	enter.tween_property(_panel, "scale", Vector2.ONE, 0.34).set_delay(0.05).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var drift := create_tween().set_loops()
	drift.tween_property(_backdrop, "scale", Vector2(1.15, 1.15), 16.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drift.tween_property(_backdrop, "scale", Vector2(1.12, 1.12), 16.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _request_new_game() -> void:
	if _starting:
		return
	if GameEntry.create_save_library().has_files():
		_confirming = true
		_continue.hide()
		_new_game.hide()
		_quit.hide()
		$Center/Panel/Margin/Content/Settings.hide()
		$Center/Panel/Margin/Content/LoadGame.hide()
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
	$Center/Panel/Margin/Content/Settings.show()
	$Center/Panel/Margin/Content/LoadGame.show()
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
	_selected_slot = ""
	_continue_game.call_deferred()

func _continue_game() -> void:
	await _music.fade_out()
	var error := GameEntry.continue_game(get_tree(), _selected_slot)
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
	$Center/Panel/Margin/Content/Settings.disabled = value
	$Center/Panel/Margin/Content/LoadGame.disabled = value
	_confirmation.get_node("Confirm").disabled = value
	_confirmation.get_node("Cancel").disabled = value
