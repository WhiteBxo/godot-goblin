class_name FreeCraftingPanel
extends VBoxContainer
## Selection and presentation only. The host submits the requested formula.

signal formula_requested(materials: Array[String], iced: bool)
## Explicit first-confirmation: fixing the permanent price of the displayed formula.
signal confirm_requested(materials: Array[String])

const Artwork = preload("res://src/UI/milk_tea/item_artwork.gd")

var _production: TeaProduction
var _scroll: ScrollContainer
var _slots: GridContainer
var _slot_rows: Array[HBoxContainer] = []
var _options: Array[OptionButton] = []
var _selected: Array[String] = []
var _ice_option: OptionButton
var _preview: Label
var _notice: Label
var _preview_card: PanelContainer
var _preview_head: HBoxContainer
var _preview_icon: TextureRect
var _drink_name: Label
var _drink_meta: Label
var _price: Label
var _result: Label
var _craft: Button
var _confirm: Button
var _refreshing := false
## 当前选料命中委托特调，而不是需要报价的普通自由配方。
var _experiment := false
## 这一杯所属委托的报酬说明；宿主在跳转过来时填入，只出现在特调预览里。
var _mission_hint := ""
var _order_requirement: Dictionary = {}
## Scaled-down material art, keyed by id so a refresh does not rebuild textures.
var _icon_cache: Dictionary = {}

func _ready() -> void:
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	scroll.add_child(content)
	# 2×2: four inputs cost two rows instead of four, which leaves the sheet
	# enough height to be readable on a 360px screen.
	_slots = GridContainer.new()
	_slots.columns = 2
	_slots.add_theme_constant_override("h_separation", 10)
	_slots.add_theme_constant_override("v_separation", 4)
	content.add_child(_slots)
	var ice_row := HBoxContainer.new()
	ice_row.name = "IceRow"
	# 选料与预览共用滚动区，长预览不能把基底和辅料挤成零高度。
	_slots.add_child(ice_row)
	var ice_label := Label.new()
	ice_label.text = "冰块"
	ice_label.custom_minimum_size.x = 40
	ice_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ice_row.add_child(ice_label)
	_ice_option = OptionButton.new()
	_ice_option.name = "IceOption"
	_ice_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ice_option.add_item("不加冰")
	_ice_option.add_item("加冰")
	_ice_option.item_selected.connect(func(_index: int) -> void:
		_clear_result()
		_refresh_preview())
	ice_row.add_child(_ice_option)
	# 制作按钮固定在底部；配方详情与选料一起滚动。
	# The formula reads as a recipe card: what the cup is called on top, the
	# sheet underneath, the price at the foot.
	_preview_card = PanelContainer.new()
	_preview_card.name = "PreviewCard"
	_preview_card.theme_type_variation = &"PreviewCard"
	_preview_card.visible = false
	content.add_child(_preview_card)
	var card_body := VBoxContainer.new()
	card_body.add_theme_constant_override("separation", 4)
	_preview_card.add_child(card_body)
	_preview_head = HBoxContainer.new()
	_preview_head.name = "Head"
	_preview_head.add_theme_constant_override("separation", 8)
	card_body.add_child(_preview_head)
	_preview_icon = Artwork.preview(32)
	_preview_icon.name = "DrinkIcon"
	_preview_head.add_child(_preview_icon)
	var head_text := VBoxContainer.new()
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_text.add_theme_constant_override("separation", 2)
	_preview_head.add_child(head_text)
	_drink_name = Label.new()
	_drink_name.name = "DrinkName"
	_drink_name.theme_type_variation = &"PreviewTitle"
	_drink_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head_text.add_child(_drink_name)
	_drink_meta = Label.new()
	_drink_meta.name = "DrinkMeta"
	_drink_meta.theme_type_variation = &"Hint"
	_drink_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head_text.add_child(_drink_meta)
	_preview = Label.new()
	_preview.name = "Details"
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Cramped lines were half of why the sheet read as a wall of text.
	_preview.add_theme_constant_override("line_spacing", 4)
	card_body.add_child(_preview)
	# "why can I not do this" is a different kind of sentence from the sheet, so
	# it gets its own line and its own colour.
	_notice = Label.new()
	_notice.name = "Notice"
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_body.add_child(_notice)
	_price = Label.new()
	_price.name = "Price"
	card_body.add_child(_price)
	# 制作结果是一次性反馈：放在固定位置，不跟预览一起滚出可视区或被滚动区下沿切断。
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.visible = false
	add_child(_result)
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
		for row: Node in _slot_rows:
			row.free()
		_slot_rows.clear()
		_options.clear()
		for index in range(slot_count):
			var row := HBoxContainer.new()
			row.name = "SlotRow%d" % index
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_slots.add_child(row)
			# Keep the ice cell last: everything above it is a material slot.
			_slots.move_child(row, index)
			var label := Label.new()
			label.text = "基底" if index == 0 else "辅料 %d" % index
			label.custom_minimum_size.x = 40
			label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(label)
			var option := OptionButton.new()
			option.name = "Slot%d" % index
			option.fit_to_longest_item = false
			option.clip_text = true
			option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			option.item_selected.connect(_on_slot_selected.bind(index))
			row.add_child(option)
			_options.append(option)
			_slot_rows.append(row)
	for index in range(slot_count):
		var option := _options[index]
		option.clear()
		option.add_item("请选择基底" if index == 0 else "不添加")
		option.set_item_metadata(0, "")
		var selected := 0
		for choice: Dictionary in _production.get_formula_choices(index == 0):
			var line := "%s · %s%s" % [choice.name, _choice_flavors(choice), "（缺货）" if choice.uses == 0 else ""]
			var item := option.item_count
			# The popup is a list of things: show the thing, not just its name.
			var icon := _choice_icon(choice.id)
			if icon != null:
				option.add_icon_item(icon, line)
			else:
				option.add_item(line)
			option.set_item_metadata(item, choice.id)
			option.get_popup().set_item_tooltip(item, _choice_tooltip(choice))
			if choice.id == _selected[index]:
				selected = item
		option.select(selected)
		_selected[index] = str(option.get_item_metadata(selected))
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
	_clear_result()
	_refresh_preview()
	_reveal_card.call_deferred()

