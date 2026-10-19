class_name WalletTransactions
extends Node
## Main-thread synchronous transactions. No await, external calls or signals in commit.

signal changed
signal transaction_finished(result: Dictionary)

const LIMIT: int = WarehouseInventory.MAX_QUANTITY
const SCHEMA_VERSION: int = 3
## Every price, reward and balance in the game uses this single currency.
const CURRENCY_SYMBOL: String = "G"
## One 古怪金币 carries this face value. The coin is the Day 1 form of G, not a second currency.
const COIN_FACE_VALUE: int = 10

static func format_money(amount: int) -> String:
	return "%d%s" % [amount, CURRENCY_SYMBOL]

static func coin_worth(count: int) -> int:
	return count * COIN_FACE_VALUE

var _inventory: WarehouseInventory
var _balance: int = 0
var _products: Dictionary = {}
var _rewards: Dictionary = {}
var _merchant_stock: Dictionary = {}
var _requests: Dictionary = {}
var _claimed: Dictionary = {}
## recipe_id -> permanent price record. Fixed at first confirmation, never re-rolled.
var _recipe_prices: Dictionary = {}
## signature_id -> {reward, claimed, receipt}. One payout per stable signature ID.
var _signature_rewards: Dictionary = {}
## craft request_id -> {recipe_id, quantity, drink_id}. Durable craft receipts.
var _formula_crafts: Dictionary = {}
var _rules: EconomyRules
var _flag_lookup: Callable
var _busy: bool = false
var _task_lookup: Callable
var _defaults: Dictionary
var _session_guard: Callable

func _init(menu: TeaMenu = WarehouseInventory.CATALOG) -> void:
	if menu == null:
		menu = WarehouseInventory.CATALOG
	_inventory = WarehouseInventory.new(menu)
	_inventory.set_signature_access(is_signature_available)
	_inventory.name = "WarehouseInventory"
	add_child(_inventory)
	_inventory.changed.connect(_on_inventory_changed)
	_rules = _inventory.get_economy_rules()
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
func get_product_definition(product_id: Variant) -> Dictionary:
	if not _id(product_id) or not _products.has(product_id) or not _valid_product(_products[product_id]):
		return {}
	return _products[product_id].duplicate(true)

func _valid_product(product: Variant) -> bool:
	if not product is Dictionary or not _amount(product.get("price"), true) or _inventory.get_definition(product.get("item_id")) == null:
		return false
	for field: Variant in product:
		if field not in ["item_id", "price", "stock", "discounted_price", "discount_flag"]:
			return false
	if product.has("stock") and not _amount(product.stock, true):
		return false
	if _inventory.get_definition(product.item_id).economy_scope == "quest":
		return false
	if product.has("discounted_price") and (not _amount(product.discounted_price, true) or product.discounted_price > product.price):
		return false
	if product.has("discount_flag") and (not product.has("discounted_price") or not product.discount_flag is String or not StoryLibrary.is_namespaced(product.discount_flag)):
		return false
	return true

## Query and purchase resolve the same explicit integer price and session fact.
## Quote queries are read-only; a quote does not reserve stock or lock eligibility.

func get_product_quote(product_id: Variant) -> Dictionary:
	if not _id(product_id) or not _products.has(product_id):
		return {"ok": false, "code": "unknown_product", "message": "商品不存在。"}
	var product := get_product_definition(product_id)
	if product.is_empty():
		return {"ok": false, "code": "invalid_configuration", "message": "商品配置无效。"}
	if product.has("discount_flag") and not _flag_lookup.is_valid():
		return {"ok": false, "code": "eligibility_unavailable", "message": "折扣资格尚未绑定共享会话。"}
	var discounted: bool = product.has("discounted_price") and (not product.has("discount_flag") or _flag_lookup.call(product.discount_flag))
	return {"ok": true, "code": "ok", "message": "",
		"product_id": product_id, "item_id": product.item_id,
		"base_price": product.price, "discounted": discounted,
		"unit_price": product.discounted_price if discounted else product.price,
		"stock": _merchant_stock[product_id] if product.has("stock") else null}

