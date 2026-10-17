class_name TeaProduction
extends Node
## GameState owns the session. Crafting produces inventory items, never delivery facts.

signal changed

const CATALOG: Resource = preload("res://src/resources/milk_tea/basic_menu.tres")

var _menu: TeaMenu = CATALOG
var _state: Node

var _inventory: WarehouseInventory
var _completed: int = 0
var _submitting: bool = false
var _recipes: Array[TeaRecipe] = []
var _by_key: Dictionary = {}
var _by_product: Dictionary = {}
var _recipe_errors := PackedStringArray()

func _init() -> void:
	_rebuild_recipes()

func select_menu(menu: TeaMenu) -> void:
	_menu = menu
	_rebuild_recipes()

func is_submitting() -> bool:
	return _submitting

func to_dict() -> Dictionary:
	var ids: Array[String] = []
	for index in range(_completed):
		ids.append(_menu.orders[index].id)
	return {"completed_order_ids": ids}

## The selected order queue only allows a completed prefix, never gaps.
func is_valid_snapshot(data: Variant) -> bool:
	if not data is Dictionary or not data.get("completed_order_ids") is Array:
		return false
	var ids: Array = data.completed_order_ids
	if ids.size() > _menu.orders.size():
		return false
	for index in range(ids.size()):
		if not ids[index] is String or ids[index] != _menu.orders[index].id:
			return false
	return true

func restore_state(data: Variant) -> Error:
	if _submitting or (is_instance_valid(_inventory) and _inventory.is_session_locked()):
		return ERR_BUSY
	if not is_valid_snapshot(data):
		return ERR_INVALID_DATA
	if _completed != data.completed_order_ids.size():
		_completed = data.completed_order_ids.size()
		changed.emit()
	return OK

func configure(inventory: WarehouseInventory, state: Node = null) -> void:
	# A business session cannot be rebound or reset by reopening its UI.
	if _inventory != null or inventory == null:
		return
	_inventory = inventory
	_state = state
	if is_instance_valid(_state):
		_state.state_changed.connect(_on_inventory_changed)
	_inventory.changed.connect(_on_inventory_changed)

func get_inventory() -> WarehouseInventory:
	return _inventory

func _on_inventory_changed() -> void:
	if not _submitting:
		changed.emit()

func get_ingredients() -> Array[Dictionary]:
	return _inventory.get_ingredients() if is_instance_valid(_inventory) else []

func get_stock(id: String) -> int:
	return _inventory.get_stock(id) if is_instance_valid(_inventory) else 0

func get_completed_count() -> int:
	return _completed

func get_recipes() -> Array[TeaRecipe]:
	var result: Array[TeaRecipe] = []
	for recipe: TeaRecipe in _recipes:
		result.append(recipe.duplicate(true) as TeaRecipe)
	return result

## Recipes the current session may offer; locked ones stay invisible to the UI.
func get_available_recipes() -> Array[TeaRecipe]:
	var result: Array[TeaRecipe] = []
	if _menu.recipe_book == null:
		return result
	return _menu.recipe_book.get_recipes_for(_state)

func get_recipe_by_product(product_id: String) -> TeaRecipe:
	var recipe: TeaRecipe = _by_product.get(product_id)
	return recipe.duplicate(true) as TeaRecipe if recipe != null else null

func get_recipe_errors() -> PackedStringArray:
	return _recipe_errors.duplicate()

func get_item_name(id: String) -> String:
	if not is_instance_valid(_inventory):
		return id
	var definition := _inventory.get_definition(id)
	return definition.display_name if definition != null else id

func get_order() -> Dictionary:
	if _completed >= _menu.orders.size():
		return {}
	var order: Dictionary = _menu.orders[_completed]
	if order.has("accepted_flag") and (not is_instance_valid(_state) or not _state.get_flag(order.accepted_flag)):
		return {}
	var copy: Dictionary = order.duplicate(true)
	var recipe := get_recipe_by_product(str(copy.get("product_id", "")))
	copy["recipe"] = recipe.materials.duplicate() if recipe != null else []
	return copy

func get_order_text() -> String:
	var order := get_order()
	if order.is_empty():
		return "今日制作已全部完成 · 共 %d 杯" % _completed if _completed >= _menu.orders.size() else "当前没有已接取订单，请查看订单板。"
	return "订单 #%03d · %s × 1\n%s · 常温 · 少糖" % [_completed + 1, order.name, " + ".join(get_recipe_names(order.recipe))]

func get_recipe_names(recipe: Array) -> PackedStringArray:
	var names := PackedStringArray()
	for id: String in recipe:
		for ingredient: Dictionary in get_ingredients():
			if ingredient.id == id:
				names.append(ingredient.name)
	return names

