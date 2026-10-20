class_name TaskDelivery
extends Node
## Session coordinator. GameState owns task facts/receipts; WarehouseInventory owns items.

signal delivered(order_id: String)
signal order_cancelled(order_id: String)
## 失败也发信号：调试日志需要真实原因；返回值与调用方行为保持不变。
signal delivery_failed(order_id: String, reason: String)
signal availability_changed

const StateData = preload("res://src/core/game_state.gd")

var _journal: TaskJournal
var _state: StateData
var _inventory: WarehouseInventory
var _orders: Dictionary = {}
var _committing := false
var _batches: Array[Dictionary] = []
var _availability: Dictionary = {}

## Optional scene-local gates. Unmanaged orders retain their existing behavior.
## A freed gate owner fails closed until the replacement scene binds its gate.
func set_order_availability(order_ids: Array[String], predicate: Callable) -> Error:
	if _committing or not predicate.is_valid():
		return ERR_UNAVAILABLE
	for id: String in order_ids:
		if not _orders.has(id):
			return ERR_DOES_NOT_EXIST
		var existing: Callable = _availability.get(id, Callable())
		if existing.is_valid() and existing != predicate:
			return ERR_ALREADY_EXISTS
	for id: String in order_ids:
		_availability[id] = predicate
	refresh_availability()
	return OK

func is_order_available(order_id: String) -> bool:
	if not _availability.has(order_id):
		return true
	var predicate: Callable = _availability[order_id]
	return predicate.is_valid() and predicate.call(order_id) == true

func refresh_availability() -> void:
	availability_changed.emit()

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
		if delivery.has("items") or delivery.has("uses"):
			if delivery.has("uses") and inventory != state.get_warehouse_inventory():
				return ERR_INVALID_DATA
			for id: String in delivery.get("uses", delivery.get("items")):
				if inventory.get_definition(id) == null:
					return ERR_INVALID_DATA
		elif delivery.has("drink"):
			if inventory != state.get_warehouse_inventory():
				return ERR_INVALID_DATA
			if delivery.drink.has("formula"):
				var formula := inventory.calculate_formula(delivery.drink.formula, false)
				if not formula.ok or not DrinkFormula.matches(formula, delivery.drink):
					return ERR_INVALID_DATA
			if delivery.drink.has("base_id"):
				var base := inventory.get_definition(delivery.drink.base_id)
				if base == null or not base.can_be_base or not base.free_recipe_allowed:
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
	if delivery.has("drink") or delivery.has("uses"):
		return {}
	if delivery.has("items"):
		# JSON numbers arrive as floats; the inventory only accepts ints.
		var requirement := {}
		for id: String in delivery.items:
			requirement[id] = int(delivery.items[id])
		return requirement
	return {String(delivery.product_id): 1}

func get_use_requirement(order_id: String) -> Dictionary:
	var result := {}
	if _orders.has(order_id):
		for id: String in _orders[order_id].delivery.get("uses", {}):
			result[id] = int(_orders[order_id].delivery.uses[id])
	return result

func _has_requirement(order_id: String) -> bool:
	if not get_use_requirement(order_id).is_empty():
		return _inventory.has_uses(get_use_requirement(order_id))
	return _inventory.has_materials(get_requirement(order_id))

func accept_order(order_id: String) -> Error:
	if _committing or not _ready_for_delivery() or not _orders.has(order_id):
		return ERR_UNAVAILABLE
	var task: Dictionary = _orders[order_id]
	if not _state.get_task_result(task.id).is_empty() or _state.get_flag(_receipt_key(order_id)) or _state.get_flag(task.complete_when.key):
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

## Cancellation settles only the task. Prepared cups and materials remain owned;
## no delivery receipt, completion count or reward is created.
func cancel_order(order_id: String) -> Error:
	if _committing or not _ready_for_delivery() or not _orders.has(order_id):
		return ERR_UNAVAILABLE
	var task: Dictionary = _orders[order_id]
	if not task.get("allow_cancel", false) or not is_order_accepted(order_id):
		return ERR_UNAVAILABLE
	_committing = true
	var error := _state.settle_task_result(task.id, "cancelled", "主动取消订单")
	if error == OK:
		order_cancelled.emit(order_id)
	_committing = false
	return error

func is_order_cancelled(order_id: String) -> bool:
	return (_orders.has(order_id) and is_instance_valid(_state)
		and _state.get_task_result(_orders[order_id].id).get("status") == "cancelled")

