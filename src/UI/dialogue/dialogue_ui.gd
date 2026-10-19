class_name DialogueUI
extends Control

signal advance_requested
signal choice_requested(index: int)
signal cancel_requested
## One signal per revealed character; the host owns the sound and its volume.
signal character_revealed(character: String)
## Emitted when Esc lands on a story-owned line: finish the remaining lines
## without cancelling the host event.
signal skip_requested

@export_range(1.0, 200.0) var characters_per_second: float = 32.0
@export_range(0.0, 0.5, 0.01) var comma_pause: float = 0.06
@export_range(0.0, 0.5, 0.01) var sentence_pause: float = 0.12
@export_range(0.0, 0.5, 0.01) var ellipsis_pause: float = 0.18
@export_range(0.0, 0.5, 0.01) var portrait_fade_seconds: float = 0.14
## Holding confirm for this long starts continuous fast-forward.
@export_range(0.1, 1.0, 0.05) var fast_forward_hold_seconds: float = 0.35
@export_range(0.02, 0.3, 0.01) var fast_forward_interval: float = 0.06

@onready var _speaker: Label = $Panel/Margin/Content/Speaker
@onready var _portrait: TextureRect = $Portrait
@onready var _text: RichTextLabel = $Panel/Margin/Content/Line/Text
@onready var _choice_scroll: ScrollContainer = $Panel/Margin/Content/ChoiceScroll
@onready var _choices: VBoxContainer = $Panel/Margin/Content/ChoiceScroll/Choices
@onready var _hint: Label = $Panel/Margin/Content/Hint

var _buttons: Array[Button] = []
var _selected: int = 0
var _reveal_remaining: float = 0.0
var _portrait_tween: Tween
var _revealing: bool = false
var _input_ready_frame: int = 0
var _previous_focus: Control
var _ui_manager: UIManager
var _screen_id: StringName
var _closing_dialogue := false
var _cancel_protected := false
var _auto_seconds := 0.0
var _auto_remaining := 0.0
var _hold_seconds := 0.0
var _hold_armed := true
var _fast_forward_remaining := 0.0

func bind_ui(manager: UIManager, id: StringName) -> void:
	_ui_manager = manager
	_screen_id = id

func on_ui_closed() -> void:
	if not _closing_dialogue:
		cancel_requested.emit()

func get_default_focus() -> Control:
	return _buttons[_selected] if not _revealing and not _buttons.is_empty() else null


func _ready() -> void:
	hide()


## Returns the reason the line could not be shown so the caller can end the
## dialogue instead of leaving its input lock on with no visible text.
func present_line(speaker: String, text: String, portrait: Texture2D, choices: Array[String], portrait_on_left: bool = false) -> Error:
	if is_instance_valid(_ui_manager):
		var open_error := _ui_manager.open_screen(_screen_id)
		if open_error != OK:
			return open_error
	elif not visible:
		_previous_focus = get_viewport().gui_get_focus_owner()
	var portrait_changed := not visible or _speaker.text != speaker or _portrait.texture != portrait
	_speaker.text = speaker
	set_portrait(portrait)
	if portrait_changed:
		_finish_portrait_fade()
		if portrait != null and portrait_fade_seconds > 0.0:
			_portrait.modulate.a = 0.0
			_portrait_tween = create_tween()
			_portrait_tween.tween_property(_portrait, "modulate:a", 1.0, portrait_fade_seconds)
	_portrait.offset_left = -268.0 if portrait_on_left else 28.0
	_portrait.offset_right = -28.0 if portrait_on_left else 268.0
	_text.text = text
	_text.visible_characters = 0
	_text.scroll_to_line(0)
	_reveal_remaining = 1.0 / characters_per_second
	_revealing = not text.is_empty()
	_auto_seconds = float(PlayerPreferences.get_values().dialogue_auto)
	_auto_remaining = 0.0
	_clear_choices()
	_selected = 0
	for index in range(choices.size()):
		var button := Button.new()
		button.text = choices[index]
		# The manager confirms a valid choice for both mouse and custom keyboard input.
		button.set_meta("ui_press_sound", "")
		button.custom_minimum_size.y = 24
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void: choice_requested.emit(index))
		button.focus_entered.connect(func() -> void: _selected = index)
		_choices.add_child(button)
		_buttons.append(button)
	_choice_scroll.hide()
	_update_hint()
	_input_ready_frame = Engine.get_process_frames() + 1
	show()
	if not _revealing:
		reveal_all()
	elif is_zero_approx(PlayerPreferences.get_values().dialogue_speed):
		reveal_all()
	return OK


