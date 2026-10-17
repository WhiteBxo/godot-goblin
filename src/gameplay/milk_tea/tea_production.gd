class_name TeaProduction
extends Node
## One shop session. Inventory is injected; only this component commits orders.

signal changed

const CATALOG: Resource = preload("res://src/resources/milk_tea/basic_menu.tres")

var _inventory: WarehouseInventory
var _completed: int = 0
var _submitting: bool = false

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
		return "今日订单已全部完成 · 共 %d 杯" % _completed
	return "订单 #%03d · %s × 1\n%s · 常温 · 少糖" % [_completed + 1, order.name, " + ".join(get_recipe_names(order.recipe))]

func get_recipe_names(recipe: Array) -> PackedStringArray:
	var names := PackedStringArray()
	for id: String in recipe:
		for ingredient: Dictionary in get_ingredients():
			if ingredient.id == id:
				names.append(ingredient.name)
	return names

func make_drink(recipe: Array[String], order_id: String = "") -> Dictionary:
	if _submitting or not is_instance_valid(_inventory):
		return {"ok": false, "message": "制作系统尚未就绪或正在交付。"}
	var order := get_order()
	if order.is_empty():
		return {"ok": false, "message": "今日订单已全部完成。"}
	if not order_id.is_empty() and order_id != order.id:
		return {"ok": false, "message": "该订单已交付或已变更，请核对当前订单。"}
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
	# No await or signal between validation and commit. Inventory listeners see
	# both the new order count and fully consumed stock; reject synchronous reentry.
	_completed += 1
	if not _inventory.try_consume(materials):
		_completed -= 1
		_submitting = false
		return {"ok": false, "message": "原料库存不足，无法制作。未消耗库存。"}
	changed.emit()
	_submitting = false
	return {"ok": true, "message": "%s制作完成，已交付订单 #%03d！" % [order.name, _completed]}