func can_accept_order(order_id: String) -> bool:
	if not _orders.has(order_id) or not is_instance_valid(_state) or not is_order_available(order_id):
		return false
	var task: Dictionary = _orders[order_id]
	var view := _journal.get_task(task.id)
	if task.activate_when.type != "flag" or not view.get("revealed", false) or view.status in ["completed", "failed", "expired", "cancelled"] or _state.get_flag(_receipt_key(order_id)):
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
		if task.delivery.has("drink"):
			parts.append("自由饮品：" + DrinkFormula.requirement_text(task.delivery.drink, _ingredient_names()))
		var use_requirement := get_use_requirement(order_id)
		for id: String in use_requirement:
			parts.append("%s × %d 次" % [_inventory.get_definition(id).display_name, use_requirement[id]])
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
		if preferred.delivery.target_object_id == target_object_id and _has_requirement(preferred_order_id):
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
		if (task.delivery.has("drink") and not _matching_drink(task.delivery.drink).is_empty()) or (not task.delivery.has("drink") and _has_requirement(order_id)):
			return try_submit(order_id, target_object_id)
	if not active_fallback.is_empty():
		return try_submit(active_fallback, target_object_id)
	if not fallback.is_empty():
		return try_submit(fallback, target_object_id)
	return _failure("该 NPC 不是当前订单的交付对象。")

## Canonical entry point. Products and materials both commit through one schedule.
func try_submit(order_id: String, target_object_id: String, drink_id: String = "") -> Dictionary:
	if _committing or not _ready_for_delivery():
		return _failure("交付系统尚未就绪或正在提交。", order_id)
	if not _orders.has(order_id):
		return _failure("订单不存在。", order_id)
	if not is_order_available(order_id):
		return _failure("该订单尚未发布，或顾客当前无法接待。", order_id)
	var task: Dictionary = _orders[order_id]
	if task.delivery.target_object_id != target_object_id:
		return _failure("成品或交付对象与订单不符。未消耗库存。", order_id)
	if _state.get_flag(_receipt_key(order_id)) or _journal.get_task(task.id).get("status") != "active":
		return _failure("任务未激活或已经完成，不能交付。", order_id)
	if not _state.can_complete_task(task.id):
		return _failure("任务已结束、已到截止点或存在失败条件，不能交付。", order_id)
	if task.delivery.has("accepted_flag") and not _state.get_flag(task.delivery.accepted_flag):
		return _failure("请先在订单板接取这张订单。", order_id)
	var requirement := get_requirement(order_id)
	var use_costs := get_use_requirement(order_id)
	var missing := PackedStringArray()
	for id: String in requirement:
		var shortfall: int = int(requirement[id]) - _inventory.get_stock(id)
		if shortfall > 0:
			missing.append("%s ×%d" % [_inventory.get_definition(id).display_name, shortfall])
	for id: String in use_costs:
		var shortfall: int = use_costs[id] - _inventory.get_uses(id)
		if shortfall > 0:
			missing.append("%s ×%d 次" % [_inventory.get_definition(id).display_name, shortfall])
	if not missing.is_empty():
		return _failure("还缺：" + "、".join(missing) + "。", order_id)
	var drink_costs := {}
	var sale_price := 0
	if task.delivery.has("drink"):
		var drink := _matching_drink(task.delivery.drink, drink_id)
		if drink.is_empty():
			return _failure("没有符合订单要求的饮品。这单要求：%s。请核对基底槽与辅料；未消耗库存。" % DrinkFormula.requirement_text(task.delivery.drink, _ingredient_names(), true), order_id)
		if not drink.get("priced", false):
			return _failure("该饮品尚未确认售价，不能作为普通订单出售。", order_id)
		var record: Dictionary = _state.get_transactions().get_formula_price(drink.ingredients)
		if record.is_empty():
			return _failure("该饮品尚未确认售价，不能作为普通订单出售。", order_id)
		drink_costs[drink.id] = 1
		sale_price = _state.get_transactions().get_drink_sale_price(drink)
	elif task.delivery.has("product_id"):
		sale_price = _product_sale_price(str(task.delivery.product_id))
		if sale_price < 0 and not task.get("rewards", {}).has("money"):
			return _failure("该成品没有可用的固定售价，不能作为普通订单出售。", order_id)
	var rewards := {}
	for id: String in task.get("rewards", {}).get("items", {}):
		rewards[id] = int(task.rewards.items[id])
		var remaining: int = _inventory.get_stock(id) - int(requirement.get(id, 0))
		if use_costs.has(id):
			var uses: int = _inventory.get_uses(id) - int(use_costs[id])
			var per := _inventory.get_uses_per_portion(id)
			remaining = int(uses / per) + (1 if uses % per != 0 else 0)
		if remaining > WarehouseInventory.MAX_QUANTITY - rewards[id]:
			return _failure("奖励库存已满：" + _inventory.get_definition(id).display_name + "。请腾出空间后重试。", order_id)
	if _inventory == _state.get_warehouse_inventory() and _state.get_transactions().get_balance() > WalletTransactions.LIMIT - int(task.get("rewards", {}).get("money", 0)):
		return _failure("钱包已满，请腾出余额后重试。", order_id)
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
		# Explicitly configured money (including zero) overrides the formula price.
		var money := int(task.get("rewards", {}).get("money", sale_price))
		var error := _state.commit_delivery(requirement, rewards, money, facts, get_completed_count() + 1, "delivery:" + order_id, delivered.emit.bind(order_id), drink_costs, task.id, use_costs)
		_committing = false
		if error != OK:
			return _failure("交付结算失败：请检查成品、奖励容量或钱包上限。未消耗库存。", order_id)
		var money_delta := _state.get_transactions().get_balance() - balance_before
		var committed_items := {}
		var gains := PackedStringArray()
		if money_delta > 0:
			gains.append("报酬 " + WalletTransactions.format_money(money_delta))
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
	_inventory.set_session_locked(true)
	var error := _state.commit_delivery_facts(facts, get_completed_count() + 1, task.id)
	if error != OK:
		_inventory.set_session_locked(false)
		_inventory.restore_state(before)
	_inventory.set_block_signals(was_blocked)
	if error == OK:
		_inventory.changed.emit()
		delivered.emit(order_id)
	_inventory.set_session_locked(false)
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
	if delivery.has("drink"):
		return try_submit(order_id, target_object_id, product_id)
	if delivery.has("product_id"):
		if product_id != delivery.product_id:
			return _failure("成品或交付对象与订单不符。未消耗库存。", order_id)
	elif not product_id.is_empty():
		return _failure("该订单需要物资，不需要成品。未消耗库存。", order_id)
	return try_submit(order_id, target_object_id)

