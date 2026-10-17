class_name DeveloperPanel
extends Control

signal speed_multiplier_selected(multiplier: float)
signal close_requested
signal respawn_requested
signal restart_requested
signal clear_log_requested
signal events_reload_requested
signal event_trigger_requested(event_id: String)
signal flag_write_requested(key: String, value: bool)
signal variable_write_requested(key: String, value_text: String)
signal event_complete_requested(event_id: String)
signal phase_enter_requested(index: int)
signal session_reset_requested
signal log_source_changed(source: String)
signal log_export_requested

@onready var speed_selector: OptionButton = %SpeedSelector
@onready var status_text: TextEdit = %StatusText
@onready var story_text: TextEdit = %StoryText
@onready var log_text: TextEdit = %LogText
@onready var log_source: OptionButton = %LogSource
@onready var log_message: Label = %LogMessage
@onready var _export_log: Button = %ExportLog
@onready var event_list: ItemList = %EventList
@onready var event_message: Label = %EventMessage
@onready var event_trigger: Button = %TriggerEvent
@onready var _event_confirmation: VBoxContainer = %EventConfirmation
@onready var _event_rows: Array = []
@onready var wallet_text: TextEdit = %WalletText
@onready var inventory_text: TextEdit = %InventoryText
@onready var production_text: TextEdit = %ProductionText
@onready var task_text: TextEdit = %TaskText
@onready var bridge_text: TextEdit = %BridgeText
@onready var _respawn: Button = %Respawn
@onready var _restart: Button = %Restart
@onready var _confirmation: VBoxContainer = %Confirmation
@onready var phase_selector: OptionButton = %PhaseSelector
@onready var _phase_detail: Label = %PhaseDetail
@onready var _flag_key: LineEdit = %FlagKey
@onready var _flag_value: OptionButton = %FlagValue
@onready var _apply_flag: Button = %ApplyFlag
@onready var _variable_key: LineEdit = %VariableKey
@onready var _variable_value: LineEdit = %VariableValue
@onready var _apply_variable: Button = %ApplyVariable
@onready var _event_id: LineEdit = %EventId
@onready var _complete_event: Button = %CompleteEvent
@onready var _enter_phase: Button = %EnterPhase
@onready var _write_hint: Label = %WriteHint
@onready var _write_result: Label = %WriteResult
@onready var _reset_session: Button = %ResetSession
@onready var _reset_confirmation: VBoxContainer = %ResetConfirmation

## Write controls mirror the host guard; every disabled state carries its reason.
const WRITE_READY_HINT := "写入会立即生效，并在事件日志追加一条“调试写入”记录。"
var _write_available := false
var _write_reason := ""
var _phase_signature := "<unset>"
var _phase_unavailable := ""
var _phases: Array[Dictionary] = []

