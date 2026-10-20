class_name DrinkFormula
extends RefCounted
## Pure calculation. No stock, scene nodes, side effects or mutable shared results.

const LIMIT := 2147483647
const ICE_ID := "ice"
const TAG_KEYS: PackedStringArray = ["flavors", "textures", "effects"]
const TASTE_NAMES: Dictionary = {"sweetness": "甜度", "sourness": "酸度", "bitterness": "苦度", "spiciness": "辣度", "milkiness": "奶香度", "booziness": "酒香度"}

static func describe(drink: Dictionary, show_taste := true) -> String:
	if not drink.has("name"):
		return str(drink.get("message", "暂无饮品。"))
	var names := {}
	for id: String in drink.get("ingredient_names", {}):
		names[id] = drink.ingredient_names[id]
	if drink.get("read_only", false):
		var legacy := PackedStringArray([str(drink.name)])
		legacy.append("历史记录 · 不可出售")
		legacy.append("配方：" + "、".join(PackedStringArray(drink.get("ingredients", []))))
		return "\n".join(legacy)
	var lines := PackedStringArray([str(drink.name), "预设爆品" if not str(drink.signature_id).is_empty() else "普通饮品"])
	var ingredients := PackedStringArray()
	for id: String in drink.counts:
		ingredients.append("%s ×%d" % [drink.ingredient_names[id], drink.counts[id]])
	lines.append("配方：" + "、".join(ingredients))
	lines.append("冰块：" + ("加冰" if drink.get("iced", false) else "不加冰"))
	if show_taste:
		var taste := PackedStringArray()
		for key: String in IngredientDefinition.TASTE_KEYS:
			taste.append("%s %d" % [TASTE_NAMES[key], drink.taste[key]])
		lines.append(" · ".join(taste))
	for index in range(TAG_KEYS.size()):
		lines.append("%s：%s" % [["风味", "口感", "特殊效果"][index], "、".join(drink[TAG_KEYS[index]]) if not drink[TAG_KEYS[index]].is_empty() else "无"])
	lines.append("售价：%s · 单杯成本：%s" % ["未定价" if drink.price <= 0 else "%dG" % drink.price, "未知" if drink.cost == null else "%.2fG" % drink.cost])
	for field: String in ["appearance", "tasting_note", "discovery_note"]:
		if not str(drink.get(field, "")).is_empty():
			lines.append("\n" + str(drink[field]))
	return "\n".join(lines)

## Additive order changes the generated name, but never the identity or signature.
static func key_for(materials: Variant, iced := false) -> String:
	if not materials is Array or materials.is_empty():
		return ""
	var additives: Array[String] = []
	for id: Variant in materials:
		if not id is String or not id.is_valid_identifier():
			return ""
	for index in range(1, materials.size()):
		additives.append(materials[index])
	additives.sort()
	# Keep all existing non-iced IDs stable. Serving variants retain their names
	# independently in stock without changing the underlying ingredient formula.
	var identity: Array = [materials[0], additives]
	if iced:
		identity.append("iced")
	return "drink_" + JSON.stringify(identity).sha256_text()

