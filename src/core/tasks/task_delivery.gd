class_name TaskDelivery
extends Node
## Session coordinator. GameState owns task facts/receipts; WarehouseInventory owns items.

signal delivered(order_id: String)

const StateData = preload("res://src/core/game_state.gd")

var _journal: TaskJournal
var _state: StateData
var _inventory: WarehouseInventory
var _orders: Dictionary = {}
var _committing := false

func configure(catalog: TaskCatalog, journal: TaskJournal, state: StateData, inventory: WarehouseInventory) -> Error:
	if _committing or not is_instance_valid(journal) or not is_instance_valid(state) or not is_instance_valid(inventory) or catalog == null:
		return ERR_INVALID_PARAMETER
	var orders := {}
	for task: Dictionary in catalog.get_tasks():
		if not task.has("delivery"):
			continue
		var product := inventory.get_definition(task.delivery.product_id)
		if product == null or product.category != "product":
			return ERR_INVALID_DATA
		for id: String in task.get("rewards", {}).get("items", {}):
			if inventory.get_definition(id) == null:
				return ERR_INVALID_DATA
		orders[task.delivery.order_id] = task
	_journal = journal
	_state = state
	_inventory = inventory
	_orders = orders
	return OK

func get_orders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for task: Dictionary in _orders.values():
		result.append(task.delivery.duplicate(true))
	return result

func accept_order(order_id: String) -> Error:
	if _committing or not _ready_for_delivery() or not _orders.has(order_id):
		return ERR_UNAVAILABLE
	var task: Dictionary = _orders[order_id]
	if _state.get_flag(_receipt_key(order_id)) or _state.get_flag(task.complete_when.key):
		return ERR_ALREADY_EXISTS
	# Existing story-driven conditions remain under StoryDirector's control.
	if task.activate_when.type != "flag" or not _journal.get_task(task.id).get("revealed", false):
		return ERR_UNAVAILABLE
	_state.set_flag(task.activate_when.key)
	return OK

func get_completed_count() -> int:
	var count := 0
	if is_instance_valid(_state):
		for order_id: String in _orders:
			if _state.get_flag(_receipt_key(order_id)):
				count += 1
	return count

func get_requirements_text(target_names: Dictionary = {}) -> String:
	var lines := PackedStringArray()
	for order_id: String in _orders:
		var task: Dictionary = _orders[order_id]
		var view := _journal.get_task(task.id)
		if _state.get_flag(_receipt_key(order_id)) or not view.get("revealed", false) or view.get("status") != "active":
			continue
		var product := _inventory.get_definition(task.delivery.product_id)
		lines.append("%s：%s × 1 → %s" % [task.title, product.display_name, target_names.get(task.delivery.target_object_id, task.delivery.target_object_id)])
	return "\n".join(lines)

func deliver_to(target_object_id: String) -> Dictionary:
	if not _ready_for_delivery():
		return _failure("交付系统尚未就绪。")
	# Prefer a deliverable order; another missing cup must not block this NPC.
	var fallback: Dictionary = {}
	for order_id: String in _orders:
		var task: Dictionary = _orders[order_id]
		if task.delivery.target_object_id != target_object_id:
			continue
		fallback = task.delivery
		if not _state.get_flag(_receipt_key(order_id)) and _journal.get_task(task.id).get("status") == "active" and _inventory.get_stock(task.delivery.product_id) > 0:
			return try_deliver(order_id, task.delivery.product_id, target_object_id)
	if not fallback.is_empty():
		return try_deliver(fallback.order_id, fallback.product_id, target_object_id)
	return _failure("该 NPC 不是当前订单的交付对象。")

func try_deliver(order_id: String, product_id: String, target_object_id: String) -> Dictionary:
	if _committing or not _ready_for_delivery():
		return _failure("交付系统尚未就绪或正在提交。")
	if not _orders.has(order_id):
		return _failure("订单不存在。")
	var task: Dictionary = _orders[order_id]
	var requirement: Dictionary = task.delivery
	if requirement.product_id != product_id or requirement.target_object_id != target_object_id:
		return _failure("成品或交付对象与订单不符。未消耗库存。")
	if _state.get_flag(_receipt_key(order_id)) or _journal.get_task(task.id).get("status") != "active":
		return _failure("任务未激活或已经完成，不能交付。")
	var rewards := {}
	for id: String in task.get("rewards", {}).get("items", {}):
		rewards[id] = int(task.rewards.items[id])
	var before := _inventory.to_dict()
	_committing = true
	# Signals are synchronous in Godot. Hold inventory notification until the
	# completion and durable receipt are committed; observers see the full result.
	var was_blocked := _inventory.is_blocking_signals()
	_inventory.set_block_signals(true)
	if not _inventory.try_exchange({product_id: 1}, rewards):
		_inventory.set_block_signals(was_blocked)
		_committing = false
		return _failure("成品不足或奖励库存已满。未消耗库存。")
	var facts := {task.complete_when.key: true, _receipt_key(order_id): true}
	var error := _state.apply_flags(facts)
	if error != OK:
		_inventory.restore_state(before)
	_inventory.set_block_signals(was_blocked)
	if error == OK:
		_inventory.changed.emit()
		delivered.emit(order_id)
	_committing = false
	if error != OK:
		return _failure("交付提交失败。未消耗库存。")
	return {"ok": true, "message": "交付成功，任务已完成。" + ("奖励：" + task.rewards.text if not rewards.is_empty() else "")}

func _ready_for_delivery() -> bool:
	return is_instance_valid(_journal) and is_instance_valid(_state) and is_instance_valid(_inventory)

func _receipt_key(order_id: String) -> String:
	return "delivery." + order_id + ".completed"

func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
