class_name DialogueUI
extends Control

signal advance_requested
signal choice_requested(index: int)
signal cancel_requested

@export_range(1.0, 200.0) var characters_per_second: float = 32.0

@onready var _speaker: Label = $Panel/Margin/Content/Speaker
@onready var _portrait: TextureRect = $Portrait
@onready var _text: RichTextLabel = $Panel/Margin/Content/Line/Text
@onready var _choice_scroll: ScrollContainer = $Panel/Margin/Content/ChoiceScroll
@onready var _choices: VBoxContainer = $Panel/Margin/Content/ChoiceScroll/Choices
@onready var _hint: Label = $Panel/Margin/Content/Hint

var _buttons: Array[Button] = []
var _selected: int = 0
var _characters: float = 0.0
var _revealing: bool = false
var _input_ready_frame: int = 0
var _previous_focus: Control
var _ui_manager: UIManager
var _screen_id: StringName
var _closing_dialogue := false

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


func present_line(speaker: String, text: String, portrait: Texture2D, choices: Array[String], portrait_on_left: bool = false) -> void:
	if is_instance_valid(_ui_manager):
		if _ui_manager.open_screen(_screen_id) != OK:
			return
	elif not visible:
		_previous_focus = get_viewport().gui_get_focus_owner()
	_speaker.text = speaker
	set_portrait(portrait)
	_portrait.offset_left = -268.0 if portrait_on_left else 28.0
	_portrait.offset_right = -28.0 if portrait_on_left else 268.0
	_text.text = text
	_text.visible_characters = 0
	_text.scroll_to_line(0)
	_characters = 0.0
	_revealing = not text.is_empty()
	_clear_choices()
	_selected = 0
	for index in range(choices.size()):
		var button := Button.new()
		button.text = choices[index]
		button.custom_minimum_size.y = 24
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void: choice_requested.emit(index))
		button.focus_entered.connect(func() -> void: _selected = index)
		_choices.add_child(button)
		_buttons.append(button)
	_choice_scroll.hide()
	_hint.text = "E / 空格 / Enter 显示全文 · Esc 结束"
	_input_ready_frame = Engine.get_process_frames() + 1
	show()
	if not _revealing:
		reveal_all()


## Change only the image; text reveal, choices, focus and placement stay intact.
func set_portrait(portrait: Texture2D) -> void:
	_portrait.texture = portrait
	_portrait.visible = portrait != null


func is_revealing() -> bool:
	return _revealing


func reveal_all() -> void:
	_revealing = false
	_text.visible_characters = -1
	_choice_scroll.visible = not _buttons.is_empty()
	_hint.text = "↑↓ 选择 · E / 空格 / Enter 确认 · Esc 结束" if not _buttons.is_empty() else "E / 空格 / Enter 继续 · Esc 结束"
	if not _buttons.is_empty():
		_buttons[_selected].grab_focus()


func close_dialogue() -> void:
	_closing_dialogue = true
	if is_instance_valid(_ui_manager):
		_ui_manager.close_screen(_screen_id)
	hide()
	set_portrait(null)
	_revealing = false
	_clear_choices()
	if not is_instance_valid(_ui_manager) and is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	_previous_focus = null
	_closing_dialogue = false


func _process(delta: float) -> void:
	if not visible or not _revealing:
		return
	_characters += delta * characters_per_second
	_text.visible_characters = int(_characters)
	if _text.visible_characters >= _text.get_total_character_count():
		reveal_all()


func _input(event: InputEvent) -> void:
	if is_instance_valid(_ui_manager):
		return
	handle_ui_input(event)

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
		cancel_requested.emit()
	elif confirm:
		if not _revealing and not _buttons.is_empty():
			choice_requested.emit(_selected)
		else:
			advance_requested.emit()
	elif not _revealing and not _buttons.is_empty():
		_selected = wrapi(_selected + (1 if event.is_action("ui_down") else -1), 0, _buttons.size())
		_buttons[_selected].grab_focus()


func _clear_choices() -> void:
	for button in _buttons:
		_choices.remove_child(button)
		button.queue_free()
	_buttons.clear()
