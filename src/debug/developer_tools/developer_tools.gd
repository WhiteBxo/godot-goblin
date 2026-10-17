class_name DeveloperTools
extends Node

const SPEED_MULTIPLIERS := [1, 2, 4, 8]
const RECENT_TRANSACTION_LIMIT := 5
const TOGGLE_ACTION := &"debug_toggle_console"
const SCREEN_ID := &"developer_console"
## Phase rows come from data; only the file the host already loads is read.
const PHASES_PATH := "res://src/resources/story/day1_stages_01_02_phases.json"

var _set_multiplier: Callable
var _get_multiplier: Callable
var _panel: DeveloperPanel
var _context: Dictionary = {}
var _story: StoryDirector
var _dialogue: DialogueManager
var _ui: UIManager
var _configured := false
var _refresh_elapsed := 0.0
var _transactions: WalletTransactions
var _inventory: WarehouseInventory
var _production: TeaProduction
var _tasks: TaskJournal
var _delivery: TaskDelivery
var _bridge: GameplayBridge
var _recent_transactions: Array[Dictionary] = []
var _event_rows: Array = []
var _event_message := ""
var _phases: Array[Dictionary] = []
var _phases_error := ""

func _ready() -> void:
	if DebugRuntime.is_enabled() and not InputMap.has_action(TOGGLE_ACTION):
		InputMap.add_action(TOGGLE_ACTION)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_F3
		InputMap.action_add_event(TOGGLE_ACTION, key)

## Optional context: public status/respawn/restart/guard Callables and scene services.
## Missing capabilities disable only their own controls; observation remains available.
func configure(set_multiplier: Callable, get_multiplier: Callable, panel: DeveloperPanel, context: Dictionary = {}) -> Error:
	close_panel()
	if is_instance_valid(_ui):
		_ui.unregister_screen(SCREEN_ID)
	if is_instance_valid(_panel):
		_disconnect_panel()
	_set_multiplier = set_multiplier
	_get_multiplier = get_multiplier
	_panel = panel
	_context = context.duplicate()
	_ui = context.get("ui_manager") as UIManager
	_story = context.get("story") as StoryDirector
	_dialogue = context.get("dialogue") as DialogueManager
	# 日志订阅归单例：换场景、重载或换宿主都只是重绑，缓冲不清空。
	var log := dev_log()
	if log != null:
		log.bind_services(context)
	bind_business_services(context)
	_load_phases()
	_configured = DebugRuntime.is_enabled() and is_instance_valid(_panel)
	if not _configured:
		if is_instance_valid(_panel):
			_panel.hide()
		return ERR_UNCONFIGURED
	_panel.configure_choices(PackedInt32Array(SPEED_MULTIPLIERS))
	_panel.speed_multiplier_selected.connect(set_player_speed_multiplier)
	_panel.close_requested.connect(close_panel)
	_panel.respawn_requested.connect(return_to_spawn)
	_panel.restart_requested.connect(restart_scene)
	_panel.clear_log_requested.connect(clear_log)
	_panel.events_reload_requested.connect(reload_story_events)
	_panel.event_trigger_requested.connect(trigger_story_event)
	_panel.flag_write_requested.connect(write_flag)
	_panel.variable_write_requested.connect(write_variable)
	_panel.event_complete_requested.connect(complete_event)
	_panel.phase_enter_requested.connect(enter_phase)
	_panel.session_reset_requested.connect(reset_session)
	_panel.log_source_changed.connect(_on_log_source_changed)
	_panel.log_export_requested.connect(export_log)
	_panel.hide()
	if is_instance_valid(_ui):
		_ui.register_screen(SCREEN_ID, _panel, &"debug", true)
	refresh()
	return OK if _set_multiplier.is_valid() and _get_multiplier.is_valid() else ERR_UNCONFIGURED

func _disconnect_panel() -> void:
	for pair: Array in [[_panel.speed_multiplier_selected, set_player_speed_multiplier],
		[_panel.close_requested, close_panel], [_panel.respawn_requested, return_to_spawn],
		[_panel.restart_requested, restart_scene], [_panel.clear_log_requested, clear_log],
		[_panel.events_reload_requested, reload_story_events],
		[_panel.event_trigger_requested, trigger_story_event],
		[_panel.flag_write_requested, write_flag], [_panel.variable_write_requested, write_variable],
		[_panel.event_complete_requested, complete_event], [_panel.phase_enter_requested, enter_phase],
		[_panel.session_reset_requested, reset_session],
		[_panel.log_source_changed, _on_log_source_changed], [_panel.log_export_requested, export_log]]:
		var source: Signal = pair[0]
		if source.is_connected(pair[1]):
			source.disconnect(pair[1])

