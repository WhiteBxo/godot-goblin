class_name GatheringService
extends Node
## Owns harvest rules and state keys. WarehouseInventory owns items; GameState owns facts.

signal harvested(point: GatherPoint, item_id: String, amount: int, stock: int)

const StateData = preload("res://src/core/game_state.gd")
const REFRESH_MODES: PackedStringArray = ["once", "daily"]

var _state: StateData
var _inventory: WarehouseInventory
var _points: Dictionary = {}
var _order: Array[GatherPoint] = []
var _committing := false


## Validate every point before publishing any of them.
func configure(state: StateData, inventory: WarehouseInventory, points: Array[GatherPoint]) -> Error:
	if _committing:
		return ERR_BUSY
	if not is_instance_valid(state) or not is_instance_valid(inventory):
		return ERR_INVALID_PARAMETER
	var registry := {}
	var order: Array[GatherPoint] = []
	for point: GatherPoint in points:
		if not is_instance_valid(point):
			return ERR_INVALID_DATA
		var point_id := String(point.interaction_id)
		if point_id.is_empty() or not point_id.is_valid_identifier() or registry.has(point_id):
			return ERR_INVALID_DATA
		var definition := inventory.get_definition(point.item_id)
		if not point.item_id.is_valid_identifier() or definition == null or definition.category == "product":
			return ERR_INVALID_DATA
		if point.amount < 1 or point.amount > WarehouseInventory.MAX_QUANTITY:
			return ERR_INVALID_DATA
		if point.refresh_mode not in REFRESH_MODES:
			return ERR_INVALID_DATA
		if not point.required_flag.is_empty() and not StoryLibrary.is_namespaced(point.required_flag):
			return ERR_INVALID_DATA
		registry[point_id] = point
		order.append(point)
	for previous: GatherPoint in _order:
		if is_instance_valid(previous) and registry.get(String(previous.interaction_id)) != previous:
			previous.bind_gathering(Callable())
	if is_instance_valid(_state) and _state.state_changed.is_connected(_schedule_presentation):
		_state.state_changed.disconnect(_schedule_presentation)
	_state = state
	_inventory = inventory
	_points = registry
	_order = order
	for point: GatherPoint in _order:
		point.bind_gathering(is_harvestable)
	_state.state_changed.connect(_schedule_presentation)
	_schedule_presentation()
	return OK

func _schedule_presentation() -> void:
	_refresh_presentation.call_deferred()

func _refresh_presentation() -> void:
	if not is_inside_tree():
		return
	for point: GatherPoint in _order:
		if is_instance_valid(point):
			point.update_presentation(is_harvestable(point))


func has_point(id: StringName) -> bool:
	return get_point(id) != null


func get_point(id: StringName) -> GatherPoint:
	var point: GatherPoint = _points.get(String(id))
	return point if is_instance_valid(point) else null


func get_points() -> Array[GatherPoint]:
	return _order.duplicate()


## Read-only gate used by every GatherPoint; never mutates state.
func is_harvestable(point: GatherPoint) -> bool:
	return _unavailable_reason(point).is_empty()


func harvest(id: StringName) -> Dictionary:
	var point := get_point(id)
	var reason := _unavailable_reason(point)
	if not reason.is_empty():
		return _failure(reason)
	var item_id := point.item_id
	var amount := point.amount
	# Catalog and amount are validated in configure. Capacity is the only
	# rejection the inventory can still report, so check it before committing.
	if _inventory.get_stock(item_id) > WarehouseInventory.MAX_QUANTITY - amount:
		return _failure("库存已满，无法采集。未获得物品。")
	if not _state.begin_business_transaction():
		return _failure("会话正在更新，暂时无法采集。")

	var before := _inventory.to_dict()
	var inventory_blocked := _inventory.is_blocking_signals()
	var state_blocked := _state.is_blocking_signals()
	var day_key := _day_key(point)
	var total_key := _total_key(item_id)
	var previous_day := int(_state.get_variable(day_key, 0))
	var previous_total := int(_state.get_variable(total_key, 0))
	_committing = true
	_inventory.set_block_signals(true)
	_state.set_block_signals(true)

	# Stock goes in first so a rejected commit can restore an exact snapshot; the
	# one-way once flag is written last and never survives a rejected harvest.
	var committed := _inventory.try_exchange({}, {item_id: amount})
	var day_written := false
	var total_written := false
	if committed and point.refresh_mode == "daily":
		day_written = _state.set_variable(day_key, _state.current_day)
		committed = day_written
	if committed:
		total_written = _state.set_variable(total_key, previous_total + amount)
		committed = total_written
	if committed and point.refresh_mode == "once":
		committed = _state.apply_flags({_once_key(point): true}) == OK
	if not committed:
		if total_written:
			_state.set_variable(total_key, previous_total)
		if day_written:
			_state.set_variable(day_key, previous_day)
		_inventory.restore_state(before)
		_inventory.set_block_signals(inventory_blocked)
		_state.set_block_signals(state_blocked)
		_committing = false
		_state.end_business_transaction()
		return _failure("库存已满，无法采集。未获得物品。")

	_inventory.set_block_signals(inventory_blocked)
	_state.set_block_signals(state_blocked)
	var stock := _inventory.get_stock(item_id)
	_state.state_changed.emit()
	_inventory.changed.emit()
	harvested.emit(point, item_id, amount, stock)
	_committing = false
	_state.end_business_transaction()
	var message := "采集成功：%s × %d（现有 %d）。" % [_display_name(item_id), amount, stock]
	if not point.success_description.is_empty():
		message = point.success_description + "\n" + message
	return {"ok": true, "message": message,
		"item_id": item_id, "amount": amount, "stock": stock}


func _exit_tree() -> void:
	if is_instance_valid(_state) and _state.state_changed.is_connected(_schedule_presentation):
		_state.state_changed.disconnect(_schedule_presentation)
	for point: GatherPoint in _order:
		if is_instance_valid(point):
			point.bind_gathering(Callable())
	_points.clear()
	_order.clear()


func _unavailable_reason(point: GatherPoint) -> String:
	if not _ready_for_gathering():
		return "采集系统尚未就绪。"
	if _committing:
		return "采集系统正在提交。"
	if not is_instance_valid(point) or _points.get(String(point.interaction_id)) != point:
		return "该采集点不存在。"
	if Day1Access.is_market_only(_state):
		return "先在集市附近看看，接下委托后再采集。"
	if not point.required_flag.is_empty() and not _state.get_flag(point.required_flag):
		return "现在还不能采集。"
	if point.refresh_mode == "once":
		if _state.get_flag(_once_key(point)):
			return "这个采集点已经采过了。"
		return ""
	if int(_state.get_variable(_day_key(point), 0)) >= _state.current_day:
		return "今天已经采集过了，明天再来。"
	return ""


func _ready_for_gathering() -> bool:
	return is_instance_valid(_state) and is_instance_valid(_inventory) and not _inventory.is_session_locked()


func _display_name(item_id: String) -> String:
	var definition := _inventory.get_definition(item_id)
	return definition.display_name if definition != null else item_id


func _once_key(point: GatherPoint) -> String:
	return "gather." + String(point.interaction_id) + ".harvested"


func _day_key(point: GatherPoint) -> String:
	return "gather." + String(point.interaction_id) + ".day"


func _total_key(item_id: String) -> String:
	return "gather.total." + item_id


func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message, "item_id": "", "amount": 0, "stock": 0}