## Change only the image; text reveal, choices, focus and placement stay intact.
func set_portrait(portrait: Texture2D) -> void:
	if _portrait.texture != portrait or portrait == null:
		_finish_portrait_fade()
	_portrait.texture = portrait
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if portrait is AtlasTexture else CanvasItem.TEXTURE_FILTER_LINEAR
	_portrait.visible = portrait != null


func is_revealing() -> bool:
	return _revealing


func reveal_all() -> void:
	_revealing = false
	_reveal_remaining = 0.0
	_finish_portrait_fade()
	_text.visible_characters = -1
	_choice_scroll.visible = not _buttons.is_empty()
	_update_hint()
	if not _buttons.is_empty():
		_buttons[_selected].grab_focus()


func close_dialogue() -> void:
	_closing_dialogue = true
	if is_instance_valid(_ui_manager):
		_ui_manager.close_screen(_screen_id)
	hide()
	set_portrait(null)
	_revealing = false
	_reveal_remaining = 0.0
	_auto_seconds = 0.0
	_auto_remaining = 0.0
	_hold_seconds = 0.0
	_fast_forward_remaining = 0.0
	_clear_choices()
	if not is_instance_valid(_ui_manager) and is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	_previous_focus = null
	_closing_dialogue = false


func _process(delta: float) -> void:
	if not visible or get_tree().paused:
		return
	if _revealing:
		_reveal(delta)
	_tick_fast_forward(delta)
	_tick_auto_advance(delta)


func _reveal(delta: float) -> void:
	var speed: float = PlayerPreferences.get_values().dialogue_speed
	if is_zero_approx(speed):
		reveal_all()
		return
	_reveal_remaining -= delta
	while _reveal_remaining <= 0.0 and _revealing:
		_text.visible_characters += 1
		if _text.visible_characters >= _text.get_total_character_count():
			reveal_all()
		else:
			var index := _text.visible_characters - 1
			if index >= 0 and index < _text.text.length():
				character_revealed.emit(_text.text[index])
			_reveal_remaining += (1.0 / characters_per_second + _punctuation_pause(_text.visible_characters - 1)) / speed


## Holding confirm keeps advancing; choices always wait for a deliberate key.
func _tick_fast_forward(delta: float) -> void:
	var held := Input.is_action_pressed("interact") or Input.is_action_pressed("ui_accept")
	if not held:
		_hold_seconds = 0.0
		_fast_forward_remaining = 0.0
		_hold_armed = true
		return
	if not _hold_armed:
		return
	_hold_seconds += delta
	if _hold_seconds < fast_forward_hold_seconds:
		return
	if not _revealing and not _buttons.is_empty():
		return
	_fast_forward_remaining -= delta
	if _fast_forward_remaining > 0.0:
		return
	_fast_forward_remaining = fast_forward_interval
	advance_requested.emit()


func _tick_auto_advance(delta: float) -> void:
	if _auto_seconds <= 0.0 or _revealing or not _buttons.is_empty():
		_auto_remaining = 0.0
		return
	if _hold_seconds > 0.0:
		return
	_auto_remaining += delta
	if _auto_remaining < _auto_seconds:
		return
	_auto_remaining = 0.0
	advance_requested.emit()


