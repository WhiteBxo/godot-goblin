class_name TeaProductionPanel
extends VBoxContainer

signal make_requested(recipe: Array[String], order_id: String)

var _production: TeaProduction
var _selectors: Array[OptionButton] = []
var _order: Label
var _result: Label
var _make: Button
var _order_id: String = ""

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_order = Label.new()
	_order.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_order)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	for title: String in ["茶底", "奶精", "小料"]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		var label := Label.new()
		label.text = title
		column.add_child(label)
		var selector := OptionButton.new()
		selector.custom_minimum_size = Vector2(130, 30)
		selector.fit_to_longest_item = false
		column.add_child(selector)
		_selectors.append(selector)
	_make = Button.new()
	_make.text = "制作并交付 · 常温 / 少糖"
	_make.custom_minimum_size.y = 32
	_make.pressed.connect(_request_make)
	add_child(_make)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size.y = 36
	add_child(_result)

func configure(production: TeaProduction) -> void:
	if is_instance_valid(_production) and _production.changed.is_connected(refresh):
		_production.changed.disconnect(refresh)
	_production = production
	_production.changed.connect(refresh)

func refresh(clear_result: bool = false) -> void:
	_order.text = _production.get_order_text()
	_order_id = _production.get_order().get("id", "")
	var categories: Array[String] = ["tea", "milk", "topping"]
	for index in range(_selectors.size()):
		var selector := _selectors[index]
		var previous: String = ""
		if selector.selected >= 0:
			previous = str(selector.get_selected_metadata())
		selector.clear()
		selector.add_item("请选择" if index < 2 else "不加小料")
		selector.set_item_metadata(0, "")
		for ingredient in _production.get_ingredients():
			if ingredient.category != categories[index]:
				continue
			var amount := _production.get_stock(ingredient.id)
			selector.add_item("%s · %d份" % [ingredient.name, amount])
			var item := selector.item_count - 1
			selector.set_item_metadata(item, ingredient.id)
			selector.set_item_disabled(item, amount <= 0)
			if ingredient.id == previous and amount > 0:
				selector.select(item)
	_make.disabled = _production.get_order().is_empty()
	if clear_result:
		_result.text = "每杯各用 1 份；糖浆自动加入 1 份。"
		_result.remove_theme_color_override("font_color")

func show_result(result: Dictionary) -> void:
	if result.ok:
		for selector in _selectors:
			selector.select(0)
	refresh()
	_result.text = result.message
	_result.add_theme_color_override("font_color", Color("bde3a5") if result.ok else Color("ffd08c"))

func _request_make() -> void:
	var recipe: Array[String] = []
	for selector in _selectors:
		var id := str(selector.get_selected_metadata())
		if not id.is_empty():
			recipe.append(id)
	recipe.append("syrup")
	make_requested.emit(recipe, _order_id)
