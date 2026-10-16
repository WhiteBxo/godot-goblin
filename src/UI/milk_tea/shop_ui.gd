class_name ShopUI
extends Control

signal closed

@onready var _modal: Control = $Modal
@onready var _prompt: Label = $Prompt
@onready var _title: Label = $Modal/Center/Panel/Margin/Content/Title
@onready var _description: Label = $Modal/Center/Panel/Margin/Content/Description
@onready var _close: Button = $Modal/Center/Panel/Margin/Content/Close

func _ready() -> void:
	_close.pressed.connect(close)

func show_prompt(point: InteractionPoint) -> void:
	_prompt.text = "[E] " + point.display_name if point != null else ""
	_prompt.visible = point != null and not is_open()

func set_popup_layer(layer: CanvasLayer) -> void:
	_modal.reparent(layer)

func open(point: InteractionPoint) -> void:
	_title.text = point.display_name
	_description.text = point.description
	_modal.show()
	_prompt.hide()
	_close.grab_focus()

func close() -> void:
	if not is_open():
		return
	_modal.hide()
	closed.emit()

func is_open() -> bool:
	return _modal.visible

func _input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