func get_panel() -> DeveloperPanel:
	return _panel

func is_open() -> bool:
	return is_instance_valid(_panel) and _panel.visible

func toggle_panel() -> void:
	if is_open():
		close_panel()
	elif _configured and DebugRuntime.is_enabled():
		_open_panel()

func _open_panel() -> void:
	if not _configured or not DebugRuntime.is_enabled() or not is_instance_valid(_panel):
		return
	refresh()
	if is_instance_valid(_ui):
		_ui.open_screen(SCREEN_ID)
	else:
		_panel.show()
	_panel.get_default_focus().grab_focus()

func close_panel() -> void:
	if is_instance_valid(_ui):
		_ui.close_screen(SCREEN_ID)
	if is_instance_valid(_panel):
		_panel.cancel_restart()
		_panel.hide()

func _input(event: InputEvent) -> void:
	if not _configured or not DebugRuntime.is_enabled():
		return
	if event.is_action(TOGGLE_ACTION):
		get_viewport().set_input_as_handled()
		if event.is_pressed() and not event.is_echo():
			toggle_panel()
		return
	if not is_open():
		return
	# Keep pause ownership unchanged, including when inspecting an already paused game.
	if event.is_action("pause_game") or event.is_action("ui_cancel"):
		get_viewport().set_input_as_handled()
		if event.is_action_pressed("ui_cancel") and not event.is_echo():
			close_panel()
		return
	# GUI navigation/text selection stays native; gameplay input cannot reach scene tools.
	for action: StringName in [&"interact", &"debug_cycle_walls", &"debug_toggle_overview", &"debug_settlement_routes"]:
		if event.is_action(action):
			get_viewport().set_input_as_handled()
			return

func _allowed(key: String) -> bool:
	var guard: Callable = _context.get(key, Callable())
	return not guard.is_valid() or bool(guard.call())

func _has_action(key: String) -> bool:
	var action: Callable = _context.get(key, Callable())
	return action.is_valid()

func set_player_speed_multiplier(multiplier: float) -> void:
	if not _configured or not DebugRuntime.is_enabled() or not _allowed("can_control") or not _set_multiplier.is_valid() or not _get_multiplier.is_valid():
		return
	if multiplier != int(multiplier) or int(multiplier) not in SPEED_MULTIPLIERS:
		return
	_set_multiplier.call(multiplier)
	refresh()

func return_to_spawn() -> void:
	if _configured and DebugRuntime.is_enabled() and _allowed("can_control") and _has_action("respawn"):
		_context.respawn.call()
		refresh()

## Called only after the panel's inline confirmation; never clears GameState.
func restart_scene() -> void:
	if _configured and DebugRuntime.is_enabled() and _allowed("can_restart") and _has_action("restart"):
		close_panel()
		_context.restart.call()

func _process(delta: float) -> void:
	if not DebugRuntime.is_enabled():
		close_panel()
		return
	if not is_open():
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.2:
		_refresh_elapsed = 0.0
		refresh()

func refresh() -> void:
	if not _configured or not DebugRuntime.is_enabled():
		return
	var status: Callable = _context.get("status", Callable())
	var data: Dictionary = status.call() if status.is_valid() else {}
	var state: Node = _context.get("state")
	var snapshot: Dictionary = state.to_dict() if is_instance_valid(state) else {}
	data["fps"] = Engine.get_frames_per_second()
	_panel.set_status(data, snapshot)
	_panel.set_story(snapshot, _story.get_runtime_status() if is_instance_valid(_story) else {})
	_panel.set_capabilities(_set_multiplier.is_valid() and _get_multiplier.is_valid() and _allowed("can_control"),
		_has_action("respawn") and _allowed("can_control"), _has_action("restart") and _allowed("can_restart"))
	if _get_multiplier.is_valid():
		_panel.set_speed_multiplier(float(_get_multiplier.call()))
	# 只读单例的副本；来源过滤在读取时生效，缓冲本身始终完整。
	_panel.set_log(_log_lines())
	refresh_event_rows()
	_panel.set_business(_business_snapshot())
	_update_write_controls()

