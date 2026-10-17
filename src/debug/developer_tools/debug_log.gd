class_name DebugLog
extends Node
## 跨场景调试日志单例（autoload DevLog）。
## 职责只有环形缓冲、来源/级别分区、信号订阅与导出；不产生游戏存档数据，也不参与 GameState 快照。
## Release 不装引擎 logger、不订阅信号、不写文件；运行时关闭调试工具后记录一律丢弃。
## 按项目惯例用 /root/DevLog 节点路径取实例（--script 模式下 autoload 全局名不可用），
## 类型与常量由 class_name DebugLog 提供。

const CAPACITY := 500
const EXPORT_DIR := "user://logs"

## 来源分区：面板按这些标签过滤，导出文件头也用它。
const SOURCE_STORY := "剧情"
const SOURCE_DIALOGUE := "对话"
const SOURCE_BUSINESS := "业务"
const SOURCE_TASK := "任务"
const SOURCE_BRIDGE := "Bridge"
const SOURCE_ENGINE := "引擎"
const SOURCE_DEBUG := "调试写入"
const SOURCES: Array[String] = [SOURCE_STORY, SOURCE_DIALOGUE, SOURCE_BUSINESS, SOURCE_TASK,
	SOURCE_BRIDGE, SOURCE_ENGINE, SOURCE_DEBUG]

const LEVEL_INFO := "信息"
const LEVEL_WARNING := "警告"
const LEVEL_ERROR := "错误"

## 引擎 logger 可能从任意线程回调，缓冲的读写都走同一把锁。
var _entries: Array[Dictionary] = []
var _mutex := Mutex.new()
var _logger: Logger
var _in_logger := false

var _story: StoryDirector
var _dialogue: DialogueManager
var _transactions: WalletTransactions
var _delivery: TaskDelivery
var _bridge: GameplayBridge
## 每组订阅各自记录 [目标, 信号, Callable]，重绑时只拆自己那一组。
var _story_links: Array = []
var _dialogue_links: Array = []
var _business_links: Array = []
var _task_links: Array = []
var _bridge_links: Array = []


func _ready() -> void:
	# Release：最先返回，不建缓冲、不装 logger、不订阅任何信号。
	if not DebugRuntime.is_enabled():
		return
	_install_engine_logger()


## ---------------------------------------------------------------- 记录与读取

## 唯一的外部写入入口：来源取 SOURCE_*，级别取 LEVEL_*。
func record(source: String, level: String, text: String) -> void:
	if not DebugRuntime.is_enabled():
		return
	_append(source, level, text)

func _append(source: String, level: String, text: String) -> void:
	# 时间与格式先在锁外算好，临界区只做数组操作。
	var time := Time.get_time_string_from_system()
	_mutex.lock()
	_entries.append({"time": time, "source": source, "level": level, "text": text})
	while _entries.size() > CAPACITY:
		_entries.pop_front()
	_mutex.unlock()

## 空来源表示全部；返回值是独立副本，调用方清空或修改都不影响缓冲。
func get_entries(source: String = "") -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	_mutex.lock()
	for entry: Dictionary in _entries:
		if source.is_empty() or entry["source"] == source:
			entries.append(entry.duplicate())
	_mutex.unlock()
	return entries

func get_lines(source: String = "") -> Array[String]:
	var lines: Array[String] = []
	for entry: Dictionary in get_entries(source):
		lines.append(format_entry(entry))
	return lines

func count() -> int:
	_mutex.lock()
	var total := _entries.size()
	_mutex.unlock()
	return total

func clear() -> void:
	_mutex.lock()
	_entries.clear()
	_mutex.unlock()

func format_entry(entry: Dictionary) -> String:
	return "[%s] %s · %s · %s" % [entry.get("time", ""), entry.get("source", ""),
		entry.get("level", ""), entry.get("text", "")]

