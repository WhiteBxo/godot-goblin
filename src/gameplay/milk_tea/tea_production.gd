class_name TeaProduction
extends Node
## GameState owns the session. Crafting produces inventory items, never delivery facts.

signal changed

const CATALOG: Resource = preload("res://src/resources/milk_tea/basic_menu.tres")

var _inventory: WarehouseInventory
var _completed: int = 0
var _submitting: bool = false

func is_submitting() -> bool:
	return _submitting

func to_dict() -> Dictionary:
	var ids: Array[String] = []
	for index in range(_completed):
		ids.append(CATALOG.orders[index].id)
	return {"completed_order_ids": ids}

## The current fixed teaching queue only allows a completed prefix, never gaps.
func is_valid_snapshot(data: Variant) -> bool:
	if not data is Dictionary or not data.get("completed_order_ids") is Array:
		return false
	var ids: Array = data.completed_order_ids
	if ids.size() > CATALOG.orders.size():
		return false
	for index in range(ids.size()):
		if not ids[index] is String or ids[index] != CATALOG.orders[index].id:
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

func configure(inventory: WarehouseInventory) -> void:
	# A business session cannot be rebound or reset by reopening its UI.
	if _inventory != null or inventory == null:
		return
	_inventory = inventory
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

func get_order() -> Dictionary:
	if _completed >= CATALOG.orders.size():
		return {}
	return CATALOG.orders[_completed].duplicate(true)

func get_order_text() -> String:
	var order := get_order()
	if order.is_empty():
		return "今日制作已全部完成 · 共 %d 杯" % _completed
	return "订单 #%03d · %s × 1\n%s · 常温 · 少糖" % [_completed + 1, order.name, " + ".join(get_recipe_names(order.recipe))]

func get_recipe_names(recipe: Array) -> PackedStringArray:
	var names := PackedStringArray()
	for id: String in recipe:
		for ingredient: Dictionary in get_ingredients():
			if ingredient.id == id:
				names.append(ingredient.name)
	return names

func make_drink(recipe: Array[String], order_id: String = "") -> Dictionary:
	if _submitting or not is_instance_valid(_inventory) or _inventory.is_session_locked():
		return {"ok": false, "message": "制作系统尚未就绪或正在制作。"}
	var order := get_order()
	if order.is_empty():
		return {"ok": false, "message": "今日制作已全部完成。"}
	if not order_id.is_empty() and order_id != order.id:
		return {"ok": false, "message": "该制作订单已完成或已变更，请核对当前订单。"}
	var expected: Array = order.recipe.duplicate()
	var selected := recipe.duplicate()
	expected.sort()
	selected.sort()
	if expected != selected:
		return {"ok": false, "message": "原料与订单不符，请核对茶底、奶精和小料。未消耗库存。"}
	var materials: Dictionary = {}
	for id: String in selected:
		materials[id] = int(materials.get(id, 0)) + 1
	if not _inventory.has_materials(materials):
		return {"ok": false, "message": "原料库存不足，无法制作。未消耗库存。"}
	_submitting = true
	# Inventory commits ingredients and the finished cup together. No task mutation.
	# Keep the lock through all synchronous notifications.
	_completed += 1
	if not _inventory.try_exchange(materials, {order.product_id: 1}):
		_completed -= 1
		_submitting = false
		return {"ok": false, "message": "原料不足或成品库存已满。未消耗库存。"}
	changed.emit()
	_submitting = false
	return {"ok": true, "message": "%s制作完成，已放入库存。请携带成品交给指定 NPC。" % order.name}
