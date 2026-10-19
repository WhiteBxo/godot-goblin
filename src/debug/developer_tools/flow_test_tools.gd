class_name FlowTestTools
extends RefCounted
## Debug-only operations use injected public services. Fixtures are real saves.

const ROOT := "user://developer_flow"
const JOB := ROOT + "/job.json"
var context: Dictionary = {}
var message := "先生成检查点，再选择现场启动独立试玩。作弊会影响当前会话及其自动存档。"
var _job_path: String

func _init(job_path: String = JOB) -> void:
	_job_path = job_path

func configure(services: Dictionary) -> void:
	context = services.duplicate()

func block_reason() -> String:
	if not DebugRuntime.is_enabled():
		return "开发工具已关闭。"
	var story := context.get("story") as StoryDirector
	if is_instance_valid(story) and story.is_busy():
		return "剧情演出进行中：" + str(story.get_runtime_status().get("event_id", ""))
	var dialogue := context.get("dialogue") as DialogueManager
	if is_instance_valid(dialogue) and dialogue.is_active():
		return "对白进行中，请结束对白后操作。"
	var guard: Callable = context.get("can_cheat", context.get("can_control", Callable()))
	if not guard.is_valid() or not guard.call():
		return "当前正在演出、切场景、初始化或玩家不可用。"
	return ""

func _result(text: String, ok := true) -> bool:
	message = text
	var log := context.get("log") as DebugLog
	if is_instance_valid(log):
		log.record(DebugLog.SOURCE_DEBUG, DebugLog.LEVEL_INFO if ok else DebugLog.LEVEL_WARNING, text)
	return ok

func add_money(amount: int) -> bool:
	if not block_reason().is_empty():
		return _result(block_reason(), false)
	var wallet := context.get("transactions") as WalletTransactions
	if wallet == null or amount <= 0 or amount > 10000:
		return _result("钱包不可用或数量超出 1–10000。", false)
	var receipt := wallet.add_money(amount, "debug.flow.%d.%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	return _result("调试补钱 +%dG：%s" % [amount, receipt.get("message", "")], receipt.get("ok", false))

func add_item(id: String, amount: int) -> bool:
	if not block_reason().is_empty():
		return _result(block_reason(), false)
	var inventory := context.get("inventory") as WarehouseInventory
	var ok := inventory != null and amount > 0 and amount <= 100 and inventory.add_ingredient(id, amount)
	return _result("调试补物品 %s ×%d：%s" % [id, amount, "成功" if ok else "失败（目录、数量或会话锁）"], ok)

func craft(product_id: String) -> bool:
	if not block_reason().is_empty():
		return _result(block_reason(), false)
	var production := context.get("production") as TeaProduction
	if production == null:
		return _result("制作服务不可用。", false)
	var recipe := production.get_recipe_by_product(product_id)
	if recipe == null or not recipe.is_available(context.get("state")):
		return _result("配方尚未解锁或不存在。", false)
	var receipt := production.craft(recipe.materials)
	return _result("调试快速制作 %s：%s；成品仍需亲自交付。" % [product_id, receipt.get("message", "")], receipt.get("ok", false))

func locate(id: String) -> bool:
	if not block_reason().is_empty():
		return _result(block_reason(), false)
	var player_getter: Callable = context.get("get_player", Callable())
	var level_getter: Callable = context.get("get_level", Callable())
	if not player_getter.is_valid() or not level_getter.is_valid():
		return _result("定位能力不可用。", false)
	var player := player_getter.call() as PlayerController
	var level: Node = level_getter.call()
	var ok := false
	if player != null and is_instance_valid(level) and level.has_method("get_interaction_points"):
		for point: InteractionPoint in level.get_interaction_points():
			if String(point.interaction_id) != id or not point.is_visible_in_tree() or not point.interaction_enabled:
				continue
			for offset: Vector2 in [Vector2(0, 20), Vector2(20, 0), Vector2(-20, 0), Vector2(0, -20), Vector2(0, 32)]:
				var position := point.global_position + offset
				var transform := player.global_transform
				transform.origin = position
				var half_size: Vector2 = player.footprint_half_size if player is FloorAwareShopPlayer else Vector2.ZERO
				if level.has_method("can_stand_at") and not level.can_stand_at(position, half_size):
					continue
				if not player.test_move(transform, Vector2.ZERO, null, 0.08, true):
					player.teleport_to(position)
					var facing := PlayerController.Facing.UP if offset.y > 0 else PlayerController.Facing.DOWN
					if offset.x != 0:
						facing = PlayerController.Facing.LEFT if offset.x > 0 else PlayerController.Facing.RIGHT
					player.face_direction(facing)
					ok = true
					break
			break
	return _result("定位 %s：%s" % [id, "成功，请关闭面板后按 E 交互" if ok else "没有安全落点或目标已失效"], ok)

func get_items() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var inventory := context.get("inventory") as WarehouseInventory
	if inventory != null:
		for id: String in inventory.to_dict().get("ingredients", {}):
			var definition := inventory.get_definition(id)
			rows.append({"id": id, "label": "%s (%s)" % [definition.display_name if definition != null else id, id]})
	return rows

func get_recipes() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var production := context.get("production") as TeaProduction
	if production != null:
		for recipe: TeaRecipe in production.get_available_recipes():
			rows.append({"id": recipe.product_id, "label": production.get_item_name(recipe.product_id)})
	return rows

func get_targets() -> Array:
	var rows: Array = []
	var getter: Callable = context.get("get_level", Callable())
	var level: Node = getter.call() if getter.is_valid() else null
	if is_instance_valid(level) and level.has_method("get_interaction_points"):
		for point: InteractionPoint in level.get_interaction_points():
			if point.is_visible_in_tree() and point.interaction_enabled and not point.interaction_id.is_empty():
				rows.append({"id": String(point.interaction_id), "label": "%s (%s)" % [point.display_name, point.interaction_id]})
	return rows

func get_job() -> Dictionary:
	if not FileAccess.file_exists(_job_path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(_job_path))
	return value if value is Dictionary else {}

func job_running() -> bool:
	var job := get_job()
	var pid := int(job.get("pid", -1))
	return pid > 0 and OS.is_process_running(pid)

func generate() -> bool:
	if not DebugRuntime.is_enabled() or not OS.has_feature("editor") or job_running():
		return _result("仅编辑器 Debug 可生成，且不能重复启动正在生成的任务。", false)
	var directory := ProjectSettings.globalize_path(ROOT.path_join("run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]))
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return _result("无法创建检查点目录。", false)
	var log_path := directory.path_join("generation.log")
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--headless", "--quit-after", "36000", "--path", ProjectSettings.globalize_path("res://"), "--log-file", log_path,
		"--script", "res://tests/verify_two_day_flow.gd", "--", "--ordinary-order", "--save-fixtures=" + directory]))
	if pid < 0:
		return _result("无法启动检查点生成进程。", false)
	var file := FileAccess.open(_job_path, FileAccess.WRITE)
	if file == null:
		OS.kill(pid)
		return _result("无法记录生成任务。", false)
	file.store_string(JSON.stringify({"pid": pid, "directory": directory, "log": log_path}))
	return _result("已后台运行两天真实流程，结束后刷新列表；日志：" + log_path)