func _reveal_card() -> void:
	if is_instance_valid(_scroll) and _preview_card.visible:
		var card_top := _preview_card.get_global_rect().position.y
		var view_top := _scroll.get_global_rect().position.y
		if card_top > view_top:
			_scroll.ensure_control_visible(_preview_head)

## 32px catalog art halved for the popup row: still on the pixel grid, and short
## enough that eleven materials fit on a 360px-tall screen without scrolling.
func _choice_icon(id: String) -> Texture2D:
	if id.is_empty() or not is_instance_valid(_production):
		return null
	if _icon_cache.has(id):
		return _icon_cache[id]
	var definition := _production.get_inventory().get_definition(id)
	var source: Texture2D = definition.icon if definition != null else null
	var texture: Texture2D = null
	if source != null:
		var image := source.get_image()
		if image != null:
			image.resize(maxi(1, image.get_width() / 2), maxi(1, image.get_height() / 2), Image.INTERPOLATE_NEAREST)
			texture = ImageTexture.create_from_image(image)
	_icon_cache[id] = texture
	return texture

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
	_clear_result()
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
	var details := PackedStringArray()
	var notices := PackedStringArray()
	var drink_name := ""
	var meta := ""
	var price_text := ""
	if result.has("name"):
		var described := DrinkFormula.describe(result, false).split("\n")
		drink_name = str(described[0]) if not described.is_empty() else ""
		var kind := str(described[1]) if described.size() > 1 else ""
		var taste := ""
		for index in range(2, described.size()):
			var line := str(described[index])
			# The price is a decision, not a detail line: it gets its own row.
			if line.begins_with("售价："):
				price_text = line.trim_prefix("售价：").split(" · ")[0]
				continue
			# 冰块 is already on screen as a slot; 风味 and 口感 share a line so the
			# sheet stays two rows tall instead of swallowing the whole panel.
			if line.begins_with("冰块："):
				continue
			if line.begins_with("风味："):
				taste = line
				continue
			if line.begins_with("口感："):
				taste = taste + " · " + line if not taste.is_empty() else line
				details.append(taste)
				taste = ""
				continue
			if line == "特殊效果：无":
				continue
			details.append(line)
		var cost := "未知" if result.get("cost") == null else "%.2fG" % float(result.get("cost"))
		meta = "%s · 单杯成本 %s" % [kind, cost]
	elif not (materials.is_empty() and not _result.text.is_empty()):
		# 刚做完一杯时结果行已经说明了状态，预览不再重复喊“请选择一个基底”。
		notices.append(str(result.get("message", "")))
	if not result.ok and result.has("name"):
		notices.append(str(result.get("message", "")))
	if not pricing_hint.is_empty():
		notices.append(pricing_hint)
	elif result.ok and not priced:
		notices.append("请先确认报价，之后才能制作。")
	if not _order_requirement.is_empty():
		var names := {}
		for id: String in [str(_order_requirement.get("base_id", ""))]:
			names[id] = _production.get_inventory().get_ingredient_view(id).get("name", id)
		notices.append("当前订单 · " + DrinkFormula.requirement_text(_order_requirement, names))
		if result.ok:
			notices.append("这杯符合当前订单，制作后可交付。" if DrinkFormula.matches(result, _order_requirement) else "这杯尚不符合当前订单，请核对基底、风味和效果。")
	_present_card(drink_name, meta, details, notices, price_text, priced)

