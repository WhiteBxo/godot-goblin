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
	var snapshot := state.to_dict()
	board.refresh()
	check(state.to_dict() == snapshot, "Reading the board never accepts orders or writes facts")
	for id: String in ["day1_group_c", "day1_group_a", "day1_group_b"]:
		check(delivery.accept_order(id) == OK, "Explicitly accept " + id)
	check(delivery.accept_order("day1_group_c") == ERR_ALREADY_EXISTS, "Repeated acceptance is a no-op")
	state.set_variable(OrderBoardModel.TRACKED_KEY, "day1_group_c")
	check(board.get_tracked_entry().order_id == "day1_group_c", "Manual tracking takes priority")
	for id: String in ["day1_group_c", "day1_group_a", "day1_group_b"]:
		var entry := board.get_entry(id)
		check(entry.can_craft, "Any accepted group order can be prepared")
		check(production.craft(entry.recipe_materials).ok, "Craft out of queue order: " + id)
		check(board.get_entry(id).ready, "Readiness follows actual inventory")
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
	inventory.add_ingredient("plain_milk_tea", 1)
	check(board.get_entry("day1_group_a").ready, "Existing product is deliverable without crafting")
	inventory.try_consume({"plain_milk_tea": 1})
	check(not board.get_entry("day1_group_a").ready, "Consuming shared stock immediately clears readiness")
	var amount := inventory.get_stock("syrup")
	inventory.try_consume({"syrup": amount})
	check(board.get_entry("day1_group_a").stage == "missing_materials" and not board.get_entry("day1_group_a").can_craft, "Shortage disables order crafting")
	var copy := board.get_entries()
	copy[0].items.clear()
	check(not board.get_entries()[0].items.is_empty(), "Queries return detached nested snapshots")
	board.free()
	delivery.free()
	journal.free()
	state.free()
	print("ORDER_BOARD: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
