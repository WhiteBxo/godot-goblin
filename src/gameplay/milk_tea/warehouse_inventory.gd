class_name WarehouseInventory
extends Node
## Quantities in portions; lifetime is controlled by its owner. Never modifies the shared catalog Resource.
## A portion holds uses_per_portion uses (1 for every item outside the 2026-10-18
## sheet). `quantity` counts portions including one opened portion; `used` is how
## many uses that opened portion has spent. Free recipes spend uses; deliveries,
## payments, throws and the fixed teaching recipes keep taking whole portions.

signal changed

const CATALOG: TeaMenu = preload("res://src/resources/milk_tea/basic_menu.tres")
const SCHEMA_VERSION: int = 3
const MAX_QUANTITY: int = 2147483647
const PROPERTY_GROUPS: PackedStringArray = ["flavor_tags", "combat_attributes", "special_effects", "acquisition_sources"]

var _definitions: Dictionary = {}
var _state: Dictionary = {}
var _drinks: Dictionary = {}
var _encyclopedia: Dictionary = {}
var _rules: RecipeRules
var _session_locked := false

## Used by the owning GameState while publishing a complete replacement.
func set_session_locked(locked: bool) -> void:
	_session_locked = locked

func is_session_locked() -> bool:
	return _session_locked

func _init(menu: TeaMenu = CATALOG) -> void:
	if menu == null:
		return
	# Validate the whole catalog before publishing any runtime state.
	var definitions: Dictionary = {}
	for ingredient in menu.ingredients:
		if ingredient == null or not ingredient.id.is_valid_identifier() or definitions.has(ingredient.id):
			return
		if ingredient.display_name.is_empty() or ingredient.origin not in ["human", "otherworld"] or ingredient.uses_per_portion < 1:
			return
		definitions[ingredient.id] = ingredient.duplicate(true)
	for id: Variant in menu.initial_stock:
		if not id is String or not definitions.has(id) or not _is_quantity(menu.initial_stock[id], true):
			return
	for id: Variant in menu.initial_discovery:
		if not id is String or not definitions.has(id) or not _valid_properties(menu.initial_discovery[id]):
			return
	_definitions = definitions
	_rules = menu.recipe_rules.duplicate(true) if menu.recipe_rules != null else null
	for id: String in _definitions:
		var amount: int = menu.initial_stock.get(id, 0)
		_state[id] = {"quantity": amount, "used": 0, "discovered": amount > 0 or menu.initial_discovery.has(id),
			"known_properties": Array(menu.initial_discovery.get(id, [])).duplicate()}

func get_definition(id: Variant) -> IngredientDefinition:
	if not _has_id(id):
		return null
	return _definitions[id].duplicate(true)

func get_stock(id: Variant) -> int:
	return _state[id].quantity if _has_id(id) else 0

func get_recipe_slots() -> int:
	return _rules.slot_count if _rules != null else 0

func calculate_formula(materials: Variant, enforce_slots := true, iced := false) -> Dictionary:
	return DrinkFormula.evaluate(materials, get_definition, _rules, enforce_slots, iced)

