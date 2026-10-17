extends SceneTree
## 临时验收脚本：在真实 Day 1 宿主里打开 Console「事件」页，重载目录并触发一个事件，
## 打印事件列表、结果行与事件日志。默认 headless 运行；加 `-- --capture` 时保存截图。

const SHOT_PREFIX := "res://artifacts/console_events_"

var _capture := false

func _initialize() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")

func _run() -> void:
	if _capture:
		DisplayServer.window_set_size(Vector2i(1280, 800))
	var game: MainGame = load("res://src/core/main.tscn").instantiate()
	game.day1_story_enabled = true
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame
	var director := game.get_story_director()
	for index in range(600):
		if not director.get_event_ids().is_empty():
			break
		await process_frame
	print("catalogue=", director.get_event_ids().size(), " source=", director.get_event_source_path())
	if director.is_busy():
		director.cancel_event("preview reset")
	await process_frame
	await process_frame
	var tools := game.get_debug_tools()
	var panel := tools.get_panel()
	tools.toggle_panel()
	await process_frame
	var tabs: TabContainer = panel.get_node("Panel/Margin/Tools/Tabs")
	var details: TabContainer = panel.get_node("Panel/Margin/Tools/Tabs/剧情/Details")
	tabs.current_tab = 2
	details.current_tab = 2
	tools.refresh()
	await process_frame
	print("=== 事件列表 ===")
	for index in range(panel.event_list.item_count):
		print(panel.event_list.get_item_text(index))
	print("=== 结果行 ===")
	print(panel.event_message.text)
	await _shot("01_list")

	print("=== 重新加载 ===")
	panel.get_node("%ReloadEvents").pressed.emit()
	await process_frame
	print(panel.event_message.text)
	await _shot("02_reloaded")

	var target := _first_idle_event(director)
	print("=== 触发 ===", target)
	var row := _index_of(panel, target)
	panel.event_list.select(row)
	panel.event_list.item_selected.emit(row)
	panel.get_node("%TriggerEvent").pressed.emit()
	await process_frame
	print("confirm visible=", panel.get_node("%EventConfirmation").visible)
	await _shot("03_confirmation")
	panel.get_node("%ConfirmEvent").pressed.emit()
	await process_frame
	print("panel visible after confirm=", panel.visible, " busy=", director.is_busy())
	for index in range(6):
		await process_frame
	print("=== 日志尾部 ===")
	for line in tools.get_log().slice(maxi(0, tools.get_log().size() - 6)):
		print(line)
	director.cancel_event("preview done")
	game.get_dialogue_manager().end_dialogue(true)
	await process_frame
	quit(0)

## 已完成或条件不满足的事件会被拒绝，选第一个可以真正开始的。
func _first_idle_event(director: StoryDirector) -> String:
	for id: String in director.get_event_ids():
		var summary := director.get_event_summary(id)
		if summary.get("conditions_met", false) and not summary.get("completed", false):
			return id
	return ""

func _index_of(panel: DeveloperPanel, id: String) -> int:
	for index in range(panel.event_list.item_count):
		if String(panel.event_list.get_item_metadata(index)) == id:
			return index
	return 0

func _shot(id: String) -> void:
	if not _capture:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s%s.png" % [SHOT_PREFIX, id])
	print("shot: ", id)
