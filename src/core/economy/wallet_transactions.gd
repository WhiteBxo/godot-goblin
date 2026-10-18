class_name WalletTransactions
extends Node
## Main-thread synchronous transactions. No await, external calls or signals in commit.

signal changed
signal transaction_finished(result: Dictionary)

const LIMIT: int = WarehouseInventory.MAX_QUANTITY
const SCHEMA_VERSION: int = 1

var _inventory: WarehouseInventory
var _balance: int = 0
var _products: Dictionary = {}
var _rewards: Dictionary = {}
var _merchant_stock: Dictionary = {}
var _requests: Dictionary = {}
var _claimed: Dictionary = {}
var _busy: bool = false
var _task_lookup: Callable
var _defaults: Dictionary
var _session_guard: Callable

func _init(menu: TeaMenu = WarehouseInventory.CATALOG) -> void:
	if menu == null:
		menu = WarehouseInventory.CATALOG
	_inventory = WarehouseInventory.new(menu)
	_inventory.name = "WarehouseInventory"
	add_child(_inventory)
	_inventory.changed.connect(_on_inventory_changed)
	_balance = menu.initial_balance if _amount(menu.initial_balance, true) else 0
	_products = menu.products.duplicate(true)
	_rewards = menu.transaction_rewards.duplicate(true)
	for id: Variant in _products:
		var product: Variant = _products[id]
		if id is String and product is Dictionary and product.has("stock") and _amount(product.stock, true):
			_merchant_stock[id] = product.stock
	_defaults = to_dict()

func get_inventory() -> WarehouseInventory:
	return _inventory

func get_balance() -> int:
	return _balance

## Valid products in configured order; malformed entries remain queryable by ID
## for their diagnostic but are never offered as purchasable products.
func get_product_quotes() -> Array[Dictionary]:
	var quotes: Array[Dictionary] = []
	for product_id: Variant in _products:
		var quote := get_product_quote(product_id)
		if quote.ok:
			quotes.append(quote)
	return quotes

## Read-only projection of this session's static product and live merchant stock.
## Only scalar values escape; callers may edit the copy without changing the wallet.
## A quote does not reserve stock or authorize a later purchase.
func get_product_quote(product_id: Variant) -> Dictionary:
	if not _id(product_id) or not _products.has(product_id):
		return {"ok": false, "code": "unknown_product", "message": "商品不存在。"}
	var product: Variant = _products[product_id]
	if not product is Dictionary or not _amount(product.get("price"), true) or _inventory.get_definition(product.get("item_id")) == null or (product.has("stock") and not _amount(product.stock, true)):
		return {"ok": false, "code": "invalid_configuration", "message": "商品配置无效。"}
	return {"ok": true, "code": "ok", "message": "",
		"product_id": product_id, "item_id": product.item_id, "unit_price": product.price,
		"stock": _merchant_stock[product_id] if product.has("stock") else null}

func is_busy() -> bool:
	return _busy or (_session_guard.is_valid() and _session_guard.call())

func set_session_guard(guard: Callable) -> void:
	_session_guard = guard

func set_task_lookup(lookup: Callable) -> void:
	_task_lookup = lookup

func get_default_state() -> Dictionary:
	return _defaults.duplicate(true)

func add_money(amount: Variant, request_id: Variant) -> Dictionary:
	return _execute("credit", request_id, "", amount)

func spend_money(amount: Variant, request_id: Variant) -> Dictionary:
	return _execute("debit", request_id, "", amount)

func purchase(product_id: Variant, quantity: Variant, request_id: Variant) -> Dictionary:
	return _execute("purchase", request_id, product_id, quantity)

func claim_reward(reward_id: Variant, request_id: Variant) -> Dictionary:
	return _execute("reward", request_id, reward_id, 1)

func _execute(kind: String, request_id: Variant, subject: Variant, quantity: Variant) -> Dictionary:
	# Nested calls return directly: emitting another result here could recurse forever.
	if is_busy():
		return _result(false, "busy", "交易正在处理中。", request_id)
	_busy = true
	var result := _prepare_and_commit(kind, request_id, subject, quantity)
	transaction_finished.emit(result.duplicate(true))
	_busy = false
	return result