func _ready() -> void:
	var details: TabContainer = $Panel/Margin/Tools/Tabs/剧情/Details
	details.set_tab_title(0, "状态数据")
	details.set_tab_title(1, "事件日志")
	details.set_tab_title(2, "事件")
	var sections: TabContainer = $Panel/Margin/Tools/Tabs/业务/Sections
	for pair: Array in [[0, "钱包"], [1, "仓库"], [2, "产出"], [3, "任务"], [4, "Bridge"]]:
		sections.set_tab_title(pair[0], pair[1])
	var writes: TabContainer = $"Panel/Margin/Tools/Tabs/写状态/Sections"
	for pair: Array in [[0, "flag"], [1, "variable"], [2, "事件"], [3, "阶段"], [4, "会话"]]:
		writes.set_tab_title(pair[0], pair[1])
	speed_selector.item_selected.connect(_on_speed_selected)
	# Embedded popup windows receive input before the main viewport.
	speed_selector.get_popup().window_input.connect(_on_popup_input)
	%Close.pressed.connect(func() -> void: close_requested.emit())
	_respawn.pressed.connect(func() -> void: respawn_requested.emit())
	_restart.pressed.connect(func() -> void: _confirmation.show())
	%ConfirmRestart.pressed.connect(func() -> void:
		_confirmation.hide()
		restart_requested.emit())
	%CancelRestart.pressed.connect(cancel_restart)
	%ClearLog.pressed.connect(func() -> void: clear_log_requested.emit())
	log_source.clear()
	log_source.add_item("全部来源")
	log_source.set_item_metadata(0, "")
	for source: String in DebugLog.SOURCES:
		log_source.add_item(source)
		log_source.set_item_metadata(log_source.item_count - 1, source)
	log_source.select(0)
	log_source.item_selected.connect(func(_index: int) -> void: log_source_changed.emit(get_log_source()))
	log_source.get_popup().window_input.connect(_on_popup_input)
	_export_log.pressed.connect(func() -> void: log_export_requested.emit())
	%ReloadEvents.pressed.connect(func() -> void: events_reload_requested.emit())
	event_trigger.pressed.connect(_on_trigger_pressed)
	%ConfirmEvent.pressed.connect(_on_event_confirmed)
	%CancelEvent.pressed.connect(cancel_event_trigger)
	event_list.item_selected.connect(func(_index: int) -> void: _update_event_controls())
	_flag_value.clear()
	_flag_value.add_item("true", 1)
	_flag_value.add_item("false", 0)
	_flag_value.select(0)
	for popup: OptionButton in [_flag_value, phase_selector]:
		popup.get_popup().window_input.connect(_on_popup_input)
	_apply_flag.pressed.connect(func() -> void: flag_write_requested.emit(_flag_key.text, _flag_value.get_selected_id() == 1))
	_apply_variable.pressed.connect(func() -> void: variable_write_requested.emit(_variable_key.text, _variable_value.text))
	_complete_event.pressed.connect(func() -> void: event_complete_requested.emit(_event_id.text))
	_enter_phase.pressed.connect(func() -> void: phase_enter_requested.emit(phase_selector.selected))
	phase_selector.item_selected.connect(func(_index: int) -> void: _update_phase_detail())
	# Enter applies the surrounding field without leaving the keyboard.
	for field: LineEdit in [_flag_key, _variable_key, _event_id]:
		field.text_submitted.connect(func(_text: String) -> void: _submit_field(field))
	_reset_session.pressed.connect(func() -> void: _reset_confirmation.show())
	%ConfirmReset.pressed.connect(func() -> void:
		_reset_confirmation.hide()
		session_reset_requested.emit())
	%CancelReset.pressed.connect(cancel_write_confirmations)
	_apply_write_availability()
	hide()

func uses_native_gui_input() -> bool:
	return true

func get_default_focus() -> Control:
	return %Close

func on_ui_closed() -> void:
	cancel_restart()

func cancel_restart() -> void:
	_confirmation.hide()
	cancel_event_trigger()
	cancel_write_confirmations()
	speed_selector.get_popup().hide()
	if is_instance_valid(log_source):
		log_source.get_popup().hide()

func cancel_write_confirmations() -> void:
	_reset_confirmation.hide()
	if is_instance_valid(phase_selector):
		phase_selector.get_popup().hide()
	if is_instance_valid(_flag_value):
		_flag_value.get_popup().hide()

func configure_choices(multipliers: PackedInt32Array) -> void:
	speed_selector.clear()
	for multiplier: int in multipliers:
		speed_selector.add_item("玩家移速 %d×" % multiplier, multiplier)

func set_speed_multiplier(multiplier: float) -> void:
	speed_selector.select(speed_selector.get_item_index(int(multiplier)))

func set_capabilities(speed_available: bool, respawn_available: bool, restart_available: bool) -> void:
	speed_selector.disabled = not speed_available
	_respawn.disabled = not respawn_available
	_restart.disabled = not restart_available
	%ConfirmRestart.disabled = not restart_available
	%CharacterHint.text = "不可用的能力已禁用；剧情演出期间禁用角色操作。"

func set_status(data: Dictionary, state: Dictionary) -> void:
	var text := "场景：%s\n关卡：%s\n玩家坐标：%s\nFPS：%s\n当前天数：%s\n剧情阶段：%s" % [
		data.get("scene", "不可用"), data.get("level", "不可用"), data.get("position", "不可用"),
		data.get("fps", "不可用"), state.get("current_day", "GameState 不可用"),
		state.get("story_stage", "GameState 不可用") if not str(state.get("story_stage", "")).is_empty() else "未设置"]
	_replace_text(status_text, text)

