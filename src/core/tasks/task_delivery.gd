class_name TaskDelivery
extends Node
## Session coordinator. GameState owns task facts/receipts; WarehouseInventory owns items.

signal delivered(order_id: String)
## 失败也发信号：调试日志需要真实原因；返回值与调用方行为保持不变。
signal delivery_failed(order_id: String, reason: String)

const StateData = preload("res://src/core/game_state.gd")

var _journal: TaskJournal
var _state: StateData
var _inventory: WarehouseInventory
var _orders: Dictionary = {}
var _committing := false
var _batches: Array[Dictionary] = []

func configure_batches(batches: Array[Dictionary]) -> void:
	_batches = batches.duplicate(true)

func configure(catalog: TaskCatalog, journal: TaskJournal, state: StateData, inventory: WarehouseInventory) -> Error:
	if _committing or not is_instance_valid(journal) or not is_instance_valid(state) or not is_instance_valid(inventory) or catalog == null:
		return ERR_INVALID_PARAMETER
	var orders := {}
	for task: Dictionary in catalog.get_tasks():
		if not task.has("delivery"):
			continue
		var delivery: Dictionary = task.delivery
		if delivery.has("items"):
			for id: String in delivery.items:
				if inventory.get_definition(id) == null:
					return ERR_INVALID_DATA
		else:
			var product := inventory.get_definition(delivery.product_id)
			if product == null or product.category != "product":
				return ERR_INVALID_DATA
		for id: String in task.get("rewards", {}).get("items", {}):
			if inventory.get_definition(id) == null:
				return ERR_INVALID_DATA
		if int(task.get("rewards", {}).get("money", 0)) > 0 and inventory != state.get_warehouse_inventory():
			return ERR_INVALID_DATA
		orders[delivery.order_id] = task
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

## Materials and finished products share one shape: {item_id: quantity}.
func get_requirement(order_id: String) -> Dictionary:
	if not _orders.has(order_id):
		return {}
	var delivery: Dictionary = _orders[order_id].delivery
	if delivery.has("items"):
		# JSON numbers arrive as floats; the inventory only accepts ints.
		var requirement := {}
		for id: String in delivery.items:
			requirement[id] = int(delivery.items[id])
		return requirement
	return {String(delivery.product_id): 1}

func accept_order(order_id: String) -> Error:
	if _committing or not _ready_for_delivery() or not _orders.has(order_id):
		return ERR_UNAVAILABLE
	var task: Dictionary = _orders[order_id]
	if _state.get_flag(_receipt_key(order_id)) or _state.get_flag(task.complete_when.key):
		return ERR_ALREADY_EXISTS
	if is_order_accepted(order_id):
		return ERR_ALREADY_EXISTS
	if not can_accept_order(order_id):
		return ERR_UNAVAILABLE
	return OK if _state.set_flag(task.delivery.get("accepted_flag", task.activate_when.key)) else ERR_BUSY

func is_order_accepted(order_id: String) -> bool:
	if not _orders.has(order_id) or not is_instance_valid(_state):
		return false
	var task: Dictionary = _orders[order_id]
	if task.delivery.has("accepted_flag"):
		return _state.get_flag(task.delivery.accepted_flag) and _journal.get_task(task.id).get("status") == "active"
	return _journal.get_task(task.id).get("status") == "active"

func can_accept_order(order_id: String) -> bool:
	if not _orders.has(order_id) or not is_instance_valid(_state):
		return false
	var task: Dictionary = _orders[order_id]
	var view := _journal.get_task(task.id)
	if task.activate_when.type != "flag" or not view.get("revealed", false) or view.status == "completed" or _state.get_flag(_receipt_key(order_id)):
		return false
	# A separate chapter activation flag cannot be set by accepting an order.
	if task.delivery.has("accepted_flag") and task.delivery.accepted_flag != task.activate_when.key and view.status != "active":
		return false
	return not is_order_accepted(order_id)

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
		var parts := PackedStringArray()
		var requirement := get_requirement(order_id)
		for id: String in requirement:
			var definition := _inventory.get_definition(id)
			parts.append("%s × %d" % [definition.display_name if definition != null else id, requirement[id]])
		lines.append("%s：%s → %s" % [task.title, "、".join(parts),
			target_names.get(task.delivery.target_object_id, task.delivery.target_object_id)])
	return "\n".join(lines)

func deliver_to(target_object_id: String, preferred_order_id: String = "") -> Dictionary:
	if not _ready_for_delivery():
		return _failure("交付系统尚未就绪。")
	if _orders.has(preferred_order_id) and is_order_accepted(preferred_order_id):
		var preferred: Dictionary = _orders[preferred_order_id]
		if preferred.delivery.target_object_id == target_object_id and _inventory.has_materials(get_requirement(preferred_order_id)):
			return try_submit(preferred_order_id, target_object_id)
	# Prefer a deliverable order; another missing requirement must not block this NPC.
	# Report against an active order before an inactive one, so a later chapter's
	# order for the same NPC does not hide the current one's missing materials.
	var fallback := ""
	var active_fallback := ""
	for order_id: String in _orders:
		var task: Dictionary = _orders[order_id]
		if task.delivery.target_object_id != target_object_id:
			continue
		fallback = order_id
		if _state.get_flag(_receipt_key(order_id)) or not is_order_accepted(order_id):
			continue
		active_fallback = order_id
		if _inventory.has_materials(get_requirement(order_id)):
			return try_submit(order_id, target_object_id)
	if not active_fallback.is_empty():
		return try_submit(active_fallback, target_object_id)
	if not fallback.is_empty():
		return try_submit(fallback, target_object_id)
	return _failure("该 NPC 不是当前订单的交付对象。")