func _prepare_and_commit(kind: String, request_id: Variant, subject: Variant, quantity: Variant) -> Dictionary:
	if not _id(request_id) or not _amount(quantity):
		return _result(false, "invalid_parameter", "交易编号或数量无效。", request_id)
	if _requests.has(request_id):
		return _result(false, "duplicate_transaction", "该交易已完成，请勿重复提交。", request_id)
	var delta: int = 0
	var items: Dictionary = {}
	var next := to_dict()
	match kind:
		"credit":
			delta = quantity
		"debit":
			delta = -quantity
		"purchase":
			var quote := get_product_quote(subject)
			if not quote.ok:
				return _result(false, quote.code, quote.message, request_id)
			# Both operands are bounded to 32 bits; their product fits a signed int64.
			var cost: int = quote.unit_price * quantity
			if cost > LIMIT:
				return _result(false, "amount_overflow", "交易金额超出上限。", request_id)
			if quote.stock != null:
				if quote.stock < quantity:
					return _result(false, "out_of_stock", "商品库存不足。", request_id)
				next.merchant_stock[subject] -= quantity
			delta = -cost
			items[quote.item_id] = quantity
		"reward":
			if not _id(subject) or not _rewards.has(subject):
				return _result(false, "unknown_reward", "奖励不存在。", request_id)
			if _claimed.has("reward:" + subject):
				return _result(false, "already_claimed", "该奖励已领取。", request_id)
			var reward: Variant = _rewards[subject]
			if not reward is Dictionary or not _amount(reward.get("money"), true) or not reward.get("items") is Dictionary:
				return _result(false, "invalid_configuration", "奖励配置无效。", request_id)
			if reward.has("task_id"):
				if not _id(reward.task_id):
					return _result(false, "invalid_configuration", "任务奖励配置无效。", request_id)
				if not _task_lookup.is_valid():
					return _result(false, "task_unavailable", "任务系统尚未就绪。", request_id)
				var task: Variant = _task_lookup.call(reward.task_id)
				if not task is Dictionary or task.get("status") != "completed":
					return _result(false, "task_incomplete", "任务尚未完成。", request_id)
				# One task cannot pay twice through two differently named reward entries.
				if _claimed.has("task:" + reward.task_id):
					return _result(false, "already_claimed", "该任务奖励已领取。", request_id)
				next.claimed["task:" + reward.task_id] = true
			delta = reward.money
			items = reward.items.duplicate(true)
			next.claimed["reward:" + subject] = true
	if _balance + delta < 0:
		return _result(false, "insufficient_funds", "余额不足。", request_id)
	if _balance + delta > LIMIT:
		return _result(false, "amount_overflow", "钱包余额超出上限。", request_id)
	for item: Variant in items:
		if _inventory.get_definition(item) == null or not _amount(items[item]):
			return _result(false, "invalid_item", "物品或物品数量无效。", request_id)
		var entry: Dictionary = next.inventory.ingredients[item]
		if entry.quantity > LIMIT - items[item]:
			return _result(false, "inventory_full", "库存数量已达上限。", request_id)
		entry.quantity += items[item]
		entry.discovered = true
	next.balance = _balance + delta
	next.requests[request_id] = true
	var before := to_dict()
	# The inventory replacement is the sole fallible commit step. It is silent and
	# validates before mutation. Wallet/receipts are assigned only after it succeeds.
	if _replace(next) != OK:
		return _result(false, "commit_failed", "交易提交失败，状态未改变。", request_id)
	_publish(before)
	var result := _result(true, "ok", "交易成功。", request_id)
	result.money_delta = delta
	result.items = items.duplicate(true)
	return result

