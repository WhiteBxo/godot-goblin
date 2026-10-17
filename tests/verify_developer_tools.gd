extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_verify")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: ", description)

func _verify() -> void:
	# 用独立状态模拟任意角色，不加载洞穴地图或 CavePlayer。
	var state := {"multiplier": 1.0}
	var other_state := {"multiplier": 1.0}
	var tools: DeveloperTools = load("res://src/debug/developer_tools/developer_tools.tscn").instantiate()
	var panel: DeveloperPanel = load("res://src/debug/developer_tools/developer_panel.tscn").instantiate()
	root.add_child(tools)
	root.add_child(panel)
	await process_frame
	var setter := func(value: float) -> void: state.multiplier = value
	var getter := func() -> float: return state.multiplier
	check(tools.configure(setter, getter, panel) == OK, "Generic tool accepts injected callbacks")
	panel.speed_selector.select(3)
	panel.speed_selector.item_selected.emit(3)
	check(state.multiplier == 8.0, "Panel selection updates independent target")
	tools.set_player_speed_multiplier(2.5)
	check(state.multiplier == 8.0, "Fractional multiplier is rejected")
	check(tools.configure(func(value: float) -> void: other_state.multiplier = value, func() -> float: return other_state.multiplier, panel) == OK, "Tool can rebind to another target")
	tools.set_player_speed_multiplier(4.0)
	check(state.multiplier == 8.0 and other_state.multiplier == 4.0, "Rebinding stops changing old target")
	check(panel.speed_multiplier_selected.get_connections().size() == 1, "Reconfiguration does not duplicate signal connections")
	paused = true
	check(tools.can_process(), "Generic tool remains active during pause")
	tools.set_player_speed_multiplier(2.0)
	check(other_state.multiplier == 2.0, "Paused tool still updates target")
	paused = false
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	tools.set_player_speed_multiplier(8.0)
	check(other_state.multiplier == 2.0, "Disabled tools ignore direct API calls")
	check(tools.configure(setter, getter, panel) == ERR_UNCONFIGURED and not panel.visible, "Disabled configuration hides panel")
	ProjectSettings.set_setting("debug/developer_tools/enabled", null)
	check(tools.configure(Callable(), getter, panel) == ERR_UNCONFIGURED, "Invalid binding fails safely")
	await _verify_observation(tools, panel, setter, getter)
	await _verify_business(tools, panel, setter, getter)
	await _verify_writes(tools, panel, setter, getter)
	await _verify_events(tools, panel)
	await _verify_shared_log()
	tools.queue_free()
	panel.queue_free()
	await process_frame
	print("Developer tools: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _verify_observation(tools: DeveloperTools, panel: DeveloperPanel, setter: Callable, getter: Callable) -> void:
	check(not panel.visible, "Console defaults to collapsed")
	tools.configure(Callable(), Callable(), panel)
	tools.toggle_panel()
	check(panel.visible and panel.speed_selector.disabled, "Observer opens without player capabilities")
	check(panel.story_text.text.contains("StoryDirector 不可用") and panel.story_text.text.contains("GameState 不可用"), "Missing services are explicit")
	tools.close_panel()
	var state := root.get_node("GameState")
	var before: Dictionary = state.to_dict()
	var ui: DialogueUI = load("res://src/UI/dialogue/dialogue_ui.tscn").instantiate()
	root.add_child(ui)
	var manager := DialogueManager.new()
	root.add_child(manager)
	manager.configure(ui)
	var director := StoryDirector.new()
	root.add_child(director)
	director.configure(manager)
	var restarted := {"count": 0}
	var context := {"state": state, "story": director, "restart": func() -> void: restarted.count += 1}
	tools.configure(setter, getter, panel, context)
	check(panel.story_text.text.contains("未加载剧情事件"), "Unloaded catalogue remains unloaded by observation")
	check(not director.get_runtime_status().loaded, "Console does not lazily load stories")
	state.set_flag("console.observed")
	state.set_variable("console.long_text", "long text ".repeat(100))
	state.complete_event("console.observed")
	tools.refresh()
	check(panel.story_text.text.contains("console.observed") and panel.story_text.text.contains("long text ".repeat(100)), "Readonly view retains full flags, variables and completed events")
	check(state.get_flag("console.observed"), "Observation preserves state")
	check(director.load_events("res://tests/fixtures/story_events.json") == OK, "Real story fixture loads")
	tools.configure(setter, getter, panel, context)
	tools.bind_story_director(director)
	tools.bind_story_director(director)
	tools.clear_log()
	check(director.request_event("test.repeat") == OK, "Real repeat event starts")
	await process_frame
	await process_frame
	await process_frame
	check(tools.get_log().size() == 4, "Real start/step/complete/finish produce exactly four entries after rebinding")
	check(tools.get_log()[0].contains("事件开始") and tools.get_log()[2].contains("事件完成"), "Log reflects actual successful lifecycle")
	check(director.load_events("res://tests/fixtures/developer_console_events.json") == OK and director.request_event("console.skip") == OK, "Conditional skip event executes through loader")
	await process_frame
	await process_frame
	await process_frame
	check("\n".join(tools.get_log()).contains("步骤跳过 console.skip / 0 · Step conditions not met"), "Skip log includes real reason")
	director.load_events("res://tests/fixtures/story_events.json")
	check(director.request_event("test.wait") == OK, "Cancellable event starts")
	director.cancel_event("console test cancellation")
	check(tools.get_log().back().contains("事件失败 test.wait") and tools.get_log().back().contains("console test cancellation"), "Failure log preserves actual reason")
	for index in range(130):
		director.request_event("test.repeat")
		await process_frame
		await process_frame
		await process_frame
	check(tools.get_log().size() == DebugLog.CAPACITY, "Log ring retains at most 500 real signal entries")
	var copy := tools.get_log()
	copy.clear()
	check(tools.get_log().size() == DebugLog.CAPACITY, "Log snapshot cannot mutate buffer")
	panel.clear_log_requested.emit()
	check(tools.get_log().is_empty(), "Clear log control empties buffer")
	var other := StoryDirector.new()
	root.add_child(other)
	tools.bind_story_director(other)
	director.request_event("test.repeat")
	await process_frame
	await process_frame
	await process_frame
	check(tools.get_log().is_empty(), "Replacing director disconnects old source")
	tools.bind_story_director(null)
	tools.toggle_panel()
	panel.get_node("%Restart").pressed.emit()
	check(restarted.count == 0 and panel.get_node("%Confirmation").visible, "Restart request requires explicit confirmation")
	panel.get_node("%CancelRestart").pressed.emit()
	check(restarted.count == 0 and not panel.get_node("%Confirmation").visible, "Restart cancellation is harmless")
	panel.get_node("%Restart").pressed.emit()
	panel.get_node("%ConfirmRestart").pressed.emit()
	check(restarted.count == 1 and not panel.visible, "Confirmation invokes injected restart once")
	state.restore_state(before)
	other.queue_free()
	director.queue_free()
	manager.queue_free()
	ui.queue_free()
	await process_frame

## 业务页只读观察：数据进入文本快照，缺失服务显示不可用，观察不改变业务事实。
func _verify_business(tools: DeveloperTools, panel: DeveloperPanel, setter: Callable, getter: Callable) -> void:
	var state := root.get_node("GameState")
	var wallet: WalletTransactions = state.get_transactions()
	var inventory: WarehouseInventory = state.get_warehouse_inventory()
	var production: TeaProduction = state.get_tea_production()
	var catalog := TaskCatalog.new()
	check(catalog.load_file("res://src/resources/tasks/tasks.json") == OK, "Business task catalogue loads")
	var journal := TaskJournal.new()
	root.add_child(journal)
	journal.configure(catalog, state)
	var delivery := TaskDelivery.new()
	root.add_child(delivery)
	check(delivery.configure(catalog, journal, state, inventory) == OK, "Delivery binds the shared inventory")
	var director := StoryDirector.new()
	root.add_child(director)
	var screens := UIManager.new()
	root.add_child(screens)
	var bridge := GameplayBridge.new()
	root.add_child(bridge)
	bridge.configure(director, screens)
	check(bridge.load_phases("res://tests/fixtures/task_phases.json") == OK, "Bridge fixture loads for observation")
	bridge.last_error = "console bridge error"
	tools.configure(setter, getter, panel, {})
	check(panel.wallet_text.text.contains("WalletTransactions 不可用")
		and panel.inventory_text.text.contains("WarehouseInventory 不可用")
		and panel.production_text.text.contains("TeaProduction 不可用")
		and panel.task_text.text.contains("TaskJournal 不可用")
		and panel.bridge_text.text.contains("GameplayBridge 不可用"), "Missing business services are explicit")
	var original: Dictionary = state.to_dict()
	var context := {"state": state, "story": director, "transactions": wallet, "inventory": inventory,
		"production": production, "tasks": journal, "delivery": delivery, "bridge": bridge}
	check(tools.configure(setter, getter, panel, context) == OK, "Business services bind through context")
	wallet.add_money(7, "console.credit")
	check(wallet.spend_money(99999, "console.refused").code == "insufficient_funds", "Rejected transaction is observable")
	tools.refresh()
	check(panel.wallet_text.text.contains("余额：%d" % wallet.get_balance()), "Wallet balance matches the live wallet")
	check(panel.wallet_text.text.contains("insufficient_funds") and panel.wallet_text.text.contains("余额不足。"), "Rejected transaction keeps its real code and message")
	check(panel.wallet_text.text.contains("console.credit") and panel.wallet_text.text.contains("交易成功。"), "Accepted transaction keeps its real result")
	for index in range(6):
		wallet.add_money(1, "console.recent_%d" % index)
	tools.refresh()
	check(not panel.wallet_text.text.contains("console.credit") and not panel.wallet_text.text.contains("console.recent_0")
		and panel.wallet_text.text.contains("console.recent_5"), "Signal history keeps only the newest five results")
	check(panel.inventory_text.text.contains("醒神菇（insomnia_mushroom）× 0 · 未发现"), "Zero-stock undiscovered items stay listed")
	var order_index := panel.inventory_text.text.find("红茶")
	check(order_index >= 0 and order_index < panel.inventory_text.text.find("珍珠（pearl）")
		and panel.inventory_text.text.find("珍珠（pearl）") < panel.inventory_text.text.find("醒神菇（insomnia_mushroom）"), "Warehouse keeps catalogue order")
	check(panel.production_text.text.contains(production.get_order_text())
		and panel.production_text.text.contains("已完成：%d 杯" % production.get_completed_count())
		and panel.production_text.text.contains("提交中：否"), "Production order text and progress shown")
	state.set_flag("task.shop.first_order.active")
	tools.refresh()
	check(panel.task_text.text.contains("shop.first_order") and panel.task_text.text.contains("完成第一笔订单"), "Active task list renders the journal projection")
	check(panel.task_text.text.contains("order_001：珍珠奶茶（成品） ×1"), "Delivery requirement comes from TaskDelivery.get_requirement")
	check(panel.task_text.text.contains("当前目标："), "Current main objective is shown")
	check(panel.bridge_text.text.contains("已载入 phase：1") and panel.bridge_text.text.contains("允许开始剧情：是")
		and panel.bridge_text.text.contains("console bridge error"), "Bridge phase, guard and last error are shown")
	var before: Dictionary = state.to_dict()
	var projection_before := str(journal.get_active_tasks())
	var inventory_text_before := panel.inventory_text.text
	for index in range(3):
		tools.refresh()
	check(panel.inventory_text.text == inventory_text_before, "Unchanged observation keeps the same text snapshot")
	check(state.to_dict() == before, "Observation leaves wallet, inventory, production and task facts unchanged")
	check(wallet.get_balance() == int(before.economy.balance) and inventory.to_dict() == before.business.inventory,
		"Read-only calls keep balance and stock identical")
	check(str(journal.get_active_tasks()) == projection_before and journal.get_task("shop.first_order").status == "active",
		"Read-only calls keep the task projection identical")
	state.restore_state(original)
	bridge.queue_free()
	screens.queue_free()
	director.queue_free()
	delivery.queue_free()
	journal.queue_free()
	await process_frame

## 写状态页：写入只走公开 API、busy 时拒绝、阶段进入写完成条件 flag，
## 来源“调试写入”的日志与正常流程可区分；Release 边界由 verify_debug_build 覆盖。
func _verify_writes(tools: DeveloperTools, panel: DeveloperPanel, setter: Callable, getter: Callable) -> void:
	var state := root.get_node("GameState")
	var original: Dictionary = state.to_dict()
	var phases: Array[Dictionary] = _phase_rows()
	check(phases.size() == 3, "Phase data exposes three stages")
	check(tools.configure(setter, getter, panel, {"state": state}) == OK, "Write page binds GameState through context")
	var configured_phases := tools.get_phases()
	check(configured_phases.size() == phases.size(), "Phase list is read from phase data instead of being hardcoded")
	var matches_data := configured_phases.size() == phases.size()
	for index in range(mini(configured_phases.size(), phases.size())):
		matches_data = matches_data and configured_phases[index].id == phases[index].id \
			and configured_phases[index].flag == phases[index].flag
	check(matches_data, "Phase ids and flags match the phase JSON exactly")
	var selector := panel.get_node("%PhaseSelector") as OptionButton
	check(selector.item_count == phases.size(), "Phase dropdown lists every stage from data")
	check(selector.get_item_text(0).contains(phases[0].id) and selector.get_item_text(0).contains(phases[0].flag),
		"Dropdown shows the stage id together with its completion flag")
	check(not panel.get_node("%ApplyFlag").disabled, "Writes are enabled when the host guard allows control")
	tools.clear_log()
	check(tools.write_flag("console.debug_written", true) and state.get_flag("console.debug_written"),
		"Flag write reaches GameState.set_flag")
	check(panel.get_node("%WriteResult").text.contains("console.debug_written"), "Flag result is echoed in the panel")
	check("\n".join(tools.get_log()).contains("调试写入 · 信息 · flag console.debug_written = true"),
		"Injected flag is logged with the debug-write source")
	check(not tools.write_flag("console.debug_written", true)
		and panel.get_node("%WriteResult").text.contains("没有产生写入"), "Unchanged flag is reported instead of silently dropped")
	check(not tools.write_flag("nounderscore", true) and not state.has_flag("nounderscore"),
		"Invalid flag key is refused by GameState")
	check(panel.get_node("%WriteResult").text.contains("false") and "\n".join(tools.get_log()).contains("调试写入 · 警告 · 被拒绝"),
		"API false return is echoed and logged as a refusal")
	check(tools.write_variable("console.debug_count", "42") and typeof(state.get_variable("console.debug_count")) == TYPE_INT,
		"Integer text parses to int")
	check(tools.write_variable("console.debug_ratio", "1.5") and typeof(state.get_variable("console.debug_ratio")) == TYPE_FLOAT,
		"Decimal text parses to float")
	check(tools.write_variable("console.debug_on", "true") and typeof(state.get_variable("console.debug_on")) == TYPE_BOOL,
		"true/false text parses to bool")
	check(tools.write_variable("console.debug_name", "珍珠") and state.get_variable("console.debug_name") == "珍珠",
		"Remaining text is stored as String")
	check(not tools.write_variable("console.debug_name", "珍珠")
		and panel.get_node("%WriteResult").text.contains("没有产生写入"), "Unchanged variable is reported instead of silently dropped")
	check("\n".join(tools.get_log()).contains("调试写入 · 信息 · variable console.debug_ratio（float）"),
		"Variable log records the parsed type")
	check(tools.complete_event("console.debug_event") and state.is_event_completed("console.debug_event"),
		"Event completion reaches GameState.complete_event")
	check(not tools.complete_event("console.debug_event")
		and panel.get_node("%WriteResult").text.contains("已标记完成"), "Duplicate event completion is reported")
	var phase: Dictionary = phases[1]
	state.set_story_stage(phase.stage)
	state.complete_event(phase.after_event)
	tools.clear_log()
	check(tools.enter_phase(1), "Phase entry accepts a real stage from the dropdown")
	check(state.get_flag(phase.flag), "Phase entry writes the completion condition flag")
	check(not state.get_flag(phase.completion_flag), "Phase entry leaves completion_flag to GameplayBridge")
	check(panel.get_node("%WriteResult").text.contains(phase.id)
		and panel.get_node("%WriteResult").text.contains(phase.completion_flag),
		"Phase result names the stage and the bridge-produced flag")
	check("\n".join(tools.get_log()).contains("调试写入 · 信息 · 阶段 %s" % phase.id),
		"Phase entry is logged with the debug-write source")
	check(not tools.enter_phase(99), "Out-of-range phase index is refused")
	# Busy story: the real director reason must replace a static warning.
	var ui: DialogueUI = load("res://src/UI/dialogue/dialogue_ui.tscn").instantiate()
	root.add_child(ui)
	var manager := DialogueManager.new()
	root.add_child(manager)
	manager.configure(ui)
	var director := StoryDirector.new()
	root.add_child(director)
	director.configure(manager)
	director.load_events("res://tests/fixtures/story_events.json")
	var guarded := {"state": state, "story": director, "can_control": func() -> bool: return false}
	tools.configure(setter, getter, panel, guarded)
	director.request_event("test.wait")
	tools.refresh()
	var hint_label := panel.get_node("%WriteHint") as Label
	var hint := hint_label.text
	check(hint.contains("写入已禁用") and hint.contains("剧情演出进行中"), "Write guard explains the real busy reason")
	check(panel.get_node("%ApplyFlag").disabled and panel.get_node("%EnterPhase").disabled,
		"Busy story disables every write control")
	check(not tools.write_flag("console.blocked", true) and not state.has_flag("console.blocked"),
		"Busy story refuses the direct write API")
	check("\n".join(tools.get_log()).contains("调试写入 · 警告 · 被拒绝 · flag console.blocked"), "Refusal is logged with its reason")
	director.cancel_event("console write test")
	tools.configure(setter, getter, panel, {"state": state})
	tools.refresh()
	check(not panel.get_node("%ApplyFlag").disabled, "Writes return after the story ends")
	# Reset is behind a confirmation and never happens on the first press.
	var before_reset: Dictionary = state.to_dict()
	panel.get_node("%ResetSession").pressed.emit()
	check(panel.get_node("%ResetConfirmation").visible, "Session reset asks before clearing anything")
	check(state.to_dict() == before_reset, "Opening the reset confirmation leaves GameState intact")
	panel.get_node("%CancelReset").pressed.emit()
	check(not panel.get_node("%ResetConfirmation").visible and state.to_dict() == before_reset,
		"Reset cancellation is harmless")
	check(tools.reset_session() and state.get_flags().is_empty() and state.get_variable("console.debug_count") == null,
		"Confirmed reset returns the session to a new game")
	# Disabled tools cannot write even through the public API.
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	tools.configure(setter, getter, panel, {"state": state})
	var after_reset: Dictionary = state.to_dict()
	check(not tools.write_flag("console.disabled_write", true) and state.to_dict() == after_reset,
		"Disabled tools refuse writes")
	ProjectSettings.set_setting("debug/developer_tools/enabled", null)
	state.restore_state(original)
	director.queue_free()
	manager.queue_free()
	ui.queue_free()
	await process_frame

func _phase_rows() -> Array[Dictionary]:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DeveloperTools.PHASES_PATH))
	var rows: Array[Dictionary] = []
	if not data is Dictionary or not data.get("phases") is Array:
		return rows
	for entry: Dictionary in data["phases"]:
		rows.append({"id": str(entry.id), "flag": str(entry.completion.flag),
			"completion_flag": str(entry.completion_flag), "stage": str(entry.stage),
			"after_event": str(entry.after_event)})
	return rows

