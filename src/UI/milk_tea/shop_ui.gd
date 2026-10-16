class_name ShopUI
extends Control
## HUD facade; the popup is a separate scene owned by its screen layer.

signal opened
signal closed
signal make_requested(recipe: Array[String])
var _production: TeaProduction

func configure_production(production: TeaProduction) -> void:
	_production = production
	if is_instance_valid(_popup):
		_popup.configure_production(production)
		_popup.make_requested.connect(func(recipe: Array[String]) -> void: make_requested.emit(recipe))

func show_production_result(result: Dictionary) -> void:
	if is_instance_valid(_popup):
		_popup.show_production_result(result)

@onready var _prompt: Label = $Prompt
var _popup: ShopPopup
var _manager: UIManager

func set_popup_layer(layer: CanvasLayer) -> void:
	if is_instance_valid(_popup):
		return
	_popup = preload("res://src/UI/milk_tea/shop_popup.tscn").instantiate()
	layer.add_child(_popup)
	_popup.close_requested.connect(close)
	if _production != null:
		_popup.configure_production(_production)
		_popup.make_requested.connect(func(recipe: Array[String]) -> void: make_requested.emit(recipe))

func bind_manager(manager: UIManager) -> void:
	_manager = manager
	_manager.register_screen(&"shop_hud", self, &"hud", false)
	_manager.open_screen(&"shop_hud")
	_manager.register_screen(&"shop", _popup, &"popup", true)
	_manager.screen_closed.connect(func(id: StringName) -> void:
		if id == &"shop":
			closed.emit())

func bind_tea_making(tea: TeaMaking) -> void:
	_popup.bind_tea_making(tea)
	tea.configure(func() -> bool:
		return is_open() and _popup.is_making_station() and _popup.can_process()
		)

func show_prompt(point: InteractionPoint) -> void:
	_prompt.text = "[E] " + point.display_name if point != null else ""
	_prompt.visible = point != null and not is_open()

func open(point: InteractionPoint) -> void:
	if not is_instance_valid(_popup):
		return
	if is_instance_valid(_manager):
		if _manager.open_screen(&"shop") != OK:
			return
	else:
		_popup.show()
		_popup.get_default_focus().grab_focus()
	_popup.present(point)
	_prompt.hide()
	opened.emit()

func close() -> void:
	if not is_open():
		return
	if is_instance_valid(_manager):
		_manager.close_screen(&"shop")
	else:
		_popup.hide()
		closed.emit()

func is_open() -> bool:
	return is_instance_valid(_popup) and _popup.visible

func _input(event: InputEvent) -> void:
	if not is_instance_valid(_manager) and is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if is_instance_valid(_popup) and not _popup.is_queued_for_deletion():
		_popup.queue_free()