func _on_log_source_changed(_source: String) -> void:
	refresh()

## StoryDirector 的五个信号由 DevLog 统一订阅；Console 只保留引用用于页面观察。
## 这样过门或重载后缓冲区仍由单例持有，不会随场景一起清零。
func bind_story_director(story: StoryDirector) -> void:
	_story = story
	var log := dev_log()
	if log != null:
		log.bind_story_director(story)

## Read-only catalogue join for the event page. Parsing runs at the console's
## 0.2 s refresh rate and only changed rows reach the view.
func refresh_event_rows() -> void:
	_panel.set_event_available(is_instance_valid(_story))
	if not is_instance_valid(_story):
		_event_rows = []
		_panel.set_events(_event_rows)
		_panel.set_event_message(_event_message if not _event_message.is_empty() else "StoryDirector 不可用，无法读取事件列表。")
		return
	var rows: Array = []
	for id: String in _story.get_event_ids():
		var summary := _story.get_event_summary(id)
		if summary.is_empty():
			continue
		summary["id"] = id
		rows.append(summary)
	if rows != _event_rows:
		_event_rows = rows
		_panel.set_events(rows)
	# Reload/trigger results stay visible until the next one; otherwise show the state.
	var note := _event_message
	if note.is_empty():
		note = "已加载 %d 个事件：选中后可重新加载或确认触发。" % rows.size() if not rows.is_empty() else "未加载剧情事件：宿主尚未加载事件文件。"
	_panel.set_event_message(note)

func get_event_message() -> String:
	return _event_message

## Reloads the file the host actually loaded; the console never picks another path.
## The director owns refusal reasons, so ERR_BUSY and validation errors stay verbatim.
func reload_story_events() -> Error:
	if not _configured or not DebugRuntime.is_enabled():
		return ERR_UNCONFIGURED
	if not is_instance_valid(_story):
		_set_event_message("StoryDirector 不可用，无法重新加载。")
		return ERR_UNCONFIGURED
	var path := _story.get_event_source_path()
	if path.is_empty():
		_set_event_message("未加载事件文件：宿主没有提供事件路径。")
		_append_log("调试重载跳过 · 宿主未加载事件文件")
		refresh()
		return ERR_UNCONFIGURED
	var error := _story.load_events(path)
	if error != OK:
		_set_event_message("重新加载被拒绝（%s）：%s" % [error_string(error), _story.last_error])
		_append_log("调试重载失败 %s · %s" % [path, _story.last_error])
		refresh()
		return error
	var parts := PackedStringArray(["已重新加载 %s · %d 个事件" % [path, _story.get_event_ids().size()]])
	_append_log("调试重载事件 %s · %d 个" % [path, _story.get_event_ids().size()])
	var dialogue_result := _reload_dialogue()
	if not String(dialogue_result[1]).is_empty():
		parts.append(String(dialogue_result[1]))
	_set_event_message("；".join(parts) + "。")
	refresh()
	return dialogue_result[0]

## Story text lives in the dialogue catalogue, so a reload refreshes it too, again
## from the host's own path. An active dialogue is left alone and reported instead.
func _reload_dialogue() -> Array:
	if not is_instance_valid(_dialogue):
		return [OK, ""]
	if _dialogue.is_active():
		return [ERR_BUSY, "对白进行中，已跳过对白目录刷新"]
	var path := _dialogue.get_dialogue_source_path()
	if path.is_empty():
		return [OK, ""]
	var error := _dialogue.load_dialogues(path)
	if error != OK:
		_append_log("调试重载对白失败 %s · %s" % [path, _dialogue.last_error])
		return [error, "对白重载被拒绝（%s）：%s" % [error_string(error), _dialogue.last_error]]
	_append_log("调试重载对白 %s" % path)
	return [OK, "对白 %s" % path]

## Runs only after the panel's inline confirmation. The console closes itself first,
## so its modal never competes with the sequence it starts; a refusal reopens the
## panel so the director's own reason stays visible.
func trigger_story_event(event_id: String) -> Error:
	if not _configured or not DebugRuntime.is_enabled():
		return ERR_UNCONFIGURED
	if not is_instance_valid(_story):
		_set_event_message("StoryDirector 不可用，无法触发事件。")
		return ERR_UNCONFIGURED
	close_panel()
	var error := _story.request_event(event_id)
	if error == OK:
		_set_event_message("已请求触发 %s。" % event_id)
		_append_log("调试触发事件 %s" % event_id)
		return OK
	_set_event_message("触发 %s 被拒绝（%s）：%s" % [event_id, error_string(error), _story.last_error])
	_append_log("调试触发失败 %s · %s" % [event_id, _story.last_error])
	_open_panel()
	return error

