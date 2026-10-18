class_name WarehousePanel
extends VBoxContainer
## Read-only presentation; state and discovery masking belong to the service.

var _inventory: WarehouseInventory
var _filter: OptionButton
var _list: ItemList
var _details: Label
var _selected_id: String = ""

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_filter = OptionButton.new()
	_filter.name = "OriginFilter"
	for title: String in ["全部", "人类食材", "异世界食材", "剧情物品"]:
		_filter.add_item(title)
	_filter.item_selected.connect(func(_index: int) -> void: refresh())
	add_child(_filter)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	_list = ItemList.new()
	_list.name = "IngredientList"
	_list.custom_minimum_size = Vector2(164, 72)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(16, 16)
	_list.item_selected.connect(_select_item)
	row.add_child(_list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_details = Label.new()
	_details.name = "IngredientDetails"
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(_details)

func configure(inventory: WarehouseInventory) -> void:
	if is_instance_valid(_inventory) and _inventory.changed.is_connected(refresh):
		_inventory.changed.disconnect(refresh)
	_inventory = inventory
	_inventory.changed.connect(refresh)
	refresh()

func get_list() -> ItemList:
	return _list

func get_details() -> Label:
	return _details

func refresh() -> void:
	if not is_instance_valid(_inventory):
		return
	var origin: String = ["", "human", "otherworld", ""][_filter.selected]
	_list.clear()
	var selected := -1
	for ingredient in _inventory.get_ingredients(origin):
		if (_filter.selected == 3 and ingredient.category != "story_item") or (_filter.selected in [1, 2] and ingredient.category == "story_item"):
			continue
		var quantity := "%d" % ingredient.quantity
		if int(ingredient.uses_per_portion) > 1:
			quantity = "%d 份（本份余 %d 次）" % [ingredient.quantity, ingredient.current_portion_uses]
		var index := _list.add_item("%s  %s%s" % [ingredient.name, quantity, " · 缺货" if ingredient.quantity == 0 else ""], ingredient.icon)
		_list.set_item_metadata(index, ingredient.id)
		if ingredient.id == _selected_id:
			selected = index
	if _filter.selected == 0:
		for drink: Dictionary in _inventory.get_drinks():
			var index := _list.add_item("%s · %d 杯" % [drink.name, drink.quantity])
			_list.set_item_metadata(index, drink.id)
			_list.set_item_tooltip(index, drink.name)
			if drink.id == _selected_id:
				selected = index
	if _list.item_count == 0:
		_selected_id = ""
		_details.text = "暂无已发现物品。"
		return
	selected = maxi(selected, 0)
	_list.select(selected)
	_select_item(selected)

func _select_item(index: int) -> void:
	_selected_id = _list.get_item_metadata(index)
	var drink := _inventory.get_drink_record(_selected_id)
	if not drink.is_empty():
		_details.text = DrinkFormula.describe(drink) + "\n库存：%d 杯" % drink.quantity
		return
	var ingredient := _inventory.get_ingredient_view(_selected_id)
	if ingredient.category == "story_item":
		_details.text = "%s · %d 枚\n剧情物品\n金币上印着某种兽类，价值未知。" % [ingredient.name, ingredient.quantity]
		return
	var category: String = {"tea": "茶底", "milk": "奶基底", "syrup": "糖浆", "topping": "小料", "product": "成品", "material": "原料"}.get(ingredient.category, ingredient.category)
	var lines: PackedStringArray = ["%s · %d 份%s" % [ingredient.name, ingredient.quantity, " · 缺货" if ingredient.quantity == 0 else ""],
		"来源：%s · 用途：%s" % ["人类食材" if ingredient.origin == "human" else "异世界食材", category],
		"稀有度：%s" % ingredient.rarity]
	if int(ingredient.uses_per_portion) > 1:
		lines.append("每份 %d 次 · 本份剩余 %d 次 · 总剩余 %d 次" % [ingredient.uses_per_portion, ingredient.current_portion_uses, ingredient.uses])
	# Spreadsheet-only fields stay hidden until the item itself is discovered.
	if not str(ingredient.form).is_empty():
		lines.append("形态：%s · 加工：%s" % [ingredient.form, _property_text(ingredient.processing_methods)])
	if int(ingredient.price) > 0:
		lines.append("标价：%d 金币" % int(ingredient.price))
	lines.append("已知风味：%s" % _property_text(ingredient.flavor_tags))
	lines.append("战斗属性：%s" % _property_text(ingredient.combat_attributes))
	lines.append("特殊效果：%s" % _property_text(ingredient.special_effects))
	lines.append("获取方式：%s" % _property_text(ingredient.acquisition_sources))
	if not str(ingredient.description).is_empty():
		lines.append("\n%s" % ingredient.description)
	_details.text = "\n".join(lines)

func _property_text(values: PackedStringArray) -> String:
	return "、".join(values) if not values.is_empty() else "无"
