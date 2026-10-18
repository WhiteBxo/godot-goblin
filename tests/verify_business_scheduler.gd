extends SceneTree

const StateData = preload("res://src/core/game_state.gd")
const Scheduler = preload("res://src/gameplay/milk_tea/business_scheduler.gd")
const Visit = preload("res://src/gameplay/milk_tea/customer_visit.gd")
const ACTOR = preload("res://src/debug/actors/demo_actor.tscn")

## Test-only persistence adapter. Production must use A's guarded atomic interface.
class TestStore extends RefCounted:
	var value: Dictionary = {}
	var reject := false
	var writes := 0
	func read(_id: String) -> Dictionary:
		return value.duplicate(true)
	func commit(_id: String, expected: Dictionary, next: Dictionary) -> Error:
		if reject:
			return ERR_BUSY
		var current := value if not value.is_empty() else {"version": 1, "published_stages": [], "groups": {}, "closed": false}
		if expected != current:
			return ERR_BUSY
		value = next.duplicate(true)
		writes += 1
		return OK

var _checks := 0
var _failures: Array[String] = []
var _host: Node2D
var _state: StateData
var _delivery: TaskDelivery
var _board: OrderBoardModel
var _store: TestStore
var _scheduler: BusinessScheduler
var _plan: Dictionary
var _served: Array[String] = []
var _completed: Array[String] = []
var _transitions: Array[String] = []
var _fail_moves: Array[String] = []
var _reentry: Array[int] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)
		push_error(message)

func _frames(count: int = 3) -> void:
	for index in range(count):
		await physics_frame
	await process_frame

func _new_session() -> void:
	_host = Node2D.new()
	root.add_child(_host)
	_state = StateData.new()
	check(_state.select_business_profile("day1") == OK, "Use existing recipe/inventory profile")
	_host.add_child(_state)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/resources/tasks/day1_stages_01_02.json"))
	var template: Dictionary = data.tasks[0].duplicate(true)
	data.tasks.clear()
	var story_customers: Array = []
	for index in range(5):
		var id := "visit_%d" % index
		var task := template.duplicate(true)
		task.id = "test." + id
		task.erase("reveal_when")
		task.activate_when.key = "test.open"
		task.complete_when.key = "test." + id + ".done"
		task.objectives = [{"id": "deliver", "text": "交付", "complete_when": task.complete_when.duplicate(true)}]
		task.delivery.order_id = id
		task.delivery.target_object_id = id
		task.delivery.accepted_flag = "test." + id + ".accepted"
		data.tasks.append(task)
		if index > 0:
			story_customers.append({"id": id, "actor_ids": [id], "order_ids": [id]})
	# One fixture group has two orders: a partial delivery must not release it.
	var extra: Dictionary = data.tasks.back().duplicate(true)
	extra.id = "test.visit_4_extra"
	extra.complete_when.key = "test.visit_4_extra.done"
	extra.objectives = [{"id": "deliver", "text": "交付", "complete_when": extra.complete_when.duplicate(true)}]
	extra.delivery.order_id = "visit_4_extra"
	extra.delivery.accepted_flag = "test.visit_4_extra.accepted"
	data.tasks.append(extra)
	story_customers.back().order_ids.append("visit_4_extra")
	var catalog := TaskCatalog.new()
	check(catalog.load_json(JSON.stringify(data)) == OK, "Fixture reuses formal order requirement/reward")
	var journal := TaskJournal.new()
	_host.add_child(journal)
	check(journal.configure(catalog, _state) == OK, "Bind fixture catalog")
	_delivery = TaskDelivery.new()
	_host.add_child(_delivery)
	check(_delivery.configure(catalog, journal, _state, _state.get_warehouse_inventory()) == OK, "Use actual atomic delivery")
	_board = OrderBoardModel.new()
	_host.add_child(_board)
	_board.configure(catalog, journal, _state, _state.get_warehouse_inventory(), _state.get_tea_production(), _delivery)
	_state.set_flag("test.open")
	_plan = {"session_id": "test.day2", "stages": [
		{"id": "ordinary", "ordinary_customers": [{"id": "visit_0", "actor_ids": ["visit_0"], "order_ids": ["visit_0"]}]},
		{"id": "fixed", "story_customers": story_customers}]}
	_store = TestStore.new()
	_scheduler = Scheduler.new()
	_host.add_child(_scheduler)
	check(_scheduler.configure(_plan, _state, _delivery, _store.read, _store.commit) == OK, "Configure independent scheduler")
	_watch()

