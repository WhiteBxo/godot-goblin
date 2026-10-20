class_name FreeCraftingPanel
extends VBoxContainer
## Selection and presentation only. The host submits the requested formula.

signal formula_requested(materials: Array[String], iced: bool)
## Explicit first-confirmation: fixing the permanent price of the displayed formula.
signal confirm_requested(materials: Array[String])

const Artwork = preload("res://src/UI/milk_tea/item_artwork.gd")

var _images: Array[TextureRect] = []
var _production: TeaProduction
var _scroll: ScrollContainer
var _slots: VBoxContainer
var _options: Array[OptionButton] = []
var _selected: Array[String] = []
var _ice_option: OptionButton
var _preview: Label
var _result: Label
var _craft: Button
var _confirm: Button
var _refreshing := false
## 当前选料命中委托特调，而不是需要报价的普通自由配方。
var _experiment := false
## 这一杯所属委托的报酬说明；宿主在跳转过来时填入，只出现在特调预览里。
var _mission_hint := ""
var _order_requirement: Dictionary = {}

func _ready() -> void:
	var scroll := ScrollContainer.new()
	_scroll = scroll
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
	# 选料与预览共用滚动区，长预览不能把基底和辅料挤成零高度。
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
	# 制作按钮固定在底部；配方详情与选料一起滚动。
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
			var line := "%s · %s%s" % [choice.name, _choice_flavors(choice), "（缺货）" if choice.uses == 0 else ""]
			option.add_item(line)
			var item := option.item_count - 1
			option.set_item_metadata(item, choice.id)
			option.get_popup().set_item_tooltip(item, _choice_tooltip(choice))
			if choice.id == _selected[index]:
				selected = item
		option.select(selected)
		_selected[index] = str(option.get_item_metadata(selected))
		_refresh_slot_image(index)
	_refreshing = false
	_refresh_preview()

## The authored flavor tags lead; texture stands in only when a material has no
## taste of its own, so a listed ingredient never reads as "no flavor at all".
func _choice_flavors(choice: Dictionary) -> String:
	var flavors := "、".join(choice.get("flavors", PackedStringArray()))
	if not flavors.is_empty():
		return flavors
	var textures := "、".join(choice.get("textures", PackedStringArray()))
	return textures if not textures.is_empty() else "无特殊风味"

## Flavor, mouthfeel and effect of the sheet row, for the hover tooltip.
func _choice_tooltip(choice: Dictionary) -> String:
	var lines := PackedStringArray()
	for pair: Array in [["风味", choice.get("flavors", PackedStringArray())], ["口感", choice.get("textures", PackedStringArray())],
			["特殊效果", choice.get("effects", PackedStringArray())]]:
		var tags: PackedStringArray = pair[1]
		if not tags.is_empty():
			lines.append("%s：%s" % [pair[0], "、".join(tags)])
	return "\n".join(lines)

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
	# 委托特调按固定配方结算，不受普通自由配方的原料白名单限制。
	if not materials.is_empty() and not _production.get_inventory().calculate_formula(materials).ok \
			and _production.find_experiment_recipe(materials) == null:
		return false
	_selected.clear()
	_selected.assign(materials)
	_ice_option.select(1 if iced else 0)
	_result.text = ""
	refresh()
	# 带着配方进来时从基底看起，不要让焦点把上一行顶出可视区。
	if is_instance_valid(_scroll):
		_scroll.set_deferred("scroll_vertical", 0)
	return get_materials() == materials

