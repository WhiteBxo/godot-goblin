extends Control
## F6 visual gallery for the shared UI theme and components.
## Debug-only: not referenced by the game entry or any production scene.

const T := preload("res://src/resources/ui/ui_tokens.gd")


func _ready() -> void:
	var background := ColorRect.new()
	background.color = T.SCREEN
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, T.SPACE_4)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", T.SPACE_6)
	scroll.add_child(column)

	var header := Label.new()
	header.text = "UI KIT · 暖棕主题"
	header.theme_type_variation = &"Title"
	column.add_child(header)
	var subtitle := Label.new()
	subtitle.text = "所有控件直接使用 game_theme.tres；改 tokens 后重新生成主题。"
	subtitle.theme_type_variation = &"Hint"
	column.add_child(subtitle)

	_typography(column)
	_buttons(column)
	_panels(column)
	_order_slip(column)
	_prompt(column)
	_lists(column)
	_tabs(column)
	_inputs(column)
	_text(column)


func _section(parent: VBoxContainer, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", T.SPACE_2)
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = &"H2"
	box.add_child(heading)
	box.add_child(HSeparator.new())
	parent.add_child(box)
	return box

func _order_slip(parent: VBoxContainer) -> void:
	var box := _section(parent, "订单笺 · 纸色与墨色")
	var ticket: OrderTicket = preload("res://src/UI/components/order_ticket.tscn").instantiate()
	ticket.custom_minimum_size = Vector2(0, 216)
	box.add_child(ticket)
	ticket.present({"title": "珍珠奶茶 ×1", "target_name": "哥布林乙", "status_text": "待制作",
		"stage": "prepare", "status": "active", "product_id": "pearl_milk_tea",
		"icon": preload("res://assets/ui/milk_tea/products/classic_boba_milk_tea.png"),
		"items": [{"name": "珍珠奶茶", "owned": 0, "needed": 1}],
		"missing_text": "", "rewards": "古怪硬币 ×1", "hint": "前往制作台，配方已备好"}, "追踪此单", true)


func _caption(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Hint"
	parent.add_child(label)


func _row(parent: Control) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", T.SPACE_3)
	row.add_theme_constant_override("v_separation", T.SPACE_2)
	parent.add_child(row)
	return row


func _typography(parent: VBoxContainer) -> void:
	var box := _section(parent, "文字与徽标")
	_caption(box, "Title 24 / H2 12 / 正文 12 / Hint 12；只用这三个字号。")
	_row(box).add_child(_label("Title · 手册", &"Title"))
	_row(box).add_child(_label("H2 · 当前目标", &"H2"))
	_row(box).add_child(_label("正文 · 珍珠奶茶 × 1", &""))
	_row(box).add_child(_label("Hint · 方向键选择", &"Hint"))
	_row(box).add_child(_label("Muted · 暂无记录", &"Muted"))
	_row(box).add_child(_label("Value · 128 G", &"Value"))
	var states := _row(box)
	states.add_child(_label("Success · 已完成", &"Success"))
	states.add_child(_label("Warning · 材料不足", &"Warning"))
	states.add_child(_label("Danger · 操作失败", &"Danger"))
	var badges := _row(box)
	badges.add_child(_label("主线", &"BadgeMain"))
	badges.add_child(_label("委托", &"Badge"))
	badges.add_child(_label("已完成", &"BadgeDone"))
	badges.add_child(_label("已锁定", &"BadgeMuted"))
	_row(box).add_child(_label("E", &"Keycap"))


func _buttons(parent: VBoxContainer) -> void:
	var box := _section(parent, "按钮")
	_caption(box, "normal / hover / pressed / focus / disabled；Primary 用于唯一主操作。")
	var row := _row(box)
	row.add_child(_button("普通按钮"))
	row.add_child(_button("主操作", &"PrimaryButton"))
	row.add_child(_button("次操作", &"GhostButton"))
	row.add_child(_button("危险操作", &"DangerButton"))
	var disabled := _button("不可用")
	disabled.disabled = true
	row.add_child(disabled)
	var icon := _button("×", &"IconButton")
	icon.custom_minimum_size = Vector2(28, 28)
	row.add_child(icon)
	var selector := OptionButton.new()
	selector.add_item("选择饮品")
	selector.add_item("薄荷冰奶茶 ×2")
	selector.add_item("售空饮品")
	selector.set_item_disabled(2, true)
	_row(box).add_child(selector)


func _panels(parent: VBoxContainer) -> void:
	var box := _section(parent, "面板")
	_caption(box, "Panel / InsetPanel / CardPanel / SunkenPanel，边框与内边距统一由主题提供。")
	var row := _row(box)
	for spec: Array in [[&"", "Panel"], [&"InsetPanel", "InsetPanel"], [&"CardPanel", "CardPanel"], [&"SunkenPanel", "SunkenPanel"]]:
		var panel := PanelContainer.new()
		panel.theme_type_variation = StringName(spec[0])
		panel.custom_minimum_size = Vector2(180, 64)
		var label := _label(spec[1], &"")
		panel.add_child(label)
		row.add_child(panel)


func _prompt(parent: VBoxContainer) -> void:
	var box := _section(parent, "交互提示")
	_caption(box, "PromptBar 由 Keycap + 面板组成，位于屏幕底部居中。")
	var prompt := preload("res://src/UI/components/prompt_bar.tscn").instantiate()
	prompt.custom_minimum_size = Vector2(0, 40)
	box.add_child(prompt)
	prompt.show_prompt("收银台")


func _lists(parent: VBoxContainer) -> void:
	var box := _section(parent, "列表")
	_caption(box, "ItemList 的选中、悬停、禁用与焦点都来自主题；不再在场景里写颜色。")
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(360, 132)
	list.allow_reselect = true
	for text: String in ["主线 · 完成第一笔订单", "委托 · 酒馆的醒神菇委托", "委托 · 聚落补给", "委托 · 回顾告示内容", "已完成的旧记录"]:
		list.add_item(text)
	list.set_item_disabled(4, true)
	list.select(0)
	box.add_child(list)


func _tabs(parent: VBoxContainer) -> void:
	var box := _section(parent, "页签")
	_caption(box, "选中项 2px 金线，未选中 1px 暗线；页签下内容共用同一套内边距。")
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(360, 132)
	for title: String in ["委托", "异闻录"]:
		var page := MarginContainer.new()
		page.name = title
		for side: String in ["left", "top", "right", "bottom"]:
			page.add_theme_constant_override("margin_" + side, T.SPACE_3)
		var label := _label("%s 页内容" % title, &"")
		page.add_child(label)
		tabs.add_child(page)
	box.add_child(tabs)


func _inputs(parent: VBoxContainer) -> void:
	var box := _section(parent, "输入与进度")
	_caption(box, "LineEdit / SpinBox / CheckBox / ProgressBar 使用同一套凹陷底与金色焦点。")
	var row := _row(box)
	var line := LineEdit.new()
	line.placeholder_text = "搜索"
	line.custom_minimum_size = Vector2(160, 28)
	row.add_child(line)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 9
	spin.value = 3
	spin.custom_minimum_size = Vector2(96, 28)
	row.add_child(spin)
	var check := CheckBox.new()
	check.text = "自动保存"
	check.button_pressed = true
	row.add_child(check)
	var bars := _row(box)
	var progress := ProgressBar.new()
	progress.value = 45
	progress.custom_minimum_size = Vector2(220, 8)
	progress.show_percentage = false
	bars.add_child(progress)
	var success := ProgressBar.new()
	success.theme_type_variation = &"SuccessBar"
	success.value = 100
	success.custom_minimum_size = Vector2(120, 8)
	success.show_percentage = false
	bars.add_child(success)


func _text(parent: VBoxContainer) -> void:
	var box := _section(parent, "长文本")
	var text := RichTextLabel.new()
	text.bbcode_enabled = false
	text.fit_content = false
	text.custom_minimum_size = Vector2(0, 96)
	text.text = "目标\n[已完成] 查看订单板接单\n[未完成] 制作珍珠奶茶  0 / 1\n[未完成] 交付并收款\n\n交付对象：人类顾客\n交付成品：珍珠奶茶（成品）\n奖励：营业收入 10"
	box.add_child(text)


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	if variation != &"":
		label.theme_type_variation = variation
	return label


func _button(text: String, variation: StringName = &"") -> Button:
	var button := Button.new()
	button.text = text
	if variation != &"":
		button.theme_type_variation = variation
	return button