func _set_event_message(message: String) -> void:
	_event_message = message
	if is_instance_valid(_panel):
		_panel.set_event_message(message)

## Optional read-only business services. A missing entry only blanks its own
## section; the tool never creates, resets or repairs a business service.
func bind_business_services(context: Dictionary) -> void:
	_bind_transactions(context.get("transactions") as WalletTransactions)
	_inventory = context.get("inventory") as WarehouseInventory
	_production = context.get("production") as TeaProduction
	_tasks = context.get("tasks") as TaskJournal
	_delivery = context.get("delivery") as TaskDelivery
	_bridge = context.get("bridge") as GameplayBridge

func _bind_transactions(transactions: WalletTransactions) -> void:
	if is_instance_valid(_transactions) and _transactions.transaction_finished.is_connected(_on_transaction_finished):
		_transactions.transaction_finished.disconnect(_on_transaction_finished)
	if transactions != _transactions:
		_recent_transactions.clear()
	_transactions = transactions
	if is_instance_valid(_transactions) and DebugRuntime.is_enabled():
		_transactions.transaction_finished.connect(_on_transaction_finished)

## Results arrive by signal only; the console never replays or polls past transactions.
func _on_transaction_finished(result: Dictionary) -> void:
	if not DebugRuntime.is_enabled():
		return
	_recent_transactions.append({"time": Time.get_time_string_from_system(),
		"code": str(result.get("code", "")), "message": str(result.get("message", "")),
		"balance": int(result.get("balance", 0)), "request_id": str(result.get("request_id", ""))})
	if _recent_transactions.size() > RECENT_TRANSACTION_LIMIT:
		_recent_transactions.pop_front()

## Pure reads: every getter below is a snapshot or a derived check.
func _business_snapshot() -> Dictionary:
	var snapshot := {}
	if is_instance_valid(_transactions):
		var recent: Array[Dictionary] = []
		for index in range(_recent_transactions.size() - 1, -1, -1):
			recent.append(_recent_transactions[index])
		snapshot["wallet"] = {"balance": _transactions.get_balance(),
			"busy": _transactions.is_busy(), "recent": recent}
	snapshot["inventory"] = _inventory_snapshot()
	snapshot["production"] = _production_snapshot()
	snapshot["tasks"] = _tasks_snapshot()
	snapshot["bridge"] = _bridge.get_runtime_status() if is_instance_valid(_bridge) else {}
	return snapshot

## The id order comes from the inventory snapshot so undiscovered and empty
## items stay listed; per-item values still come from the public getters.
func _inventory_snapshot() -> Dictionary:
	if not is_instance_valid(_inventory):
		return {}
	var ingredients: Dictionary = _inventory.to_dict().get("ingredients", {})
	var items: Array[Dictionary] = []
	for id: String in ingredients:
		var definition: IngredientDefinition = _inventory.get_definition(id)
		items.append({"id": id, "name": definition.display_name if definition != null else id,
			"quantity": _inventory.get_stock(id), "discovered": _inventory.is_discovered(id)})
	return {"items": items}

func _production_snapshot() -> Dictionary:
	if not is_instance_valid(_production):
		return {}
	return {"order_text": _production.get_order_text(), "completed": _production.get_completed_count(),
		"submitting": _production.is_submitting()}

func _tasks_snapshot() -> Dictionary:
	if not is_instance_valid(_tasks):
		return {}
	var requirements := _delivery_requirements()
	var rows: Array[Dictionary] = []
	for task: Dictionary in _tasks.get_active_tasks():
		var delivery: Dictionary = task.get("delivery", {})
		var target := str(delivery.get("target_object_id", ""))
		rows.append({"id": task.get("id", ""), "type": task.get("type", ""), "title": task.get("title", ""),
			"requirements": requirements.get(target, PackedStringArray())})
	return {"main": _tasks.get_current_main_task(), "active": rows}