## Pure preview used by both the UI and craft(); never mutates stock or order progress.
func preview_craft(materials: Array, quantity: int = 1) -> Dictionary:
	var normalized: Array[String] = []
	for id: Variant in materials:
		if id is String and not id.is_empty():
			normalized.append(id)
	var result := {"code": "busy", "recipe_id": "", "product_id": "", "product_name": "",
		"materials": normalized, "quantity": quantity, "missing": {}, "advances_order": false, "order_id": "",
		"message": "制作系统尚未就绪。"}
	if not is_instance_valid(_inventory):
		return result
	if quantity < 1 or quantity > WarehouseInventory.MAX_QUANTITY:
		result.code = "invalid_quantity"
		result.message = "制作杯数必须为 1 至 %d。" % WarehouseInventory.MAX_QUANTITY
		return result
	if normalized.is_empty():
		result.code = "empty"
		result.message = "请从左侧选择原料。"
		return result
	for id: String in normalized:
		if _inventory.get_definition(id) == null:
			result.code = "unknown_material"
			result.message = "存在无法识别的原料，未消耗库存。"
			return result
	var recipe := _recipe_for_key(TeaRecipe.key_for(normalized))
	if recipe == null:
		result.code = "unknown_recipe"
		result.message = "这不是已知配方，未消耗库存。"
		return result
	# A gated recipe never leaks its product or its material shortfall.
	if not recipe.is_available(_state):
		result.code = "locked"
		result.message = "该配方尚未解锁。未消耗库存。"
		return result
	var costs := _counts(normalized)
	var missing: Dictionary = {}
	for id: String in costs:
		var lack: int = int(costs[id]) * quantity - _inventory.get_stock(id)
		if lack > 0:
			missing[id] = lack
	result.code = "ok"
	result.recipe_id = recipe.id
	result.product_id = recipe.product_id
	result.product_name = get_item_name(recipe.product_id)
	var order := get_order()
	result.order_id = str(order.get("id", ""))
	result.advances_order = not order.is_empty() and str(order.get("product_id", "")) == recipe.product_id
	if not missing.is_empty():
		result.code = "missing_materials"
		result.missing = missing
		result.message = "原料不足：%s。未消耗库存。" % _missing_text(missing)
		return result
	if _inventory.get_stock(recipe.product_id) > WarehouseInventory.MAX_QUANTITY - quantity:
		result.code = "capacity"
		result.message = "成品库存容量不足。未消耗库存。"
		return result
	result.message = "%s ×%d 制作完成，已放入库存。" % [result.product_name, quantity]
	if result.advances_order:
		result.message = "%s ×%d 制作完成，已放入库存并计入当前订单。" % [result.product_name, quantity]
	return result

## Capacity is limited by every ingredient and by the product inventory ceiling.
func get_max_craftable(materials: Array) -> int:
	var preview := preview_craft(materials)
	if preview.code != "ok":
		return 0
	var maximum: int = WarehouseInventory.MAX_QUANTITY - get_stock(preview.product_id)
	var costs := _counts(materials)
	for id: String in costs:
		maximum = mini(maximum, int(get_stock(id) / int(costs[id])))
	return maximum

## Free crafting: the only commit path for both the crafting panel and make_drink().
func craft(materials: Array, quantity: int = 1) -> Dictionary:
	if _submitting or not is_instance_valid(_inventory) or _inventory.is_session_locked():
		return {"ok": false, "code": "busy", "message": "制作系统尚未就绪或正在制作。"}
	var preview := preview_craft(materials, quantity)
	if preview.code != "ok":
		# Return the whole preview so callers keep the details, e.g. the missing
		# amounts, instead of only the code.
		var rejected: Dictionary = preview.duplicate(true)
		rejected.ok = false
		return rejected
	var costs := _counts(preview.materials)
	for id: String in costs:
		costs[id] *= quantity
	_submitting = true
	var completed_before := _completed
	# Count only the contiguous, accepted orders fulfilled by this batch.
	for _cup in range(mini(quantity, _menu.orders.size() - _completed)):
		var order := get_order()
		if order.is_empty() or str(order.get("product_id", "")) != preview.product_id:
			break
		_completed += 1
	# Publish complete progress together with the single inventory exchange.
	if not _inventory.try_exchange(costs, {preview.product_id: quantity}):
		_completed = completed_before
		_submitting = false
		return {"ok": false, "code": "capacity", "message": "原料不足或成品库存已满。未消耗库存。"}
	changed.emit()
	_submitting = false
	var result: Dictionary = preview.duplicate(true)
	result.ok = true
	return result

