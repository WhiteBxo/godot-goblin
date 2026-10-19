extends SceneTree
## Headless verification for gathering points, item requirements and inventory contention.

const StateData = preload("res://src/core/game_state.gd")
const TASKS := "res://src/resources/tasks/tasks.json"
const GATHER_POINT: PackedScene = preload("res://src/gameplay/gathering/gather_point.tscn")
const NIGHT := "world.phase.night"
const MUSHROOM := "insomnia_mushroom"

var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)


func _run() -> void:
	_test_configuration()
	_test_availability_and_commit()
	_test_failures()
	_test_reentry()
	_test_snapshot()
	_test_item_delivery()
	_test_contention()
	_test_projection()
	await _test_host()
	print("GATHERING: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _make_point(id: String, item: String = MUSHROOM, mode: String = "daily", flag: String = NIGHT) -> GatherPoint:
	var point: GatherPoint = GATHER_POINT.instantiate()
	point.interaction_id = StringName(id)
	point.display_name = id
	point.item_id = item
	point.amount = 1
	point.refresh_mode = mode
	point.required_flag = flag
	return point


func _typed(points: Array) -> Array[GatherPoint]:
	var result: Array[GatherPoint] = []
	for point: GatherPoint in points:
		result.append(point)
	return result


func _rig(tag: String, points: Array) -> Dictionary:
	var state := StateData.new()
	var inventory := state.get_warehouse_inventory()
	var service := GatheringService.new()
	service.name = "GatheringService" + tag
	var container := Node.new()
	container.name = "Points" + tag
	root.add_child(container)
	for point: GatherPoint in points:
		container.add_child(point)
	root.add_child(service)
	var error := service.configure(state, inventory, _typed(points))
	return {"state": state, "inventory": inventory, "service": service,
		"container": container, "error": error}


func _drop(rig: Dictionary) -> void:
	rig.service.free()
	rig.container.free()
	rig.state.free()


func _test_configuration() -> void:
	var point := _make_point("night_gather_0")
	var duplicate := _make_point("night_gather_0")
	var product := _make_point("night_gather_x", "pearl_milk_tea")
	var unknown := _make_point("night_gather_y", "missing_item")
	var zero := _make_point("night_gather_z")
	zero.amount = 0
	var weekly := _make_point("night_gather_w")
	weekly.refresh_mode = "weekly"
	var flat_flag := _make_point("night_gather_f")
	flat_flag.required_flag = "night"
	var rig := _rig("config", [point])
	_check(rig.error == OK, "Valid gather point configures")
	var state: StateData = rig.state
	var inventory: WarehouseInventory = rig.inventory
	var service: GatheringService = rig.service
	_check(service.has_point(&"night_gather_0") and service.get_points().size() == 1, "Configured point is registered")
	_check(service.configure(state, inventory, _typed([point, duplicate])) == ERR_INVALID_DATA, "Duplicate point IDs are rejected")
	_check(service.configure(state, inventory, _typed([product])) == ERR_INVALID_DATA, "Finished products cannot be gathered")
	_check(service.configure(state, inventory, _typed([unknown])) == ERR_INVALID_DATA, "Unknown item IDs are rejected")
	_check(service.configure(state, inventory, _typed([zero])) == ERR_INVALID_DATA, "Zero amounts are rejected")
	_check(service.configure(state, inventory, _typed([weekly])) == ERR_INVALID_DATA, "Unknown refresh modes are rejected")
	_check(service.configure(state, inventory, _typed([flat_flag])) == ERR_INVALID_DATA, "Required flags need a namespace")
	_check(service.has_point(&"night_gather_0") and service.get_points().size() == 1, "Rejected configurations keep the live registry")
	_check(service.configure(state, inventory, _typed([])) == OK and not service.has_point(&"night_gather_0"), "Replacing with an empty list unbinds old points")
	_drop(rig)
	for extra: GatherPoint in [duplicate, product, unknown, zero, weekly, flat_flag]:
		extra.free()


func _test_availability_and_commit() -> void:
	var daily := _make_point("night_gather_0")
	var once := _make_point("night_gather_6", MUSHROOM, "once")
	var rig := _rig("commit", [daily, once])
	var state: StateData = rig.state
	var inventory: WarehouseInventory = rig.inventory
	var service: GatheringService = rig.service
	_check(not service.is_harvestable(daily) and not service.harvest(&"night_gather_0").ok, "Missing night flag blocks gathering")
	_check(inventory.get_stock(MUSHROOM) == 0, "Blocked gathering adds nothing")
	state.set_flag(NIGHT)
	_check(service.is_harvestable(daily), "Night flag opens the point")

	var counts := {"state": 0, "inventory": 0, "harvested": 0}
	state.state_changed.connect(func() -> void: counts.state += 1)
	inventory.changed.connect(func() -> void: counts.inventory += 1)
	service.harvested.connect(func(_point: GatherPoint, _item: String, _amount: int, _stock: int) -> void: counts.harvested += 1)
	var result := service.harvest(&"night_gather_0")
	_check(result.ok and result.item_id == MUSHROOM and result.amount == 1 and result.stock == 1, "Harvest reports the committed stock")
	_check(inventory.get_stock(MUSHROOM) == 1 and inventory.is_discovered(MUSHROOM), "Harvest adds a discovered item to the shared inventory")
	_check(int(state.get_variable("gather.night_gather_0.day", 0)) == 1, "Daily point records the harvest day")
	_check(int(state.get_variable("gather.total.insomnia_mushroom", 0)) == 1, "Harvest accumulates a per-item total")
	_check(counts.state == 1 and counts.inventory == 1 and counts.harvested == 1, "A committed harvest notifies every observer once")
	_check(not service.is_harvestable(daily) and not service.harvest(&"night_gather_0").ok, "Daily point is spent for the day")
	state.set_current_day(2)
	_check(service.is_harvestable(daily) and service.harvest(&"night_gather_0").ok, "Next day reopens the daily point")
	_check(inventory.get_stock(MUSHROOM) == 2, "Second-day harvest adds one more portion")

	_check(service.harvest(&"night_gather_6").ok and inventory.get_stock(MUSHROOM) == 3, "Once point can be gathered")
	_check(state.get_flag("gather.night_gather_6.harvested"), "Once point records a permanent flag")
	state.set_current_day(3)
	_check(not service.is_harvestable(once) and not service.harvest(&"night_gather_6").ok, "Once point never refills")
	_check(inventory.get_stock(MUSHROOM) == 3, "Rejected refill adds nothing")
	_drop(rig)


func _test_failures() -> void:
	var rig := _rig("failure", [_make_point("night_gather_0")])
	var state: StateData = rig.state
	var inventory: WarehouseInventory = rig.inventory
	var service: GatheringService = rig.service
	var before := state.to_dict()
	var stock := inventory.to_dict()
	_check(not service.harvest(&"missing_point").ok and inventory.to_dict() == stock and state.to_dict() == before, "Unknown point IDs change nothing")
	state.set_flag(NIGHT)
	inventory.add_ingredient(MUSHROOM, WarehouseInventory.MAX_QUANTITY)
	var full := inventory.to_dict()
	var full_state := state.to_dict()
	_check(not service.harvest(&"night_gather_0").ok and inventory.to_dict() == full and state.to_dict() == full_state, "Full inventory rejects the harvest without writing facts")
	_check(not state.has_flag("gather.night_gather_0.harvested"), "Rejected harvest never spends a point")
	_drop(rig)


func _test_reentry() -> void:
	var rig := _rig("reentry", [_make_point("night_gather_0")])
	var state: StateData = rig.state
	var inventory: WarehouseInventory = rig.inventory
	var service: GatheringService = rig.service
	state.set_flag(NIGHT)
	var seen := {"reentry": false, "blocked_reset": false, "blocked_restore": false}
	var snapshot := state.to_dict()
	service.harvested.connect(func(_point: GatherPoint, _item: String, _amount: int, _stock: int) -> void:
		seen.reentry = not service.harvest(&"night_gather_0").ok
		seen.blocked_reset = not state.reset_state()
		seen.blocked_restore = state.restore_state(snapshot) == ERR_BUSY)
	_check(service.harvest(&"night_gather_0").ok, "First harvest succeeds")
	_check(seen.reentry and seen.blocked_reset and seen.blocked_restore, "Observers cannot re-enter the session during a harvest")
	_check(inventory.get_stock(MUSHROOM) == 1, "Re-entry cannot duplicate the item")
	_drop(rig)


func _test_snapshot() -> void:
	var rig := _rig("snapshot", [_make_point("night_gather_0"), _make_point("night_gather_6", MUSHROOM, "once")])
	var state: StateData = rig.state
	var inventory: WarehouseInventory = rig.inventory
	var service: GatheringService = rig.service
	state.set_flag(NIGHT)
	_check(service.harvest(&"night_gather_0").ok and service.harvest(&"night_gather_6").ok, "Two points harvested before the snapshot")
	var snapshot := state.to_dict()

	var restored := StateData.new()
	_check(restored.restore_state(snapshot) == OK, "Gathering facts restore through the v2 snapshot")
	_check(int(restored.get_variable("gather.total.insomnia_mushroom", 0)) == 2 and restored.get_flag("gather.night_gather_6.harvested"), "Restored session keeps totals and once flags")
	var restored_inventory := restored.get_warehouse_inventory()
	_check(restored_inventory.get_stock(MUSHROOM) == 2, "Restored session keeps gathered stock")
	var container := Node.new()
	root.add_child(container)
	var daily := _make_point("night_gather_0")
	var once := _make_point("night_gather_6", MUSHROOM, "once")
	container.add_child(daily)
	container.add_child(once)
	var rebuilt := GatheringService.new()
	root.add_child(rebuilt)
	_check(rebuilt.configure(restored, restored_inventory, _typed([daily, once])) == OK, "Service rebuilds on the restored session")
	_check(not rebuilt.is_harvestable(daily) and not rebuilt.is_harvestable(once), "Restored points stay spent")
	restored.set_current_day(2)
	_check(rebuilt.is_harvestable(daily) and not rebuilt.is_harvestable(once), "Daily restores with the day, once stays spent")
	_check(restored.start_new_game() == OK, "New game resets the session")
	restored.set_flag(NIGHT)
	_check(rebuilt.is_harvestable(daily) and rebuilt.is_harvestable(once), "New game reopens every gather point")
	rebuilt.free()
	container.free()
	restored.free()
	_drop(rig)


func _activate(state: StateData) -> void:
	state.set_flag(NIGHT)
	state.set_flag("task.tavern.insomnia.active")


func _test_item_delivery() -> void:
	var catalog := TaskCatalog.new()
	_check(catalog.load_file(TASKS) == OK, "Task catalog accepts the material order: " + catalog.last_error)
	var state := StateData.new()
	var journal := TaskJournal.new()
	journal.configure(catalog, state)
	var inventory := state.get_warehouse_inventory()
	var delivery := TaskDelivery.new()
	_check(delivery.configure(catalog, journal, state, inventory) == OK, "Delivery accepts a material requirement")
	_check(delivery.get_requirement("order_insomnia_01") == {MUSHROOM: 3}, "Material requirement normalises JSON numbers to ints")
	_check(delivery.get_requirement("order_001") == {"pearl_milk_tea": 1}, "Finished-product orders keep their single-item requirement")
	_activate(state)
	_check(journal.get_task("tavern.insomnia_order").status == "active", "Material order activates")
	inventory.try_exchange({}, {MUSHROOM: 2})
	var stock := inventory.to_dict()
	var facts := state.to_dict()
	_check(not delivery.deliver_to("tavern").ok and inventory.to_dict() == stock and state.to_dict() == facts, "Short material delivery consumes nothing")
	_check(not delivery.try_deliver("order_insomnia_01", "pearl_milk_tea", "tavern").ok, "Material orders refuse a product argument")
	inventory.try_exchange({}, {MUSHROOM: 1})
	_check(delivery.try_deliver("order_insomnia_01", "", "tavern").ok, "Legacy signature submits materials with an empty product")
	_check(inventory.get_stock(MUSHROOM) == 0 and inventory.get_stock("syrup") == 12, "Material delivery consumes the list and pays the reward once")
	_check(state.get_flag("tavern.insomnia.delivered") and state.get_flag("delivery.order_insomnia_01.completed"), "Material delivery writes the completion flag and receipt")
	_check(journal.get_task("tavern.insomnia_order").status == "completed", "Material order projects as completed")
	stock = inventory.to_dict()
	facts = state.to_dict()
	_check(not delivery.try_submit("order_insomnia_01", "tavern").ok and inventory.to_dict() == stock and state.to_dict() == facts, "Repeated material submission is refused")
	delivery.free()
	journal.free()
	state.free()


func _test_contention() -> void:
	var data := {
		"version": 1,
		"tasks": [{
			"id": "test.contention",
			"type": "main",
			"title": "库存争抢",
			"description": "材料先扣先得。",
			"activate_when": {"type": "flag", "key": "test.contention.active"},
			"complete_when": {"type": "flag", "key": "test.contention.done"},
			"objectives": [{"id": "submit", "text": "提交红茶",
				"complete_when": {"type": "flag", "key": "test.contention.done"}}],
			"delivery": {"order_id": "test_contention_01", "items": {"black_tea": 3}, "target_object_id": "tavern"}
		}]
	}
	var catalog := TaskCatalog.new()
	_check(catalog.load_json(JSON.stringify(data)) == OK, "Inline material order loads: " + catalog.last_error)
	var state := StateData.new()
	var journal := TaskJournal.new()
	journal.configure(catalog, state)
	var inventory := state.get_warehouse_inventory()
	var delivery := TaskDelivery.new()
	delivery.configure(catalog, journal, state, inventory)
	state.set_flag("test.contention.active")
	inventory.try_consume({"black_tea": 9})
	_check(inventory.get_stock("black_tea") == 3, "Three portions remain")
	_check(inventory.try_consume({"black_tea": 1}), "Crafting-style consumption takes one portion first")
	var remaining := inventory.to_dict()
	_check(not delivery.try_submit("test_contention_01", "tavern").ok and inventory.to_dict() == remaining, "Submission rejects the shortfall instead of going negative")
	_check(inventory.get_stock("black_tea") == 2, "Stock never drops below zero")
	inventory.try_exchange({}, {"black_tea": 1})
	_check(delivery.try_submit("test_contention_01", "tavern").ok and inventory.get_stock("black_tea") == 0, "First come first served: the refilled list is consumed once")

	var bad := data.duplicate(true)
	bad.tasks[0].delivery.items = {"black_tea": 3}
	bad.tasks[0].delivery.product_id = "pearl_milk_tea"
	_check(catalog.load_json(JSON.stringify(bad)) == ERR_INVALID_DATA, "A delivery cannot carry both product_id and items")
	for invalid: Variant in [{}, {"black_tea": 0}, {"black_tea": 1.5}, {"black_tea": true}, {"bad id": 1}, {"black_tea": 2147483648}, "black_tea"]:
		var broken := data.duplicate(true)
		broken.tasks[0].delivery.items = invalid
		_check(catalog.load_json(JSON.stringify(broken)) == ERR_INVALID_DATA, "Malformed material lists are rejected: " + str(invalid))
	delivery.free()
	journal.free()
	state.free()


func _test_projection() -> void:
	var catalog := TaskCatalog.new()
	catalog.load_file(TASKS)
	var state := StateData.new()
	var journal := TaskJournal.new()
	journal.configure(catalog, state)
	_activate(state)
	state.set_variable("gather.total.insomnia_mushroom", 2)
	var view := journal.get_task("tavern.insomnia_order")
	_check(view.objectives[0].progress == 2.0 and view.objectives[0].target == 3.0 and not view.objectives[0].completed, "Gather objective reports partial progress")
	state.set_variable("gather.total.insomnia_mushroom", 3)
	view = journal.get_task("tavern.insomnia_order")
	_check(view.objectives[0].completed and view.status == "active" and view.current_objective.id == "deliver_mushrooms", "Gather objective completes before delivery")
	journal.free()
	state.free()


func _frames() -> void:
	for index in range(4):
		await physics_frame
	await process_frame


func _press_interact() -> void:
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventAction.new()
	event.action = &"interact"
	Input.parse_input_event(event)
	await process_frame


func _move_player(player: Node2D, target: Vector2) -> void:
	player.global_position = target + Vector2(0, 24)
	await _frames()


func _test_host() -> void:
	var state: StateData = root.get_node("GameState")
	state.start_new_game()
	state.select_business_profile("day1")
	state.set_current_day(2)
	state.set_story_stage("day2.s03.travel_tavern")
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/gathering_%d" % OS.get_process_id())
	var game: MainGame = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames()
	var level := game.get_active_level() as RpgChapterMap
	var service := game.get_gathering_service()
	var player := game.get_player()
	var ui := game.get_shop_ui()
	_check(level != null and service.get_points().size() == 3, "Formal RPG exterior hosts the three commercial-route resources")
	var first := service.get_point(&"night_gather_0")
	_check(not first.get_node("Marker").visible and not first.get_node("HarvestVisual").visible, "Daytime hides the night harvest artwork and clue")
	await _move_player(player, first.global_position)
	await _press_interact()
	_check(not ui.is_open(), "Daytime E cannot gather")
	_check(DayPhase.advance_to(state, 2, "night") == OK, "Real schedule opens night gathering")
	await _frames()
	var before := state.to_dict()
	for point: GatherPoint in service.get_points():
		_check(point.get_node("Marker").visible and point.get_node("HarvestVisual").visible, "Available material has matching world artwork and marker")
		_check(level.can_stand_at(point.global_position + Vector2(0, 24), Vector2(8.5, 5)), "Harvest object has a walkable approach: " + String(point.name))
		var stock := game.get_warehouse_inventory().get_stock(point.item_id)
		await _move_player(player, point.global_position)
		await _press_interact()
		_check(ui.is_open() and game.get_warehouse_inventory().get_stock(point.item_id) == stock + point.amount, "Physical E harvests the configured real material")
		ui.close()
		await _frames()
		_check(not point.get_node("Marker").visible and not point.get_node("HarvestVisual").visible and not point.is_available(), "Harvested artwork and target disappear together")
		var harvested := state.to_dict()
		await _press_interact()
		_check(state.to_dict() == harvested, "Repeated E cannot duplicate material")
	state.set_flag("day2.s03.festival_accepted")
	await _frames()
	_check(state.get_flag("day2.s03.has_gathered"), "Gathering before accepting the commission is recognized")
	var notice := game.get_chapter_gameplay().get_gathering_notice()
	_check("缺0" in notice and "已齐备" in notice, "Commission projects actual held portions and zero shortfall")
	game.get_warehouse_inventory().try_consume({"moss_green": 1})
	_check("苔痕青 1/2 · 缺1" in game.get_chapter_gameplay().get_gathering_notice(), "Using shared stock immediately changes the displayed shortfall")
	_check(state.restore_state(before) == OK, "Restore the pre-harvest state")
	await _frames()
	_check(first.get_node("HarvestVisual").visible and service.is_harvestable(first), "Restore rebuilds artwork from saved harvest facts")
	game.free()
	await _frames()
	state.reset_state()
