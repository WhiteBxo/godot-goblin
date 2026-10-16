class_name TeaProduction
extends Node
## One shop session. Only this component mutates stock and order progress.

signal changed

const CATALOG: Resource = preload("res://src/resources/milk_tea/basic_menu.tres")

var _stock: Dictionary = {}
var _completed: int = 0

func _init() -> void:
	_stock = CATALOG.initial_stock.duplicate(true)

func get_ingredients() -> Array[Dictionary]:
	return CATALOG.ingredients.duplicate(true)

func get_stock(id: String) -> int:
	return int(_stock.get(id, 0))

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
		for ingredient: Dictionary in CATALOG.ingredients:
			if ingredient.id == id:
				names.append(ingredient.name)
	return names

func make_drink(recipe: Array[String]) -> Dictionary:
	var order := get_order()
	if order.is_empty():
		return {"ok": false, "message": "今日订单已全部完成。"}
	var expected: Array = order.recipe.duplicate()
	var selected := recipe.duplicate()
	expected.sort()
	selected.sort()
	if expected != selected:
		return {"ok": false, "message": "原料与订单不符，请核对茶底、奶精和小料。未消耗库存。"}
	# Check every ingredient before committing any change.
	for id: String in selected:
		if get_stock(id) < 1:
			return {"ok": false, "message": "原料库存不足，无法制作。未消耗库存。"}
	for id: String in selected:
		_stock[id] -= 1
	_completed += 1
	changed.emit()
	return {"ok": true, "message": "%s制作完成，已交付订单 #%03d！" % [order.name, _completed]}
