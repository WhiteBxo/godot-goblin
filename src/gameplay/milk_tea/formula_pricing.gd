class_name FormulaPricing
extends RefCounted
## Pure pricing rules for goblin free formulas. No RNG side effects, stock,
## receipts or shared-Resource writes: the caller supplies the integer picker and
## commits the returned record itself.

const MAX_SLOTS := RecipeRules.MAX_SLOTS
const SCHEMA_VERSION := 1

## Canonical slot order: the base, then additives sorted by ID with one slot per
## occurrence. Reordering additives or toggling ice therefore keeps one identity.
static func canonical(materials: Variant, lookup: Callable, slot_limit: int = MAX_SLOTS) -> Dictionary:
	if not materials is Array or materials.is_empty():
		return _failure("invalid_formula", "请选择一个基底。")
	if slot_limit < 1 or slot_limit > 16 or materials.size() > mini(slot_limit, MAX_SLOTS):
		return _failure("slots", "原料超过当前槽位数量。")
	var ids: Array[String] = []
	for id: Variant in materials:
		if not id is String or id.is_empty():
			return _failure("invalid_formula", "原料编号无效。")
		if id == DrinkFormula.ICE_ID:
			return _failure("ice_option", "冰块请使用单独的加冰选项，不占原料槽位。")
		ids.append(id)
	var base: IngredientDefinition = lookup.call(ids[0])
	if base == null or not base.can_be_base or base.base_suffix not in IngredientDefinition.BASE_SUFFIXES:
		return _failure("base", "第一个槽位必须选择可用基底。")
	if base.economy_scope != "trade":
		return _failure("restricted", "该基底不能用于经营配方。")
	var goblin_slot := false
	# All slots need ordinary-recipe permission. Only ids[0] is the base;
	# additive slots never reject an ingredient for also having base eligibility.
	for id: String in ids:
		var definition: IngredientDefinition = lookup.call(id)
		if definition == null or not definition.free_recipe_allowed or definition.economy_scope != "trade":
			return _failure("restricted", "存在不可用于普通配方的原料。")
		if definition.category in ["product", "story_item"]:
			return _failure("restricted", "成品和剧情物品不能作为经营原料。")
		if definition.origin == "otherworld":
			goblin_slot = true
	if not goblin_slot:
		return _failure("human_only", "至少需要一种哥布林经营原料。")
	var additives: Array[String] = []
	for index in range(1, ids.size()):
		additives.append(ids[index])
	additives.sort()
	var ordered: Array[String] = [ids[0]]
	ordered.append_array(additives)
	var occurrences := {}
	var slots: Array[Dictionary] = []
	for id: String in ordered:
		var occurrence: int = int(occurrences.get(id, 0))
		occurrences[id] = occurrence + 1
		slots.append({"ingredient_id": id, "occurrence": occurrence})
	return {"ok": true, "code": "ok", "message": "", "slots": slots,
		"recipe_id": DrinkFormula.key_for(materials, false)}

## Lower/upper bound for an unpriced formula; the preview never rolls a price.
static func range_for(materials: Variant, lookup: Callable, rules: EconomyRules, slot_limit: int = MAX_SLOTS) -> Dictionary:
	var canonical_result := canonical(materials, lookup, slot_limit)
	if not canonical_result.ok:
		return canonical_result
	if rules == null or not rules.validate():
		return _failure("invalid_rules", "经营规则配置无效。")
	var minimum := 0
	var maximum := 0
	var cost := 0
	for slot: Dictionary in canonical_result.slots:
		var definition: IngredientDefinition = lookup.call(slot.ingredient_id)
		var bounds := _slot_bounds(definition, rules)
		if bounds.is_empty():
			return _failure("invalid_ingredient", "原料经营等级或价格配置无效。")
		cost += int(bounds.cost)
		minimum += int(bounds.cost) + int(bounds.min)
		maximum += int(bounds.cost) + int(bounds.max)
	return {"ok": true, "code": "ok", "message": "", "slots": canonical_result.slots,
		"recipe_id": canonical_result.recipe_id, "minimum": minimum, "maximum": maximum, "cost": cost}