## 导出到 user://logs/devtools_YYYYMMDD_HHMMSS.log，可按来源过滤。
## 返回 {ok, path, absolute, count, error}：失败时 path 与 error 都要能显示给使用者。
func export_file(source: String = "") -> Dictionary:
	if not DebugRuntime.is_enabled():
		return {"ok": false, "path": "", "absolute": "", "count": 0,
			"error": "Release 或调试工具已关闭，不写调试日志文件。"}
	if not DirAccess.dir_exists_absolute(EXPORT_DIR):
		var directory_error := DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
		if directory_error != OK:
			return {"ok": false, "path": EXPORT_DIR, "absolute": ProjectSettings.globalize_path(EXPORT_DIR),
				"count": 0, "error": "无法创建导出目录（错误 %s）" % error_string(directory_error)}
	var now := Time.get_datetime_dict_from_system()
	var path := "%s/devtools_%04d%02d%02d_%02d%02d%02d.log" % [EXPORT_DIR,
		now.year, now.month, now.day, now.hour, now.minute, now.second]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "path": path, "absolute": ProjectSettings.globalize_path(path), "count": 0,
			"error": "无法写入文件（错误 %s）" % error_string(FileAccess.get_open_error())}
	var lines := get_lines(source)
	file.store_line("# Developer Console 调试日志")
	file.store_line("# 导出时间：%s" % Time.get_datetime_string_from_system(true))
	file.store_line("# 来源过滤：%s · 条数：%d · 容量：%d" % [
		source if not source.is_empty() else "全部", lines.size(), CAPACITY])
	for line: String in lines:
		file.store_line(line)
	file.close()
	return {"ok": true, "path": path, "absolute": ProjectSettings.globalize_path(path),
		"count": lines.size(), "error": ""}


## ---------------------------------------------------------------- 引擎日志