static func evaluate(materials: Variant, lookup: Callable, rules: RecipeRules, enforce_slots := true, iced := false, signature_access: Callable = Callable()) -> Dictionary:
	if rules == null or rules.slot_count < 1 or rules.slot_count > 16 or rules.ordinary_price < 0 or rules.ordinary_price > LIMIT:
		return _failure("invalid_rules", "配方配置无效。")
	var key := key_for(materials, iced)
	if key.is_empty():
		return _failure("invalid_formula", "请选择一个基底。")
	if (enforce_slots and materials.size() > mini(rules.slot_count, RecipeRules.MAX_SLOTS)) or materials.size() > 64:
		return _failure("slots", "原料超过当前槽位数量。")
	var definitions: Array[IngredientDefinition] = []
	for index in range(materials.size()):
		var id: String = materials[index]
		if enforce_slots and id == ICE_ID:
			return _failure("ice_option", "冰块请使用单独的加冰选项，不占原料槽位。")
		var definition: IngredientDefinition = lookup.call(id)
		if definition == null or not definition.free_recipe_allowed or definition.category in ["product", "story_item"]:
			return _failure("restricted", "存在不可用于普通配方的原料。")
		# Position assigns the role: only slot zero needs base eligibility.
		# A base-capable ingredient in any later slot remains an additive.
		if index == 0 and (not definition.can_be_base or definition.base_suffix not in IngredientDefinition.BASE_SUFFIXES):
			return _failure("base", "第一个槽位必须选择可用基底。")
		definitions.append(definition)
	var base := definitions[0]
	var taste := base.get_taste()
	var tags := {"flavors": [], "textures": [], "effects": []}
	var counts := {}
	var names := {}
	var cost := 0.0
	var cost_known := true
	var roles := {}
	for index in range(definitions.size()):
		var ingredient := definitions[index]
		counts[ingredient.id] = int(counts.get(ingredient.id, 0)) + 1
		names[ingredient.id] = ingredient.display_name
		if ingredient.market_price < 0:
			cost_known = false
		elif ingredient.uses_per_portion > 0:
			cost += float(ingredient.market_price) / ingredient.uses_per_portion
		else:
			return _failure("invalid_ingredient", "原料使用次数配置无效。")
		for tag_index in range(TAG_KEYS.size()):
			var values: PackedStringArray = ingredient.get(["recipe_flavors", "recipe_textures", "recipe_effects"][tag_index])
			for tag: String in values:
				if not tag in tags[TAG_KEYS[tag_index]]:
					tags[TAG_KEYS[tag_index]].append(tag)
		if index > 0:
			for attribute: String in IngredientDefinition.TASTE_KEYS:
				var amount := int(ingredient.get(attribute))
				if amount >= 3:
					taste[attribute] += amount
		if not ingredient.throw_kind.is_empty():
			if rules.throw_tuning == null or not rules.throw_tuning.is_known_kind(ingredient.throw_kind):
				return _failure("unknown_role", "投掷参数缺少原料对应项。")
			roles[ingredient.throw_kind] = int(roles.get(ingredient.throw_kind, 0)) + 1
	var generated_name := base.display_name
	var additive_counts := {}
	for index in range(1, definitions.size()):
		var id := definitions[index].id
		additive_counts[id] = int(additive_counts.get(id, 0)) + 1
	for id: String in additive_counts:
		var count: int = additive_counts[id]
		generated_name += ("双重" if count == 2 else "%d重" % count if count > 2 else "") + str(names[id])
	generated_name += base.base_suffix
	var price := 0
	var signature_id := ""
	var signature_keys := {}
	var signature_ids := {}
	var matched := {}
	for signature: Dictionary in rules.signatures:
		if not signature.has_all(["id", "name", "ingredients"]) or not signature.id is String or not signature.id.is_valid_identifier() or not signature.name is String or signature.name.strip_edges().is_empty() or not signature.ingredients is Array:
			return _failure("invalid_signature", "爆品配置无效。")
		if signature.has("price") and (not signature.price is int or signature.price <= 0 or signature.price > LIMIT):
			return _failure("invalid_signature", "爆品专属售价无效。")
		if signature.has("iced") and not signature.iced is bool:
			return _failure("invalid_signature", "爆品加冰条件无效。")
		var signature_key := key_for(signature.ingredients, signature.get("iced", false))
		if signature_key.is_empty() or signature_keys.has(signature_key) or signature_ids.has(signature.id):
			return _failure("invalid_signature", "爆品配方或 ID 重复。")
		signature_keys[signature_key] = true
		signature_ids[signature.id] = true
		var ice_matches: bool = not signature.has("iced") or iced == signature.iced
		var accessible: bool = not signature_access.is_valid() or bool(signature_access.call(signature.id))
		if key_for(materials) == key_for(signature.ingredients) and ice_matches and accessible:
			signature_id = signature.id
			generated_name = signature.name
			price = int(signature.get("price", 0))
			matched = signature
			for field: String in TAG_KEYS:
				if signature.has(field):
					tags[field] = signature[field].duplicate()
	if iced and signature_id.is_empty():
		generated_name = generated_name.trim_suffix(base.base_suffix) + "冰" + base.base_suffix
	return {"ok": true, "code": "ok", "id": key, "ingredients": materials.duplicate(), "base_id": base.id,
		"name": generated_name, "iced": iced, "taste": taste, "flavors": tags.flavors, "textures": tags.textures,
		"effects": tags.effects, "counts": counts, "ingredient_names": names,
		"price": price, "cost": cost if cost_known else null, "signature_id": signature_id,
		"appearance": matched.get("appearance", ""), "tasting_note": matched.get("tasting_note", ""),
		"discovery_note": matched.get("discovery_note", ""),
		"throw": _throw_parameters(roles, rules.throw_tuning)}