func is_busy() -> bool:
	return _busy or (_session_guard.is_valid() and _session_guard.call())

func set_session_guard(guard: Callable) -> void:
	_session_guard = guard

func set_task_lookup(lookup: Callable) -> void:
	_task_lookup = lookup

func set_flag_lookup(lookup: Callable) -> void:
	_flag_lookup = lookup

func get_default_state() -> Dictionary:
	return _defaults.duplicate(true)

func get_economy_rules() -> EconomyRules:
	return _rules

## Permanent record for a formula, or {} when it has not been confirmed yet.
func get_formula_price(materials: Variant) -> Dictionary:
	var key := DrinkFormula.key_for(materials, false)
	if key.is_empty():
		return {}
	var record: Variant = _recipe_prices.get(key)
	return record.duplicate(true) if record is Dictionary else {}

func get_price_record(recipe_id: Variant) -> Dictionary:
	if not recipe_id is String:
		return {}
	var record: Variant = _recipe_prices.get(recipe_id)
	return record.duplicate(true) if record is Dictionary else {}

func is_signature_discovered(id: String) -> bool:
	return _signature_rewards.has(id)

func is_signature_available(id: String) -> bool:
	var signature := _inventory.get_recipe_rules().get_signature(id)
	return signature.get("discovery_kind", "experiment") == "experiment" or is_signature_discovered(id)

## Signature prices apply to the exact serving variant; ordinary ledger records
## remain intact so old quotes and opposite ice variants never need a re-roll.
func get_drink_sale_price(drink: Dictionary) -> int:
	if not drink.get("signature_id", "").is_empty() and int(drink.get("price", 0)) > 0:
		return int(drink.price)
	var record := get_formula_price(drink.get("ingredients", []))
	return int(record.get("selling_price", 0))

## Discovery adds a zero-stock encyclopedia record and pays once. No ingredients
## are acquired or consumed. GameState owns eligibility and the final commit.
func prepare_signature_discovery(id: String, day: int, picker: Callable) -> Dictionary:
	if is_busy() or day < 1:
		return {"ok": false, "message": "当前无法记录配方。"}
	var signature := _inventory.get_recipe_rules().get_signature(id)
	if signature.is_empty() or signature.get("discovery_kind") != "clue":
		return {"ok": false, "message": "没有可调查的爆品线索。"}
	if is_signature_discovered(id):
		return {"ok": true, "replayed": true, "message": "该爆品已记录，赏金已领取。"}
	var formula := _inventory.calculate_signature_formula(signature.ingredients, signature.iced)
	if not formula.ok or formula.signature_id != id:
		return {"ok": false, "message": "爆品配置无效。"}
	var draft := to_dict()
	var recipe_id := DrinkFormula.key_for(signature.ingredients)
	if not draft.recipe_prices.has(recipe_id):
		var quote := FormulaPricing.quote(signature.ingredients, _inventory.get_definition, _rules, picker)
		if not quote.ok:
			return quote
		draft.recipe_prices[recipe_id] = quote.record
	var entry := {"ingredients": signature.ingredients.duplicate(), "discovered_day": day, "pricing": "priced"}
	if signature.iced:
		entry["iced"] = true
	if not draft.inventory.encyclopedia.has(formula.id):
		draft.inventory.encyclopedia[formula.id] = entry
	WarehouseInventory.mark_priced_snapshot(draft.inventory, recipe_id)
	var reward := signature_reward_for(id)
	if reward < 0 or _balance > LIMIT - reward:
		return {"ok": false, "message": "钱包容量不足，配方与赏金均未提交。"}
	var receipt := "discover:" + id
	draft.requests[receipt] = true
	draft.signature_rewards[id] = {"reward": reward, "claimed": true, "receipt": receipt}
	draft.balance += reward
	if validate_state(draft) != OK:
		return {"ok": false, "message": "发现记录校验失败。"}
	return {"ok": true, "replayed": false, "draft": draft, "money_delta": reward,
		"message": "已发现「%s」，解锁赏金 %dG。" % [signature.name, reward]}