## Order-bound entry kept for existing flows: only the accepted current order may be produced.
func make_drink(recipe: Array[String], order_id: String = "") -> Dictionary:
	if _submitting or not is_instance_valid(_inventory) or _inventory.is_session_locked():
		return {"ok": false, "code": "busy", "message": "制作系统尚未就绪或正在制作。"}
	var order := get_order()
	if order.is_empty():
		return {"ok": false, "code": "no_order", "message": "今日制作已全部完成。"}
	if not order_id.is_empty() and order_id != order.id:
		return {"ok": false, "code": "stale_order", "message": "该制作订单已完成或已变更，请核对当前订单。"}
	var expected: Array = order.recipe.duplicate()
	var selected: Array = recipe.duplicate()
	expected.sort()
	selected.sort()
	if expected != selected:
		return {"ok": false, "code": "wrong_recipe", "message": "原料与订单不符，请核对茶底、奶精和小料。未消耗库存。"}
	return craft(recipe)

static func validate_menu(menu: TeaMenu) -> PackedStringArray:
	var errors := PackedStringArray()
	if menu == null:
		errors.append("菜单为空")
		return errors
	var definitions: Dictionary = {}
	for ingredient in menu.ingredients:
		if ingredient != null and not ingredient.id.is_empty():
			definitions[ingredient.id] = ingredient
	var recipe_ids: Dictionary = {}
	var material_keys: Dictionary = {}
	var recipe_products: Dictionary = {}
	for recipe: TeaRecipe in menu.get_recipes():
		if recipe == null:
			errors.append("配方为空")
			continue
		if recipe.id.is_empty() or not recipe.id.is_valid_identifier() or recipe_ids.has(recipe.id):
			errors.append("配方 ID 非法或重复：%s" % recipe.id)
			continue
		recipe_ids[recipe.id] = true
		# Menus share one recipe book, so a gated recipe whose product is absent from
		# this menu belongs to a sibling menu and is validated there instead.
		if not recipe.required_flag.is_empty() and not definitions.has(recipe.product_id):
			continue
		var product: IngredientDefinition = definitions.get(recipe.product_id)
		if product == null or product.category != "product":
			errors.append("配方 %s 的成品不存在或不是成品" % recipe.id)
		else:
			recipe_products[recipe.product_id] = true
		if recipe.materials.is_empty():
			errors.append("配方 %s 没有原料" % recipe.id)
			continue
		for id: String in recipe.materials:
			var material: IngredientDefinition = definitions.get(id)
			if material == null or material.category in ["product", "story_item"]:
				errors.append("配方 %s 的原料非法：%s" % [recipe.id, id])
		var key := recipe.get_material_key()
		if material_keys.has(key):
			errors.append("配方 %s 与其他配方原料重复" % recipe.id)
		material_keys[key] = true
	var order_ids: Dictionary = {}
	for order: Variant in menu.orders:
		if not order is Dictionary:
			errors.append("订单格式非法")
			continue
		var order_id := str(order.get("id", ""))
		if order_id.is_empty() or order_ids.has(order_id):
			errors.append("订单 ID 非法或重复：%s" % order_id)
		order_ids[order_id] = true
		if not recipe_products.has(str(order.get("product_id", ""))):
			errors.append("订单 %s 没有可用的配方" % order_id)
		if order.has("accepted_flag") and not order.accepted_flag is String:
			errors.append("订单 %s 的 accepted_flag 非法" % order_id)
	return errors

func _rebuild_recipes() -> void:
	_recipes.clear()
	_by_key.clear()
	_by_product.clear()
	_recipe_errors = validate_menu(_menu)
	if not _recipe_errors.is_empty():
		push_error("Tea menu has invalid recipes: " + "；".join(_recipe_errors))
	for source: TeaRecipe in _menu.get_recipes():
		if source == null:
			continue
		var recipe := source.duplicate(true) as TeaRecipe
		_recipes.append(recipe)
		_by_key[recipe.get_material_key()] = recipe
		if not _by_product.has(recipe.product_id):
			_by_product[recipe.product_id] = recipe

func _recipe_for_key(key: String) -> TeaRecipe:
	return _by_key.get(key)

func _counts(materials: Array) -> Dictionary:
	var counts: Dictionary = {}
	for id: Variant in materials:
		if id is String and not id.is_empty():
			counts[id] = int(counts.get(id, 0)) + 1
	return counts

func _missing_text(missing: Dictionary) -> String:
	var parts := PackedStringArray()
	for id: String in missing:
		parts.append("%s ×%d" % [get_item_name(id), missing[id]])
	return "、".join(parts)