func _update_hint() -> void:
	var escape := "Esc 跳过本段" if _cancel_protected else "Esc 结束"
	if _revealing:
		_hint.text = "E / 空格 / Enter 显示全文 · " + escape
	elif not _buttons.is_empty():
		_hint.text = "↑↓ 选择 · E / 空格 / Enter 确认" + ("" if _cancel_protected else " · Esc 结束")
	elif _auto_seconds > 0.0:
		_hint.text = "E / 空格 / Enter 继续 · 自动 %.1f 秒 · %s" % [_auto_seconds, escape]
	else:
		_hint.text = "E / 空格 / Enter 继续 · 按住快进 · " + escape


func _punctuation_pause(index: int) -> float:
	var text := _text.text
	if _pause_for_character(text[index]) == 0.0 or _pause_for_character(text[index + 1]) > 0.0:
		return 0.0
	# Closing quotes and whitespace do not turn a line-ending mark into a pause.
	var suffix := text.substr(index + 1).strip_edges()
	while not suffix.is_empty() and suffix[0] in "”’\"'」』）】)]":
		suffix = suffix.substr(1).strip_edges()
	if suffix.is_empty():
		return 0.0
	var pause := 0.0
	while index >= 0 and _pause_for_character(text[index]) > 0.0:
		pause = maxf(pause, _pause_for_character(text[index]))
		index -= 1
	return pause


func _pause_for_character(character: String) -> float:
	if character in "，、,":
		return comma_pause
	if character in "。？！.!?":
		return sentence_pause
	if character == "…":
		return ellipsis_pause
	return 0.0


func _finish_portrait_fade() -> void:
	if _portrait_tween != null:
		_portrait_tween.kill()
		_portrait_tween = null
	_portrait.modulate.a = 1.0


func _exit_tree() -> void:
	if _portrait_tween != null:
		_portrait_tween.kill()


func _input(event: InputEvent) -> void:
	if is_instance_valid(_ui_manager):
		return
	handle_ui_input(event)

## Left click reveals or advances the current line. The dialogue body passes
## mouse input through to this Control; choice buttons keep their native press,
## and the debug layer above still receives its own buttons.
func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _revealing and not _buttons.is_empty():
		return
	if Engine.get_process_frames() < _input_ready_frame:
		return
	accept_event()
	_confirm()

func _confirm() -> void:
	if not _revealing and not _buttons.is_empty():
		choice_requested.emit(_selected)
	else:
		advance_requested.emit()


## Story-owned dialogue cannot be cancelled by Esc; it finishes its remaining
## lines instead so the host event still completes.
func set_cancel_protected(value: bool) -> void:
	_cancel_protected = value
	_update_hint()


func is_cancel_protected() -> bool:
	return _cancel_protected


## Modal-stack hook: true means this view handled Esc and must stay open.
func request_back() -> bool:
	if not visible or not _cancel_protected:
		return false
	skip_requested.emit()
	return true


func handle_ui_input(event: InputEvent) -> void:
	if not visible:
		return
	var confirm := event.is_action("interact") or event.is_action("ui_accept")
	var navigate := event.is_action("ui_up") or event.is_action("ui_down")
	var cancel := event.is_action("ui_cancel")
	if not (confirm or navigate or cancel):
		return
	# Consume before dispatch, including the final key: it cannot reopen a shop UI.
	get_viewport().set_input_as_handled()
	if not event.is_pressed() or event.is_echo() or Engine.get_process_frames() < _input_ready_frame:
		return
	if cancel:
		if _cancel_protected:
			skip_requested.emit()
		else:
			cancel_requested.emit()
	elif confirm:
		_confirm()
	elif not _revealing and not _buttons.is_empty():
		_selected = wrapi(_selected + (1 if event.is_action("ui_down") else -1), 0, _buttons.size())
		_buttons[_selected].grab_focus()


func _clear_choices() -> void:
	for button in _buttons:
		_choices.remove_child(button)
		button.queue_free()
	_buttons.clear()