## Requirements are keyed by delivery order id, while the journal only exposes
## the target id: orders are grouped by target instead of inventing a task link.
func _delivery_requirements() -> Dictionary:
	var grouped := {}
	if not is_instance_valid(_delivery):
		return grouped
	for order: Dictionary in _delivery.get_orders():
		var order_id := str(order.get("order_id", ""))
		var target := str(order.get("target_object_id", ""))
		if order_id.is_empty() or target.is_empty():
			continue
		var requirement: Dictionary = _delivery.get_requirement(order_id)
		var parts := PackedStringArray()
		for id: String in requirement:
			parts.append("%s ×%d" % [_item_name(id), int(requirement[id])])
		if not grouped.has(target):
			grouped[target] = PackedStringArray()
		var lines: PackedStringArray = grouped[target]
		lines.append("%s：%s" % [order_id, "、".join(parts)])
		grouped[target] = lines
	return grouped

func _item_name(id: String) -> String:
	if is_instance_valid(_inventory):
		var definition: IngredientDefinition = _inventory.get_definition(id)
		if definition != null:
			return definition.display_name
	return id

## ---------------------------------------------------------------- 状态写入
## Every write goes through the same can_control guard as the character page,
## calls only public GameState methods, and appends one "调试写入" log entry.

func _load_phases() -> void:
	_phases.clear()
	_phases_error = ""
	if not FileAccess.file_exists(PHASES_PATH):
		_phases_error = "阶段数据不存在：%s" % PHASES_PATH
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PHASES_PATH))
	if not data is Dictionary or not data.get("phases") is Array:
		_phases_error = "阶段数据格式无效：%s" % PHASES_PATH
		return
	for entry: Variant in data["phases"]:
		if not _is_valid_phase(entry):
			continue
		var phase: Dictionary = entry
		var condition: Dictionary = phase["completion"]
		_phases.append({
			"id": str(phase["id"]), "stage": str(phase["stage"]), "after_event": str(phase["after_event"]),
			"completion_flag": str(phase["completion_flag"]), "next_event": str(phase["next_event"]),
			"flag": str(condition["flag"]),
		})
	if _phases.is_empty():
		_phases_error = "阶段数据没有可用条目：%s" % PHASES_PATH

func _is_valid_phase(entry: Variant) -> bool:
	if not entry is Dictionary:
		return false
	var phase: Dictionary = entry
	if not phase.get("completion") is Dictionary:
		return false
	for key: String in ["id", "stage", "after_event", "completion_flag", "next_event"]:
		var value: Variant = phase.get(key)
		if not value is String or str(value).is_empty():
			return false
	var condition: Dictionary = phase["completion"]
	var flag: Variant = condition.get("flag")
	return flag is String and not str(flag).is_empty()

func get_phases() -> Array[Dictionary]:
	return _phases.duplicate(true)

## Empty means writes are allowed. The reason names the real blocker, so the
## panel never shows a static warning while the host guard says otherwise.
func _write_block_reason() -> String:
	if not _configured:
		return "调试工具未配置。"
	if not DebugRuntime.is_enabled():
		return "调试工具已关闭。"
	if not _has_action("can_control") or _allowed("can_control"):
		return ""
	if is_instance_valid(_story) and _story.is_busy():
		return "剧情演出进行中，写入会打断当前演出。"
	if is_instance_valid(_ui) and _ui.is_open(&"dialogue"):
		return "对话进行中，写入会打断当前对话。"
	return "角色正由演出控制或当前不可用。"

func _state_node() -> Node:
	var state: Node = _context.get("state") as Node
	return state if is_instance_valid(state) and state.has_method("set_flag") else null

func _update_write_controls() -> void:
	if not is_instance_valid(_panel):
		return
	var blocked := _write_block_reason()
	_panel.set_write_state(_configured and DebugRuntime.is_enabled() and blocked.is_empty(), blocked)
	_panel.set_phases(_phases, _phases_error)

func write_flag(key: String, value: bool) -> bool:
	var target := key.strip_edges()
	var blocked := _write_block_reason()
	if not blocked.is_empty():
		_reject_write("flag %s：%s" % [target, blocked])
		return false
	var state := _state_node()
	if state == null:
		_reject_write("flag %s：GameState 不可用。" % target)
		return false
	if target.is_empty():
		_reject_write("flag：Key 不能为空。")
		return false
	if state.set_flag(target, value):
		_report_write("flag %s = %s" % [target, str(value)])
		refresh()
		return true
	if state.has_flag(target) and state.get_flag(target) == value:
		_report_write("flag %s 已经是 %s，没有产生写入。" % [target, str(value)])
	else:
		_reject_write("flag %s：GameState.set_flag 返回 false（Key 需 a.b 命名空间，或会话正在替换数据）。" % target)
	refresh()
	return false