## One card, three levels: the cup (title), its sheet (details), what it sells
## for (foot). Everything else stays a plain line so the eye can rank them.
func _present_card(drink_name: String, meta: String, details: PackedStringArray, notices: PackedStringArray, price_text: String, priced: bool) -> void:
	_preview_head.visible = not drink_name.is_empty()
	_drink_name.text = drink_name
	_preview_icon.texture = Artwork.DRINK_ICON
	_drink_meta.text = meta
	_drink_meta.visible = not meta.is_empty()
	_preview.text = "\n".join(details)
	_preview.visible = not _preview.text.is_empty()
	_preview.theme_type_variation = &""
	_notice.text = "\n".join(notices)
	_notice.visible = not _notice.text.is_empty()
	# A blocking sentence looks like a warning; an informational one stays quiet.
	_notice.theme_type_variation = &"Warning" if not priced or not notices.is_empty() else &"Hint"
	_price.text = "售价 " + price_text
	# The price is the one number on the card, so it keeps the value colour even
	# while it is still "未定价"; the notice above carries the ochre warning.
	_price.theme_type_variation = &"Value"
	_price.visible = not price_text.is_empty()
	_preview_card.visible = _preview_head.visible or _preview.visible or _notice.visible or _price.visible

## The tracked order remains visible while freely choosing ingredients.
func set_order_requirement(requirement: Dictionary) -> void:
	if _order_requirement == requirement:
		return
	_order_requirement = requirement.duplicate(true)
	if is_node_ready() and is_instance_valid(_production):
		_refresh_preview()

func submit() -> void:
	if _craft.disabled:
		_show_result_text("这份委托特调不加冰，请把冰块改回「不加冰」。" if _experiment else "请先确认报价，之后才能制作。", false)
		return
	formula_requested.emit(get_materials(), is_iced())

## 结果行只在有内容时占位，避免空标签在按钮上方留出一条空行。
func _show_result_text(text: String, succeeded: bool) -> void:
	_result.text = text
	_result.theme_type_variation = &"Success" if succeeded else (&"Warning" if not text.is_empty() else &"")
	_result.visible = not text.is_empty()

func _clear_result() -> void:
	_show_result_text("", false)

## 委托特调按固定成品结算：配方即报价，制作后进共享库存，不需要单独确认价格。
func _show_experiment_preview(special: Dictionary, materials: Array[String]) -> void:
	var product_name := str(special.get("product_name", ""))
	_preview_card.visible = true
	_preview_head.visible = false
	_notice.visible = false
	_price.visible = false
	_preview.visible = true
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
	_show_result_text(str(result.get("message", "")), bool(result.get("ok", false)))
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

## The generated name is a headline of its own now; tests and hosts read it here.
func get_drink_name() -> String:
	return _drink_name.text

func get_price_text() -> String:
	return _price.text

## Everything the card says about the *next step*: why it cannot be priced,
## what the tracked order still wants, whether the cup matches.
func get_notice() -> Label:
	return _notice

func get_result() -> Label:
	return _result

func get_craft_button() -> Button:
	return _craft

func get_confirm_button() -> Button:
	return _confirm
