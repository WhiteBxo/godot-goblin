class_name OrderCraftingPage
extends HBoxContainer
## Confirm the current shared shortfall; the production service commits the batch.

signal craft_requested(materials: Array[String], quantity: int)
signal track_requested(order_id: String)
signal return_requested
signal deliver_requested(order_id: String)

@onready var _list: OrderList = %OrderList
@onready var _ticket: OrderTicket = %Ticket
var _model: OrderBoardModel
var _ids: Array[String] = []
var _selected := ""
var _last_result: Dictionary = {}
var _submitting := false

func _ready() -> void:
	_list.selection_requested.connect(func(id: String) -> void:
		if id in _ids:
			_selected = id
			track_requested.emit(_selected)
			refresh())
	_ticket.primary_pressed.connect(_on_primary_pressed)
	refresh()

func configure(model: OrderBoardModel) -> void:
	if is_instance_valid(_model) and _model.changed.is_connected(refresh):
		_model.changed.disconnect(refresh)
	_model = model
	_model.changed.connect(refresh)
	refresh()

func present() -> void:
	_selected = str(_model.get_tracked_entry().get("order_id", ""))
	refresh()

func refresh() -> void:
	if not is_node_ready():
		return
	var scroll := _list.get_v_scroll_bar().value
	_ids.clear()
	var filtered: Array[Dictionary] = []
	if is_instance_valid(_model):
		for entry: Dictionary in _model.get_entries():
			if entry.status == "active" and not entry.product_id.is_empty():
				_ids.append(entry.order_id)
				filtered.append(entry)
	if _selected not in _ids:
		_selected = _ids[0] if not _ids.is_empty() else ""
	_list.set_entries(filtered, _selected)
	_list.get_v_scroll_bar().set_deferred("value", scroll)
	_refresh_detail()

func _refresh_detail() -> void:
	var entry := _model.get_entry(_selected) if is_instance_valid(_model) else {}
	var action := "制作 1 杯并入库"
	if int(entry.get("craft_quantity", 0)) > 1:
		action = "按缺口制作 %d 杯并入库" % int(entry.craft_quantity)
	if entry.is_empty():
		entry = {"title": "先接取一张饮品订单", "target_name": "订单板", "status_text": "暂无制作目标",
			"stage": "empty", "status": "empty", "product_id": "", "items": [], "missing_text": "",
			"rewards": "—", "hint": "也可以切换到已知配方或自由实验。"}
	elif entry.ready and entry.get("remaining_to_craft", 0) == 0:
		action = "立即交付"
		entry.hint = "成品已齐备，可立即交给%s" % entry.target_name
	var can_return := bool(entry.get("ready", false)) and int(entry.get("remaining_to_craft", 0)) == 0
	_ticket.present(entry, action, bool(entry.get("can_craft", false)) or can_return)

func _on_primary_pressed() -> void:
	var entry := _model.get_entry(_selected) if is_instance_valid(_model) else {}
	if entry.get("status") == "active" and entry.get("ready", false) and entry.get("remaining_to_craft", 0) == 0:
		track_requested.emit(_selected)
		deliver_requested.emit(_selected)
	else:
		submit()

func submit() -> Dictionary:
	_last_result = {}
	var entry := _model.get_entry(_selected) if is_instance_valid(_model) else {}
	if _submitting or not entry.get("can_craft", false):
		return {"ok": false, "message": "请核对当前订单和库存。"}
	_submitting = true
	var materials: Array[String] = []
	materials.assign(entry.recipe_materials)
	craft_requested.emit(materials, int(entry.craft_quantity))
	_submitting = false
	return _last_result.duplicate(true)

func show_result(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	refresh()
	if is_visible_in_tree():
		_ticket.show_result(result)

func select_order(order_id: String) -> bool:
	if order_id not in _ids:
		return false
	_selected = order_id
	refresh()
	return true

func get_default_focus() -> Control:
	return _ticket.get_primary_button() if not _ticket.get_primary_button().disabled else _list.get_default_focus()

func get_ticket() -> OrderTicket:
	return _ticket
