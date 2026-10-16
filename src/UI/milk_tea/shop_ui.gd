class_name ShopUI
extends Control

signal closed
signal make_requested(recipe: Array[String])

var _production: TeaProduction
var _production_panel: TeaProductionPanel

func configure_production(production: TeaProduction) -> void:
	_production = production
	_production_panel = TeaProductionPanel.new()
	_production_panel.name = "ProductionPanel"
	var content := _close.get_parent()
	content.add_child(_production_panel)
	content.move_child(_production_panel, _close.get_index())
	_production_panel.configure(production)
	_production_panel.make_requested.connect(func(recipe: Array[String]) -> void: make_requested.emit(recipe))
	_production_panel.hide()

func show_production_result(result: Dictionary) -> void:
	_production_panel.show_result(result)

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
	_modal.theme = theme
	_modal.reparent(layer)

func open(point: InteractionPoint) -> void:
	_title.text = point.display_name
	_description.text = point.description
	if _production != null:
		var crafting := point.interaction_id == &"tea_station"
		_production_panel.visible = crafting
		_description.visible = not crafting
		if crafting:
			_production_panel.refresh(true)
		elif point.interaction_id == &"orders":
			_description.text = _production.get_order_text() + "\n\n到制作台选择对应原料，完成后自动交付。"
		elif point.interaction_id == &"storage":
			var lines := PackedStringArray(["店铺原有食材 · 库存（份）"])
			for ingredient in _production.get_ingredients():
				lines.append("%s  %d" % [ingredient.name, _production.get_stock(ingredient.id)])
			_description.text = "\n".join(lines)
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