## Generates the permanent record. `picker` receives the inclusive markup range
## and must return an integer; the returned record is not committed here.
static func quote(materials: Variant, lookup: Callable, rules: EconomyRules, picker: Callable, slot_limit: int = MAX_SLOTS) -> Dictionary:
	if not picker.is_valid():
		return _failure("invalid_rules", "报价生成器尚未就绪。")
	var bounds := range_for(materials, lookup, rules, slot_limit)
	if not bounds.ok:
		return bounds
	var slot_costs: Array[int] = []
	var slot_markups: Array[int] = []
	var slot_prices: Array[int] = []
	var slots: Array[Dictionary] = []
	for slot: Dictionary in bounds.slots:
		var definition: IngredientDefinition = lookup.call(slot.ingredient_id)
		var limit := _slot_bounds(definition, rules)
		var picked: Variant = picker.call(limit.min, limit.max)
		if not picked is int:
			return _failure("invalid_markup", "报价加价必须为整数。")
		var markup: int = picked
		if markup < limit.min or markup > limit.max:
			return _failure("invalid_markup", "报价加价超出等级范围。")
		var price: int = int(limit.cost) + markup
		slots.append({"ingredient_id": slot.ingredient_id, "occurrence": slot.occurrence,
			"cost": int(limit.cost), "markup": markup, "price": price})
		slot_costs.append(int(limit.cost))
		slot_markups.append(markup)
		slot_prices.append(price)
	var total := 0
	for price: int in slot_prices:
		total += price
	if total > WalletTransactions.LIMIT:
		return _failure("amount_overflow", "售价超出上限。")
	return {"ok": true, "code": "ok", "message": "", "record": {
		"recipe_id": bounds.recipe_id,
		"slots": slots,
		"slot_costs": slot_costs,
		"slot_markups": slot_markups,
		"slot_prices": slot_prices,
		"selling_price": total,
		"price_generated": true,
		"pricing_version": rules.pricing_version,
	}}

## Recomputes a saved record from static data. Never rolls a new price.
static func validate_record(record: Variant, lookup: Callable, rules: EconomyRules) -> bool:
	if not record is Dictionary or rules == null or not rules.validate():
		return false
	if not record.has_all(["recipe_id", "slots", "slot_costs", "slot_markups", "slot_prices", "selling_price", "price_generated", "pricing_version"]):
		return false
	if not record.recipe_id is String or record.recipe_id.is_empty() or record.price_generated != true:
		return false
	if not _is_int(record.pricing_version) or int(record.pricing_version) != rules.pricing_version:
		return false
	if not record.slots is Array or record.slots.is_empty() or record.slots.size() > MAX_SLOTS:
		return false
	if not record.slot_costs is Array or not record.slot_markups is Array or not record.slot_prices is Array:
		return false
	if record.slot_costs.size() != record.slots.size() or record.slot_markups.size() != record.slots.size() or record.slot_prices.size() != record.slots.size():
		return false
	var materials: Array[String] = []
	var occurrences := {}
	for index in range(record.slots.size()):
		var slot: Variant = record.slots[index]
		if not slot is Dictionary or not slot.has_all(["ingredient_id", "occurrence", "cost", "markup", "price"]) or slot.size() != 5:
			return false
		var definition: IngredientDefinition = lookup.call(slot.ingredient_id)
		if definition == null or definition.economy_scope != "trade":
			return false
		var expected_occurrence: int = int(occurrences.get(slot.ingredient_id, 0))
		occurrences[slot.ingredient_id] = expected_occurrence + 1
		if not slot.ingredient_id is String or not _is_int(slot.occurrence) or int(slot.occurrence) != expected_occurrence:
			return false
		if not _is_int(slot.cost) or not _is_int(slot.markup) or not _is_int(slot.price):
			return false
		var limit := _slot_bounds(definition, rules)
		if limit.is_empty():
			return false
		if int(slot.cost) != int(limit.cost) or int(slot.markup) < limit.min or int(slot.markup) > limit.max or int(slot.price) != int(limit.cost) + int(slot.markup):
			return false
		if not _is_int(record.slot_costs[index]) or not _is_int(record.slot_markups[index]) or not _is_int(record.slot_prices[index]):
			return false
		if int(slot.cost) != int(record.slot_costs[index]) or int(slot.markup) != int(record.slot_markups[index]) or int(slot.price) != int(record.slot_prices[index]):
			return false
		materials.append(slot.ingredient_id)
	var total := 0
	for price: Variant in record.slot_prices:
		if not _is_int(price) or int(price) < 0:
			return false
		total += int(price)
	if not _is_int(record.selling_price) or int(record.selling_price) != total or total > WalletTransactions.LIMIT:
		return false
	var normalized := canonical(materials, lookup)
	if not normalized.ok or record.recipe_id != normalized.recipe_id:
		return false
	for index in range(materials.size()):
		if materials[index] != normalized.slots[index].ingredient_id:
			return false
	return true

## Uses consumed by one cup, keyed by ingredient ID (duplicates add up).
static func uses_for(record: Dictionary) -> Dictionary:
	var uses := {}
	for slot: Dictionary in record.get("slots", []):
		uses[slot.ingredient_id] = int(uses.get(slot.ingredient_id, 0)) + 1
	return uses

static func _slot_bounds(definition: IngredientDefinition, rules: EconomyRules) -> Dictionary:
	if definition.origin == "human":
		if definition.economy_scope != "trade":
			return {}
		return {"cost": 0, "min": EconomyRules.HUMAN_SLOT_MARKUP, "max": EconomyRules.HUMAN_SLOT_MARKUP}
	if definition.economy_tier < 1:
		return {}
	var cost := rules.slot_cost(definition.economy_tier)
	var bounds := rules.markup_range(definition.economy_tier)
	if cost < 0 or bounds.x < 0:
		return {}
	return {"cost": cost, "min": bounds.x, "max": bounds.y}

static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}

static func _is_int(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value))
