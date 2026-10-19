extends SceneTree

const StateData = preload("res://src/core/game_state.gd")
var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	var state := StateData.new()
	check(state.select_business_profile("day1") == OK, "Use actual Day 1 session")
	var catalog := TaskCatalog.new()
	check(catalog.load_files(Day1ChapterController.TASK_FILES) == OK, "Load formal chapter tasks")
	var journal := TaskJournal.new()
	journal.configure(catalog, state)
	var inventory: WarehouseInventory = state.get_warehouse_inventory()
	var production: TeaProduction = state.get_tea_production()
	var delivery := TaskDelivery.new()
	var setup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/resources/story/day1_stages_01_02_setup.json"))
	var batches: Array[Dictionary] = []
	batches.assign(setup.batches)
	delivery.configure_batches(batches)
	check(delivery.configure(catalog, journal, state, inventory) == OK, "Configure real delivery")
	var board := OrderBoardModel.new()
	board.configure(catalog, journal, state, inventory, production, delivery)
	board.set_target_names({"goblin_a": "哥布林甲", "goblin_b": "哥布林乙", "goblin_c": "哥布林丙"})
	check(board.get_entries().is_empty(), "Unrevealed story orders stay hidden")
	state.set_flag("day1.group_open")
	check(board.get_entries().size() == 3, "Only the three revealed orders appear")
	check(board.get_entry("day1_group_c").status == "available", "Chapter activation is not order acceptance")
	check(board.get_interaction_priority(&"goblin_c") < board.get_interaction_priority(&"orders"), "Unaccepted customers defer to the counter")
	check(board.get_interaction_priority(&"companion_without_order") < board.get_interaction_priority(&"orders"), "A companion without a catalog order cannot steal the counter")
	var snapshot := state.to_dict()
	board.refresh()
	check(state.to_dict() == snapshot, "Reading the board never accepts orders or writes facts")
	for id: String in ["day1_group_c", "day1_group_a", "day1_group_b"]:
		check(delivery.accept_order(id) == OK, "Explicitly accept " + id)
	check(delivery.accept_order("day1_group_c") == ERR_ALREADY_EXISTS, "Repeated acceptance is a no-op")
	state.set_variable(OrderBoardModel.TRACKED_KEY, "day1_group_c")
	check(board.get_tracked_entry().order_id == "day1_group_c", "Manual tracking takes priority")
	var batch := board.get_tracked_entry()
	check(batch.craft_quantity == 3, "Accepted shared demand offers a three-cup batch")
	var inventory_before := inventory.to_dict()
	var limited_material: String = batch.recipe_materials[0]
	inventory.try_spend_uses({limited_material: inventory.get_uses(limited_material) - 2})
	check(board.get_tracked_entry().craft_quantity == 2 and board.get_tracked_entry().remaining_to_craft == 3, "Partial stock limits the offered batch without hiding the remaining demand")
	var shortage := state.to_dict()
	check(not production.craft(batch.recipe_materials, 3).ok and state.to_dict() == shortage, "An oversized batch rejects atomically")
	inventory.restore_state(inventory_before)
	for id: String in ["day1_group_c", "day1_group_a", "day1_group_b"]:
		var entry := board.get_entry(id)
		check(entry.can_craft, "Any accepted group order can be prepared")
		check(production.craft(entry.recipe_materials).ok, "Craft out of queue order: " + id)
		check(board.get_entry(id).ready, "Readiness follows actual inventory")
		check(board.get_interaction_priority(StringName(entry.target_id)) > board.get_interaction_priority(&"orders"), "A ready customer wins inside the counter group")
		check(delivery.deliver_to(entry.target_id, id).ok, "Deliver out of queue order: " + id)
		check(board.get_entry(id).status == "completed", "Receipt completes " + id)
	check(state.get_flag("day1.group_settled"), "Group completion waits for all actual receipts")
	check(delivery.get_completed_count() == 3, "Completion counts deliveries, not legacy queue position")
	check(board.get_tracked_entry().is_empty(), "No active tracking remains after all orders")
	var paid := state.to_dict()
	check(not delivery.deliver_to("goblin_c", "day1_group_c").ok and state.to_dict() == paid, "Duplicate delivery never pays again")
	check(state.restore_state(snapshot) == OK, "Old session snapshot restores")
	check(board.get_entry("day1_group_c").status == "available", "Restore rebuilds acceptance from facts")
	check(delivery.accept_order("day1_group_a") == OK, "Accept before shared-stock checks")
	inventory.add_ingredient("classic_boba_milk_tea", 1)
	check(board.get_entry("day1_group_a").ready, "Existing product is deliverable without crafting")
	inventory.try_consume({"classic_boba_milk_tea": 1})
	check(not board.get_entry("day1_group_a").ready, "Consuming shared stock immediately clears readiness")
	var amount := inventory.get_stock("brown_sugar_boba")
	inventory.try_consume({"brown_sugar_boba": amount})
	check(board.get_entry("day1_group_a").stage == "missing_materials" and not board.get_entry("day1_group_a").can_craft, "Shortage disables order crafting")
	var copy := board.get_entries()
	copy[0].items.clear()
	check(not board.get_entries()[0].items.is_empty(), "Queries return detached nested snapshots")
	board.free()
	delivery.free()
	journal.free()
	state.free()
	_test_shared_orders()
	print("ORDER_BOARD: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_shared_orders() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/resources/tasks/tasks.json"))
	var template: Dictionary = data.tasks[0].duplicate(true)
	data.tasks.clear()
	for id: String in ["unaccepted", "first", "preferred", "locked"]:
		var task := template.duplicate(true)
		task.id = "test." + id
		task.activate_when.key = "test.open"
		task.complete_when.key = "test." + id + ".done"
		task.objectives = [{"id": "deliver", "text": "交付", "complete_when": task.complete_when.duplicate(true)}]
		task.delivery.order_id = id
		task.delivery.accepted_flag = "test." + id + ".accepted"
		if id == "locked":
			task.delivery.product_id = "day1_blood_milk_tea"
		data.tasks.append(task)
	var materials := template.duplicate(true)
	materials.id = "test.materials"
	materials.activate_when.key = "test.open"
	materials.complete_when.key = "test.materials.done"
	materials.objectives = [{"id": "deliver", "text": "交付", "complete_when": materials.complete_when.duplicate(true)}]
	materials.delivery = {"order_id": "materials", "items": {"black_tea": 2}, "target_object_id": "tavern", "accepted_flag": "test.materials.accepted"}
	data.tasks.append(materials)
	var catalog := TaskCatalog.new()
	check(catalog.load_json(JSON.stringify(data)) == OK, "Load shared-stock and recipe-lock scenarios")
	var state := StateData.new()
	state.select_business_profile("day1")
	state.set_flag("test.open")
	var inventory := state.get_warehouse_inventory()
	var journal := TaskJournal.new()
	journal.configure(catalog, state)
	var delivery := TaskDelivery.new()
	check(delivery.configure(catalog, journal, state, inventory) == OK, "Configure same-customer orders")
	var board := OrderBoardModel.new()
	board.configure(catalog, journal, state, inventory, state.get_tea_production(), delivery)
	for id: String in ["first", "preferred", "locked", "materials"]:
		check(delivery.accept_order(id) == OK, "Explicitly accept scenario " + id)
	check(board.get_entry("locked").stage == "recipe_locked" and not board.get_entry("locked").can_craft, "Locked recipe explains why crafting is unavailable")
	check(board.get_entry("materials").product_id.is_empty() and not board.get_entry("materials").can_craft, "Material commissions never offer crafting")
	var tea := inventory.get_stock("black_tea")
	inventory.try_consume({"black_tea": tea})
	check(board.get_entry("materials").stage == "collect" and board.get_entry("materials").missing.get("black_tea") == 2 and not board.get_entry("materials").missing_text.is_empty(), "Material orders report their exact remaining shortfall")
	inventory.add_ingredient("black_tea", tea)
	inventory.add_ingredient("day1_blood_milk_tea", 1)
	check(board.get_entry("locked").ready, "Existing product bypasses recipe lock for delivery")
	inventory.add_ingredient("pearl_milk_tea", 1)
	check(board.get_entry("first").ready and board.get_entry("preferred").ready, "One shared cup independently satisfies two orders without reservation")
	check(board.get_entry("first").remaining_to_craft == 1 and board.get_entry("preferred").can_craft, "Shared readiness leaves enough preparation capacity for every accepted order")
	state.set_variable(OrderBoardModel.TRACKED_KEY, "preferred")
	var snapshot := state.to_dict()
	state.set_variable(OrderBoardModel.TRACKED_KEY, "first")
	check(state.restore_state(snapshot) == OK and board.get_tracked_entry().order_id == "preferred", "Restoring a session recovers explicit tracking")
	var before := state.to_dict()
	check(not delivery.deliver_to("wrong_customer", "preferred").ok and state.to_dict() == before, "Wrong customer cannot consume shared stock")
	var syrup := inventory.get_stock("syrup")
	inventory.add_ingredient("syrup", WarehouseInventory.MAX_QUANTITY - syrup)
	before = state.to_dict()
	var rejected := delivery.deliver_to("fat_goblin", "preferred")
	check(not rejected.ok and "奖励库存已满" in rejected.message and state.to_dict() == before, "Capacity failure reports the reason and leaves the whole session unchanged")
	inventory.try_consume({"syrup": WarehouseInventory.MAX_QUANTITY - syrup})
	check(delivery.deliver_to("fat_goblin", "preferred").ok and board.get_entry("preferred").status == "completed", "Tracked ready order wins among same-customer orders")
	check(not board.get_entry("first").ready and board.get_entry("first").status == "active", "Delivery consumes shared cup and immediately updates the other order")
	check(board.get_tracked_entry().order_id in ["locked", "materials"], "Completion falls back to another ready order before an unprepared one")
	inventory.add_ingredient("pearl_milk_tea", 1)
	check(delivery.deliver_to("fat_goblin").ok and board.get_entry("first").status == "completed", "An earlier unaccepted order never blocks an accepted one")
	check(board.get_entry("unaccepted").status == "available", "Delivery never implicitly accepts the skipped order")
	board.free()
	delivery.free()
	journal.free()
	state.free()