static func _throw_parameters(roles: Dictionary, tuning: ThrowTuning) -> Dictionary:
	if tuning == null:
		return {}
	var area := 1.0
	var duration := tuning.base_duration
	var modifiers := {}
	var effects := {}
	for kind: String in roles:
		var stacks: int = roles[kind]
		var entry: Dictionary = tuning.modifiers.get(kind, tuning.effects.get(kind, {})).duplicate(true)
		entry["stacks"] = stacks
		# Preserve per-copy values and the multiplier, including interval/boolean
		# semantics; the phase-3 executor must not multiply pulse intervals or flags.
		if tuning.modifiers.has(kind):
			modifiers[kind] = entry
			area += float(entry.get("area_cells_add", 0.0)) * stacks
			duration += float(entry.get("duration_add", 0.0)) * stacks
		else:
			effects[kind] = entry
	return {"cell": tuning.cell, "area_cells": minf(area, tuning.max_area_cells),
		"duration": minf(duration, tuning.max_duration), "max_duration": tuning.max_duration,
		"max_area_cells": tuning.max_area_cells, "modifiers": modifiers, "effects": effects}

static func matches(drink: Dictionary, requirement: Dictionary) -> bool:
	if not drink.get("ok", false):
		return false
	if requirement.has("formula") and key_for(requirement.formula) != key_for(drink.ingredients):
		return false
	if requirement.has("base_id") and requirement.base_id != drink.base_id:
		return false
	for field: String in TAG_KEYS:
		for tag: String in requirement.get(field, []):
			if tag not in drink[field]:
				return false
	for attribute: String in requirement.get("minimum_taste", {}):
		if drink.taste.get(attribute, -1) < requirement.minimum_taste[attribute]:
			return false
	return true

static func requirement_valid(value: Variant) -> bool:
	if not value is Dictionary or value.is_empty():
		return false
	for field: Variant in value:
		if field not in ["formula", "base_id", "flavors", "textures", "effects", "minimum_taste"]:
			return false
	if value.has("formula") and (key_for(value.formula).is_empty() or value.formula.size() > 64):
		return false
	if value.has("base_id") and (not value.base_id is String or not value.base_id.is_valid_identifier()):
		return false
	for field: String in TAG_KEYS:
		if not value.has(field):
			continue
		if not value[field] is Array or value[field].is_empty():
			return false
		var seen := {}
		for tag: Variant in value[field]:
			if not tag is String or tag.strip_edges().is_empty() or seen.has(tag):
				return false
			seen[tag] = true
	if value.has("minimum_taste"):
		if not value.minimum_taste is Dictionary or value.minimum_taste.is_empty():
			return false
		for attribute: Variant in value.minimum_taste:
			var amount: Variant = value.minimum_taste[attribute]
			if attribute not in IngredientDefinition.TASTE_KEYS or typeof(amount) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(amount) or amount != floor(amount) or amount < 0 or amount > LIMIT:
				return false
	return true

static func requirement_text(requirement: Dictionary, names: Dictionary = {}) -> String:
	var parts := PackedStringArray()
	if requirement.has("formula"):
		for id: String in requirement.formula:
			parts.append(str(names.get(id, id)))
	elif requirement.has("base_id"):
		parts.append("基底：" + str(names.get(requirement.base_id, requirement.base_id)))
	for field: String in TAG_KEYS:
		for tag: String in requirement.get(field, []):
			parts.append(tag)
	for attribute: String in requirement.get("minimum_taste", {}):
		parts.append("%s ≥ %s" % [TASTE_NAMES.get(attribute, attribute), requirement.minimum_taste[attribute]])
	return "、".join(parts)

static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