## Read-only projection: fixed price when known, otherwise the tier range only.
## Never consumes RNG, never registers a price and never consumes stock.
func preview_formula_price(materials: Variant, iced := false) -> Dictionary:
	var record := get_formula_price(materials)
	var formula := _inventory.calculate_formula(materials, true, iced)
	if formula.get("ok", false) and int(formula.get("price", 0)) > 0:
		return {"ok": true, "priced": not record.is_empty(), "recipe_id": DrinkFormula.key_for(materials),
			"selling_price": int(formula.price), "minimum": int(formula.price), "maximum": int(formula.price)}
	if not record.is_empty():
		return {"ok": true, "priced": true, "recipe_id": record.recipe_id,
			"selling_price": int(record.selling_price), "slots": record.slots.duplicate(true)}
	var bounds := FormulaPricing.range_for(materials, _inventory.get_definition, _rules, _inventory.get_recipe_slots())
	if not bounds.ok:
		return bounds
	bounds["priced"] = false
	return bounds

## First confirmation only. Existing records are returned unchanged, so retries
## and reordered slots can never re-roll a price.
func confirm_formula(materials: Variant, request_id: Variant, picker: Callable) -> Dictionary:
	if is_busy():
		return _result(false, "busy", "交易正在处理中。", request_id)
	if not _id(request_id) or not materials is Array:
		return _result(false, "invalid_parameter", "配方或请求编号无效。", request_id)
	_busy = true
	var result := _confirm_formula(materials, request_id, picker)
	transaction_finished.emit(result.duplicate(true))
	_busy = false
	return result

func _confirm_formula(materials: Array, request_id: String, picker: Callable) -> Dictionary:
	var key := DrinkFormula.key_for(materials, false)
	if key.is_empty():
		return _result(false, "invalid_formula", "请选择一个基底。", request_id)
	var receipt := "price:" + request_id
	if _requests.has(receipt):
		return _result(false, "duplicate_transaction", "该报价请求已完成。", request_id)
	var existing: Variant = _recipe_prices.get(key)
	if existing is Dictionary:
		var replay := _result(true, "ok", "该配方已有固定售价。", request_id)
		replay["record"] = existing.duplicate(true)
		replay["replayed"] = true
		return replay
	for id: Variant in materials:
		if not _inventory.is_discovered(id):
			return _result(false, "undiscovered_ingredient", "存在尚未发现的原料。", request_id)
	var quote := FormulaPricing.quote(materials, _inventory.get_definition, _rules, picker, _inventory.get_recipe_slots())
	if not quote.ok:
		return _result(false, quote.code, quote.message, request_id)
	var record: Dictionary = quote.record
	var draft := to_dict()
	draft.recipe_prices[key] = record.duplicate(true)
	draft.requests[receipt] = true
	WarehouseInventory.mark_priced_snapshot(draft.inventory, key)
	if validate_state(draft) != OK:
		return _result(false, "invalid_configuration", "报价记录校验失败。", request_id)
	var before := to_dict()
	# No balance, stock or encyclopedia semantics change here: only the ledger and
	# the request receipt, committed as one inventory replacement.
	if _replace(draft) != OK:
		return _result(false, "commit_failed", "报价提交失败，状态未改变。", request_id)
	_publish(before)
	var result := _result(true, "ok", "配方售价已确认。", request_id)
	result["record"] = record.duplicate(true)
	result["replayed"] = false
	return result