func _refresh_preview() -> void:
	var materials := get_materials()
	_experiment = false
	if not materials.is_empty() and is_instance_valid(_production):
		var special := _production.preview_experiment(materials, 1)
		if not special.is_empty():
			_experiment = true
			_show_experiment_preview(special, materials)
			return
	var result := _production.preview_formula(materials, 1, is_iced())
	_preview.theme_type_variation = &""
	var quote := _production.preview_formula_price(materials, is_iced()) if not materials.is_empty() else {}
	var priced: bool = bool(quote.get("priced", false))
	var can_confirm := _production.can_confirm_formula(materials)
	var pricing_hint := ""
	if not materials.is_empty() and not quote.get("ok", false):
		pricing_hint = "纯人类饮品请到「已知配方」制作，固定售价 3G；自由实验需加入至少一种哥布林原料。" if quote.get("code") == "human_only" else str(quote.get("message", "当前配方无法报价。"))
	elif not priced and not can_confirm:
		pricing_hint = "请返回可恢复的经营阶段后确认新价格。"
	_craft.disabled = not result.ok or not priced
	_confirm.disabled = not quote.get("ok", false) or priced or not can_confirm
	_confirm.tooltip_text = pricing_hint
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
	if not pricing_hint.is_empty():
		_preview.text += "\n" + pricing_hint
	elif result.ok and not priced:
		_preview.text += "\n请先确认报价，之后才能制作。"
	if not _order_requirement.is_empty():
		var names := {}
		for id: String in [str(_order_requirement.get("base_id", ""))]:
			names[id] = _production.get_inventory().get_ingredient_view(id).get("name", id)
		_preview.text += "\n当前订单：" + DrinkFormula.requirement_text(_order_requirement, names)
		if result.ok:
			_preview.text += "\n这杯符合当前订单，制作后可交付。" if DrinkFormula.matches(result, _order_requirement) else "\n这杯尚不符合当前订单，请核对基底、风味和效果。"

## The tracked order remains visible while freely choosing ingredients.
func set_order_requirement(requirement: Dictionary) -> void:
	if _order_requirement == requirement:
		return
	_order_requirement = requirement.duplicate(true)
	if is_node_ready() and is_instance_valid(_production):
		_refresh_preview()

func submit() -> void:
	if _craft.disabled:
		_result.text = "这份委托特调不加冰，请把冰块改回「不加冰」。" if _experiment else "请先确认报价，之后才能制作。"
		return
	formula_requested.emit(get_materials(), is_iced())

## 委托特调按固定成品结算：配方即报价，制作后进共享库存，不需要单独确认价格。
func _show_experiment_preview(special: Dictionary, materials: Array[String]) -> void:
	var product_name := str(special.get("product_name", ""))
	_confirm.disabled = true
	_confirm.tooltip_text = "委托特调按配方直接制作，不需要单独报价。"
	if is_iced():
		_preview.text = "→ %s ×1\n这份委托特调不加冰，请把冰块改回「不加冰」。" % product_name
		_preview.theme_type_variation = &"Warning"
		_craft.disabled = true
		return
	if str(special.get("code")) != "ok":
		_preview.text = str(special.get("message", ""))
		_preview.theme_type_variation = &"Warning"
		_craft.disabled = true
		return
	_preview.text = "→ %s ×1\n委托特调：%s\n制作后入库，再带去交给委托人。" % [
		product_name, " + ".join(_production.get_recipe_names(materials))]
	if not _mission_hint.is_empty():
		_preview.text += "\n" + _mission_hint
	_preview.theme_type_variation = &"Success"
	_craft.disabled = false

## 委托报酬由任务结算，不在制作时计价；这一行让玩家知道这杯值多少。
func set_mission_hint(text: String) -> void:
	if text == _mission_hint:
		return
	_mission_hint = text
	if is_node_ready():
		_refresh_preview()

func show_result(result: Dictionary) -> void:
	_result.text = str(result.get("message", ""))
	_result.theme_type_variation = &"Success" if result.get("ok", false) else &"Warning"
	if bool(result.get("ok", false)) and _experiment:
		# 委托只做一杯，成品入库后清空选料，避免下一帧又显示“仅制作一杯”。
		_selected.clear()
		refresh()
	else:
		_refresh_preview()
	if _result.text.is_empty():
		return
	if result.get("ok", false):
		UIFlourish.cups(_craft, null, 1, Vector2(0.06, 0.5))
		UIFlourish.settle(_result, 0.94)
	else:
		UIFlourish.refuse(_result)

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

func get_confirm_button() -> Button:
	return _confirm