func _watch() -> void:
	_scheduler.group_served.connect(func(id: String) -> void: _served.append(id))
	_scheduler.business_completed.connect(func(id: String) -> void: _completed.append(id))
	_scheduler.customer_transition.connect(func(id: String, status: String) -> void: _transitions.append(id + ":" + status))

func _craft_and_deliver(id: String) -> void:
	var entry := _board.get_entry(id)
	check(entry.get("can_craft", false), "Accepted published order enables existing crafting consumer: " + id)
	if entry.is_empty():
		return
	check(_state.get_tea_production().craft(entry.recipe_materials).ok, "Existing production puts cup into shared inventory")
	check(not _scheduler.is_group_served(id), "Crafting is not customer service completion")
	var snapshot := _state.to_dict()
	check(not _delivery.try_submit(id, "wrong").ok and _state.to_dict() == snapshot, "Wrong recipient changes no state")
	check(_delivery.try_submit(id, entry.target_id).ok, "Atomic delivery completes service")
	var paid := _state.to_dict()
	check(not _delivery.try_submit(id, entry.target_id).ok and paid == _state.to_dict(), "Duplicate delivery cannot consume or collect again")

func _run() -> void:
	_new_session()
	check(_board.get_entries().is_empty(), "Unpublished stages hidden even when chapter gate is open")
	check(_delivery.accept_order("visit_0") == ERR_UNAVAILABLE, "Canonical acceptance obeys publication")
	check(not _delivery.try_submit("visit_0", "visit_0").ok, "Canonical delivery obeys publication")
	_store.reject = true
	check(_scheduler.publish_stage("ordinary") == ERR_BUSY and _transitions.is_empty() and _store.value.is_empty(), "Rejected persistence produces no arrival or stage facts")
	_store.reject = false
	check(_scheduler.publish_stage("ordinary") == OK, "Publish ordinary customers with one snapshot commit")
	var writes := _store.writes
	check(_scheduler.publish_stage("ordinary") == OK and _store.writes == writes, "Publishing a stage twice is idempotent")
	check(_scheduler.get_group("visit_0").status == "entering" and _board.get_entries().is_empty(), "Entering customers cannot yet accept orders")
	check(_scheduler.confirm_arrival("visit_0") == OK, "Actual arrival acknowledgement enables service")
	check(_board.get_entries().size() == 1, "Board refresh follows gate changes")
	check(_delivery.accept_order("visit_0") == OK, "Order board acceptance reuses TaskDelivery")
	check(_scheduler.request_departure("visit_0") == ERR_UNAVAILABLE, "Cannot release a customer before real delivery")
	_craft_and_deliver("visit_0")
	check(_served.is_empty(), "Delivery notification does not write during atomic settlement")
	await _frames()
	check(_served == ["visit_0"] and _scheduler.get_group("visit_0").status == "leaving", "Ordinary service emits once and requests departure after commit")
	check(_scheduler.confirm_departure("visit_0") == OK, "Real exit acknowledgement persists departure")
	check(_scheduler.request_arrival("visit_0") == ERR_ALREADY_EXISTS, "Departed customer cannot reappear")
	check(_scheduler.request_close() == ERR_UNAVAILABLE and _completed.is_empty(), "Missing A close authority stays pending")
	check(_scheduler.publish_stage("fixed") == OK, "Publish fixed stage separately")
	check(_scheduler.get_group("visit_1").status == "dormant", "Publishing fixed customers does not trigger story timing")
	for index in range(1, 5):
		var id := "visit_%d" % index
		check(_scheduler.request_arrival(id) == OK and _scheduler.confirm_arrival(id) == OK, "Fixed group arrival interface: " + id)
		check(_delivery.accept_order(id) == OK, "Fixed group uses existing acceptance")
		_craft_and_deliver(id)
		await _frames()
		if index == 4:
			check(not _scheduler.is_group_served(id) and _scheduler.request_departure(id) == ERR_UNAVAILABLE, "Partial group delivery cannot satisfy the story wait")
			check(_delivery.accept_order("visit_4_extra") == OK, "Accept group's remaining order")
			_craft_and_deliver("visit_4_extra")
			await _frames()
		check(_scheduler.is_group_served(id) and _scheduler.get_group(id).status == "waiting", "Story group can wait for receipts and keep its dialogue turn")
		check(_scheduler.request_departure(id) == OK and _scheduler.confirm_departure(id) == OK, "Fixed group release and exit interface: " + id)
	check(_scheduler.get_progress().orders_completed == 6 and _scheduler.get_progress().groups_departed == 5, "Progress derives from actual receipts and departures")
	check(_completed.is_empty() and not _scheduler.get_progress().closed, "Serving all configured orders does not invent a close rule")
	await _test_reconstruction()
	await _test_validation()
	_host.queue_free()
	await _frames()
	_new_session()
	await _test_visit()
	_host.queue_free()
	await _frames()
	_new_session()
	await _test_receipt_gap()
	_host.queue_free()
	await _frames()
	_test_formal_five()
	print("BUSINESS_SCHEDULER: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_reconstruction() -> void:
	var facts := _state.to_dict()
	var durable := _store.value.duplicate(true)
	var event_count := _transitions.size()
	var served_count := _served.size()
	_scheduler.free()
	check(not _delivery.is_order_available("visit_1"), "Freed availability owner fails closed")
	_scheduler = Scheduler.new()
	_host.add_child(_scheduler)
	check(_scheduler.configure(_plan, _state, _delivery, _store.read, _store.commit, _store.commit) == OK, "Rebuild from same durable store and same shared services")
	_watch()
	_scheduler.refresh()
	await _frames()
	check(_transitions.size() == event_count and _served.size() == served_count and _completed.is_empty(), "Rebuild does not replay visit/service/close events")
	check(_state.to_dict() == facts and _store.value == durable, "Rebuild does not regenerate delivery, income or persistence")
	check(_scheduler.request_close() == OK and _completed == ["test.day2"], "Injected test close authority persists explicit completion")
	var writes := _store.writes
	check(_scheduler.request_close() == OK and _completed.size() == 1 and writes == _store.writes, "Close is idempotent")
	check(_scheduler.publish_stage("missing") == ERR_DOES_NOT_EXIST, "Unknown stage rejected")
	check(_scheduler.request_arrival("missing") == ERR_DOES_NOT_EXIST, "Unknown fixed group rejected")
	check(_state.restore_state(facts) == OK, "Restore real session snapshot")
	_store.value = durable
	_state.state_restored.emit()
	await _frames()
	check(_completed.size() == 1 and _transitions.size() == event_count, "Restore projects facts without live event replay")
	var copy := _scheduler.get_group("visit_1")
	copy.actor_ids.clear()
	check(not _scheduler.get_group("visit_1").actor_ids.is_empty(), "Nested configuration snapshots are isolated")

func _test_validation() -> void:
	var invalid_plan := _plan.duplicate(true)
	invalid_plan.stages[1].story_customers[0].order_ids = ["missing"]
	var detached := Scheduler.new()
	check(detached.configure(invalid_plan, _state, _delivery) == ERR_INVALID_DATA, "Unknown order cannot configure a business")
	detached.free()
	var durable := _store.value.duplicate(true)
	_store.value.groups.visit_1 = "invented"
	check(not _scheduler.is_order_available("visit_1") and _scheduler.publish_stage("ordinary") == ERR_UNAVAILABLE, "Invalid persistent state fails closed")
	_store.value = durable
	# No production adapter is installed by this test; test missing callbacks explicitly.
	var empty := Scheduler.new()
	var separate_delivery := TaskDelivery.new()
	check(empty.configure(_plan, _state, separate_delivery) == ERR_INVALID_DATA, "Unconfigured delivery catalog is rejected")
	empty.free()
	separate_delivery.free()

func _test_visit() -> void:
	var entities := Node2D.new()
	_host.add_child(entities)
	var director := ActorDirector.new()
	_host.add_child(director)
	director.configure(entities)
	var visit := Visit.new()
	_host.add_child(visit)
	visit.movement_failed.connect(func(_id: String, reason: String) -> void: _fail_moves.append(reason))
	var members: Array[Dictionary] = [{"actor_id": "visit_0", "scene": ACTOR,
		"entry": Vector2(0, 100), "waiting": Vector2(40, 100), "exit": Vector2(0, 100),
		"arrival_route": [Vector2(20, 100)], "departure_route": [Vector2(20, 100)], "speed": 120.0}]
	check(visit.configure(_scheduler, director, "visit_0", members) == OK, "Bind real ActorDirector adapter")
	await _frames()
	check(entities.get_child_count() == 0, "Dormant customers are not spawned")
	check(_scheduler.publish_stage("ordinary") == OK, "Publish real moving ordinary customer")
	for index in range(100):
		if _scheduler.get_group("visit_0").status == "waiting":
			break
		await _frames(1)
	check(_scheduler.get_group("visit_0").status == "waiting" and _fail_moves.is_empty(), "Actual route arrival acknowledges service readiness")
	var actor := director.get_actor(&"visit_0")
	check(actor != null and actor.visible and actor.collision_layer == 4 and actor.global_position.distance_to(Vector2(40, 100)) < 0.6, "Present NPC occupies the existing NPC layer at its configured wait point")
	_scheduler.refresh()
	await _frames()
	check(entities.get_child_count() == 1 and director.get_actor(&"visit_0") == actor, "Refresh never creates a duplicate actor")
	check(_delivery.accept_order("visit_0") == OK, "Accept moving customer's order")
	_craft_and_deliver("visit_0")
	await _frames(2)
	check(actor.visible and actor.global_position.x > 0.5 and _scheduler.get_group("visit_0").status == "leaving", "Live departure follows its route instead of snapping to a recovery boundary")
	for index in range(100):
		if _scheduler.get_group("visit_0").status == "departed":
			break
		await _frames(1)
	check(_scheduler.get_group("visit_0").status == "departed" and not actor.visible and actor.collision_layer == 0, "Actual departure hides the customer and removes NPC collision")
	visit.free()
	visit = Visit.new()
	_host.add_child(visit)
	check(visit.configure(_scheduler, director, "visit_0", members) == OK, "Reconstruct visual adapter after completed visit")
	await _frames()
	check(entities.get_child_count() == 1 and not actor.visible, "Departed visit rebuild remains hidden without respawn")
	visit.free()
	await _test_mid_visit_restore(director, entities)
	await _test_blocked_route(director, entities)
	await _test_missing_and_reentrant_adapter()

func _test_mid_visit_restore(director: ActorDirector, entities: Node2D) -> void:
	check(_scheduler.publish_stage("fixed") == OK and _scheduler.request_arrival("visit_1") == OK, "Persist entering state before rebuilding visual component")
	var members: Array[Dictionary] = [{"actor_id": "visit_1", "scene": ACTOR,
		"entry": Vector2(0, 200), "waiting": Vector2(60, 200), "exit": Vector2(0, 200)}]
	var visit := Visit.new()
	_host.add_child(visit)
	check(visit.configure(_scheduler, director, "visit_1", members) == OK, "Restore entering boundary from authoritative snapshot")
	await _frames(8)
	var actor := director.get_actor(&"visit_1")
	check(_scheduler.get_group("visit_1").status == "waiting" and actor.global_position.distance_to(Vector2(60, 200)) < 0.6, "Recovered entry projects to wait boundary without replaying arrival route")
	visit.free()
	var count := entities.get_child_count()
	visit = Visit.new()
	_host.add_child(visit)
	check(visit.configure(_scheduler, director, "visit_1", members) == OK, "Rebind waiting group")
	await _frames(5)
	check(entities.get_child_count() == count and director.get_actor(&"visit_1") == actor, "Waiting group rebind reuses its stable registered actor")
	check(_delivery.accept_order("visit_1") == OK, "Accept restored customer order")
	_craft_and_deliver("visit_1")
	await _frames()
	visit.free()
	check(_scheduler.request_departure("visit_1") == OK, "Persist leaving while no visual adapter is attached")
	var event_count := _transitions.size()
	var income := _state.get_transactions().get_balance()
	visit = Visit.new()
	_host.add_child(visit)
	check(visit.configure(_scheduler, director, "visit_1", members) == OK, "Restore leaving boundary")
	await _frames(8)
	check(_scheduler.get_group("visit_1").status == "departed" and not actor.visible and _state.get_transactions().get_balance() == income, "Leaving restore hides once and never collects another payment")
	check(_transitions.size() == event_count + 1 and _transitions.back() == "visit_1:departed", "Recovery acknowledges real projection without replaying entering/leaving requests")
	# Restoring a snapshot during movement cancels the old action handle.
	check(_scheduler.request_arrival("visit_2") == OK, "Prepare in-flight restore scenario")
	var next_members: Array[Dictionary] = [{"actor_id": "visit_2", "scene": ACTOR,
		"entry": Vector2(0, 300), "waiting": Vector2(80, 300), "exit": Vector2(0, 300), "speed": 30.0}]
	var active := Visit.new()
	_host.add_child(active)
	# Adapter sees an existing entering state, so start with a clean dormant boundary.
	_store.value.groups.erase("visit_2")
	check(active.configure(_scheduler, director, "visit_2", next_members) == OK, "Bind next fixed customer's adapter")
	await _frames()
	check(_scheduler.request_arrival("visit_2") == OK, "Begin live entry to interrupt")
	await _frames(4)
	var snapshot := _state.to_dict()
	check(director.is_actor_controlled(&"visit_2"), "Customer is moving before restoration")
	check(_state.restore_state(snapshot) == OK, "Identical state restore remains supported")
	# Test adapter is external; notify a complete replacement after restoring its value.
	_state.state_restored.emit()
	await _frames(10)
	check(_scheduler.get_group("visit_2").status == "waiting" and not director.is_actor_controlled(&"visit_2"), "Restore cancels old motion before projecting wait boundary")
	check(_fail_moves.is_empty(), "Successful restore does not report cancellation as a route failure")
	active.free()
	visit.free()

func _test_blocked_route(director: ActorDirector, _entities: Node2D) -> void:
	var obstacle := StaticBody2D.new()
	obstacle.position = Vector2(24, 400)
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(8, 80)
	collision.shape = rectangle
	obstacle.add_child(collision)
	_host.add_child(obstacle)
	director.blocked_timeout = 0.05
	var members: Array[Dictionary] = [{"actor_id": "visit_3", "scene": ACTOR,
		"entry": Vector2(0, 400), "waiting": Vector2(60, 400), "exit": Vector2(0, 400), "timeout": 0.5}]
	var visit := Visit.new()
	_host.add_child(visit)
	visit.movement_failed.connect(func(_id: String, reason: String) -> void: _fail_moves.append(reason))
	check(visit.configure(_scheduler, director, "visit_3", members) == OK, "Bind customer with intentionally blocked fixture route")
	await _frames()
	check(_scheduler.request_arrival("visit_3") == OK, "Start blocked entry")
	for index in range(80):
		if not _fail_moves.is_empty():
			break
		await _frames(1)
	check(not _fail_moves.is_empty() and _scheduler.get_group("visit_3").status == "entering", "Blocked route reports failure and never acknowledges arrival")
	check(_delivery.accept_order("visit_3") == ERR_UNAVAILABLE, "Blocked customer cannot accept an order")
	obstacle.queue_free()
	await _frames()
	_fail_moves.clear()
	visit.retry()
	await _frames(2)
	check(_scheduler.get_group("visit_3").status == "entering", "Retry continues real movement instead of silently completing arrival")
	for index in range(100):
		if _scheduler.get_group("visit_3").status == "waiting":
			break
		await _frames(1)
	check(_scheduler.get_group("visit_3").status == "waiting" and _fail_moves.is_empty(), "Cleared route retries without duplicating the visit")
	visit.free()

func _test_missing_and_reentrant_adapter() -> void:
	_scheduler.free()
	_scheduler = Scheduler.new()
	_host.add_child(_scheduler)
	check(_scheduler.configure(_plan, _state, _delivery) == OK, "Component can be assembled while shared persistence is pending")
	check(_scheduler.publish_stage("ordinary") == ERR_UNAVAILABLE and _scheduler.request_close() == ERR_UNAVAILABLE and _board.get_entries().all(func(entry: Dictionary) -> bool: return entry.status == "completed"), "Missing shared callbacks refuse writes and hide unfinished orders")
	_scheduler.free()
	_scheduler = Scheduler.new()
	_host.add_child(_scheduler)
	_store.value = {}
	var false_ack := func(_id: String, _expected: Dictionary, _next: Dictionary) -> Error: return OK
	check(_scheduler.configure(_plan, _state, _delivery, _store.read, _store.commit, false_ack) == OK, "Rebind injectable shared adapter")
	_scheduler.stage_published.connect(func(_id: String) -> void: _reentry.append(_scheduler.publish_stage("fixed")))
	check(_scheduler.publish_stage("ordinary") == OK and _reentry == [ERR_BUSY], "Synchronous subscribers cannot write a second business transition")
	check(_store.value.published_stages == ["ordinary"], "Reentrant publication leaves the complete committed snapshot intact")
	check(_scheduler.request_close() == ERR_INVALID_DATA and not _store.value.closed, "Uncommitted close callback cannot announce business completion")
	check(_scheduler.confirm_arrival("visit_0") == OK and _delivery.is_order_available("visit_0"), "Ready scene owns its availability gate")
	_host.remove_child(_scheduler)
	check(not _delivery.is_order_available("visit_0") and _scheduler.publish_stage("fixed") == ERR_UNAVAILABLE, "Leaving the tree immediately closes the gate and refuses writes")
	_host.add_child(_scheduler)

func _test_receipt_gap() -> void:
	check(_scheduler.publish_stage("ordinary") == OK and _scheduler.confirm_arrival("visit_0") == OK, "Prepare customer for receipt/scene-exit boundary")
	check(_delivery.accept_order("visit_0") == OK, "Accept gap scenario order")
	_craft_and_deliver("visit_0")
	var income := _state.get_transactions().get_balance()
	var served_count := _served.size()
	check(_store.value.groups.visit_0 == "waiting", "Delivery receipt is durable before deferred exit commit")
	_scheduler.free()
	_scheduler = Scheduler.new()
	_host.add_child(_scheduler)
	check(_scheduler.configure(_plan, _state, _delivery, _store.read, _store.commit) == OK, "Rebuild when scene exited between receipt and departure")
	_watch()
	await _frames()
	check(_scheduler.get_group("visit_0").status == "leaving" and _served.size() == served_count, "Receipt gap recovers exit projection without replaying served event")
	check(_scheduler.confirm_departure("visit_0") == OK and _scheduler.request_arrival("visit_0") == ERR_ALREADY_EXISTS, "Recovered customer can finish exit but cannot regenerate")
	check(_state.get_transactions().get_balance() == income and not _delivery.try_submit("visit_0", "visit_0").ok, "Receipt gap never collects twice")

func _test_formal_five() -> void:
	var state := StateData.new()
	state.select_business_profile("day1")
	var catalog := TaskCatalog.new()
	check(catalog.load_file("res://src/resources/tasks/day1_stages_01_02.json") == OK, "Load unchanged formal Day 1 catalog")
	var journal := TaskJournal.new()
	journal.configure(catalog, state)
	var delivery := TaskDelivery.new()
	check(delivery.configure(catalog, journal, state, state.get_warehouse_inventory()) == OK, "Legacy flow configures without scheduler")
	var setup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/resources/story/day1_stages_01_02_setup.json"))
	var batches: Array[Dictionary] = []
	batches.assign(setup.batches)
	delivery.configure_batches(batches)
	var inventory := state.get_warehouse_inventory()
	for flag: String in ["day1.human_open", "day1.goblin_open", "day1.group_open"]:
		state.set_flag(flag)
	for id: String in ["day1_human", "day1_goblin", "day1_group_c", "day1_group_a", "day1_group_b"]:
		var order: Dictionary = {}
		for candidate: Dictionary in delivery.get_orders():
			if candidate.order_id == id:
				order = candidate
		check(delivery.accept_order(id) == OK, "Legacy explicit acceptance preserved: " + id)
		var recipe := state.get_tea_production().get_recipe_by_product(order.product_id)
		check(state.get_tea_production().craft(recipe.materials).ok, "Legacy recipe still crafts: " + id)
		check(delivery.try_submit(id, order.target_object_id).ok, "Legacy five-order settlement preserved: " + id)
	check(delivery.get_completed_count() == 5 and state.get_transactions().get_balance() == 10 and inventory.get_stock("strange_coin") == 4 and state.get_flag("day1.group_settled"), "Five formal orders retain original money, coins and batch fact")
	delivery.free()
	journal.free()
	state.free()