## 只接收 push_error / push_warning / 脚本与 shader 报错（_log_error）。
## print 走 _log_message，属于正常输出，不进缓冲，避免逐行刷屏。
class _EngineLogger extends Logger:
	var _owner: Node

	func _init(owner: Node) -> void:
		_owner = owner

	func _log_error(function_name: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		if is_instance_valid(_owner):
			_owner.call(&"_on_engine_error", function_name, file, line, code, rationale, error_type)

	## _log_message(message: String, error: bool)：print/printerr 不记录。
	func _log_message(_message: String, _error: bool) -> void:
		pass

func _install_engine_logger() -> void:
	if _logger != null:
		return
	_logger = _EngineLogger.new(self)
	OS.add_logger(_logger)

func _remove_engine_logger() -> void:
	if _logger == null:
		return
	OS.remove_logger(_logger)
	_logger = null

func _on_engine_error(function_name: String, file: String, line: int, code: String,
		rationale: String, error_type: int) -> void:
	# 记录本身出错时会再次进入这里，用标记挡住递归。
	if _in_logger or not DebugRuntime.is_enabled():
		return
	_in_logger = true
	var level := LEVEL_WARNING if error_type == Logger.ERROR_TYPE_WARNING else LEVEL_ERROR
	var detail := code if rationale.is_empty() else "%s（%s）" % [rationale, code]
	var location := "%s:%d" % [file.get_file(), line]
	var text := "%s · %s" % [location, detail] if function_name.is_empty() else "%s · %s · %s" % [
		function_name, location, detail]
	_append(SOURCE_ENGINE, level, text)
	_in_logger = false


## ---------------------------------------------------------------- 信号订阅

## 场景服务由宿主注入（DeveloperTools.configure 的 context）；换场景时整体重绑。
func bind_services(services: Dictionary) -> void:
	if not DebugRuntime.is_enabled():
		_unbind_all()
		return
	bind_story_director(services.get("story") as StoryDirector)
	_bind_dialogue(services.get("dialogue") as DialogueManager)
	_bind_transactions(services.get("transactions") as WalletTransactions)
	_bind_delivery(services.get("delivery") as TaskDelivery)
	_bind_bridge(services.get("bridge") as GameplayBridge)

func bind_story_director(story: StoryDirector) -> void:
	_unbind_group(_story_links)
	_story = story if DebugRuntime.is_enabled() and is_instance_valid(story) else null
	_bind_group(_story_links, _story, {
		&"event_started": _on_event_started, &"step_started": _on_step_started,
		&"step_skipped": _on_step_skipped, &"event_completed": _on_event_completed,
		&"event_finished": _on_event_finished,
	})

func _bind_dialogue(dialogue: DialogueManager) -> void:
	_unbind_group(_dialogue_links)
	_dialogue = dialogue if DebugRuntime.is_enabled() and is_instance_valid(dialogue) else null
	_bind_group(_dialogue_links, _dialogue, {&"dialogue_ended": _on_dialogue_ended})

func _bind_transactions(transactions: WalletTransactions) -> void:
	_unbind_group(_business_links)
	_transactions = transactions if DebugRuntime.is_enabled() and is_instance_valid(transactions) else null
	_bind_group(_business_links, _transactions, {&"transaction_finished": _on_transaction_finished})

func _bind_delivery(delivery: TaskDelivery) -> void:
	_unbind_group(_task_links)
	_delivery = delivery if DebugRuntime.is_enabled() and is_instance_valid(delivery) else null
	_bind_group(_task_links, _delivery, {
		&"delivered": _on_delivered, &"delivery_failed": _on_delivery_failed,
	})

func _bind_bridge(bridge: GameplayBridge) -> void:
	_unbind_group(_bridge_links)
	_bridge = bridge if DebugRuntime.is_enabled() and is_instance_valid(bridge) else null
	_bind_group(_bridge_links, _bridge, {
		&"phase_started": _on_phase_started, &"continuation_failed": _on_continuation_failed,
	})

func _bind_group(links: Array, target: Object, handlers: Dictionary) -> void:
	if not is_instance_valid(target):
		return
	for signal_name: StringName in handlers:
		var handler: Callable = handlers[signal_name]
		if not target.has_signal(signal_name) or target.is_connected(signal_name, handler):
			continue
		target.connect(signal_name, handler)
		links.append([target, signal_name, handler])

## 目标已释放时只丢弃记录，不碰它的信号；同一实例重复绑定不会产生重复连接。
func _unbind_group(links: Array) -> void:
	for entry: Array in links:
		# Freed targets must stay untyped: assigning one to an Object variable errors,
		# and any `is` test on it is rejected too. is_instance_valid() handles both.
		var target: Variant = entry[0]
		if is_instance_valid(target) and target.is_connected(entry[1], entry[2]):
			target.disconnect(entry[1], entry[2])
	links.clear()

func _unbind_all() -> void:
	_unbind_group(_story_links)
	_unbind_group(_dialogue_links)
	_unbind_group(_business_links)
	_unbind_group(_task_links)
	_unbind_group(_bridge_links)
	_story = null
	_dialogue = null
	_transactions = null
	_delivery = null
	_bridge = null


## ---------------------------------------------------------------- 各来源格式

func _on_event_started(id: String) -> void:
	record(SOURCE_STORY, LEVEL_INFO, "事件开始 %s" % id)

func _on_step_started(id: String, index: int, command: String) -> void:
	record(SOURCE_STORY, LEVEL_INFO, "步骤开始 %s / %d · %s" % [id, index, command])

func _on_step_skipped(id: String, index: int, reason: String) -> void:
	record(SOURCE_STORY, LEVEL_WARNING, "步骤跳过 %s / %d · %s" % [id, index, reason])

func _on_event_completed(id: String) -> void:
	record(SOURCE_STORY, LEVEL_INFO, "事件完成 %s" % id)

func _on_event_finished(id: String, succeeded: bool, reason: String) -> void:
	record(SOURCE_STORY, LEVEL_INFO if succeeded else LEVEL_ERROR,
		"事件结束 %s · 成功" % id if succeeded else "事件失败 %s · %s" % [id, reason])

func _on_dialogue_ended(id: String, cancelled: bool) -> void:
	record(SOURCE_DIALOGUE, LEVEL_WARNING if cancelled else LEVEL_INFO,
		"对话取消 %s" % id if cancelled else "对话结束 %s" % id)

## 拒绝也是真实结果：code/message 原样保留，级别降为警告。
func _on_transaction_finished(result: Dictionary) -> void:
	var code := str(result.get("code", ""))
	var detail := "%s · %s · #%s · 余额 %d" % [code if not code.is_empty() else "-",
		str(result.get("message", "")), str(result.get("request_id", "")), int(result.get("balance", 0))]
	if bool(result.get("ok", false)):
		record(SOURCE_BUSINESS, LEVEL_INFO, "交易成功 · " + detail)
	else:
		record(SOURCE_BUSINESS, LEVEL_WARNING, "交易被拒绝 · " + detail)

func _on_delivered(order_id: String) -> void:
	record(SOURCE_TASK, LEVEL_INFO, "交付完成 %s" % order_id)

func _on_delivery_failed(order_id: String, reason: String) -> void:
	record(SOURCE_TASK, LEVEL_WARNING, "交付失败 %s · %s" % [
		order_id if not order_id.is_empty() else "未知订单", reason])

func _on_phase_started(id: String) -> void:
	record(SOURCE_BRIDGE, LEVEL_INFO, "阶段开始 %s" % id)

func _on_continuation_failed(event_id: String, error: Error) -> void:
	record(SOURCE_BRIDGE, LEVEL_ERROR, "续接失败 %s · %s" % [event_id, error_string(error)])


func _exit_tree() -> void:
	_remove_engine_logger()
	_unbind_all()
