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
	for title: String in ["全部", "人类食材", "异世界食材"]:
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

func refresh() -> void:
	if not is_instance_valid(_inventory):
		return
	var origin: String = ["", "human", "otherworld"][_filter.selected]
	_list.clear()
	var selected := -1
	for ingredient in _inventory.get_ingredients(origin):
		var index := _list.add_item("%s  %d%s" % [ingredient.name, ingredient.quantity, " · 缺货" if ingredient.quantity == 0 else ""], ingredient.icon)
		_list.set_item_metadata(index, ingredient.id)
		if ingredient.id == _selected_id:
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
	var ingredient := _inventory.get_ingredient_view(_selected_id)
	var category: String = {"tea": "茶底", "milk": "奶基底", "syrup": "糖浆", "topping": "小料", "product": "成品"}.get(ingredient.category, ingredient.category)
	_details.text = "%s · %d 份%s\n来源：%s · 用途：%s\n稀有度：%s\n已知风味：%s\n战斗属性：%s\n特殊效果：%s\n获取方式：%s" % [
		ingredient.name, ingredient.quantity, " · 缺货" if ingredient.quantity == 0 else "",
		"人类食材" if ingredient.origin == "human" else "异世界食材", category, ingredient.rarity,
		_property_text(ingredient.flavor_tags), _property_text(ingredient.combat_attributes),
		_property_text(ingredient.special_effects), _property_text(ingredient.acquisition_sources)]

func _property_text(values: PackedStringArray) -> String:
	return "、".join(values) if not values.is_empty() else "无"
