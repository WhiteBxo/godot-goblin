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
	tools.queue_free()
	panel.queue_free()
	await process_frame
	print("Developer tools: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
