extends SceneTree
## Deterministic errand timing, isolated escrow, real handoff and deadlines.
const StateData = preload("res://src/core/game_state.gd")
var checks := 0
var failures: Array[String] = []
var state: Node
var service: Day2Procurement
var delivery: TaskDelivery

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func setup() -> void:
	if is_instance_valid(state):
		state.free()
	state = StateData.new(load("res://src/resources/milk_tea/day1_menu.tres"))
	root.add_child(state)
	state.select_business_profile("day1")
	DayPhase.advance_to(state, 1, "night")
	DayPhase.advance_to(state, 2, "day")
	state.set_story_stage("day2.s01")
	service = Day2Procurement.new()
	state.add_child(service)
	service.configure(state)
	var catalog := TaskCatalog.new()
	check(catalog.load_json(FileAccess.get_file_as_string("res://src/resources/tasks/day2_stages_01_05.json"), {"locations": RpgWorldMapData.location_ids()}) == OK, "Load real Day2/3 tasks with map locations")
	var journal := TaskJournal.new()
	state.add_child(journal)
	check(journal.configure(catalog, state) == OK, "Bind real task journal")
	delivery = TaskDelivery.new()
	state.add_child(delivery)
	check(delivery.configure(catalog, journal, state, state.get_warehouse_inventory()) == OK, "Bind actual task handoff")
	check(service.fund() == OK, "Receive 35G procurement escrow")
	check(service.fund() == ERR_ALREADY_EXISTS and state.get_transactions().get_balance() == 0, "Funding replay never credits the ordinary wallet")

func advance(day: int, phase: String) -> void:
	check(DayPhase.advance_to(state, day, phase) == OK, "Advance to %d/%s" % [day, phase])
	service.refresh()
	check(state.validate_snapshot(state.to_dict()) == OK, "Procurement snapshot validates at each boundary")

func _run() -> void:
	setup()
	var funded: Dictionary = state.to_dict()
	check(service.hire("day2_festival_0") != OK and state.to_dict() == funded, "Story guest cannot be hired")
	check(service.hire("day2_ordinary_b") == OK, "Hire exactly one ordinary visitor on Day2")
	check(service.hire("day2_ordinary_a") != OK, "Cannot hire a second runner")
	advance(2, "night")
	check(state.get_flag("day3.procurement.returned") and state.get_warehouse_inventory().get_uses("insomnia_mushroom") == 5, "Day2 hire returns the same night before the signature rescue cutoff")
	advance(3, "day")
	check(state.get_warehouse_inventory().get_stock("insomnia_mushroom") == 1, "The returned portion remains available on Day3 morning")
	check(service.get_status().purchase == 30 and service.get_status().fee == 5 and service.get_status().escrow == 0, "Spend 30G plus 5G from escrow only")
	var returned: Dictionary = state.to_dict()
	service.refresh()
	check(state.to_dict() == returned and state.get_transactions().get_balance() == 0, "Return cannot duplicate stock or wallet income")
	check(not delivery.try_submit("day3_procurement", "tavern").ok and state.to_dict() == returned, "Wrong recipient preserves the actual portion")
	check(delivery.try_submit("day3_procurement", "fat_goblin").ok, "Deliver the returned portion to fat goblin")
	# Advance before the deferred scene refresh to protect this real timing edge.
	DayPhase.advance_to(state, 3, "night")
	DayPhase.advance_to(state, 4, "day")
	service.refresh()
	check(service.get_status().status == "delivered" and state.get_warehouse_inventory().get_stock("insomnia_mushroom") == 0, "A valid last-day handoff remains delivered when the day changes")
	check(service.get_status().escrow == 0 and service.get_status().purchase == 30 and service.get_status().fee == 5, "Delivery keeps the settlement written when the runner returned")
	check(state.validate_snapshot(state.to_dict()) == OK, "A delivered commission still writes a valid escrow")
	check(not delivery.try_submit("day3_procurement", "fat_goblin").ok, "Handoff cannot repeat")
	setup()
	advance(2, "night")
	advance(3, "day")
	check(service.hire("day2_ordinary_c") == OK, "Late hire is allowed on Day3")
	service.refresh()
	check(not state.get_flag("day3.procurement.returned"), "Day3 hire waits for evening")
	advance(3, "night")
	check(state.get_warehouse_inventory().get_stock("insomnia_mushroom") == 1, "Late runner deterministically returns on Day3 evening")
	advance(4, "day")
	check(service.get_status().status == "expired" and not delivery.try_submit("day3_procurement", "fat_goblin").ok, "Undelivered commission expires entering Day4")
	setup()
	advance(2, "night")
	advance(3, "day")
	advance(3, "night")
	advance(4, "day")
	check(service.get_status().status == "expired" and service.get_status().refund == 35 and service.get_status().escrow == 0, "Unspent escrow is refunded to the client on expiry")
	check(state.get_transactions().get_balance() == 0, "Refund never becomes player income")
	var invalid: Dictionary = state.to_dict()
	invalid.variables[Day2Procurement.KEY].refund = 36
	check(state.restore_state(invalid) != OK, "Corrupt escrow cannot enter a restored session")
	setup()
	state.set_flag("day3.procurement.delivered")
	service.refresh()
	check(service.get_status().status == "funded" and service.get_status().escrow == 35, "A delivery flag cannot close a commission that never returned")
	check(state.validate_snapshot(state.to_dict()) == OK, "Rejecting an out-of-order delivery keeps the variable legal")
	state.free()
	print("DAY2_PROCUREMENT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