func write_variable(key: String, value_text: String) -> bool:
	var target := key.strip_edges()
	var blocked := _write_block_reason()
	if not blocked.is_empty():
		_reject_write("variable %s：%s" % [target, blocked])
		return false
	var state := _state_node()
	if state == null:
		_reject_write("variable %s：GameState 不可用。" % target)
		return false
	if target.is_empty():
		_reject_write("variable：Key 不能为空。")
		return false
	var parsed := _parse_value(value_text)
	if state.set_variable(target, parsed.value):
		_report_write("variable %s（%s）= %s" % [target, parsed.type, _value_text(parsed.value)])
		refresh()
		return true
	if state.has_variable(target) and _same_value(state.get_variable(target), parsed.value):
		_report_write("variable %s 已等于该值，没有产生写入。" % target)
	else:
		_reject_write("variable %s：GameState.set_variable 返回 false（Key 需 a.b 命名空间，或值类型不被接受）。" % target)
	refresh()
	return false

func complete_event(event_id: String) -> bool:
	var target := event_id.strip_edges()
	var blocked := _write_block_reason()
	if not blocked.is_empty():
		_reject_write("事件 %s：%s" % [target, blocked])
		return false
	var state := _state_node()
	if state == null:
		_reject_write("事件 %s：GameState 不可用。" % target)
		return false
	if target.is_empty():
		_reject_write("事件：event_id 不能为空。")
		return false
	if state.complete_event(target):
		_report_write("事件完成 %s" % target)
		refresh()
		return true
	if state.is_event_completed(target):
		_report_write("事件 %s 已标记完成，没有产生写入。" % target)
	else:
		_reject_write("事件 %s：GameState.complete_event 返回 false（id 需 a.b 命名空间，或会话正在替换数据）。" % target)
	refresh()
	return false

## Writes only the phase's completion condition flag. GameplayBridge observes it,
## writes completion_flag itself and requests next_event, so the console never
## duplicates bridge logic or calls StoryDirector/Day1ShopController internals.
func enter_phase(index: int) -> bool:
	var blocked := _write_block_reason()
	if not blocked.is_empty():
		_reject_write("阶段 %d：%s" % [index, blocked])
		return false
	if index < 0 or index >= _phases.size():
		_reject_write("阶段：索引 %d 不在阶段列表内（共 %d 项）。" % [index, _phases.size()])
		return false
	var phase: Dictionary = _phases[index]
	var state := _state_node()
	if state == null:
		_reject_write("阶段 %s：GameState 不可用。" % phase.id)
		return false
	var flag: String = phase.flag
	var changed: bool = state.set_flag(flag, true)
	var detail := _phase_progress(state, phase)
	if changed:
		_report_write("阶段 %s：已写入完成条件 flag %s。%s" % [phase.id, flag, detail])
	elif state.get_flag(flag):
		_report_write("阶段 %s：%s 已存在，未重复写入。%s" % [phase.id, flag, detail])
	else:
		_reject_write("阶段 %s：GameState.set_flag(%s) 返回 false，请检查 Key 命名空间。" % [phase.id, flag])
	refresh()
	return changed or state.get_flag(flag)

## Pure read of public facts: which prerequisite is still missing, and that the
## follow-up completion_flag is produced by the bridge rather than here.
func _phase_progress(state: Node, phase: Dictionary) -> String:
	var stage := str(state.get("story_stage"))
	var after_done: bool = state.is_event_completed(phase.after_event)
	var next_done: bool = state.is_event_completed(phase.next_event)
	if next_done:
		return "后续事件 %s 已完成，该阶段不会再推进。" % phase.next_event
	if stage == phase.stage and after_done:
		return "已满足激活条件：GameplayBridge 会写入 %s 并请求 %s，关闭面板后按既有流程播放。" % [
			phase.completion_flag, phase.next_event]
	if stage == phase.stage:
		return "剧情阶段已匹配，但前序事件 %s 尚未完成；flag 会在该阶段激活后生效。" % phase.after_event
	return "当前剧情阶段为 %s，需要 %s；flag 会在流程到达该阶段时生效。" % [
		stage if not stage.is_empty() else "未设置", phase.stage]