func set_story(state: Dictionary, runtime: Dictionary) -> void:
	var description := "StoryDirector 不可用"
	if not runtime.is_empty():
		description = "未加载剧情事件" if not runtime.loaded else "已加载 %d 个事件 · 空闲" % runtime.event_count
		if not str(runtime.event_id).is_empty():
			description += "\n执行中：%s / 步骤 %d（从 0 开始）" % [runtime.event_id, runtime.step_index]
		if not str(runtime.last_error).is_empty():
			description += "\n最近错误：" + str(runtime.last_error)
	var text := description + "\n\nGameState 不可用"
	if not state.is_empty():
		text = description + "\n\nflags（只读）\n" + JSON.stringify(state.flags, "  ")
		text += "\n\nvariables（只读）\n" + JSON.stringify(state.variables, "  ")
		text += "\n\n已完成事件（只读）\n" + JSON.stringify(state.completed_events, "  ")
	_replace_text(story_text, text)

func set_log(lines: Array[String]) -> void:
	var empty_text := "该来源暂无记录" if not get_log_source().is_empty() else "暂无调试日志记录"
	_replace_text(log_text, empty_text if lines.is_empty() else "\n".join(lines))

## 空字符串表示“全部来源”；选项元数据保存真实来源名，供过滤和导出使用。
func get_log_source() -> String:
	if log_source.item_count == 0 or log_source.selected < 0:
		return ""
	return String(log_source.get_item_metadata(log_source.selected))

func set_log_message(text: String) -> void:
	if log_message.text == text:
		return
	log_message.text = text

## Event catalogue rows from StoryDirector read-only queries. Text is refreshed in
## place while the ID set is unchanged, so selection survives the throttled refresh.
func set_events(rows: Array) -> void:
	var rebuild := event_list.item_count != rows.size()
	if not rebuild:
		for index in range(rows.size()):
			if String(event_list.get_item_metadata(index)) != String(rows[index].get("id", "")):
				rebuild = true
				break
	var selected := get_selected_event_id()
	if rebuild:
		event_list.clear()
		for row: Dictionary in rows:
			var index := event_list.add_item(_event_text(row))
			event_list.set_item_metadata(index, String(row.get("id", "")))
	else:
		for index in range(rows.size()):
			event_list.set_item_text(index, _event_text(rows[index]))
	_event_rows = rows.duplicate(true)
	_select_event(selected)
	_update_event_controls()

func set_event_available(available: bool) -> void:
	%ReloadEvents.disabled = not available
	event_trigger.disabled = not available or get_selected_event_id().is_empty()

func _update_event_controls() -> void:
	event_trigger.disabled = get_selected_event_id().is_empty()

func set_event_message(text: String) -> void:
	if event_message.text == text:
		return
	event_message.text = text

func get_selected_event_id() -> String:
	var selected := event_list.get_selected_items()
	return "" if selected.is_empty() else String(event_list.get_item_metadata(selected[0]))

func cancel_event_trigger() -> void:
	_event_confirmation.hide()

func _select_event(id: String) -> void:
	if id.is_empty():
		event_list.deselect_all()
		return
	for index in range(event_list.item_count):
		if String(event_list.get_item_metadata(index)) == id:
			event_list.select(index)
			return
	event_list.deselect_all()

## Triggering locks input and may move actors, so it always asks first.
func _on_trigger_pressed() -> void:
	var id := get_selected_event_id()
	if id.is_empty():
		set_event_message("请先在列表中选择一个事件。")
		return
	%EventConfirmText.text = "将触发 %s：剧情会锁定输入，并可能移动角色或镜头。确认后关闭面板再开始演出。" % id
	_event_confirmation.show()

func _on_event_confirmed() -> void:
	var id := get_selected_event_id()
	cancel_event_trigger()
	if not id.is_empty():
		event_trigger_requested.emit(id)

func _event_text(row: Dictionary) -> String:
	var parts := PackedStringArray([String(row.get("id", ""))])
	parts.append("已完成" if row.get("completed", false) else "未完成")
	parts.append("条件满足" if row.get("conditions_met", false) else "条件不满足")
	parts.append("%d 步" % int(row.get("step_count", 0)))
	var trigger := String(row.get("trigger", ""))
	if not trigger.is_empty():
		parts.append("路由 " + trigger)
	return "｜".join(parts)

