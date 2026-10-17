class_name WarehouseInventory
extends Node
## One session, quantities in portions. Never modifies the shared catalog Resource.

signal changed

const CATALOG: TeaMenu = preload("res://src/resources/milk_tea/basic_menu.tres")
const SCHEMA_VERSION: int = 1
const MAX_QUANTITY: int = 2147483647
const PROPERTY_GROUPS: PackedStringArray = ["flavor_tags", "combat_attributes", "special_effects", "acquisition_sources"]

var _definitions: Dictionary = {}
var _state: Dictionary = {}

func _init(menu: TeaMenu = CATALOG) -> void:
	if menu == null:
		return
	# Validate the whole catalog before publishing any runtime state.
	var definitions: Dictionary = {}
	for ingredient in menu.ingredients:
		if ingredient == null or not ingredient.id.is_valid_identifier() or definitions.has(ingredient.id):
			return
		if ingredient.display_name.is_empty() or ingredient.origin not in ["human", "otherworld"]:
			return
		definitions[ingredient.id] = ingredient.duplicate(true)
	for id: Variant in menu.initial_stock:
		if not id is String or not definitions.has(id) or not _is_quantity(menu.initial_stock[id], true):
			return
	for id: Variant in menu.initial_discovery:
		if not id is String or not definitions.has(id) or not _valid_properties(menu.initial_discovery[id]):
			return
	_definitions = definitions
	for id: String in _definitions:
		var amount: int = menu.initial_stock.get(id, 0)
		_state[id] = {"quantity": amount, "discovered": amount > 0 or menu.initial_discovery.has(id),
			"known_properties": Array(menu.initial_discovery.get(id, [])).duplicate()}

func get_definition(id: Variant) -> IngredientDefinition:
	if not _has_id(id):
		return null
	return _definitions[id].duplicate(true)

func get_stock(id: Variant) -> int:
	return _state[id].quantity if _has_id(id) else 0

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
		"quantity": get_stock(id)}
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
	if not _has_id(id) or not _is_quantity(amount) or get_stock(id) > MAX_QUANTITY - amount:
		return false
	_state[id].quantity += amount
	_state[id].discovered = true
	changed.emit()
	return true

func discover(id: Variant) -> bool:
	if not _has_id(id) or is_discovered(id):
		return false
	_state[id].discovered = true
	changed.emit()
	return true

func discover_property(id: Variant, property: Variant) -> bool:
	if not _has_id(id) or not property is String or property not in PROPERTY_GROUPS or is_property_known(id, property):
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
	if not has_materials(materials):
		return false
	for id: String in materials:
		_state[id].quantity -= materials[id]
	changed.emit()
	return true

func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "ingredients": _state.duplicate(true)}

## Complete atomic replacement; accepts a JSON round trip, but no file I/O.
func restore_state(data: Variant) -> Error:
	if not data is Dictionary or not data.has_all(["schema_version", "ingredients"]):
		return ERR_INVALID_DATA
	if not _is_snapshot_integer(data.schema_version) or data.schema_version != SCHEMA_VERSION or not data.ingredients is Dictionary:
		return ERR_INVALID_DATA
	if data.ingredients.size() != _definitions.size():
		return ERR_INVALID_DATA
	var restored: Dictionary = {}
	for id: Variant in data.ingredients:
		if not _has_id(id):
			return ERR_INVALID_DATA
		var entry: Variant = data.ingredients[id]
		if not entry is Dictionary or not entry.has_all(["quantity", "discovered", "known_properties"]):
			return ERR_INVALID_DATA
		if not _is_snapshot_integer(entry.quantity) or entry.quantity < 0 or entry.quantity > MAX_QUANTITY:
			return ERR_INVALID_DATA
		if not entry.discovered is bool or not _valid_properties(entry.known_properties):
			return ERR_INVALID_DATA
		if not entry.discovered and (entry.quantity > 0 or not entry.known_properties.is_empty()):
			return ERR_INVALID_DATA
		restored[id] = {"quantity": int(entry.quantity), "discovered": entry.discovered,
			"known_properties": Array(entry.known_properties).duplicate()}
	if restored != _state:
		_state = restored
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