## Pure preparation for one atomic craft: uses, cup, encyclopedia, receipt and the
## first-signature reward. GameState commits the returned draft under its lock.
func prepare_formula_craft(materials: Variant, quantity: Variant, iced: bool, day: int, request_id: String) -> Dictionary:
	if is_busy():
		return {"ok": false, "code": "busy", "message": "交易正在处理中。"}
	if not materials is Array or not _amount(quantity) or day < 1 or request_id.strip_edges().is_empty():
		return {"ok": false, "code": "invalid_parameter", "message": "制作请求无效。"}
	var receipt := "craft:" + request_id
	if _requests.has(receipt):
		return {"ok": false, "code": "duplicate_transaction", "message": "该制作请求已处理。"}
	var formula := _inventory.calculate_formula(materials, true, iced)
	if not formula.ok:
		return {"ok": false, "code": formula.get("code", "invalid_formula"), "message": formula.get("message", "配方无效。")}
	# Repeats reuse the recorded discovery, so reordered or iced remakes keep the
	# first discovery's ordered name instead of rewriting history.
	var recorded: Dictionary = _inventory.get_drink_record(formula.id)
	if not recorded.is_empty() and not recorded.get("read_only", false):
		formula = recorded
	var price_key := DrinkFormula.key_for(materials, false)
	var record: Variant = _recipe_prices.get(price_key)
	if not record is Dictionary:
		return {"ok": false, "code": "unpriced", "message": "该配方尚未确认售价。"}
	var uses := FormulaPricing.uses_for(record)
	var required := {}
	for id: String in uses:
		required[id] = int(uses[id]) * quantity
	for id: String in required:
		if _inventory.get_uses(id) < required[id]:
			return {"ok": false, "code": "missing_uses", "message": "原料可用次数不足。未消耗库存。"}
	var draft := to_dict()
	for id: String in required:
		if not _spend_uses(draft.inventory, id, required[id]):
			return {"ok": false, "code": "missing_uses", "message": "原料可用次数不足。未消耗库存。"}
	var drink_id: String = formula.id
	if draft.inventory.drinks.get(drink_id, 0) > LIMIT - quantity:
		return {"ok": false, "code": "capacity", "message": "该配方成品库存已满。"}
	draft.inventory.drinks[drink_id] = int(draft.inventory.drinks.get(drink_id, 0)) + quantity
	# The encyclopedia entry is the discovery record, so "first" is decided before
	# it is written. This is a handbook signal, unrelated to the signature reward.
	var first_discovery: bool = not draft.inventory.encyclopedia.has(drink_id)
	if first_discovery:
		# Keep the first discovery's ordered ingredients: reordered or iced remakes
		# must keep the recorded name instead of overwriting history.
		var entry := {"ingredients": materials.duplicate(), "discovered_day": day, "pricing": "priced"}
		if iced:
			entry["iced"] = true
		draft.inventory.encyclopedia[drink_id] = entry
	var money := 0
	var signature_id: String = formula.get("signature_id", "")
	var first_signature := false
	if not signature_id.is_empty() and not _signature_rewards.has(signature_id):
		var reward := signature_reward_for(signature_id)
		if reward < 0:
			return {"ok": false, "code": "invalid_configuration", "message": "爆品奖励配置无效。"}
		money = reward
		first_signature = true
		draft.signature_rewards[signature_id] = {"reward": reward, "claimed": true, "receipt": receipt}
	if _balance > LIMIT - money:
		return {"ok": false, "code": "amount_overflow", "message": "钱包余额超出上限。"}
	draft.balance = _balance + money
	draft.requests[receipt] = true
	draft.formula_crafts[request_id] = {"recipe_id": price_key, "quantity": quantity, "drink_id": drink_id}
	if validate_state(draft) != OK:
		return {"ok": false, "code": "invalid_configuration", "message": "制作快照校验失败。未消耗库存。"}
	return {"ok": true, "code": "ok", "message": "", "draft": draft, "formula": formula,
		"money_delta": money, "first_signature": first_signature, "first_discovery": first_discovery,
		"record": record.duplicate(true)}

## First reward from the static signature entry, or the shared default.
func signature_reward_for(signature_id: String) -> int:
	if _rules == null or not _rules.validate():
		return -1
	var rules: RecipeRules = _inventory.get_recipe_rules()
	if rules != null:
		for signature: Dictionary in rules.signatures:
			if signature.get("id") == signature_id:
				var value: Variant = signature.get("first_reward", _rules.signature_first_reward)
				return value if value is int and value >= 0 and value <= LIMIT else -1
	return _rules.signature_first_reward