## Business snapshot rendering. Every empty section means its service is missing;
## the panel never fills a gap with derived or remembered values.
func set_business(data: Dictionary) -> void:
	_replace_text(wallet_text, _wallet_text(data.get("wallet", {})))
	_replace_text(inventory_text, _inventory_text(data.get("inventory", {})))
	_replace_text(production_text, _production_text(data.get("production", {})))
	_replace_text(task_text, _task_text(data.get("tasks", {})))
	_replace_text(bridge_text, _bridge_text(data.get("bridge", {})))

func _wallet_text(wallet: Dictionary) -> String:
	if wallet.is_empty():
		return "WalletTransactions 不可用"
	var lines := PackedStringArray(["余额：%d" % int(wallet.get("balance", 0)),
		"交易状态：%s" % ("处理中" if wallet.get("busy", false) else "空闲"), "",
		"最近交易（最多 %d 条，新→旧）" % DeveloperTools.RECENT_TRANSACTION_LIMIT])
	var recent: Array = wallet.get("recent", [])
	if recent.is_empty():
		lines.append("暂无交易记录")
	for result: Dictionary in recent:
		lines.append("%s · %s · %s" % [result.get("time", ""), result.get("code", ""), result.get("message", "")])
		lines.append("    余额 %d · #%s" % [int(result.get("balance", 0)), result.get("request_id", "")])
	return "\n".join(lines)

func _inventory_text(inventory: Dictionary) -> String:
	if inventory.is_empty():
		return "WarehouseInventory 不可用"
	var items: Array = inventory.get("items", [])
	if items.is_empty():
		return "仓库没有物品"
	var lines := PackedStringArray(["物品（菜单顺序，含 0 库存）", ""])
	for item: Dictionary in items:
		lines.append("%s（%s）× %d · %s" % [item.get("name", ""), item.get("id", ""),
			int(item.get("quantity", 0)), "已发现" if item.get("discovered", false) else "未发现"])
	return "\n".join(lines)

func _production_text(production: Dictionary) -> String:
	if production.is_empty():
		return "TeaProduction 不可用"
	return "当前订单\n%s\n\n已完成：%d 杯\n提交中：%s" % [production.get("order_text", "不可用"),
		int(production.get("completed", 0)), "是" if production.get("submitting", false) else "否"]

func _task_text(tasks: Dictionary) -> String:
	if tasks.is_empty():
		return "TaskJournal 不可用"
	var lines := PackedStringArray(["当前主线任务"])
	var main: Dictionary = tasks.get("main", {})
	if main.is_empty():
		lines.append("没有进行中的主线任务")
	else:
		lines.append("%s · %s" % [main.get("id", ""), main.get("title", "")])
		var objective: Dictionary = main.get("current_objective", {})
		lines.append("当前目标：%s" % (objective.get("text", "") if not objective.is_empty() else "已完成"))
	lines.append("")
	var active: Array = tasks.get("active", [])
	lines.append("进行中任务（%d）" % active.size())
	if active.is_empty():
		lines.append("没有进行中的任务")
	for task: Dictionary in active:
		lines.append("%s · %s · %s" % [task.get("id", ""), task.get("type", ""), task.get("title", "")])
		var requirements: PackedStringArray = task.get("requirements", PackedStringArray())
		if requirements.is_empty():
			lines.append("    交付要求：无")
		else:
			lines.append("    交付要求：" + "\n    ".join(requirements))
	return "\n".join(lines)

func _bridge_text(bridge: Dictionary) -> String:
	if bridge.is_empty():
		return "GameplayBridge 不可用"
	var phase := str(bridge.get("phase_id", ""))
	var lines := PackedStringArray(["已载入 phase：%d" % int(bridge.get("phase_count", 0)),
		"启用：%s" % ("是" if bridge.get("enabled", false) else "否"),
		"阶段 id：%s" % (phase if not phase.is_empty() else "无"),
		"等待：%s" % ("是" if bridge.get("waiting", false) else "否"),
		"允许开始剧情：%s" % ("是" if bridge.get("allows_story_start", true) else "否")])
	var inflight := str(bridge.get("inflight", ""))
	if not inflight.is_empty():
		lines.append("续接中：" + inflight)
	var error := str(bridge.get("last_error", ""))
	lines.append("最近错误：" + (error if not error.is_empty() else "无"))
	return "\n".join(lines)