func get_formula_choices(base_only := false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _definitions:
		var definition: IngredientDefinition = _definitions[id]
		if id != DrinkFormula.ICE_ID and is_discovered(id) and definition.free_recipe_allowed and (not base_only or definition.can_be_base):
			var flavors := definition.recipe_flavors.duplicate() if is_property_known(id, "flavor_tags") else PackedStringArray(["未知风味"])
			result.append({"id": id, "name": definition.display_name, "flavors": flavors, "uses": get_uses(id)})
	return result

func get_drink_stock(id: Variant) -> int:
	return int(_drinks.get(id, 0)) if id is String else 0

## Consume finished cups, keeping their discovery record. Shared with selling.
func try_consume_drink(id: Variant, quantity: int = 1) -> bool:
	if _session_locked or not _is_quantity(quantity) or get_drink_stock(id) < quantity:
		return false
	_drinks[id] -= quantity
	changed.emit()
	return true

func get_drink_record(id: Variant) -> Dictionary:
	if not id is String or not _encyclopedia.has(id):
		return {}
	var entry: Dictionary = _encyclopedia[id]
	# Historical drinks remain valid when the configured slot count is reduced.
	var result := calculate_formula(entry.ingredients, false, entry.get("iced", false))
	if not result.ok:
		return {}
	result["quantity"] = get_drink_stock(id)
	result["discovered_day"] = int(entry.discovered_day)
	return result

func get_drinks(include_empty := false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _encyclopedia:
		if include_empty or get_drink_stock(id) > 0:
			result.append(get_drink_record(id))
	return result

func preview_formula(materials: Variant, quantity: int = 1, iced := false) -> Dictionary:
	var result := calculate_formula(materials, true, iced)
	if not result.ok:
		return result
	if not _is_quantity(quantity):
		return {"ok": false, "code": "invalid_quantity", "message": "制作杯数无效。"}
	if _encyclopedia.has(result.id):
		result = get_drink_record(result.id)
	result["quantity"] = quantity
	result["missing"] = {}
	for id: String in result.counts:
		var required: int = int(result.counts[id]) * quantity
		if not is_discovered(id) or get_uses(id) < required:
			result.missing[id] = required - get_uses(id)
	if not result.missing.is_empty():
		result.ok = false
		result.code = "missing_uses"
		result["message"] = "原料可用次数不足。未消耗库存。"
	elif get_drink_stock(result.id) > MAX_QUANTITY - quantity:
		result.ok = false
		result.code = "capacity"
		result["message"] = "该配方成品库存已满。未消耗库存。"
	return result

## The inventory owns portions, dynamic products and first-discovery records, so
## observers see all three together in one notification.
func try_make_formula(materials: Variant, quantity: int = 1, day: int = 1, iced := false) -> Dictionary:
	if _session_locked:
		return {"ok": false, "code": "busy", "message": "会话正在更新。"}
	var result := preview_formula(materials, quantity, iced)
	if not result.ok or day < 1:
		return result if not result.ok else {"ok": false, "code": "invalid_day", "message": "发现日期无效。"}
	var first := not _encyclopedia.has(result.id)
	for id: String in result.counts:
		_set_uses(id, get_uses(id) - int(result.counts[id]) * quantity)
	_drinks[result.id] = get_drink_stock(result.id) + quantity
	if first:
		_encyclopedia[result.id] = {"ingredients": materials.duplicate(), "discovered_day": day}
		if iced:
			_encyclopedia[result.id]["iced"] = true
	result["first_discovery"] = first
	result["message"] = "%s ×%d 已入库%s。" % [result.name, quantity, "，已记入饮品图鉴" if first else ""]
	changed.emit()
	return result

func get_uses_per_portion(id: Variant) -> int:
	return _definitions[id].uses_per_portion if _has_id(id) else 1

## Remaining uses across all portions, counting the opened one's spent uses.
func get_uses(id: Variant) -> int:
	if not _has_id(id):
		return 0
	return _state[id].quantity * get_uses_per_portion(id) - _state[id].used

func has_uses(uses: Variant) -> bool:
	if not uses is Dictionary or uses.is_empty():
		return false
	for id: Variant in uses:
		if not _has_id(id) or not _is_quantity(uses[id]) or not is_discovered(id) or get_uses(id) < uses[id]:
			return false
	return true

## Spends single uses (free recipe steps) and optionally adds whole products in the
## same notification. Nothing changes unless every entry and capacity check passes.
func try_spend_uses(uses: Variant, acquired: Variant = {}) -> bool:
	if _session_locked or not has_uses(uses) or not acquired is Dictionary:
		return false
	for id: Variant in acquired:
		if not _has_id(id) or not _is_quantity(acquired[id]):
			return false
		var remaining := _portions_for_uses(get_uses(id) - int(uses.get(id, 0)), get_uses_per_portion(id))
		if remaining > MAX_QUANTITY - acquired[id]:
			return false
	for id: String in uses:
		_set_uses(id, get_uses(id) - int(uses[id]))
	for id: String in acquired:
		_state[id].quantity += acquired[id]
		_state[id].discovered = true
	changed.emit()
	return true

func _set_uses(id: String, remaining: int) -> void:
	var per := get_uses_per_portion(id)
	var portions := _portions_for_uses(remaining, per)
	_state[id].quantity = portions
	_state[id].used = portions * per - remaining

func _portions_for_uses(remaining: int, per: int) -> int:
	@warning_ignore("integer_division")
	return remaining / per + (1 if remaining % per != 0 else 0)

func is_discovered(id: Variant) -> bool:
	return _has_id(id) and _state[id].discovered

func is_property_known(id: Variant, property: Variant) -> bool:
	return is_discovered(id) and property is String and property in _state[id].known_properties

func get_discovery(id: Variant) -> Dictionary:
	if not _has_id(id):
		return {}
	return {"discovered": is_discovered(id), "known_properties": _state[id].known_properties.duplicate()}

## A masked presentation view: unknown properties never reach the UI as real text.
func get_ingredient_view(id: Variant) -> Dictionary:
	if not is_discovered(id):
		return {}
	var definition: IngredientDefinition = _definitions[id]
	var view := {"id": id, "name": definition.display_name, "icon": definition.icon,
		"origin": definition.origin, "category": definition.category, "rarity": definition.rarity,
		"form": definition.form, "processing_methods": definition.processing_methods,
		"price": definition.price, "description": definition.description,
		"quantity": get_stock(id), "uses": get_uses(id), "uses_per_portion": definition.uses_per_portion,
		"current_portion_uses": definition.uses_per_portion - _state[id].used if get_stock(id) > 0 else 0}
	for property: String in PROPERTY_GROUPS:
		view[property] = definition.get(property).duplicate() if is_property_known(id, property) else PackedStringArray(["???"])
	return view

func get_ingredients(origin: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _definitions:
		if is_discovered(id) and (origin.is_empty() or _definitions[id].origin == origin):
			result.append(get_ingredient_view(id))
	return result

func add_ingredient(id: Variant, amount: Variant) -> bool:
	if _session_locked or not _has_id(id) or not _is_quantity(amount) or get_stock(id) > MAX_QUANTITY - amount:
		return false
	_state[id].quantity += amount
	_state[id].discovered = true
	changed.emit()
	return true

func discover(id: Variant) -> bool:
	if _session_locked or not _has_id(id) or is_discovered(id):
		return false
	_state[id].discovered = true
	changed.emit()
	return true

func discover_property(id: Variant, property: Variant) -> bool:
	if _session_locked or not _has_id(id) or not property is String or property not in PROPERTY_GROUPS or is_property_known(id, property):
		return false
	_state[id].discovered = true
	_state[id].known_properties.append(property)
	changed.emit()
	return true

func has_materials(materials: Variant) -> bool:
	if not materials is Dictionary or materials.is_empty():
		return false
	for id: Variant in materials:
		if not _has_id(id) or not _is_quantity(materials[id]) or not is_discovered(id) or get_stock(id) < materials[id]:
			return false
	return true

## No notification or mutation occurs until every entry passes validation.
func try_consume(materials: Variant) -> bool:
	return try_exchange(materials, {})

## Validate costs and gains together, including capacity, before publishing either.
## Whole portions leave unopened ones first; the opened portion goes last.
func try_exchange(materials: Variant, acquired: Variant) -> bool:
	if _session_locked or not materials is Dictionary or not acquired is Dictionary or (materials.is_empty() and acquired.is_empty()):
		return false
	if not materials.is_empty() and not has_materials(materials):
		return false
	for id: Variant in acquired:
		if not _has_id(id) or not _is_quantity(acquired[id]):
			return false
		var remaining: int = get_stock(id) - int(materials.get(id, 0))
		if remaining > MAX_QUANTITY - acquired[id]:
			return false
	for id: String in materials:
		_state[id].quantity -= materials[id]
		if _state[id].quantity == 0:
			_state[id].used = 0
	for id: String in acquired:
		_state[id].quantity += acquired[id]
		_state[id].discovered = true
	changed.emit()
	return true

func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "ingredients": _state.duplicate(true),
		"drinks": _drinks.duplicate(), "encyclopedia": _encyclopedia.duplicate(true)}

## Version 1 predates opened portions: every entry was whole.
static func migrate_snapshot(data: Variant) -> Variant:
	if not data is Dictionary or not data.get("schema_version") is int and not data.get("schema_version") is float:
		return data
	if data.schema_version not in [1, 2] or not data.get("ingredients") is Dictionary:
		return data
	if data.has("drinks") or data.has("encyclopedia"):
		return data
	var migrated: Dictionary = data.duplicate(true)
	if data.schema_version == 1:
		for id: Variant in migrated.ingredients:
			var entry: Variant = migrated.ingredients[id]
			if not entry is Dictionary or entry.size() != 3 or not entry.has_all(["quantity", "discovered", "known_properties"]):
				return data
			entry["used"] = 0
	migrated.schema_version = SCHEMA_VERSION
	migrated["drinks"] = {}
	migrated["encyclopedia"] = {}
	return migrated

## Validate a complete snapshot without mutation; accepts a JSON numeric round trip.
func validate_state(data: Variant) -> Error:
	if not data is Dictionary or not data.has_all(["schema_version", "ingredients", "drinks", "encyclopedia"]):
		return ERR_INVALID_DATA
	if not _is_snapshot_integer(data.schema_version) or data.schema_version != SCHEMA_VERSION or not data.ingredients is Dictionary:
		return ERR_INVALID_DATA
	if data.ingredients.size() != _definitions.size():
		return ERR_INVALID_DATA
	for id: Variant in data.ingredients:
		if not _has_id(id):
			return ERR_INVALID_DATA
		var entry: Variant = data.ingredients[id]
		if not entry is Dictionary or not entry.has_all(["quantity", "used", "discovered", "known_properties"]) or entry.size() != 4:
			return ERR_INVALID_DATA
		if not _is_snapshot_integer(entry.quantity) or entry.quantity < 0 or entry.quantity > MAX_QUANTITY:
			return ERR_INVALID_DATA
		# Only an existing portion can be opened, and never fully spent.
		if not _is_snapshot_integer(entry.used) or entry.used < 0 or entry.used >= get_uses_per_portion(id) or (entry.quantity == 0 and entry.used != 0):
			return ERR_INVALID_DATA
		if not entry.discovered is bool or not _valid_properties(entry.known_properties):
			return ERR_INVALID_DATA
		if not entry.discovered and (entry.quantity > 0 or not entry.known_properties.is_empty()):
			return ERR_INVALID_DATA
	if not data.drinks is Dictionary or not data.encyclopedia is Dictionary:
		return ERR_INVALID_DATA
	for id: Variant in data.encyclopedia:
		var entry: Variant = data.encyclopedia[id]
		if not id is String or not entry is Dictionary or not entry.has_all(["ingredients", "discovered_day"]):
			return ERR_INVALID_DATA
		if entry.size() != (3 if entry.has("iced") else 2) or (entry.has("iced") and not entry.iced is bool):
			return ERR_INVALID_DATA
		if not _is_snapshot_integer(entry.discovered_day) or entry.discovered_day < 1:
			return ERR_INVALID_DATA
		var formula := calculate_formula(entry.ingredients, false, entry.get("iced", false))
		if not formula.ok or formula.id != id:
			return ERR_INVALID_DATA
	for id: Variant in data.drinks:
		if not data.encyclopedia.has(id) or not _is_snapshot_integer(data.drinks[id]) or data.drinks[id] < 0 or data.drinks[id] > MAX_QUANTITY:
			return ERR_INVALID_DATA
	return OK

## Silent replacement lets the transaction owner publish all participants together.
func restore_state(data: Variant, notify: bool = true) -> Error:
	if _session_locked:
		return ERR_BUSY
	data = migrate_snapshot(data)
	if validate_state(data) != OK:
		return ERR_INVALID_DATA
	var restored: Dictionary = {}
	for id: String in data.ingredients:
		var entry: Dictionary = data.ingredients[id]
		restored[id] = {"quantity": int(entry.quantity), "used": int(entry.used), "discovered": entry.discovered,
			"known_properties": Array(entry.known_properties).duplicate()}
	var drinks := {}
	for id: String in data.drinks:
		drinks[id] = int(data.drinks[id])
	var encyclopedia: Dictionary = data.encyclopedia.duplicate(true)
	for entry: Dictionary in encyclopedia.values():
		entry.discovered_day = int(entry.discovered_day)
	if restored != _state or drinks != _drinks or encyclopedia != _encyclopedia:
		_state = restored
		_drinks = drinks
		_encyclopedia = encyclopedia
		if notify:
			changed.emit()
	return OK

func _has_id(id: Variant) -> bool:
	return id is String and _definitions.has(id)

func _is_quantity(amount: Variant, allow_zero: bool = false) -> bool:
	return amount is int and amount >= (0 if allow_zero else 1) and amount <= MAX_QUANTITY

func _is_snapshot_integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value))

func _valid_properties(properties: Variant) -> bool:
	if not properties is Array and not properties is PackedStringArray:
		return false
	var seen: Dictionary = {}
	for property: Variant in properties:
		if not property is String or property not in PROPERTY_GROUPS or seen.has(property):
			return false
		seen[property] = true
	return true
