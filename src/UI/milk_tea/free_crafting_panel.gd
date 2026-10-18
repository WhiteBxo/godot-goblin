class_name FreeCraftingPanel
extends VBoxContainer
## Selection and presentation only. The host submits the requested formula.

signal formula_requested(materials: Array[String], iced: bool)
## Explicit first-confirmation: fixing the permanent price of the displayed formula.
signal confirm_requested(materials: Array[String])

const Artwork = preload("res://src/UI/milk_tea/item_artwork.gd")

var _images: Array[TextureRect] = []
var _production: TeaProduction
var _slots: VBoxContainer
var _options: Array[OptionButton] = []
var _selected: Array[String] = []
var _ice_option: OptionButton
var _preview: Label
var _result: Label
var _craft: Button
var _confirm: Button
var _refreshing := false

func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	_slots = VBoxContainer.new()
	content.add_child(_slots)
	var ice_row := HBoxContainer.new()
	content.add_child(ice_row)
	var ice_label := Label.new()
	ice_label.text = "冰块"
	ice_label.custom_minimum_size.x = 48
	ice_row.add_child(ice_label)
	_ice_option = OptionButton.new()
	_ice_option.name = "IceOption"
	_ice_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ice_option.add_item("不加冰")
	_ice_option.add_item("加冰")
	_ice_option.item_selected.connect(func(_index: int) -> void:
		_result.text = ""
		_refresh_preview())
	ice_row.add_child(_ice_option)
	_preview = Label.new()
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_preview)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_result)
	var actions := HBoxContainer.new()
	add_child(actions)
	var clear := Button.new()
	clear.text = "清空"
	clear.theme_type_variation = &"GhostButton"
	clear.pressed.connect(func() -> void: select_formula([]))
	actions.add_child(clear)
	_confirm = Button.new()
	_confirm.text = "确认报价"
	_confirm.disabled = true
	_confirm.pressed.connect(func() -> void:
		if not _confirm.disabled:
			confirm_requested.emit(get_materials()))
	actions.add_child(_confirm)
	_craft = Button.new()
	_craft.text = "制作一杯并入库"
	_craft.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_craft.theme_type_variation = &"PrimaryButton"
	_craft.pressed.connect(submit)
	actions.add_child(_craft)

func configure(production: TeaProduction) -> void:
	if is_instance_valid(_production) and _production.changed.is_connected(refresh):
		_production.changed.disconnect(refresh)
	_production = production
	_production.changed.connect(refresh)
	refresh()

func refresh() -> void:
	if _refreshing or not is_instance_valid(_production):
		return
	_refreshing = true
	var slot_count := _production.get_recipe_slots()
	_selected.resize(slot_count)
	if _options.size() != slot_count:
		for child: Node in _slots.get_children():
			child.free()
		_options.clear()
		_images.clear()
		for index in range(slot_count):
			var row := HBoxContainer.new()
			_slots.add_child(row)
			var label := Label.new()
			label.text = "基底" if index == 0 else "辅料 %d" % index
			label.custom_minimum_size.x = 48
			row.add_child(label)
			var image := Artwork.preview(24)
			image.name = "IngredientImage"
			row.add_child(image)
			_images.append(image)
			var option := OptionButton.new()
			option.name = "Slot%d" % index
			option.fit_to_longest_item = false
			option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			option.item_selected.connect(_on_slot_selected.bind(index))
			row.add_child(option)
			_options.append(option)
	for index in range(slot_count):
		var option := _options[index]
		option.clear()
		option.add_item("请选择基底" if index == 0 else "不添加")
		option.set_item_metadata(0, "")
		var selected := 0
		for choice: Dictionary in _production.get_formula_choices(index == 0):
			var line := "%s · %s%s" % [choice.name, "、".join(choice.flavors), "（缺货）" if choice.uses == 0 else ""]
			option.add_item(line)
			var item := option.item_count - 1
			option.set_item_metadata(item, choice.id)
			if choice.id == _selected[index]:
				selected = item
		option.select(selected)
		_selected[index] = str(option.get_item_metadata(selected))
		_refresh_slot_image(index)
	_refreshing = false
	_refresh_preview()

func _on_slot_selected(item: int, slot: int) -> void:
	_selected[slot] = str(_options[slot].get_item_metadata(item))
	_refresh_slot_image(slot)
	_result.text = ""
	_refresh_preview()

func _refresh_slot_image(slot: int) -> void:
	var view := _production.get_inventory().get_ingredient_view(_selected[slot])
	_images[slot].texture = view.get("icon")
	_images[slot].tooltip_text = str(view.get("name", ""))

func get_materials() -> Array[String]:
	if _selected.is_empty() or _selected[0].is_empty():
		return []
	var result: Array[String] = [_selected[0]]
	for index in range(1, _selected.size()):
		if not _selected[index].is_empty():
			result.append(_selected[index])
	return result

func select_formula(materials: Array, iced := false) -> bool:
	if not is_instance_valid(_production) or materials.size() > _production.get_recipe_slots():
		return false
	if not materials.is_empty() and not _production.get_inventory().calculate_formula(materials).ok:
		return false
	_selected.clear()
	_selected.assign(materials)
	_ice_option.select(1 if iced else 0)
	_result.text = ""
	refresh()
	return get_materials() == materials

func _refresh_preview() -> void:
	var materials := get_materials()
	var result := _production.preview_formula(materials, 1, is_iced())
	var quote := _production.preview_formula_price(materials) if not materials.is_empty() else {}
	var priced: bool = bool(quote.get("priced", false))
	_craft.disabled = not result.ok or not priced
	_confirm.disabled = result.get("code", "") != "ok" or priced
	if result.has("name"):
		_preview.text = DrinkFormula.describe(result, false)
		if priced:
			_preview.text += "\n售价：%dG（已固定）" % int(quote.get("selling_price", 0))
		elif quote.get("ok", false):
			_preview.text += "\n价格范围：%d–%dG，确认后固定" % [int(quote.get("minimum", 0)), int(quote.get("maximum", 0))]
	else:
		_preview.text = str(result.get("message", ""))
	if not result.ok and result.has("name"):
		_preview.text += "\n" + str(result.get("message", ""))
	elif result.ok and not priced:
		_preview.text += "\n请先确认报价，之后才能制作。"

func submit() -> void:
	if _craft.disabled:
		_result.text = "请先确认报价，之后才能制作。"
		return
	formula_requested.emit(get_materials(), is_iced())

func show_result(result: Dictionary) -> void:
	_result.text = str(result.get("message", ""))
	_result.theme_type_variation = &"Success" if result.get("ok", false) else &"Warning"
	_refresh_preview()

func get_default_focus() -> Control:
	return _options[0] if not _options.is_empty() else _craft

func get_slots() -> Array[OptionButton]:
	return _options.duplicate()

func is_iced() -> bool:
	return _ice_option.selected == 1

func get_ice_option() -> OptionButton:
	return _ice_option

func get_preview() -> Label:
	return _preview

func get_craft_button() -> Button:
	return _craft
