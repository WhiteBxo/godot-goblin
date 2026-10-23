class_name WarehousePanel
extends VBoxContainer
## Read-only presentation; state and discovery masking belong to the service.

const Artwork = preload("res://src/UI/milk_tea/item_artwork.gd")
## Five 12px glyphs including the colon: 可用次数 / 已知风味 / 获取方式.
const FIELD_WIDTH: int = 60

var _image: TextureRect
var _materials: HBoxContainer
var _inventory: WarehouseInventory
var _filter: OptionButton
var _list: ItemList
var _name: Label
var _details: VBoxContainer
var _detail_lines: PackedStringArray = []
var _detail: Control
var _selected_id: String = ""
## 原料图鉴只收原料：成品杯和调饮基底不进这一页，店里的仓库照旧看全部库存。
var _ingredients_only := false
## The pane only turns when a different item is opened; a stock refresh of the
## item already on screen must leave the words still.
var _shown_id: String = ""

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
	_list.fixed_icon_size = Vector2i(32, 32)
	_list.item_selected.connect(_select_item)
	row.add_child(_list)
	var scroll := ScrollContainer.new()
	scroll.name = "DetailScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var details_column := VBoxContainer.new()
	details_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(details_column)
	# A fixed preview keeps the pixel art crisp instead of stretching it to the pane.
	_image = Artwork.preview(64)
	_image.name = "ItemImage"
	_image.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	details_column.add_child(_image)
	_name = Label.new()
	_name.name = "ItemName"
	_name.theme_type_variation = &"Title"
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_column.add_child(_name)
	_materials = HBoxContainer.new()
	details_column.add_child(_materials)
	# Two columns: the field name is a quiet right-aligned gutter, the value gets
	# the room to wrap. A page of names and values reads as a table, not a block.
	_details = VBoxContainer.new()
	_details.name = "IngredientDetails"
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.add_theme_constant_override("separation", 4)
	details_column.add_child(_details)
	_detail = details_column

func configure(inventory: WarehouseInventory) -> void:
	if is_instance_valid(_inventory) and _inventory.changed.is_connected(refresh):
		_inventory.changed.disconnect(refresh)
	_inventory = inventory
	_inventory.changed.connect(refresh)
	refresh()

func get_list() -> ItemList:
	return _list

func set_ingredients_only(value: bool) -> void:
	if _ingredients_only == value:
		return
	_ingredients_only = value
	if is_node_ready():
		refresh()

## 成品与调饮基底都不是“原料”，图鉴模式直接不列。
func _is_encyclopedia_entry(id: String) -> bool:
	var definition := _inventory.get_definition(id)
	return definition != null and definition.category != "product" and definition.show_in_encyclopedia

func get_details() -> VBoxContainer:
	return _details

## The pane's words as one readable string, for tests and tooltips.
func get_detail_text() -> String:
	return "\n".join(_detail_lines)

## Hosts that put this page straight into a modal shell need a focus target.
func get_default_focus() -> Control:
	return _list if _list != null and _list.item_count > 0 else null

func refresh() -> void:
	if not is_instance_valid(_inventory):
		return
	var origin: String = ["", "human", "otherworld", ""][_filter.selected]
	_list.clear()
	var selected := -1
	for ingredient in _inventory.get_ingredients(origin):
		if _ingredients_only and not _is_encyclopedia_entry(str(ingredient.id)):
			continue
		if (_filter.selected == 3 and ingredient.category != "story_item") or (_filter.selected in [1, 2] and ingredient.category == "story_item"):
			continue
		var quantity := "%d" % ingredient.quantity
		if int(ingredient.uses_per_portion) > 1:
			quantity = "%d 份（本份余 %d 次）" % [ingredient.quantity, ingredient.current_portion_uses]
		var index := _list.add_item("%s  %s%s" % [ingredient.name, quantity, " · 缺货" if ingredient.quantity == 0 else ""], ingredient.icon)
		_list.set_item_metadata(index, ingredient.id)
		if ingredient.id == _selected_id:
			selected = index
	if _filter.selected == 0 and not _ingredients_only:
		for drink: Dictionary in _inventory.get_drinks():
			var index := _list.add_item("%s · %d 杯" % [drink.name, drink.quantity], Artwork.DRINK_ICON)
			_list.set_item_metadata(index, drink.id)
			_list.set_item_tooltip(index, drink.name)
			if drink.id == _selected_id:
				selected = index
	if _list.item_count == 0:
		_selected_id = ""
		_image.texture = null
		_name.text = ""
		Artwork.show_materials(_materials, _inventory, [])
		_clear_details()
		_add_note("暂无已发现物品。")
		_open_detail()
		return
	selected = maxi(selected, 0)
	_list.select(selected)
	_select_item(selected)