func _matching_drink(requirement: Dictionary, preferred_id: String = "") -> Dictionary:
	for drink: Dictionary in _inventory.get_drinks():
		if (preferred_id.is_empty() or drink.id == preferred_id) and DrinkFormula.matches(drink, requirement):
			return drink
	return {}

func has_matching_drink(order_id: String) -> bool:
	return _orders.has(order_id) and _orders[order_id].delivery.has("drink") and not _matching_drink(_orders[order_id].delivery.drink).is_empty()

## Fixed human menu price from the recipe. Teaching and story recipes carry no
## fixed price: their orders must spell the money out in rewards, and a missing
## amount pays nothing instead of inventing a dynamic price. Quest-only
## products may only be sold through their task.
func _product_sale_price(product_id: String) -> int:
	var definition := _inventory.get_definition(product_id)
	if definition == null or definition.economy_scope == "quest":
		return -1
	var production: TeaProduction = _state.get_tea_production() if _state.has_method("get_tea_production") else null
	if production != null:
		var recipe := production.get_recipe_by_product(product_id)
		if recipe != null:
			return recipe.sell_price if recipe.sell_price >= 0 else 0
	return 0

func _ingredient_names() -> Dictionary:
	var names := {}
	for ingredient: IngredientDefinition in WarehouseInventory.CATALOG.ingredients:
		names[ingredient.id] = ingredient.display_name
	return names

func _ready_for_delivery() -> bool:
	return is_instance_valid(_journal) and is_instance_valid(_state) and is_instance_valid(_inventory) and not _inventory.is_session_locked()

func _receipt_key(order_id: String) -> String:
	return "delivery." + order_id + ".completed"

## 助手在返回失败结果的同时广播原因；order_id 为空表示还未定位到具体订单。
func _failure(message: String, order_id: String = "") -> Dictionary:
	delivery_failed.emit(order_id, message)
	return {"ok": false, "message": message}
