extends SceneTree

const StateData = preload("res://src/core/game_state.gd")
const FIXTURE := "res://tests/fixtures/tasks.json"
const STORY := "res://tests/fixtures/task_story.json"
const PHASES := "res://tests/fixtures/task_phases.json"
var _checks := 0
var _failures: Array[String] = []
var _references: Dictionary
var _changes := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames(count: int = 3) -> void:
	for index in range(count):
		await process_frame

func _until(predicate: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(predicate.call(), message)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var story := StoryLibrary.new()
	_check(story.load_file(STORY) == OK, "Test story uses the original strict StoryLibrary")
	_references = {"events": story.get_event_ids(), "locations": ["test.underground"]}
	_test_catalog()
	await _test_projection_and_lifecycle()
	await _test_real_orders_and_story()
	await _test_demo_host()
	print("TASK_SYSTEM: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _reject(catalog: TaskCatalog, data: Variant, field: String) -> void:
	var before := catalog.get_tasks()
	_check(catalog.load_json(JSON.stringify(data), _references) == ERR_INVALID_DATA, "Invalid task data rejected: " + field)
	_check(field in catalog.last_error, "Diagnostic includes task/field context: " + field + " -> " + catalog.last_error)
	_check(catalog.get_tasks() == before, "Rejected data retains the live catalog: " + field)

func _test_catalog() -> void:
	var catalog := TaskCatalog.new()
	_check(catalog.load_file(FIXTURE, _references) == OK, "Valid fixture catalog loads")
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var data: Dictionary
	for field: String in ["id", "type", "title", "description", "activate_when", "complete_when", "objectives"]:
		data = baseline.duplicate(true)
		data.tasks[0].erase(field)
		_reject(catalog, data, "tasks[0]")
	var mutations := [
		["id", "bad id", "/id"], ["type", "sideways", "/type"],
		["title", 7, "/title"], ["description", "  ", "/description"],
		["difficulty", "extreme", "/difficulty"], ["location_id", "test.missing", "/location_id"],
		["activate_when", {"type": "unknown"}, "/activate_when/type"],
		["activate_when", {"type": "flag", "key": "unscoped"}, "/key"],
		["complete_when", {"type": "variable_at_least", "key": "shop.orders_completed", "value": 2}, "/complete_when"],
		["reveal_when", null, "/reveal_when"], ["rewards", {"text": false}, "/rewards/text"],
		["rewards", {"text": "x", "money": 100}, "/rewards"], ["objectives", [], "/objectives"],
		["unexpected", true, "Unknown field"]]
	for mutation: Array in mutations:
		data = baseline.duplicate(true)
		data.tasks[0][mutation[0]] = mutation[1]
		_reject(catalog, data, mutation[2])
	data = baseline.duplicate(true)
	data.tasks.append(data.tasks[0].duplicate(true))
	_reject(catalog, data, "tasks[2]/id")
	data = baseline.duplicate(true)
	data.tasks[0].objectives.append(data.tasks[0].objectives[0].duplicate(true))
	_reject(catalog, data, "objectives[3]/id")
	for condition: Variant in [null, true, {"type": "event_completed", "id": "task_test.missing"}, {"type": "variable_at_least", "key": "shop.orders_completed", "value": "2"}, {"type": "variable_at_least", "key": "shop.orders_completed", "value": 0}, {"type": "flag", "key": "shop.orders_viewed", "value": true}]:
		data = baseline.duplicate(true)
		data.tasks[0].objectives[0].complete_when = condition
		_reject(catalog, data, "objectives[0]/complete_when")
	for field: String in ["text", "required", "id"]:
		data = baseline.duplicate(true)
		data.tasks[0].objectives[0][field] = 10
		_reject(catalog, data, "objectives[0]")
	data = baseline.duplicate(true)
	for objective: Dictionary in data.tasks[0].objectives:
		objective.required = false
	_reject(catalog, data, "required")
	_reject(catalog, {"version": true, "tasks": []}, "Tasks")
	_reject(catalog, {"version": 2, "tasks": []}, "Tasks")
	_reject(catalog, {"version": 1, "tasks": [], "typo": true}, "Unknown field")
	var before := catalog.get_tasks()
	_check(catalog.load_json("{") != OK and "line" in catalog.last_error and catalog.get_tasks() == before, "JSON errors are diagnosed and atomic")
	_check(catalog.load_file("res://tests/fixtures/missing_tasks.json") == ERR_FILE_NOT_FOUND and catalog.get_tasks() == before, "Missing file preserves catalog")
	_check(catalog.load_file(FIXTURE) == ERR_INVALID_DATA and "reference" in catalog.last_error, "Event/location references require an injected registry")
	_check(catalog.load_file(FIXTURE, {"events": false}) == ERR_INVALID_DATA and "references/events" in catalog.last_error, "Reference registry types are validated")
	_check(catalog.load_file(FIXTURE, {"locations": ["test.same", "test.same"]}) == ERR_INVALID_DATA and "references/locations" in catalog.last_error, "Duplicate registry IDs rejected")
	var external := catalog.get_tasks()
	external[0].title = "external edit"
	_check(catalog.get_tasks() == before, "Catalog getters isolate mutable definitions")
	_check(catalog.load_json('{"version":1,"tasks":[]}') == OK and catalog.last_error.is_empty() and catalog.get_tasks().is_empty(), "Empty valid catalog replaces old definitions and clears diagnostics")

func _test_projection_and_lifecycle() -> void:
	var state := StateData.new()
	root.add_child(state)
	var catalog := TaskCatalog.new()
	catalog.load_file(FIXTURE, _references)
	var journal := TaskJournal.new()
	journal.projection_changed.connect(func() -> void: _changes += 1)
	var snapshot := state.to_dict()
	_check(journal.configure(catalog, state) == OK and state.to_dict() == snapshot, "Initial projection is computed before entering tree, without state writes")
	root.add_child(journal)
	var hud: TaskHUD = load("res://src/UI/tasks/task_hud.tscn").instantiate()
	hud.bind_journal(journal)
	root.add_child(hud)
	await _frames()
	_check(journal.get_task("missing.task").is_empty(), "Unknown task query returns empty")
	_check(journal.get_task("test.progress").status == "inactive" and journal.get_active_tasks().is_empty() and not hud.visible, "Inactive tasks never show in active list or HUD")
	state.set_flag("task.test.completed")
	_check(journal.get_task("test.progress").status == "inactive", "An isolated completion fact does not activate a task")
	state.set_flag("task.test.completed", false)
	state.set_flag("task.test.active")
	var view := journal.get_task("test.progress")
	_check(view.status == "active" and hud.visible and journal.get_active_tasks().size() == 1, "Activation immediately updates active list and HUD")
	_check(view.title == "???" and view.description == "???" and view.location_id.is_empty() and view.difficulty == "???" and view.rewards.text == "???", "Unrevealed task details are masked")
	_check(view.current_objective.text == "???" and view.objectives[2].target == null and view.objectives[2].location_id.is_empty(), "Parent reveal masks objective text, counters and location")
	state.set_flag("test.reveal_task")
	view = journal.get_task("test.progress")
	_check(view.title == "测试主线" and view.location_id == "test.underground" and view.difficulty == "high" and view.rewards.text == "???", "Task reveal exposes confirmed metadata while reward remains hidden")
	_check(view.current_objective.id == "board" and "查看订单板" in hud.get_node("Margin/Content/Objective").text, "First required incomplete objective displays")
	state.set_flag("shop.orders_viewed")
	_check(journal.get_task("test.progress").current_objective.id == "deliveries" and journal.get_task("test.progress").current_objective.text == "???", "Optional event does not block current required objective")
	state.set_flag("test.reveal_objective")
	state.set_flag("test.reveal_reward")
	state.complete_event("task_test.review")
	view = journal.get_task("test.progress")
	_check(view.objectives[1].completed and view.objectives[2].location_id == "test.underground" and view.rewards.revealed, "Completed event, objective reveal and reward reveal project correctly")
	for invalid: Variant in [null, true, "2", [], {}]:
		state.set_variable("shop.orders_completed", invalid)
		_check(not journal.get_task("test.progress").objectives[2].completed and journal.get_task("test.progress").objectives[2].progress == 0, "Non-numeric counters cannot complete an objective")
	state.set_variable("shop.orders_completed", 1)
	_check(journal.get_task("test.progress").current_objective.progress == 1 and "1 / 2" in hud.get_node("Margin/Content/Objective").text, "Numeric progress appears in HUD: %s; %s" % [journal.get_task("test.progress").current_objective, hud.get_node("Margin/Content/Objective").text])
	var saved_window_size := root.size
	var saved_canvas_size := root.content_scale_size
	root.content_scale_size = Vector2i(320, 360)
	root.size = Vector2i(320, 360)
	await _frames()
	_check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(hud.get_global_rect()), "HUD wraps within narrow viewport bounds")
	await _capture("00_counter_narrow")
	root.content_scale_size = saved_canvas_size
	root.size = saved_window_size
	await _frames()
	state.set_variable("shop.orders_completed", 2.0)
	_check(journal.get_task("test.progress").current_objective.is_empty() and journal.get_task("test.progress").status == "active" and "等待" in hud.get_node("Margin/Content/Objective").text, "All objectives reached still wait for an explicit final fact")
	state.complete_event("task_test.accept")
	_check(journal.get_task("test.commission").status == "active" and journal.get_active_tasks().size() == 2 and journal.get_current_main_task().id == "test.progress", "Commission activates via completed event without replacing tracked main")
	state.complete_event("task_test.finish")
	_check(journal.get_task("test.commission").status == "completed", "Authoritative completed event finishes a commission")
	var before_changes := _changes
	state.state_changed.emit()
	state.set_story_stage("test.unrelated")
	state.set_variable("unrelated.counter", 17)
	journal.refresh()
	_check(_changes == before_changes, "Repeated/unrelated state notifications emit no projection changes")
	snapshot = state.to_dict()
	var exposed := journal.get_task("test.progress")
	exposed.objectives[0].text = "mutated"
	var active := journal.get_active_tasks()
	active.clear()
	journal.get_current_main_task().current_objective.clear()
	journal.refresh()
	_check(state.to_dict() == snapshot and journal.get_task("test.progress").objectives[0].text == "查看订单板", "Reads, refreshes and returned data mutations never modify state or projection")
	catalog.load_json('{"version":1,"tasks":[]}')
	journal.refresh()
	_check(not journal.get_active_tasks().is_empty(), "Journal owns a definition snapshot; catalog reload requires explicit reconfigure")
	var saved := state.to_dict()
	state.set_flag("task.test.completed")
	_check(journal.get_task("test.progress").status == "completed" and not hud.visible, "Only explicit final fact completes main and hides HUD")
	state.restore_state(saved)
	_check(journal.get_task("test.progress").status == "active" and hud.visible and state.to_dict() == saved, "Restore refreshes projection without modifying the snapshot")
	state.reset_state()
	_check(journal.get_active_tasks().is_empty() and not hud.visible, "Reset clears task projection immediately")
	state.restore_state(saved)
	catalog.load_file(FIXTURE, _references)
	journal.configure(catalog, state)
	journal.configure(catalog, state)
	_check(state.state_changed.get_connections().size() == 1, "Repeated Journal configure has one state subscription")
	hud.bind_journal(journal)
	hud.bind_journal(journal)
	_check(journal.projection_changed.get_connections().size() == 2, "HUD rebinding keeps one subscription alongside test observer")
	root.remove_child(hud)
	_check(journal.projection_changed.get_connections().size() == 1, "HUD disconnects when leaving tree")
	root.add_child(hud)
	_check(journal.projection_changed.get_connections().size() == 2 and hud.visible, "Same HUD reconnects and refreshes when reentering tree")
	root.remove_child(journal)
	_check(state.state_changed.get_connections().is_empty(), "Journal disconnects on leaving tree")
	state.reset_state()
	root.add_child(journal)
	_check(journal.get_active_tasks().is_empty() and not hud.visible and state.state_changed.get_connections().size() == 1, "Same Journal reconnects and recomputes changes missed outside tree")
	var other_state := StateData.new()
	root.add_child(other_state)
	other_state.restore_state(saved)
	journal.configure(catalog, other_state)
	_check(state.state_changed.get_connections().is_empty() and other_state.state_changed.get_connections().size() == 1 and hud.visible, "Rebinding moves observation to the injected state only")
	_check(journal.configure(null, other_state) == ERR_INVALID_PARAMETER and hud.visible, "Invalid reconfigure preserves working projection")
	hud.bind_journal(null)
	_check(not hud.visible, "HUD can unbind and clear safely")
	hud.free()
	journal.free()
	_check(other_state.state_changed.get_connections().is_empty(), "Freeing Journal leaves no state callbacks")
	other_state.free()
	state.free()

func _capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await _frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/task_system")
	root.get_texture().get_image().save_png("res://.godot/task_system/" + name + ".png")

func _test_real_orders_and_story() -> void:
	var state: StateData = root.get_node("GameState")
	state.reset_state()
	var original_debug: Variant = ProjectSettings.get_setting("debug/developer_tools/enabled", null)
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	var initial_connections := state.state_changed.get_connections().size()
	var game: MainGame = load("res://src/core/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames()
	var journal := game.get_task_journal()
	var hud: TaskHUD = game.get_node("HudLayer/TaskHUD")
	var shop := game.get_shop_ui()
	var director := game.get_story_director()
	var inventory := game.get_warehouse_inventory()
	var production := game.get_tea_production()
	var points := {}
	for point: InteractionPoint in (game.get_active_level() as MilkTeaShop).get_interaction_points():
		points[point.interaction_id] = point
	_check(journal != null and not hud.visible and state.get_flags().is_empty(), "Production host loads catalog with no automatic activation or Demo facts")
	_check(not director.get_runtime_status().loaded and director.get_runtime_status().event_count == 0, "Production host does not load fixture or Demo story")
	_check(not game.get_ui_manager().has_modal() and (game.get_player() as PlayerController).movement_enabled, "Task HUD adds no modal/input lock")
	_check(game.get_dialogue_manager().start_dialogue("demo.greeting") == OK, "Existing dialogue can reserve modal")
	shop.open(points[&"orders"])
	_check(not shop.is_open() and not state.get_flag("shop.orders_viewed"), "Rejected UI open cannot report a viewed board")
	game.get_dialogue_manager().end_dialogue(true)
	_check(director.load_events(STORY) == OK and director.request_event("task_test.accept") == OK, "Explicit fixture story request activates task via real Director")
	await _until(func() -> bool: return state.is_event_completed("task_test.accept"), "Activation story completes")
	_check(journal.get_task("shop.first_order").status == "active" and hud.visible, "Story-written activation immediately appears in HUD")
	await _capture("01_active")
	shop.open(points[&"storage"])
	shop.close()
	shop.open(points[&"tea_station"])
	shop.close()
	_check(not state.get_flag("shop.orders_viewed") and not state.get_flag("shop.order_001_delivered"), "Storage, station and closing UI do not report board view or delivery")
	state.set_flag("task_test.route_review")
	_check(director.request_interaction("orders") == OK, "A matching story route still handles the interaction")
	await _until(func() -> bool: return state.is_event_completed("task_test.review"), "Routed event completes through original Director")
	_check(not shop.is_open() and not state.get_flag("shop.orders_viewed"), "Accepted/completed story route alone does not report opening fallback order UI")
	_check(director.request_interaction("orders") == ERR_DOES_NOT_EXIST, "No story route retains existing UI fallback")
	shop.open(points[&"orders"])
	_check(state.get_flag("shop.orders_viewed") and journal.get_task("shop.first_order").current_objective.id == "deliver_order", "Actual order board presentation advances board objective")
	_check(shop.is_open() and not (game.get_player() as PlayerController).movement_enabled, "Existing board popup retains movement lock")
	shop.close()
	_check((game.get_player() as PlayerController).movement_enabled, "Closing board restores movement")
	await _capture("02_delivery_target")
	var stock_before := inventory.to_dict()
	var facts_before := state.to_dict()
	_check(not production.make_drink(["green_tea", "creamer", "pearl", "syrup"]).ok, "Wrong recipe is rejected by real business")
	_check(inventory.to_dict() == stock_before and state.to_dict() == facts_before and not journal.get_task("shop.first_order").objectives[1].completed, "Wrong recipe preserves stock, facts and task target")
	inventory.try_consume({"black_tea": inventory.get_stock("black_tea")})
	var scarce := inventory.to_dict()
	_check(not production.make_drink(["black_tea", "creamer", "pearl", "syrup"]).ok, "Insufficient stock rejects a valid recipe")
	_check(inventory.to_dict() == scarce and state.to_dict() == facts_before and not state.get_flag("shop.order_001_delivered"), "Shortage never reports delivery or partially consumes materials")
	inventory.restore_state(stock_before)
	shop.open(points[&"tea_station"])
	var panel: TeaProductionPanel = game.get_node("PopupLayer/Modal/Center/Panel/Margin/Content/ProductionPanel")
	var selectors: Array[OptionButton] = []
	for column in panel.get_child(1).get_children():
		selectors.append(column.get_child(1))
	panel.get_child(2).pressed.emit()
	_check(production.get_completed_count() == 0 and not state.get_flag("shop.order_001_delivered"), "Incomplete UI submission does not complete task")
	selectors[0].select(1)
	selectors[1].select(1)
	selectors[2].select(1)
	panel.get_child(2).pressed.emit()
	_check(production.get_completed_count() == 1 and not state.get_flag("shop.order_001_delivered") and inventory.get_stock("pearl_milk_tea") == 1, "Real UI crafting puts a carried cup in inventory without completing task")
	_check(inventory.get_stock("black_tea") == 11 and inventory.get_stock("syrup") == 9, "Real delivery consumes each actual ingredient once")
	_check(journal.get_task("shop.first_order").current_objective.id == "deliver_order" and journal.get_task("shop.first_order").status == "active" and not director.is_busy(), "Crafting leaves delivery objective active")
	var active_snapshot := state.to_dict()
	shop.close()
	_check(game.get_task_delivery().try_deliver("order_001", "pearl_milk_tea", "fat_goblin").ok, "Explicit delivery completes active task")
	_check(journal.get_task("shop.first_order").status == "completed" and inventory.get_stock("pearl_milk_tea") == 0 and inventory.get_stock("syrup") == 10, "Delivery consumes cup and pays configured reward")
	var committed := state.to_dict()
	var committed_stock := inventory.to_dict()
	var notifications: Array[bool] = []
	journal.projection_changed.connect(func() -> void: notifications.append(true))
	production.changed.emit()
	state.state_changed.emit()
	journal.refresh()
	_check(notifications.is_empty() and state.to_dict() == committed and inventory.to_dict() == committed_stock, "Duplicate notifications never re-complete, consume, write or notify UI")
	shop.close()
	await _capture("03_waiting_story")
	_check(game.get_gameplay_bridge().load_phases(PHASES) == OK, "Existing GameplayBridge loads isolated delivery phase")
	shop.open(points[&"storage"])
	await _frames(8)
	_check(journal.get_task("shop.first_order").status == "completed" and not director.is_busy(), "Bridge respects modal after business task completion")
	game.get_ui_manager().set_paused(true)
	shop.close()
	await _frames(8)
	_check(not director.is_busy() and not state.get_flag("task.shop.first_order.completed"), "Bridge respects pause without task taking over waiting")
	game.get_ui_manager().set_paused(false)
	await _until(func() -> bool: return state.is_event_completed("task_test.finish"), "Existing Bridge resumes explicit completion story")
	_check(journal.get_task("shop.first_order").status == "completed" and not hud.visible and state.story_stage == "task_test.done", "Story end fact completes task and clears HUD")
	_check(inventory.to_dict() == committed_stock, "Follow-up story never repeats delivery reward or changes inventory")
	var finished_snapshot := state.to_dict()
	game.free()
	await _frames()
	_check(state.state_changed.get_connections().size() == initial_connections and state.to_dict() == finished_snapshot, "Host destruction disconnects Journal and leaves shared progress intact")
	var next_game: MainGame = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(next_game)
	current_scene = next_game
	await _frames()
	_check(next_game.get_task_journal().get_task("shop.first_order").status == "completed" and not next_game.get_node("HudLayer/TaskHUD").visible, "Settlement reuses same projection after host replacement")
	state.restore_state(active_snapshot)
	_check(next_game.get_task_journal().get_task("shop.first_order").status == "active" and next_game.get_node("HudLayer/TaskHUD").visible and state.to_dict() == active_snapshot, "Restore in rebuilt host reconstructs active task without replay or state writes")
	state.reset_state()
	_check(not next_game.get_node("HudLayer/TaskHUD").visible, "Reset hides rebuilt host HUD")
	next_game.free()
	await _frames()
	_check(state.state_changed.get_connections().size() == initial_connections, "Scene rebuilding accumulates no state subscriptions")
	ProjectSettings.set_setting("debug/developer_tools/enabled", original_debug)

func _test_demo_host() -> void:
	var state: StateData = root.get_node("GameState")
	state.set_flag("test.saved_before_demo")
	var before := state.to_dict()
	var demo: Node = load("res://src/debug/tasks/task_demo.tscn").instantiate()
	root.add_child(demo)
	current_scene = demo
	await _until(func() -> bool: return state.is_event_completed("task_test.accept"), "F6 acceptance host runs isolated activation fixture")
	var game: MainGame = demo.get_node("Game")
	_check(game.get_task_journal().get_task("shop.first_order").status == "active" and game.get_node("HudLayer/TaskHUD").visible, "F6 host exposes real task and business for manual play")
	_check(not state.get_flag("test.saved_before_demo"), "F6 host isolates its state from existing progress")
	demo.free()
	await _frames()
	_check(state.to_dict() == before, "Leaving F6 host restores the previous GameState snapshot")
	state.reset_state()