func reset_session() -> bool:
	var blocked := _write_block_reason()
	if not blocked.is_empty():
		_reject_write("会话重置：%s" % blocked)
		return false
	var state := _state_node()
	if state == null or not state.has_method("start_new_game"):
		_reject_write("会话重置：GameState 不可用。")
		return false
	var error: Error = state.start_new_game()
	if error == OK:
		_report_write("会话重置：钱包、库存、任务与剧情进度已回到新游戏状态。")
		refresh()
		return true
	_reject_write("会话重置失败：%s（%d）" % [error_string(error), error])
	refresh()
	return false

## bool → int → float → String; nothing else is inferred from the text field.
func _parse_value(text: String) -> Dictionary:
	var trimmed := text.strip_edges()
	match trimmed.to_lower():
		"true":
			return {"value": true, "type": "bool"}
		"false":
			return {"value": false, "type": "bool"}
	if trimmed.is_valid_int():
		return {"value": trimmed.to_int(), "type": "int"}
	if trimmed.is_valid_float() and is_finite(trimmed.to_float()):
		return {"value": trimmed.to_float(), "type": "float"}
	return {"value": trimmed, "type": "String"}

func _value_text(value: Variant) -> String:
	return "\"%s\"" % value if value is String else str(value)

func _same_value(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	return left == right

## 日志统一来自跨场景单例 DevLog：Console 只挑过滤条件，不再自己持有缓冲。
func get_log() -> Array[String]:
	var log := dev_log()
	var empty: Array[String] = []
	return log.get_lines() if log != null else empty

func _log_lines() -> Array[String]:
	var log := dev_log()
	var empty: Array[String] = []
	if log == null:
		return empty
	return log.get_lines(_panel.get_log_source() if is_instance_valid(_panel) else "")

## 跨场景单例按项目惯例取节点路径：Release 或宿主缺少 DevLog 时返回 null，调用方自行跳过。
func dev_log() -> DebugLog:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/DevLog") as DebugLog

## One entry per accepted write and per refusal. Both carry the debug-write source,
## so injected facts stay distinguishable from normal story flow.
func _report_write(message: String) -> void:
	if is_instance_valid(_panel):
		_panel.set_write_result(message)
	_append_log(message)

func _reject_write(message: String) -> void:
	if is_instance_valid(_panel):
		_panel.set_write_result(message)
	_append_log("被拒绝 · %s" % message, DebugLog.LEVEL_WARNING)

func clear_log() -> void:
	var log := dev_log()
	if log != null:
		log.clear()
	if is_instance_valid(_panel):
		_panel.set_log(_log_lines())

## 导出当前过滤视图；成功与失败都回显路径，失败时连同错误原因一起显示。
func export_log() -> Dictionary:
	if not _configured or not DebugRuntime.is_enabled():
		var blocked := {"ok": false, "path": "", "absolute": "", "count": 0,
			"error": "调试工具已关闭，不写日志文件。"}
		if is_instance_valid(_panel):
			_panel.set_log_message("导出失败：%s" % blocked.error)
		return blocked
	var log := dev_log()
	if log == null:
		var missing := {"ok": false, "path": "", "absolute": "", "count": 0, "error": "DevLog 单例不可用。"}
		if is_instance_valid(_panel):
			_panel.set_log_message("导出失败：%s" % missing.error)
		return missing
	var result: Dictionary = log.export_file(_panel.get_log_source() if is_instance_valid(_panel) else "")
	if is_instance_valid(_panel):
		var message := "导出失败：%s · %s" % [result.get("path", ""), result.get("error", "未知错误")]
		if bool(result.get("ok", false)):
			message = "已导出 %d 条到 %s" % [int(result.get("count", 0)), result.get("path", "")]
			if not str(result.get("absolute", "")).is_empty():
				message += "（%s）" % result.get("absolute", "")
		_panel.set_log_message(message)
	return result

## 调试动作自身产生的记录，来源固定为“调试写入”。
func _append_log(message: String, level: String = DebugLog.LEVEL_INFO) -> void:
	var log := dev_log()
	if log != null:
		log.record(DebugLog.SOURCE_DEBUG, level, message)

## 离树只释放自己的面板与引用：DevLog 的缓冲和订阅属于单例，
## 旧场景晚于新场景离树时不能把新场景刚绑好的订阅拆掉。
func _exit_tree() -> void:
	close_panel()
	if is_instance_valid(_ui):
		_ui.unregister_screen(SCREEN_ID)
	_story = null
	_dialogue = null
	bind_business_services({})