## Spends uses inside a draft snapshot, keeping the opened portion last.
func _spend_uses(inventory: Dictionary, id: String, amount: int) -> bool:
	if not inventory.get("ingredients") is Dictionary or not inventory.ingredients.has(id):
		return false
	var entry: Dictionary = inventory.ingredients[id]
	var per: int = _inventory.get_uses_per_portion(id)
	var remaining: int = int(entry.quantity) * per - int(entry.used) - amount
	if remaining < 0:
		return false
	@warning_ignore("integer_division")
	var portions := remaining / per + (1 if remaining % per != 0 else 0)
	entry.quantity = portions
	entry.used = portions * per - remaining
	return true

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
func prepare_delivery(costs: Dictionary, rewards: Dictionary, money: int, request_id: String, drink_costs: Dictionary = {}, use_costs: Dictionary = {}) -> Dictionary:
	if is_busy() or not _id(request_id) or not _amount(money, true) or _requests.has(request_id):
		return {}
	if (not costs.is_empty() and not _inventory.has_materials(costs)) or _balance > LIMIT - money:
		return {}
	var next := to_dict()
	for id: Variant in drink_costs:
		if not id is String or not _amount(drink_costs[id]) or _inventory.get_drink_stock(id) < drink_costs[id]:
			return {}
		next.inventory.drinks[id] -= drink_costs[id]
	for id: Variant in use_costs:
		if not id is String or not _amount(use_costs[id]) or not _spend_uses(next.inventory, id, use_costs[id]):
			return {}
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

## One draft for partial portions, fixed cups, payments and grants. Amounts are
## uses, never temporary whole portions; no observer can see intermediate stock.
func prepare_exchange(request_id: String, use_costs: Dictionary = {}, use_gains: Dictionary = {}, money_delta: int = 0, items: Dictionary = {}, item_costs: Dictionary = {}) -> Dictionary:
	if is_busy() or not _id(request_id) or _requests.has(request_id) or absi(money_delta) > LIMIT:
		return {}
	if _balance + money_delta < 0 or _balance + money_delta > LIMIT:
		return {}
	var next := to_dict()
	for id: Variant in item_costs:
		if not id is String or not _amount(item_costs[id]) or not next.inventory.ingredients.has(id):
			return {}
		var entry: Dictionary = next.inventory.ingredients[id]
		# A partially consumed portion cannot be delivered as a full portion.
		if int(entry.quantity) - (1 if int(entry.used) > 0 else 0) < item_costs[id]:
			return {}
		entry.quantity -= item_costs[id]
	for id: Variant in use_costs:
		if not id is String or not _amount(use_costs[id]) or not _spend_uses(next.inventory, id, use_costs[id]):
			return {}
	for id: Variant in use_gains:
		if not id is String or not _amount(use_gains[id]) or not next.inventory.ingredients.has(id):
			return {}
		var per := _inventory.get_uses_per_portion(id)
		var entry: Dictionary = next.inventory.ingredients[id]
		var remaining: int = int(entry.quantity) * per - int(entry.used) + int(use_gains[id])
		@warning_ignore("integer_division")
		var portions: int = remaining / per + (1 if remaining % per > 0 else 0)
		if portions > LIMIT:
			return {}
		entry.quantity = portions
		entry.used = portions * per - remaining
		entry.discovered = true
	for id: Variant in items:
		if not id is String or not _amount(items[id]) or not next.inventory.ingredients.has(id):
			return {}
		var entry: Dictionary = next.inventory.ingredients[id]
		if int(entry.quantity) > LIMIT - int(items[id]):
			return {}
		entry.quantity += items[id]
		entry.discovered = true
	next.balance += money_delta
	next.requests[request_id] = true
	return next if validate_state(next) == OK else {}

func _result(ok: bool, code: String, message: String, request_id: Variant) -> Dictionary:
	return {"ok": ok, "code": code, "message": message, "request_id": request_id,
		"balance": _balance, "money_delta": 0, "items": {}}

func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "balance": _balance, "inventory": _inventory.to_dict(),
		"merchant_stock": _merchant_stock.duplicate(), "requests": _requests.duplicate(), "claimed": _claimed.duplicate(),
		"recipe_prices": _recipe_prices.duplicate(true), "signature_rewards": _signature_rewards.duplicate(true),
		"formula_crafts": _formula_crafts.duplicate(true)}

