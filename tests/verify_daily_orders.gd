extends SceneTree
## Daily orders are ordinary play, not story beats: they unlock in the isolated teaching pool and each one settles 10G through the real delivery path.

const StateData = preload("res://src/core/game_state.gd")

var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	var host := Node2D.new()
	root.add_child(host)
	var state := StateData.new()
	_check(state.select_business_profile("day1") == OK, "Daily orders run on the Day 1 profile")
	host.add_child(state)
	var catalog := TaskCatalog.new()
	var loaded := catalog.load_files(Day1ChapterController.TASK_FILES, {"locations": RpgWorldMapData.location_ids()})
	_check(loaded == OK, "Catalog loads the story files and the daily pool: " + catalog.last_error)
	if loaded != OK:
		quit(1)
		return
	var journal := TaskJournal.new()
	host.add_child(journal)
	_check(journal.configure(catalog, state) == OK, "Journal projects the daily pool")
	var inventory := state.get_warehouse_inventory()
	var delivery := TaskDelivery.new()
	host.add_child(delivery)
	_check(delivery.configure(catalog, journal, state, inventory) == OK, "Delivery accepts the daily pool")

	var ids: Array[String] = ["day1_daily_tea_a", "day1_daily_tea_b", "day1_daily_tea_c"]
	for id: String in ids:
		_check(delivery.get_requirement(id).size() == 1, "Daily order " + id + " names one product")
		_check(not delivery.can_accept_order(id), "Daily order " + id + " stays closed before the story batch settles")

	state.set_flag("day1.group_settled")
	for id: String in ids:
		_check(not delivery.can_accept_order(id), "Teaching pool stays absent from the formal chapter")
	state.set_flag("debug.teaching_orders")
	for id: String in ids:
		_check(delivery.can_accept_order(id), "Daily order " + id + " opens after the story batch settles")

	_check(delivery.accept_order("day1_daily_tea_a") == OK, "Accepting a daily order sets its own flag")
	_check(not delivery.can_accept_order("day1_daily_tea_a"), "An accepted order cannot be accepted twice")
	_check(delivery.can_accept_order("day1_daily_tea_b"), "Accepting one order leaves its siblings open")

	var balance_before := state.get_transactions().get_balance()
	_check(delivery.try_submit("day1_daily_tea_a", "goblin_a").ok == false, "An empty shelf cannot settle")
	_check(state.get_transactions().get_balance() == balance_before, "A rejected delivery leaves the balance untouched")

	_check(inventory.add_ingredient("pearl_milk_tea", 1), "Stock one plain milk tea")
	var result := delivery.try_submit("day1_daily_tea_a", "goblin_a")
	_check(result.ok, "Delivering a made drink settles the order")
	_check(state.get_transactions().get_balance() - balance_before == 10, "A daily order pays exactly 10G")
	_check(inventory.get_stock("pearl_milk_tea") == 0, "Settlement consumes the drink")
	_check(not delivery.can_accept_order("day1_daily_tea_a"), "A settled daily order closes")
	_check(delivery.try_submit("day1_daily_tea_a", "goblin_a").ok == false, "A settled order cannot be delivered twice")

	_check(inventory.add_ingredient("coconut_milk_tea", 1), "Stock one coconut jasmine tea")
	_check(delivery.accept_order("day1_daily_tea_b") == OK, "The second daily order is independent")
	_check(delivery.try_submit("day1_daily_tea_b", "goblin_b").ok, "The second daily order settles")
	_check(state.get_transactions().get_balance() - balance_before == 20, "Two daily orders pay 20G in total")

	var board := OrderBoardModel.new()
	host.add_child(board)
	board.configure(catalog, journal, state, inventory, state.get_tea_production(), delivery)
	var tracked := board.get_entry("day1_daily_tea_c")
	_check(not tracked.is_empty() and tracked.status == "available", "The order board lists the remaining daily order")
	_check(tracked.rewards == "10G", "The order board shows the real reward text")

	print("DAILY_ORDERS: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