func _select_item(index: int) -> void:
	_selected_id = _list.get_item_metadata(index)
	_fill_detail()
	_open_detail()

## The pane opens on the new item instead of swapping the words in place.
## Alpha and scale only, so the split layout never reflows.
func _open_detail() -> void:
	var changed := _selected_id != _shown_id
	_shown_id = _selected_id
	if changed:
		UIFlourish.reveal(_detail, 0.99)

func _fill_detail() -> void:
	_clear_details()
	var drink := _inventory.get_drink_record(_selected_id)
	if not drink.is_empty():
		_image.texture = Artwork.DRINK_ICON
		Artwork.show_materials(_materials, _inventory, drink.ingredients)
		_name.text = str(drink.name)
		_add_note(DrinkFormula.describe(drink), UITokens.TEXT)
		_add_row("库存", "%d 杯" % drink.quantity)
		return
	var ingredient := _inventory.get_ingredient_view(_selected_id)
	_image.texture = ingredient.icon
	Artwork.show_materials(_materials, _inventory, [])
	if ingredient.category == "story_item":
		# Each story item carries its own note; never borrow another item's words.
		var note := str(ingredient.description)
		_name.text = str(ingredient.name)
		_add_row("用途", "剧情物品")
		_add_row("数量", "%d 枚" % ingredient.quantity)
		if not note.is_empty():
			_add_gap()
			_add_note(note)
		return
	var category: String = {"tea": "茶底", "milk": "奶基底", "syrup": "糖浆", "topping": "小料", "product": "成品", "material": "原料"}.get(ingredient.category, ingredient.category)
	_name.text = str(ingredient.name)
	_add_row("数量", "%d 份%s" % [ingredient.quantity, " · 缺货" if ingredient.quantity == 0 else ""],
		UITokens.DANGER if ingredient.quantity == 0 else UITokens.TEXT)
	_add_row("来源", "人类食材" if ingredient.origin == "human" else "异世界食材")
	_add_row("用途", category)
	_add_row("稀有度", str(ingredient.rarity))
	if int(ingredient.uses_per_portion) > 1:
		_add_row("可用次数", "每份 %d 次 · 本份剩余 %d 次 · 总剩余 %d 次" % [ingredient.uses_per_portion, ingredient.current_portion_uses, ingredient.uses])
	# Spreadsheet-only fields stay hidden until the item itself is discovered.
	if not str(ingredient.form).is_empty():
		_add_row("形态", "%s · 加工：%s" % [ingredient.form, _property_text(ingredient.processing_methods)])
	if int(ingredient.price) > 0:
		_add_row("标价", WalletTransactions.format_money(int(ingredient.price)))
	_append_if_any("已知风味", ingredient.flavor_tags)
	_append_if_any("战斗属性", ingredient.combat_attributes)
	_append_if_any("特殊效果", ingredient.special_effects)
	_append_if_any("获取方式", ingredient.acquisition_sources)
	if not str(ingredient.description).is_empty():
		_add_gap()
		_add_note(str(ingredient.description))

func _clear_details() -> void:
	for child: Node in _details.get_children():
		child.free()
	_detail_lines.clear()

## A field row: the name is a quiet right-aligned gutter, the value takes the
## rest of the line. A rich label reports its wrapped height, so a long value
## grows the row instead of being clipped.
func _add_row(label: String, value: String, color: Color = UITokens.TEXT) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var field := Label.new()
	field.text = label + "："
	field.theme_type_variation = &"Muted"
	field.custom_minimum_size = Vector2(FIELD_WIDTH, 0)
	field.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	field.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(field)
	row.add_child(_wrapped(value, color))
	_details.add_child(row)
	_detail_lines.append("%s：%s" % [label, value])

func _add_note(text: String, color: Color = UITokens.TEXT_DIM) -> void:
	_details.add_child(_wrapped(text, color))
	_detail_lines.append(text)

func _wrapped(text: String, color: Color) -> RichTextLabel:
	var content := RichTextLabel.new()
	content.bbcode_enabled = false
	content.fit_content = true
	content.scroll_active = false
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_color_override("default_color", color)
	content.text = text
	return content

func _add_gap() -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	_details.add_child(gap)

## An empty property is not information; a column of "无" only pushes the real
## lines off the pane.
func _append_if_any(label: String, values: PackedStringArray) -> void:
	if values.is_empty():
		return
	if values.size() == 1 and values[0] == "???":
		_add_row(label, "???", UITokens.TEXT_MUTED)
	else:
		_add_row(label, "、".join(values))

func _property_text(values: PackedStringArray) -> String:
	return "、".join(values) if not values.is_empty() else "无"