## 事件页：只读列表节流更新、重载复用宿主真实路径、触发前确认并回显 Director 原文原因。
func _verify_events(tools: DeveloperTools, panel: DeveloperPanel) -> void:
	var state := root.get_node("GameState")
	var manager := DialogueManager.new()
	root.add_child(manager)
	var director := StoryDirector.new()
	root.add_child(director)
	director.configure(manager)
	check(manager.load_dialogues("res://tests/fixtures/dialogue_edge_cases.json") == OK,
		"Dialogue fixture loads for the combined reload")
	check(tools.configure(func(_value: float) -> void: pass, func() -> float: return 1.0, panel,
		{"state": state, "story": director, "dialogue": manager}) == OK,
		"Event page binds the story director through context")
	tools.refresh()
	check(director.get_event_ids().is_empty() and not director.get_runtime_status().loaded,
		"Event page observation never loads the catalogue")
	check(panel.event_list.item_count == 0 and panel.event_message.text.contains("未加载"),
		"Unloaded catalogue shows an empty list and an explicit note")
	check(director.load_events("res://tests/fixtures/story_events.json") == OK, "Story fixture loads for the event page")
	var expected: Array[String] = ["test.choice", "test.conditions", "test.dialogue", "test.missing_dialogue",
		"test.repeat", "test.sequence", "test.sfx", "test.wait"]
	check(director.get_event_ids() == expected, "Read-only API lists every catalogue ID in stable order")
	tools.refresh()
	check(panel.event_list.item_count == expected.size(), "Event page lists every loaded event")
	check(_event_row(panel, "test.sequence").contains("5 步") and _event_row(panel, "test.sequence").contains("条件满足"),
		"Row shows step count and met conditions")
	check(_event_row(panel, "test.conditions").contains("条件不满足"),
		"Row reports unmet conditions without rejecting the request")
	var summary: Dictionary = director.get_event_summary("test.sequence")
	check(summary["once"] and int(summary["step_count"]) == 5 and not summary["completed"],
		"Summary projects once, steps and completion")
	check(director.get_event_summary("test.unknown").is_empty(), "Unknown event has no summary")
	state.complete_event("test.dialogue")
	tools.refresh()
	check(director.get_event_summary("test.dialogue")["completed"] and _event_row(panel, "test.dialogue").contains("已完成"),
		"Completion comes from GameState completed_events")
	var path := "user://console-events-%d.json" % OS.get_process_id()
	_write_event_file(path, ["debug.alpha"])
	check(director.load_events(path) == OK and director.get_event_source_path() == path,
		"Director reports the path the host actually loaded")
	tools.refresh()
	check(panel.event_list.item_count == 1 and not _event_row(panel, "debug.alpha").is_empty(),
		"List follows the host's real file")
	_write_event_file(path, ["debug.alpha", "debug.beta"])
	panel.get_node("%ReloadEvents").pressed.emit()
	check(panel.event_list.item_count == 2 and not _event_row(panel, "debug.beta").is_empty(),
		"Reload button updates the list from the same file")
	check(tools.get_event_message().contains("已重新加载")
		and "\n".join(tools.get_log()).contains("调试重载事件"), "Reload result and debug-source log are recorded")
	check(tools.get_event_message().contains("对白 res://tests/fixtures/dialogue_edge_cases.json")
		and "\n".join(tools.get_log()).contains("调试重载对白 res://tests/fixtures/dialogue_edge_cases.json"),
		"Reload also refreshes the host's dialogue catalogue")
	var index := _event_index(panel, "debug.alpha")
	panel.event_list.select(index)
	panel.event_list.item_selected.emit(index)
	panel.get_node("%TriggerEvent").pressed.emit()
	check(panel.get_node("%EventConfirmation").visible and not director.is_busy(),
		"Trigger asks for confirmation before locking input")
	panel.get_node("%ConfirmEvent").pressed.emit()
	check(not panel.visible and director.is_busy(), "Confirmation closes the console before the sequence starts")
	check(tools.get_log().back().contains("调试触发事件 debug.alpha"), "Trigger is logged with debug provenance")
	await _until_idle(director)
	check(director.get_event_summary("debug.alpha")["completed"], "Triggered once event records completion")
	var refused := tools.trigger_story_event("debug.alpha")
	check(refused == ERR_ALREADY_EXISTS and panel.visible, "Completed once event is refused and the console reopens")
	check(tools.get_event_message().contains("Story event already completed: debug.alpha"),
		"Refusal shows the director's own reason")
	check(tools.get_log().back().contains("调试触发失败")
		and tools.get_log().back().contains("Story event already completed"),
		"Refusal is logged verbatim")
	var hold_path := "user://console-hold-%d.json" % OS.get_process_id()
	_write_event_file(hold_path, ["debug.hold"], 3.0)
	director.load_events(hold_path)
	check(director.request_event("debug.hold") == OK, "Holding event starts for the busy check")
	check(tools.reload_story_events() == ERR_BUSY, "Reload is refused while a sequence is running")
	check(tools.get_event_message().contains("running or finishing"), "Busy refusal shows the director's own reason")
	director.cancel_event("console event page test")
	await _until_idle(director)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(hold_path)
	director.queue_free()
	manager.queue_free()
	await process_frame

