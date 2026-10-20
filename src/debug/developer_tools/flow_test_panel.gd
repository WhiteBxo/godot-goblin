class_name FlowTestPanel
extends VBoxContainer

signal close_requested

var tools: FlowTestTools
var _body: VBoxContainer
var _status: TextEdit
var _message: Label
var _fixtures: OptionButton
var _items: OptionButton
var _recipes: OptionButton
var _targets: OptionButton
var _amount: SpinBox
var _cheats: Array[Button] = []
var _elapsed := 0.0
var _generate: Button
var _launch: Button
var _tabs: TabContainer

func _ready() -> void:
	name = "流程测试"
	_body = self
	_label("前两天流程测试台", "H2")
	_label("检查点来自真实流程。独立试玩使用单独存档；下方作弊会修改当前会话，自动保存也会保留。", "Warning")
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)
	_section("当前流程")
	_status = TextEdit.new()
	_status.editable = false
	_status.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_status.custom_minimum_size.y = 110
	_body.add_child(_status)
	_button("导出并复制问题报告", func() -> void: tools.export_report())
	_section("检查点试玩")
	_label("首次点击生成，后台运行完整两天流程；通过后刷新。可在当前窗口继续游戏。", "Hint")
	_generate = _button("后台生成两天检查点", func() -> void: tools.generate())
	_button("刷新检查点 / 物品 / 定位列表", reload_choices)
	_fixtures = _choice()
	_launch = _button("从所选检查点启动独立试玩", func() -> void: tools.launch(_selected(_fixtures)))
	_section("作弊调试")
	_label("当前会话作弊（每次操作记录日志）", "H2")
	_amount = SpinBox.new()
	_amount.min_value = 1
	_amount.max_value = 100
	_amount.value = 10
	_amount.prefix = "物品份数 "
	_body.add_child(_amount)
	_cheats.append(_button("增加 100G", func() -> void: tools.add_money(100)))
	_items = _choice()
	_cheats.append(_button("补充所选物品", func() -> void: tools.add_item(_selected(_items), int(_amount.value))))
	_recipes = _choice()
	_cheats.append(_button("制作所选配方一杯（消耗原料）", func() -> void: tools.craft(_selected(_recipes))))
	_targets = _choice()
	_cheats.append(_button("定位到所选对象附近", func() -> void: tools.locate(_selected(_targets))))
	_label("快速跳过整段：用检查点重开；局部标记：沿用“写状态”页。快速制作仍需接单和交付，定位仍需按 E 触发交互。", "Hint")
	_body = self
	_message = _label("", "Hint")
	_message.max_lines_visible = 3
	_message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _section(title: String) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

func configure(service: FlowTestTools) -> void:
	tools = service
	reload_choices()
	refresh()

func _label(text: String, variation: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(label)
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func() -> void:
		if tools != null:
			action.call()
			refresh())
	_body.add_child(button)
	return button

func _choice() -> OptionButton:
	var choice := OptionButton.new()
	choice.fit_to_longest_item = false
	_body.add_child(choice)
	choice.get_popup().window_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed(&"debug_toggle_console") and not event.is_echo():
			choice.get_popup().set_input_as_handled()
			choice.get_popup().hide()
			close_requested.emit())
	return choice

func close_popups() -> void:
	for choice: OptionButton in [_fixtures, _items, _recipes, _targets]:
		choice.get_popup().hide()

func _selected(choice: OptionButton) -> String:
	return str(choice.get_selected_metadata()) if choice.selected >= 0 else ""

func _populate(choice: OptionButton, rows: Array) -> void:
	var previous := _selected(choice)
	choice.clear()
	for row: Dictionary in rows:
		choice.add_item(row.label)
		choice.set_item_metadata(choice.item_count - 1, row.id)
		if row.id == previous:
			choice.select(choice.item_count - 1)
	choice.disabled = rows.is_empty()
	if rows.is_empty():
		choice.add_item("暂无可用项目")
		choice.set_item_metadata(0, "")

func reload_choices() -> void:
	if tools == null:
		return
	_populate(_fixtures, tools.get_fixtures())
	_populate(_items, tools.get_items())
	_populate(_recipes, tools.get_recipes())
	_populate(_targets, tools.get_targets())

func refresh() -> void:
	if tools == null:
		return
	var tasks := tools.context.get("tasks") as TaskJournal
	var task := tasks.get_current_main_task() if tasks != null else {}
	var state: Node = tools.context.get("state")
	var bridge := tools.context.get("bridge") as GameplayBridge
	var runtime := bridge.get_runtime_status() if bridge != null else {}
	_status.text = "日期 / 阶段：%s / %s\n主线：%s\n当前目标：%s\nBridge：%s → %s\n写入限制：%s" % [
		state.get("current_day") if is_instance_valid(state) else "不可用",
		state.get("story_stage") if is_instance_valid(state) else "不可用",
		task.get("title", "暂无主线"), task.get("current_objective", {}).get("text", "暂无待办目标"),
		runtime.get("phase_id", "不可用"), runtime.get("next_event", ""),
		tools.block_reason() if not tools.block_reason().is_empty() else "可操作"]
	var running := tools.job_running()
	_generate.disabled = running or not OS.has_feature("editor")
	_launch.disabled = _selected(_fixtures).is_empty() or running or not OS.has_feature("editor")
	for button: Button in _cheats:
		button.disabled = not tools.block_reason().is_empty()
	_cheats[0].disabled = _cheats[0].disabled or tools.context.get("transactions") == null
	_cheats[1].disabled = _cheats[1].disabled or _selected(_items).is_empty()
	_cheats[2].disabled = _cheats[2].disabled or _selected(_recipes).is_empty()
	_cheats[3].disabled = _cheats[3].disabled or _selected(_targets).is_empty()
	_message.text = tools.message
	var job := tools.get_job()
	if not job.is_empty():
		_message.text += "\n生成状态：%s\n日志：%s" % ["运行中" if running else "已退出；刷新列表，若为空请检查日志", job.get("log", "")]
	_message.tooltip_text = _message.text

func _process(delta: float) -> void:
	if not is_visible_in_tree() or tools == null:
		return
	_elapsed += delta
	if _elapsed >= 0.5:
		_elapsed = 0.0
		refresh()