## v1 had no permanent price ledger. Old cups stay historical; no reward is
## re-issued and no price is invented while migrating.
func migrate_snapshot(data: Variant) -> Variant:
	if not data is Dictionary or not data.get("inventory") is Dictionary or not data.get("requests") is Dictionary:
		return data
	if data.get("schema_version") == SCHEMA_VERSION:
		var current: Dictionary = data.duplicate(true)
		current.inventory = WarehouseInventory.migrate_snapshot(data.inventory)
		return current
	if data.get("schema_version") not in [1, 2]:
		return data
	var migrated: Dictionary = data.duplicate(true)
	var old_prices: Variant = data.inventory.get("recipe_prices", {})
	if not old_prices is Dictionary:
		return data
	if not migrated.has("recipe_prices"):
		migrated["recipe_prices"] = {}
		for id: Variant in old_prices:
			var price: Variant = old_prices[id]
			if not price is Dictionary or not price.get("ingredients") is Array:
				return data
			var converted: Dictionary = price.duplicate(true)
			converted.erase("ingredients")
			converted["slots"] = []
			var seen := {}
			for index in range(price.ingredients.size()):
				var ingredient: Variant = price.ingredients[index]
				for field: String in ["slot_costs", "slot_markups", "slot_prices"]:
					if not price.get(field) is Array or price[field].size() != price.ingredients.size():
						return data
				converted.slots.append({"ingredient_id": ingredient, "occurrence": seen.get(ingredient, 0),
					"cost": price.slot_costs[index], "markup": price.slot_markups[index], "price": price.slot_prices[index]})
				seen[ingredient] = int(seen.get(ingredient, 0)) + 1
			migrated.recipe_prices[id] = converted
	if not migrated.has("formula_crafts"):
		migrated["formula_crafts"] = {}
		var rewards := {}
		if not data.get("signature_rewards", {}) is Dictionary or not data.get("claimed") is Dictionary:
			return data
		for id: Variant in data.get("signature_rewards", {}):
			var reward: Variant = data.signature_rewards[id]
			if not reward is Dictionary or not reward.has_all(["amount", "request_id", "recipe_id"]):
				return data
			if not id is String or not reward.request_id is String or not reward.recipe_id is String or not data.claimed.get("signature:" + id, false):
				return data
			var receipt: String = str(reward.request_id)
			if receipt.is_empty() and data.get("claimed", {}).has("signature:" + str(id)):
				receipt = "legacy.signature:" + str(id)
				migrated.requests[receipt] = true
			rewards[id] = {"reward": reward.amount, "claimed": true, "receipt": receipt, "legacy": true, "recipe_id": reward.recipe_id}
		# The first economy branch stored paid signatures only in `claimed`.
		# Retain that receipt only when an actual priced discovery witnesses it.
		for key: Variant in data.claimed:
			if not key is String or not key.begins_with("signature:"):
				continue
			var id: String = key.trim_prefix("signature:")
			if rewards.has(id):
				continue
			var recipe := _signature_recipe(id, migrated.inventory)
			if recipe.is_empty() or not migrated.recipe_prices.has(recipe):
				return data
			var receipt := "legacy.signature:" + id
			migrated.requests[receipt] = true
			rewards[id] = {"reward": signature_reward_for(id), "claimed": true, "receipt": receipt, "legacy": true, "recipe_id": recipe}
		migrated["signature_rewards"] = rewards
	if not migrated.has("signature_rewards"):
		migrated["signature_rewards"] = {}
	migrated.inventory = WarehouseInventory.migrate_snapshot(data.inventory)
	migrated.schema_version = SCHEMA_VERSION
	return migrated

func _signature_recipe(signature: String, inventory: Dictionary) -> String:
	if not inventory.get("encyclopedia", {}) is Dictionary:
		return ""
	for entry: Variant in inventory.get("encyclopedia", {}).values():
		if not entry is Dictionary or not entry.get("ingredients") is Array:
			continue
		var formula := _inventory.calculate_signature_formula(entry.ingredients, entry.get("iced", false))
		if formula.ok and formula.signature_id == signature:
			return DrinkFormula.key_for(entry.ingredients, false)
	return ""