func _write_event_file(path: String, ids: Array[String], wait: float = 0.0) -> void:
	var events := {}
	for id: String in ids:
		var steps: Array = [{"command": "set_flag", "key": id}]
		if wait > 0.0:
			steps = [{"command": "wait", "seconds": wait}]
		events[id] = {"once": true, "steps": steps}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "events": events}))
	file.close()

func _event_index(panel: DeveloperPanel, id: String) -> int:
	for index in range(panel.event_list.item_count):
		if String(panel.event_list.get_item_metadata(index)) == id:
			return index
	return -1

func _event_row(panel: DeveloperPanel, id: String) -> String:
	var index := _event_index(panel, id)
	return "" if index < 0 else panel.event_list.get_item_text(index)

func _until_idle(director: StoryDirector) -> void:
	for index in range(180):
		if not director.is_busy():
			return
		await process_frame

## 跨场景日志：两个独立 Console（模拟过门/重载后的新宿主）共享同一份单例缓冲；
## 来源与级别可区分，导出真正落地，禁用（Release 同一条判定）时不订阅、不写文件。
func _verify_shared_log() -> void:
	var state := root.get_node("GameState")
	var log: DebugLog = root.get_node_or_null("DevLog")
	check(log != null, "Cross-scene log singleton is registered as an autoload")
	if log == null:
		return
	var original: Dictionary = state.to_dict()
	state.start_new_game()
	var manager := DialogueManager.new()
	root.add_child(manager)
	var director := StoryDirector.new()
	root.add_child(director)
	director.configure(manager)
	check(director.load_events("res://tests/fixtures/story_events.json") == OK, "Log fixture loads for the shared buffer")
	var catalog := TaskCatalog.new()
	check(catalog.load_file("res://src/resources/tasks/tasks.json") == OK, "Task catalogue loads for the log probe")
	var journal := TaskJournal.new()
	root.add_child(journal)
	journal.configure(catalog, state)
	var delivery := TaskDelivery.new()
	root.add_child(delivery)
	check(delivery.configure(catalog, journal, state, state.get_warehouse_inventory()) == OK, "Delivery binds for the log probe")
	var screens := UIManager.new()
	root.add_child(screens)
	var bridge := GameplayBridge.new()
	root.add_child(bridge)
	bridge.configure(director, screens)
	var services := {"state": state, "story": director, "dialogue": manager,
		"transactions": state.get_transactions(), "delivery": delivery, "bridge": bridge}
	var noop_set := func(_value: float) -> void: pass
	var one := func() -> float: return 1.0

	var before_pair: Array = await _make_console()
	var old_console: DeveloperTools = before_pair[0]
	var old_panel: DeveloperPanel = before_pair[1]
	var after_pair: Array = await _make_console()
	var new_console: DeveloperTools = after_pair[0]
	var new_panel: DeveloperPanel = after_pair[1]
	check(old_console.configure(noop_set, one, old_panel, services) == OK, "Console before the scene change binds services")
	log.clear()
	check(director.request_event("test.repeat") == OK, "Story runs before the scene change")
	await process_frame
	await process_frame
	await process_frame
	var traveled := old_console.get_log().size()
	check(traveled == 4, "Console before the scene change records the whole short event")
	# 过门 / reload 之后新宿主重建 Console：缓冲由单例持有，不再从零开始。
	check(new_console.configure(noop_set, one, new_panel, services) == OK, "Console after the scene change binds services")
	check(new_console.get_log().size() == traveled, "New console sees entries written before it existed")
	new_console.clear_log()
	check(old_console.get_log().is_empty(), "Clearing from one console clears the shared buffer")
	old_console.queue_free()
	old_panel.queue_free()
	await process_frame
	check(director.request_event("test.wait") == OK, "Story starts after the old host exited")
	await process_frame
	check("\n".join(new_console.get_log()).contains("事件开始 test.wait"), "Entries keep accumulating after the old host is gone")
	director.cancel_event("shared log probe")
	await _until_idle(director)

	# 来源与级别：每条都带真实来源标签，失败保留原文原因。
	var last: Dictionary = log.get_entries().back()
	check(last.source == DebugLog.SOURCE_STORY and last.level == DebugLog.LEVEL_ERROR
		and String(last.text).contains("事件失败 test.wait") and String(last.text).contains("shared log probe"),
		"Story failure is recorded as 剧情/错误 with the real reason")
	log.clear()
	manager.dialogue_ended.emit("log.probe", true)
	last = log.get_entries().back()
	check(last.source == DebugLog.SOURCE_DIALOGUE and last.level == DebugLog.LEVEL_WARNING
		and String(last.text).contains("对话取消 log.probe"), "Cancelled dialogue is recorded as 对话/警告")
	log.clear()
	state.get_transactions().spend_money(99999, "console.log_declined")
	last = log.get_entries().back()
	check(last.source == DebugLog.SOURCE_BUSINESS and last.level == DebugLog.LEVEL_WARNING
		and String(last.text).contains("insufficient_funds") and String(last.text).contains("余额不足。"),
		"Rejected transaction keeps its code and message as 业务/警告")
	log.clear()
	var refused: Dictionary = delivery.try_submit("missing_order", "npc_probe")
	last = log.get_entries().back()
	check(not refused.ok and last.source == DebugLog.SOURCE_TASK and last.level == DebugLog.LEVEL_WARNING
		and String(last.text).contains("订单不存在。"), "Task delivery failure is recorded as 任务/警告")
	log.clear()
	bridge.continuation_failed.emit("log.event", ERR_BUSY)
	last = log.get_entries().back()
	check(last.source == DebugLog.SOURCE_BRIDGE and last.level == DebugLog.LEVEL_ERROR
		and String(last.text).contains("log.event"), "Bridge continuation failure is recorded as Bridge/错误")
	log.clear()
	push_error("devlog engine probe")
	last = log.get_entries().back()
	check(last.source == DebugLog.SOURCE_ENGINE and last.level == DebugLog.LEVEL_ERROR
		and String(last.text).contains("devlog engine probe"), "Engine push_error is captured as 引擎/错误")
	log.clear()
	push_warning("devlog warning probe")
	last = log.get_entries().back()
	check(last.source == DebugLog.SOURCE_ENGINE and last.level == DebugLog.LEVEL_WARNING
		and String(last.text).contains("devlog warning probe"), "Engine push_warning is captured as 引擎/警告")
	log.clear()
	check(new_console.write_flag("console.log_flag", true), "Debug write reaches GameState through the console")
	last = log.get_entries().back()
	check(last.source == DebugLog.SOURCE_DEBUG and last.level == DebugLog.LEVEL_INFO
		and String(last.text).contains("flag console.log_flag = true"), "Debug write is recorded as 调试写入/信息")

	# 来源过滤只挑视图，缓冲本身保持完整；导出落地到 user://logs。
	push_warning("devlog filter probe")
	var engine_item := _source_index(new_panel, DebugLog.SOURCE_ENGINE)
	check(engine_item >= 0, "Source filter lists every partition")
	new_panel.log_source.select(engine_item)
	new_panel.log_source.item_selected.emit(engine_item)
	check(new_panel.log_text.text.contains("引擎") and not new_panel.log_text.text.contains("调试写入"),
		"Filter shows only the chosen source")
	check(log.count() == log.get_entries().size(), "Filtering never mutates the buffer")
	new_panel.log_source.select(0)
	new_panel.log_source.item_selected.emit(0)
	check(new_panel.log_text.text.contains("调试写入"), "All-sources filter restores every partition")

	log.clear()
	director.request_event("test.wait")
	director.cancel_event("export probe")
	await _until_idle(director)
	new_console.write_flag("console.log_export", true)
	var exported: Dictionary = new_console.export_log()
	check(bool(exported.ok) and FileAccess.file_exists(String(exported.path)), "Export creates the file on disk")
	check(String(exported.path).begins_with("user://logs/devtools_") and String(exported.path).ends_with(".log"),
		"Export path follows user://logs/devtools_YYYYMMDD_HHMMSS.log")
	var exported_text := FileAccess.get_file_as_string(String(exported.path))
	check(exported_text.contains("事件失败 test.wait") and exported_text.contains("flag console.log_export = true"),
		"Exported file keeps the key lines")
	check(new_panel.log_message.text.contains("已导出") and new_panel.log_message.text.contains("devtools_"),
		"Export result shows the real path")
	if bool(exported.ok):
		DirAccess.remove_absolute(String(exported.path))

	# 禁用与 Release 走同一条 is_enabled 判定：不订阅、不记录、不写文件。
	var log_dir := DirAccess.open(DebugLog.EXPORT_DIR)
	var files_before := log_dir.get_files().size() if log_dir != null else 0
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	check(new_console.configure(noop_set, one, new_panel, services) == ERR_UNCONFIGURED,
		"Disabled console refuses configuration")
	check(director.event_started.get_connections().is_empty(), "Disabled state holds no story subscription")
	log.clear()
	director.request_event("test.repeat")
	await process_frame
	check(log.count() == 0, "Disabled state records nothing")
	var blocked: Dictionary = new_console.export_log()
	check(not bool(blocked.ok) and new_panel.log_message.text.contains("导出失败"),
		"Disabled export reports the failure instead of staying silent")
	log_dir = DirAccess.open(DebugLog.EXPORT_DIR)
	check((log_dir.get_files().size() if log_dir != null else 0) == files_before,
		"Disabled export creates no file")
	ProjectSettings.set_setting("debug/developer_tools/enabled", null)

	new_console.queue_free()
	new_panel.queue_free()
	state.restore_state(original)
	bridge.queue_free()
	screens.queue_free()
	delivery.queue_free()
	journal.queue_free()
	director.queue_free()
	manager.queue_free()
	await process_frame

func _make_console() -> Array:
	var tools: DeveloperTools = load("res://src/debug/developer_tools/developer_tools.tscn").instantiate()
	var panel: DeveloperPanel = load("res://src/debug/developer_tools/developer_panel.tscn").instantiate()
	root.add_child(tools)
	root.add_child(panel)
	await process_frame
	return [tools, panel]

func _source_index(panel: DeveloperPanel, source: String) -> int:
	for index in range(panel.log_source.item_count):
		if String(panel.log_source.get_item_metadata(index)) == source:
			return index
	return -1