## Pure preparation. GameState commits this draft with the delivery facts under its lock.
func prepare_delivery(costs: Dictionary, rewards: Dictionary, money: int, request_id: String, drink_costs: Dictionary = {}) -> Dictionary:
	if is_busy() or not _id(request_id) or not _amount(money, true) or _requests.has(request_id):
		return {}
	if (not costs.is_empty() and not _inventory.has_materials(costs)) or _balance > LIMIT - money:
		return {}
	var next := to_dict()
	for id: Variant in drink_costs:
		if not id is String or not _amount(drink_costs[id]) or _inventory.get_drink_stock(id) < drink_costs[id]:
			return {}
		next.inventory.drinks[id] -= drink_costs[id]
	for id: String in costs:
		var entry: Dictionary = next.inventory.ingredients[id]
		entry.quantity -= costs[id]
		# Mirrors WarehouseInventory.try_exchange: the opened portion leaves last.
		if entry.quantity == 0:
			entry.used = 0
	for id: String in rewards:
		if _inventory.get_definition(id) == null or not _amount(rewards[id]):
			return {}
		var entry: Dictionary = next.inventory.ingredients[id]
		if entry.quantity > LIMIT - rewards[id]:
			return {}
		entry.quantity += rewards[id]
		entry.discovered = true
	next.balance += money
	next.requests[request_id] = true
	return next if validate_state(next) == OK else {}

func _result(ok: bool, code: String, message: String, request_id: Variant) -> Dictionary:
	return {"ok": ok, "code": code, "message": message, "request_id": request_id,
		"balance": _balance, "money_delta": 0, "items": {}}

func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "balance": _balance, "inventory": _inventory.to_dict(),
		"merchant_stock": _merchant_stock.duplicate(), "requests": _requests.duplicate(), "claimed": _claimed.duplicate()}

func validate_state(data: Variant) -> Error:
	if not data is Dictionary or not data.has_all(["schema_version", "balance", "inventory", "merchant_stock", "requests", "claimed"]):
		return ERR_INVALID_DATA
	if not _snapshot_amount(data.schema_version) or data.schema_version != SCHEMA_VERSION or not _snapshot_amount(data.balance):
		return ERR_INVALID_DATA
	if _inventory.validate_state(data.inventory) != OK or not data.merchant_stock is Dictionary or data.merchant_stock.size() != _merchant_stock.size():
		return ERR_INVALID_DATA
	for id: Variant in data.merchant_stock:
		if not _merchant_stock.has(id) or not _snapshot_amount(data.merchant_stock[id]):
			return ERR_INVALID_DATA
	for field: String in ["requests", "claimed"]:
		if not data[field] is Dictionary:
			return ERR_INVALID_DATA
		for id: Variant in data[field]:
			if not _id(id) or not data[field][id] is bool or not data[field][id]:
				return ERR_INVALID_DATA
	return OK

func restore_state(data: Variant, notify: bool = true) -> Error:
	if is_busy():
		return ERR_BUSY
	if data is Dictionary and data.has("inventory"):
		data = data.duplicate(true)
		data.inventory = WarehouseInventory.migrate_snapshot(data.inventory)
	_busy = true
	var before := to_dict()
	var error := _replace(data)
	if error == OK and notify:
		_publish(before)
	_busy = false
	return error

func _replace(data: Variant) -> Error:
	if validate_state(data) != OK:
		return ERR_INVALID_DATA
	if _inventory.restore_state(data.inventory, false) != OK:
		return ERR_INVALID_DATA
	_balance = int(data.balance)
	_merchant_stock = data.merchant_stock.duplicate()
	for id: String in _merchant_stock:
		_merchant_stock[id] = int(_merchant_stock[id])
	_requests = data.requests.duplicate()
	_claimed = data.claimed.duplicate()
	return OK

## Called by GameState only after the story fields have also been replaced.
func publish_restored(before: Dictionary) -> void:
	_busy = true
	_publish(before)
	_busy = false

func _publish(before: Dictionary) -> void:
	if before == to_dict():
		return
	if before.inventory != _inventory.to_dict():
		_inventory.changed.emit()
	changed.emit()

func _on_inventory_changed() -> void:
	if not _busy:
		changed.emit()

func _id(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

func _amount(value: Variant, allow_zero: bool = false) -> bool:
	return value is int and value >= (0 if allow_zero else 1) and value <= LIMIT

func _snapshot_amount(value: Variant) -> bool:
	return (value is int or (value is float and is_finite(value) and value == floor(value))) and value >= 0 and value <= LIMIT