## Canonical entry point. Products and materials both commit through one schedule.
func try_submit(order_id: String, target_object_id: String) -> Dictionary:
	if _committing or not _ready_for_delivery():
		return _failure("交付系统尚未就绪或正在提交。", order_id)
	if not _orders.has(order_id):
		return _failure("订单不存在。", order_id)
	var task: Dictionary = _orders[order_id]
	if task.delivery.target_object_id != target_object_id:
		return _failure("成品或交付对象与订单不符。未消耗库存。", order_id)
	if _state.get_flag(_receipt_key(order_id)) or _journal.get_task(task.id).get("status") != "active":
		return _failure("任务未激活或已经完成，不能交付。", order_id)
	if task.delivery.has("accepted_flag") and not _state.get_flag(task.delivery.accepted_flag):
		return _failure("请先查看订单板接单。未消耗库存。", order_id)
	var requirement := get_requirement(order_id)
	var rewards := {}
	for id: String in task.get("rewards", {}).get("items", {}):
		rewards[id] = int(task.rewards.items[id])
	if _inventory == _state.get_warehouse_inventory():
		var balance_before := _state.get_transactions().get_balance()
		var reward_stock := {}
		for id: String in rewards:
			reward_stock[id] = _inventory.get_stock(id)
		_committing = true
		var facts := {task.complete_when.key: true, _receipt_key(order_id): true}
		for batch: Dictionary in _batches:
			var complete := true
			for member: String in batch.orders:
				complete = complete and (member == order_id or _state.get_flag(_receipt_key(member)))
			if complete:
				facts[batch.completion_flag] = true
		var error := _state.commit_delivery(requirement, rewards, int(task.get("rewards", {}).get("money", 0)), facts, get_completed_count() + 1, "delivery:" + order_id, delivered.emit.bind(order_id))
		_committing = false
		if error != OK:
			return _failure("交付结算失败：请检查成品、奖励容量或钱包上限。未消耗库存。", order_id)
		var money_delta := _state.get_transactions().get_balance() - balance_before
		var committed_items := {}
		var gains := PackedStringArray()
		if money_delta > 0:
			gains.append("营业收入 %d" % money_delta)
		for id: String in rewards:
			var quantity: int = _inventory.get_stock(id) - reward_stock[id] + int(requirement.get(id, 0))
			committed_items[id] = quantity
			gains.append("%s × %d" % [_inventory.get_definition(id).display_name, quantity])
		return {"ok": true, "money_delta": money_delta, "items": committed_items,
			"message": "交付成功，任务已完成。" + ("所得：" + "、".join(gains) if not gains.is_empty() else "")}
	var before := _inventory.to_dict()
	if not _state.begin_business_transaction():
		return _failure("会话正在更新，暂时无法交付。", order_id)
	_committing = true
	# Signals are synchronous in Godot. Hold inventory notification until the
	# completion and durable receipt are committed; observers see the full result.
	var was_blocked := _inventory.is_blocking_signals()
	_inventory.set_block_signals(true)
	if not _inventory.try_exchange(requirement, rewards):
		_inventory.set_block_signals(was_blocked)
		_committing = false
		_state.end_business_transaction()
		return _failure("所需成品或物资不足，或奖励库存已满。未消耗库存。", order_id)
	var facts := {task.complete_when.key: true, _receipt_key(order_id): true}
	var state_blocked := _state.is_blocking_signals()
	_state.set_block_signals(true)
	var error := _state.apply_flags(facts)
	if error != OK:
		_inventory.restore_state(before)
	else:
		_state.set_variable("shop.orders_completed", maxi(int(_state.get_variable("shop.orders_completed", 0)), get_completed_count()))
	_state.set_block_signals(state_blocked)
	_inventory.set_block_signals(was_blocked)
	if error == OK:
		_state.state_changed.emit()
		_inventory.changed.emit()
		delivered.emit(order_id)
	_committing = false
	_state.end_business_transaction()
	if error != OK:
		return _failure("交付提交失败。未消耗库存。", order_id)
	return {"ok": true, "message": "交付成功，任务已完成。" + ("奖励：" + task.rewards.text if not rewards.is_empty() else "")}

## Legacy signature kept for existing callers: finished products pass their ID,
## material orders pass an empty string.
func try_deliver(order_id: String, product_id: String, target_object_id: String) -> Dictionary:
	if not _orders.has(order_id):
		return _failure("订单不存在。", order_id)
	var delivery: Dictionary = _orders[order_id].delivery
	if delivery.has("product_id"):
		if product_id != delivery.product_id:
			return _failure("成品或交付对象与订单不符。未消耗库存。", order_id)
	elif not product_id.is_empty():
		return _failure("该订单需要物资，不需要成品。未消耗库存。", order_id)
	return try_submit(order_id, target_object_id)

func _ready_for_delivery() -> bool:
	return is_instance_valid(_journal) and is_instance_valid(_state) and is_instance_valid(_inventory) and not _inventory.is_session_locked()

func _receipt_key(order_id: String) -> String:
	return "delivery." + order_id + ".completed"

## 助手在返回失败结果的同时广播原因；order_id 为空表示还未定位到具体订单。
func _failure(message: String, order_id: String = "") -> Dictionary:
	delivery_failed.emit(order_id, message)
	return {"ok": false, "message": message}
