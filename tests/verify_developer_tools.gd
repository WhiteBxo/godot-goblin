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
	for index in range(60):
		director.request_event("test.repeat")
		await process_frame
		await process_frame
		await process_frame
	check(tools.get_log().size() == DeveloperTools.LOG_CAPACITY, "Log ring retains at most 200 real signal entries")
	var copy := tools.get_log()
	copy.clear()
	check(tools.get_log().size() == DeveloperTools.LOG_CAPACITY, "Log snapshot cannot mutate buffer")
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