func get_fixtures() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var job := get_job()
	var directory := str(job.get("directory", ""))
	if directory.is_empty() or job_running() or not FileAccess.file_exists(directory.path_join("complete.json")):
		return rows
	var completion: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("complete.json")))
	if not completion is Dictionary or completion.get("failures", 1) != 0:
		return rows
	for name: String in DirAccess.get_directories_at(directory):
		var path := directory.path_join(name)
		var loaded := SaveStore.new(path).load_save()
		if loaded.error != OK or int(loaded.data.game_state.current_day) > 2:
			continue
		rows.append({"id": path, "day": loaded.data.game_state.current_day, "stage": loaded.data.game_state.story_stage,
			"label": "第%d天 · %s · %s" % [loaded.data.game_state.current_day, name, loaded.data.game_state.story_stage]})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.day < b.day if a.day != b.day else a.stage.naturalnocasecmp_to(b.stage) < 0)
	return rows

func launch(directory: String) -> bool:
	if not DebugRuntime.is_enabled() or not OS.has_feature("editor"):
		return _result("独立试玩需要编辑器 Debug。", false)
	var valid := false
	for row: Dictionary in get_fixtures():
		valid = valid or row.id == directory
	if not valid:
		return _result("请选择已验证的检查点。", false)
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--path", ProjectSettings.globalize_path("res://"), "--script",
		"res://src/debug/developer_tools/flow_test_runner.gd", "--", directory]))
	return _result("独立试玩已启动；自动保存写入独立目录。" if pid >= 0 else "启动失败。", pid >= 0)

func report() -> String:
	var state: Node = context.get("state")
	var status: Callable = context.get("status", Callable())
	var story := context.get("story") as StoryDirector
	var bridge := context.get("bridge") as GameplayBridge
	var tasks := context.get("tasks") as TaskJournal
	var log := context.get("log") as DebugLog
	return "游戏流程问题报告\n复现步骤：\n预期结果：\n实际结果：\n" + JSON.stringify({
		"engine": Engine.get_version_info(), "host": status.call() if status.is_valid() else {},
		"write_blocker": block_reason(), "save_directory": GameEntry.create_save_store().directory,
		"story": story.get_runtime_status() if story != null else {},
		"bridge": bridge.get_runtime_status() if bridge != null else {},
		"main_task": tasks.get_current_main_task() if tasks != null else {},
		"state": state.to_dict() if is_instance_valid(state) else {},
		"logs": log.get_entries() if log != null else []}, "\t")

func export_report() -> bool:
	if not DebugRuntime.is_enabled():
		return false
	if DirAccess.make_dir_recursive_absolute(ROOT) != OK:
		return _result("无法创建报告目录。", false)
	var path := ROOT.path_join("report_%d_%d.txt" % [OS.get_process_id(), Time.get_ticks_usec()])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _result("报告写入失败。", false)
	var text := report()
	file.store_string(text)
	file.close()
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(text)
	return _result("报告已导出并在支持时复制到剪贴板：" + ProjectSettings.globalize_path(path))