func validate_state(data: Variant) -> Error:
	if not data is Dictionary or not data.has_all(["schema_version", "balance", "inventory", "merchant_stock", "requests", "claimed",
			"recipe_prices", "signature_rewards", "formula_crafts"]):
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
	if not data.recipe_prices is Dictionary or not data.signature_rewards is Dictionary or not data.formula_crafts is Dictionary:
		return ERR_INVALID_DATA
	for id: Variant in data.recipe_prices:
		if not _id(id) or not FormulaPricing.validate_record(data.recipe_prices[id], _inventory.get_definition, _rules):
			return ERR_INVALID_DATA
		if data.recipe_prices[id].recipe_id != id:
			return ERR_INVALID_DATA
	for id: Variant in data.signature_rewards:
		var claim: Variant = data.signature_rewards[id]
		if not _id(id) or not claim is Dictionary or claim.size() != (5 if claim.has("legacy") else 3) or not claim.has_all(["reward", "claimed", "receipt"]):
			return ERR_INVALID_DATA
		var clue: bool = claim.get("receipt") == "discover:" + str(id) and _inventory.get_recipe_rules().get_signature(id).get("discovery_kind") == "clue"
		if not _snapshot_amount(claim.reward) or claim.claimed != true or not _id(claim.receipt) or not data.requests.has(claim.receipt) or (not clue and not claim.get("legacy", false) and not data.formula_crafts.has(String(claim.receipt).trim_prefix("craft:"))):
			return ERR_INVALID_DATA
		if claim.has("legacy") and claim.legacy != true:
			return ERR_INVALID_DATA
		var recipe := _signature_recipe(id, data.inventory)
		if recipe.is_empty() or not data.recipe_prices.has(recipe):
			return ERR_INVALID_DATA
		if claim.has("legacy"):
			if not claim.has("recipe_id") or claim.recipe_id != recipe or not data.claimed.get("signature:" + id, false):
				return ERR_INVALID_DATA
		elif not clue:
			var craft: Variant = data.formula_crafts[String(claim.receipt).trim_prefix("craft:")]
			if not craft is Dictionary or craft.get("recipe_id") != recipe:
				return ERR_INVALID_DATA
		var signature_found := false
		for signature: Dictionary in _inventory.get_recipe_rules().signatures:
			if signature.get("id") == id:
				signature_found = int(claim.reward) == signature_reward_for(id)
		if not signature_found:
			return ERR_INVALID_DATA
	for key: String in data.claimed:
		if key.begins_with("signature:") and not data.signature_rewards.has(key.trim_prefix("signature:")):
			return ERR_INVALID_DATA
	for request_id: Variant in data.formula_crafts:
		var craft: Variant = data.formula_crafts[request_id]
		if not _id(request_id) or not craft is Dictionary or craft.size() != 3 or not craft.has_all(["recipe_id", "quantity", "drink_id"]):
			return ERR_INVALID_DATA
		if not data.requests.has("craft:" + request_id) or not data.recipe_prices.has(craft.recipe_id):
			return ERR_INVALID_DATA
		if not _snapshot_amount(craft.quantity) or int(craft.quantity) < 1 or not _id(craft.drink_id):
			return ERR_INVALID_DATA
		if not data.inventory.get("encyclopedia", {}).has(craft.drink_id):
			return ERR_INVALID_DATA
		if DrinkFormula.key_for(data.inventory.encyclopedia[craft.drink_id].ingredients, false) != craft.recipe_id:
			return ERR_INVALID_DATA
	for drink_id: String in data.inventory.encyclopedia:
		var entry: Dictionary = data.inventory.encyclopedia[drink_id]
		if entry.get("pricing") == "priced" and not data.recipe_prices.has(DrinkFormula.key_for(entry.ingredients, false)):
			return ERR_INVALID_DATA
	return OK

func restore_state(data: Variant, notify: bool = true) -> Error:
	if is_busy():
		return ERR_BUSY
	data = migrate_snapshot(data)
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
	_recipe_prices = data.recipe_prices.duplicate(true)
	_signature_rewards = data.signature_rewards.duplicate(true)
	_formula_crafts = data.formula_crafts.duplicate(true)
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
