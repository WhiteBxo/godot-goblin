extends SceneTree
## Real Day 2 objectives resolve to authored map regions; missing or unknown
## locations never invent a target.

const DAY2_TASKS := "res://src/resources/tasks/day2_stages_01_05.json"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count: int = 3) -> void:
	for index in range(count):
		await process_frame

func _run() -> void:
	var state: Node = root.get_node("GameState")
	state.reset_state()
	var locations := RpgWorldMapData.location_ids()
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DAY2_TASKS))
	check(definitions is Dictionary and definitions.get("tasks") is Array, "Published Day 2 tasks parse")
	var unknown: Array[String] = []
	for task: Dictionary in definitions.tasks:
		for objective: Dictionary in task.get("objectives", []):
			var location: String = objective.get("location_id", "")
			if not location.is_empty() and location not in locations:
				unknown.append(location)
	check(unknown.is_empty(), "Every published objective location exists in RpgWorldMapData: " + ", ".join(unknown))
	var catalog := TaskCatalog.new()
	check(catalog.load_file(DAY2_TASKS, {"locations": locations}) == OK, "Catalog accepts the real task file with map references: " + catalog.last_error)
	var journal := TaskJournal.new()
	root.add_child(journal)
	check(journal.configure(catalog, state) == OK, "Journal binds the real Day 2 catalog")
	state.set_flag("day1.s06.completed")
	state.set_flag("day2.s02.open")
	state.set_flag("day2.s02.closed")
	await frames()
	var task := journal.get_current_main_task()
	check(task.get("id") == "day2.main.tavern", "Day 2 reaches the tavern task after closing business")
	check(task.get("current_objective", {}).get("location_id") == "settlement.tavern", "Tavern objective exposes its authored location")
	var player := Node2D.new()
	root.add_child(player)
	var panel: SettlementMapPanel = load("res://src/UI/map/map_panel.tscn").instantiate()
	root.add_child(panel)
	panel.show()
	panel.configure(RpgWorldMapData.new(), player, journal, func() -> Array[String]:
		var known: Array[String] = ["settlement.shop", "settlement.tavern"]
		return known)
	await frames()
	panel.refresh()
	await frames()
	var canvas := panel.get_map_canvas()
	check(canvas.target.get("position") == RpgWorldMapData.get_entrance_position("settlement.tavern"), "Map marks the real tavern entrance")
	check(canvas.target.get("name") == "酒馆 · 裂牙", "Map target uses the authored region name")
	var details: Label = panel.get_node("ModalShell").get_content().get_node("Details/Objective")
	check("酒馆" in details.text and "位置未标注" not in details.text and "地图上未标注" not in details.text, "Objective text names the mapped region without a missing-location warning")
	# A task without a location keeps its text but draws no target.
	var no_location := TaskCatalog.new()
	check(no_location.load_json(JSON.stringify({"version": 1, "tasks": [{
		"id": "test.no_location", "type": "main", "title": "无地点", "description": "夹具",
		"activate_when": {"type": "flag", "key": "test.no_location.active"},
		"complete_when": {"type": "flag", "key": "test.no_location.done"},
		"objectives": [{"id": "go", "text": "自由行动",
			"complete_when": {"type": "flag", "key": "test.no_location.done"}}]}]})) == OK, "Location-free fixture loads")
	journal.configure(no_location, state)
	state.set_flag("test.no_location.active")
	await frames()
	panel.refresh()
	await frames()
	check(canvas.target.is_empty(), "An objective without location_id draws no map target")
	check(not ("地图上未标注" in details.text), "A location-free objective does not claim the map lacks its position")
	# A valid reference with no map region is reported as unmapped, never guessed.
	var missing := TaskCatalog.new()
	check(missing.load_json(JSON.stringify({"version": 1, "tasks": [{
		"id": "test.missing_region", "type": "main", "title": "未知地点", "description": "夹具",
		"activate_when": {"type": "flag", "key": "test.missing_region.active"},
		"complete_when": {"type": "flag", "key": "test.missing_region.done"},
		"objectives": [{"id": "go", "text": "前往未知地点", "location_id": "settlement.missing_region",
			"complete_when": {"type": "flag", "key": "test.missing_region.done"}}]}]}), {"locations": ["settlement.missing_region"]}) == OK, "Unknown-region fixture loads through its explicit reference")
	journal.configure(missing, state)
	state.set_flag("test.missing_region.active")
	await frames()
	panel.refresh()
	await frames()
	check(canvas.target.is_empty(), "A valid reference without a map region draws no target")
	check("地图上未标注" in details.text, "The map reports an unmapped location instead of guessing")
	panel.queue_free()
	player.queue_free()
	journal.queue_free()
	state.reset_state()
	await frames()
	print("MAP_TARGETS: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
