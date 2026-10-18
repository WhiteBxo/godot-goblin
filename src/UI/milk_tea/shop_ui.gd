class_name ShopUI
extends Control
## HUD facade; the popup is a separate scene owned by its screen layer.

signal point_opened(id: StringName)
signal opened
signal closed
signal craft_requested(materials: Array[String], quantity: int)
signal accept_requested(order_id: String)
signal track_requested(order_id: String)
signal formula_requested(materials: Array[String], iced: bool)
var _production: TeaProduction
var _inventory: WarehouseInventory
var _orders: OrderBoardModel
var _prompt_point: InteractionPoint

func get_popup() -> ShopPopup:
	return _popup

func configure_inventory(inventory: WarehouseInventory) -> void:
	_inventory = inventory
	if is_instance_valid(_popup):
		_popup.configure_inventory(inventory)

func configure_production(production: TeaProduction) -> void:
	_production = production
	if is_instance_valid(_popup):
		_popup.configure_production(production)

func configure_orders(model: OrderBoardModel) -> void:
	if is_instance_valid(_orders) and _orders.changed.is_connected(_refresh_order_prompt):
		_orders.changed.disconnect(_refresh_order_prompt)
	_orders = model
	_orders.changed.connect(_refresh_order_prompt)
	_popup.configure_orders(model)

func show_feedback(message: String, succeeded: bool = true) -> void:
	$Feedback/Panel/Text.text = message
	$Feedback/Panel/Text.theme_type_variation = &"Success" if succeeded else &"Warning"
	$Feedback.visible = not message.is_empty()
	$FeedbackTimer.start()

func get_feedback_text() -> String:
	return $Feedback/Panel/Text.text if $Feedback.visible else ""

func get_prompt_text() -> String:
	return _prompt.get_text()

func show_order_requirements(message: String) -> void:
	if is_instance_valid(_popup):
		_popup.show_order_requirements(message)

func show_interaction_result(message: String) -> void:
	if is_instance_valid(_popup):
		_popup.show_interaction_result(message)

func show_production_result(result: Dictionary) -> void:
	if is_instance_valid(_popup):
		_popup.show_production_result(result)

func select_formula(materials: Array, iced := false) -> bool:
	return is_instance_valid(_popup) and _popup.select_formula(materials, iced)

func show_formula_result(result: Dictionary) -> void:
	_popup.show_formula_result(result)

@export var help_text := "小小奶茶店 · WASD 移动 · E 交互 · Esc / P 暂停"
@export var show_help := true
@export var close_text := "返回店铺  [Esc]"

@onready var _prompt: PromptBar = $Prompt
var _popup: ShopPopup
var _manager: UIManager

func _ready() -> void:
	$Header.text = help_text
	$Header.visible = show_help
	$FeedbackTimer.timeout.connect(func() -> void: $Feedback.hide())

func set_popup_layer(layer: CanvasLayer) -> void:
	if is_instance_valid(_popup):
		return
	_popup = preload("res://src/UI/milk_tea/shop_popup.tscn").instantiate()
	layer.add_child(_popup)
	_popup.get_shell().get_close_button().text = close_text
	_popup.close_requested.connect(close)
	_popup.craft_requested.connect(func(materials: Array[String], quantity: int) -> void: craft_requested.emit(materials, quantity))
	_popup.accept_requested.connect(func(id: String) -> void: accept_requested.emit(id))
	_popup.track_requested.connect(func(id: String) -> void: track_requested.emit(id))
	_popup.formula_requested.connect(formula_requested.emit)
	if _inventory != null:
		_popup.configure_inventory(_inventory)
	if _production != null:
		_popup.configure_production(_production)

func bind_manager(manager: UIManager) -> void:
	_manager = manager
	_manager.register_screen(ScreenIds.SHOP_HUD, self, &"hud", false)
	_manager.open_screen(ScreenIds.SHOP_HUD)
	_manager.register_screen(ScreenIds.SHOP, _popup, &"popup", true)
	_manager.screen_closed.connect(func(id: StringName) -> void:
		if id == ScreenIds.SHOP:
			closed.emit())

func bind_tea_making(tea: TeaMaking) -> void:
	_popup.bind_tea_making(tea)
	tea.configure(func() -> bool:
		return is_open() and _popup.is_making_station() and _popup.can_process()
		)

func show_prompt(point: InteractionPoint) -> void:
	_prompt_point = point
	if point == null or is_open():
		_prompt.clear()
	else:
		var text := point.display_name
		if is_instance_valid(_orders):
			var tracked := _orders.get_tracked_entry()
			if tracked.get("target_id") == String(point.interaction_id) and tracked.get("ready", false):
				text = "交付 · " + tracked.title
			else:
				for entry: Dictionary in _orders.get_entries():
					if entry.status == "active" and entry.ready and entry.target_id == String(point.interaction_id):
						text = "交付 · " + entry.title
						break
		_prompt.show_prompt(text)

func _refresh_order_prompt() -> void:
	show_prompt(_prompt_point if is_instance_valid(_prompt_point) else null)

func open(point: InteractionPoint) -> void:
	if not is_instance_valid(_popup):
		return
	if is_instance_valid(_manager):
		if _manager.open_screen(ScreenIds.SHOP) != OK:
			return
	else:
		_popup.show()
		_popup.get_default_focus().grab_focus()
	_popup.present(point)
	$Feedback.hide()
	point_opened.emit(point.interaction_id)
	_focus_popup.call_deferred()
	_prompt.clear()
	opened.emit()

func _focus_popup() -> void:
	if not is_inside_tree() or not is_open():
		return
	var focus := _popup.get_default_focus()
	if is_instance_valid(focus) and focus.is_inside_tree() and focus.is_visible_in_tree():
		focus.grab_focus()

func close() -> void:
	if not is_open():
		return
	if is_instance_valid(_manager):
		_manager.close_screen(ScreenIds.SHOP)
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