func _replace_text(view: TextEdit, text: String) -> void:
	if view.text == text:
		return
	var scroll := view.scroll_vertical
	view.text = text
	view.scroll_vertical = scroll

func _on_speed_selected(index: int) -> void:
	speed_multiplier_selected.emit(float(speed_selector.get_item_id(index)))

func _on_popup_input(event: InputEvent) -> void:
	if DebugRuntime.is_enabled() and event.is_action_pressed(DeveloperTools.TOGGLE_ACTION) and not event.is_echo():
		close_requested.emit()

## Phase rows come from phase data only. A duplicate rebuild keeps the current
## selection, so the throttled refresh cannot close or reset an open dropdown.
func set_phases(phases: Array[Dictionary], error_text: String) -> void:
	var signature := error_text
	for phase: Dictionary in phases:
		signature += "\n%s|%s" % [phase.id, phase.flag]
	if signature == _phase_signature:
		return
	var previous := get_selected_phase_index()
	_phase_signature = signature
	_phase_unavailable = error_text
	_phases = phases.duplicate(true)
	phase_selector.clear()
	if not error_text.is_empty() or phases.is_empty():
		phase_selector.add_item("阶段数据不可用")
		phase_selector.set_item_disabled(0, true)
		phase_selector.select(0)
		phase_selector.tooltip_text = error_text if not error_text.is_empty() else "没有可用的阶段数据。"
		_update_phase_detail()
		_apply_write_availability()
		return
	for index in range(phases.size()):
		phase_selector.add_item("%s · %s" % [phases[index].id, phases[index].flag], index)
		phase_selector.set_item_tooltip(index, "%s · %s\n阶段 %s · 后续事件 %s" % [
			phases[index].id, phases[index].flag, phases[index].stage, phases[index].next_event])
	phase_selector.select(maxi(previous, 0) if previous < phases.size() else 0)
	phase_selector.tooltip_text = ""
	_update_phase_detail()
	_apply_write_availability()

## Item text is clipped by the panel width; this line always shows the full
## completion flag, stage and follow-up event of the selected phase.
func _update_phase_detail() -> void:
	var index := get_selected_phase_index()
	if index < 0 or index >= _phases.size():
		_phase_detail.text = "没有可用的阶段数据。"
		return
	var phase: Dictionary = _phases[index]
	_phase_detail.text = "完成条件 %s\n阶段 %s · 后续事件 %s" % [phase.flag, phase.stage, phase.next_event]

## The host owns the reason text: busy story, active dialogue and performance
## control each arrive as their own sentence instead of a static warning.
func set_write_state(available: bool, reason: String) -> void:
	_write_available = available
	_write_reason = reason
	_apply_write_availability()

func set_write_result(text: String) -> void:
	_write_result.text = text

func get_selected_phase_index() -> int:
	return phase_selector.selected if phase_selector.item_count > 0 else -1

func _apply_write_availability() -> void:
	var phases_ready := _phase_unavailable.is_empty() and phase_selector.item_count > 0 and not phase_selector.is_item_disabled(0)
	_apply_flag.disabled = not _write_available
	_apply_variable.disabled = not _write_available
	_complete_event.disabled = not _write_available
	_reset_session.disabled = not _write_available
	%ConfirmReset.disabled = not _write_available
	phase_selector.disabled = not _write_available or not phases_ready
	_enter_phase.disabled = not _write_available or not phases_ready
	_enter_phase.text = "写入完成条件并刷新" if phases_ready else "阶段数据不可用"
	for field: LineEdit in [_flag_key, _variable_key, _variable_value, _event_id]:
		field.editable = _write_available
	if _write_available:
		_write_hint.text = WRITE_READY_HINT
	else:
		_write_hint.text = "写入已禁用：%s" % (_write_reason if not _write_reason.is_empty() else "当前宿主不允许写入游戏状态。")

func _submit_field(field: LineEdit) -> void:
	if not _write_available:
		return
	if field == _flag_key:
		_apply_flag.pressed.emit()
	elif field == _variable_key or field == _variable_value:
		_apply_variable.pressed.emit()
	else:
		_complete_event.pressed.emit()
