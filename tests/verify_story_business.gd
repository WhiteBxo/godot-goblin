extends SceneTree
## Business command layer only. Fixtures never stand in for formal Day 2 values:
## no prices, rewards, close rules or task IDs from the design drafts are used.

const StateData = preload("res://src/core/game_state.gd")
const Purchase = preload("res://src/core/economy/tavern_purchase.gd")
const Casino = preload("res://src/core/economy/fixed_story_casino.gd")
const Scheduler = preload("res://src/gameplay/milk_tea/business_scheduler.gd")
const EVENTS := "res://tests/fixtures/story_business_events.json"

var _checks := 0
var _failures: Array[String] = []
var _state: StateData
var _adapter: StoryBusinessAdapter

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames(count := 4) -> void:
	for index in range(count):
		await process_frame

func _until(predicate: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec() + 2000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(predicate.call(), message)

func _run() -> void:
	_state = root.get_node("GameState")
	var before := _state.to_dict()
	_test_library()
	_check(_state.start_new_game() == OK, "Explicit new game initializes the shared session")
	_adapter = StoryBusinessAdapter.new()
	_adapter.configure(_state, _unlock, func(location: String) -> bool: return SettlementMap.MAP_LOCATIONS.has(location))
	_test_unconfigured()
	_test_unlock()
	_test_purchase()
	_test_casino()
	_test_business()
	await _test_director()
	_check(_state.restore_state(before) == OK, "Restore the pre-test session")
	print("STORY_BUSINESS: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _unlock() -> Error:
	_state.set_flag("day1.s04.map_available")
	return OK if _state.get_flag("day1.s04.map_available") else ERR_BUSY

func _load_steps(steps: Array) -> Error:
	var library := StoryLibrary.new()
	return library.load_json(JSON.stringify({"version": 1, "events": {"test.lib": {"once": false, "steps": steps}}}))

func _test_library() -> void:
	_check(_load_steps([
		{"command": "unlock_map", "locations": ["settlement.tavern"]},
		{"command": "unlock_map", "locations": []},
		{"command": "tavern_purchase", "product_id": "griffin_amber_wine", "quantity": 1, "receipt": "test.lib.buy"},
		{"command": "casino_settle", "step": "first_loss"},
		{"command": "casino_settle", "step": "waive", "reason": "剧情免除"},
		{"command": "business", "action": "publish", "stage_id": "s1"},
		{"command": "business", "action": "request_arrival", "group_id": "human"},
		{"command": "business", "action": "close"}]) == OK, "Business commands pass the real Loader")
	for invalid: Dictionary in [
		{"command": "unlock_map", "locations": "settlement.tavern"},
		{"command": "unlock_map", "locations": ["tavern"]},
		{"command": "tavern_purchase", "product_id": "wine", "quantity": 0, "receipt": "test.lib.buy"},
		{"command": "tavern_purchase", "product_id": "wine", "quantity": 1.5, "receipt": "test.lib.buy"},
		{"command": "tavern_purchase", "product_id": "", "quantity": 1, "receipt": "test.lib.buy"},
		{"command": "tavern_purchase", "product_id": "wine", "quantity": 1, "receipt": "receipt"},
		{"command": "casino_settle", "step": "first_win"},
		{"command": "casino_settle", "step": "waive"},
		{"command": "business", "action": "open"},
		{"command": "business", "action": "publish"},
		{"command": "business", "action": "confirm_arrival"}]:
		_check(_load_steps([invalid]) == ERR_INVALID_DATA, "Invalid business step is rejected: " + JSON.stringify(invalid))

func _test_unconfigured() -> void:
	var empty := StoryBusinessAdapter.new()
	_check(not empty.unlock_map([]).ok, "Unbound map service refuses unlocking")
	_check(not empty.purchase("wine", 1, "test.empty.buy").ok, "Unbound tavern refuses purchases")
	_check(not empty.casino("first_loss", "").ok, "Unbound casino refuses settlement")
	_check(not empty.business("close", "", "").ok, "Unbound scheduler refuses closing")

func _test_unlock() -> void:
	_state.set_flag("day1.s04.map_available", false)
	var result := _adapter.unlock_map(["settlement.tavern"])
	_check(result.ok and _state.get_flag("day1.s04.map_available"), "Map unlock publishes the real availability fact")
	_check(_state.get_flag("ui.map.known.settlement.tavern"), "Unlock publishes the authored region knowledge")
	var known := _adapter.unlock_map(["settlement.nowhere"])
	_check(not known.ok and known.code == "unknown_location" and not _state.get_flag("ui.map.known.settlement.nowhere"), "Unknown regions are rejected without writing knowledge")
	_check(_adapter.unlock_map(["settlement.tavern"]).ok, "Repeated unlock stays idempotent")

func _offers() -> Dictionary:
	return {"test_wine": {"item_id": "griffin_amber_wine", "price": 10, "discounted_price": 8, "stock": 2},
		"test_tea": {"item_id": "black_tea", "price": 3}}

func _test_purchase() -> void:
	var menu: TeaMenu = WarehouseInventory.CATALOG.duplicate(true)
	menu.initial_balance = 12
	menu.products = Purchase.compile_products(_offers()).products
	var wallet := WalletTransactions.new(menu)
	var tavern := Purchase.new()
	root.add_child(tavern)
	_check(tavern.configure(wallet, _offers()) == OK, "Real tavern purchase binds the session wallet")
	_adapter.set_tavern(tavern)
	var result := _adapter.purchase("test_wine", 1, "test.story.buy")
	_check(result.ok and wallet.get_balance() == 4 and wallet.get_inventory().get_stock("griffin_amber_wine") == 1, "Authored purchase charges and delivers real goods")
	_check(_state.get_flag("test.story.buy"), "Successful purchase projects the durable step fact")
	var replay := _adapter.purchase("test_wine", 1, "test.story.buy")
	_check(replay.ok and wallet.get_balance() == 4 and wallet.get_inventory().get_stock("griffin_amber_wine") == 1, "Settled receipt replays without a second charge")
	var poor := _adapter.purchase("test_wine", 1, "test.story.poor")
	_check(not poor.ok and poor.code == "insufficient_funds" and not _state.get_flag("test.story.poor"), "Refused purchase projects no fact")
	_check(not _adapter.purchase("missing", 1, "test.story.missing").ok, "Unconfigured product is refused")
	tavern.free()
	wallet.free()

func _task() -> Dictionary:
	return {"id": "story_test.debt", "type": "commission", "title": "命令层债务夹具", "description": "隔离配置，不代表正式债务。",
		"activate_when": {"type": "flag", "key": "story_test.debt_active"},
		"complete_when": {"type": "flag", "key": "story_test.debt_paid"}, "allow_cancel": true,
		"delivery": {"order_id": "test_debt", "items": {"black_tea": 1}, "target_object_id": "test_boss", "accepted_flag": "story_test.debt_accepted"},
		"objectives": [{"id": "pay", "text": "测试交付", "complete_when": {"type": "flag", "key": "story_test.debt_paid"}}]}

func _test_casino() -> void:
	var state := StateData.new()
	root.add_child(state)
	_check(state.select_business_profile("day1") == OK, "Casino fixture uses the shared profile")
	var catalog := TaskCatalog.new()
	_check(catalog.load_json(JSON.stringify({"version": 1, "tasks": [_task()]})) == OK, "Casino fixture passes the real task schema")
	_check(state.bind_task_catalog(catalog) == OK, "Casino fixture binds the catalog")
	var casino := Casino.new()
	root.add_child(casino)
	_check(casino.configure(state, catalog, {"debt_task_id": "story_test.debt", "loss_receipt": "story_test.first_loss",
		"win_receipt": "story_test.second_win", "reward_items": {"phantom_gold_mushroom": 2, "rainbow_cube": 1}}) == OK,
		"Casino accepts an explicit reward bundle")
	_adapter.set_casino(casino)
	_check(_adapter.casino("first_loss", "").ok and state.get_flag("story_test.first_loss"), "First authored round settles once")
	_check(_adapter.casino("first_loss", "").ok and state.get_flag("story_test.first_loss"), "Repeated first round replays as success")
	_check(_adapter.casino("second_win", "").ok and state.get_flag("story_test.second_win"), "Second authored round settles")
	_check(_adapter.casino("waive", "剧情免除").ok and state.get_task_result("story_test.debt").status == "cancelled", "Waiver uses the real cancellation result")
	_check(_adapter.casino("waive", "重复").ok, "Repeated waiver replays as success")
	_check(_adapter.casino("first_loss", "").ok, "Settled first round stays replay-safe after the waiver")
	casino.free()
	state.free()

const RULE := {"from": {"day": 1, "phase": "night"}, "to": {"day": 2, "phase": "day"},
	"required_stages": ["s1"], "served_groups": [], "departed_groups": [], "required_flags": [],
	"completed_flag": "story_test.closed"}

func _business_fixture(session_id: String, close_rule: Dictionary) -> BusinessScheduler:
	var host := Node.new()
	root.add_child(host)
	var state := StateData.new()
	host.add_child(state)
	_check(state.select_business_profile("day1") == OK, "Business fixture uses the shared profile")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/resources/tasks/day1_stages_01_02.json"))
	var catalog := TaskCatalog.new()
	_check(catalog.load_json(JSON.stringify(data)) == OK, "Business fixture loads the real order catalog")
	var journal := TaskJournal.new()
	host.add_child(journal)
	_check(journal.configure(catalog, state) == OK, "Business fixture binds the journal")
	var delivery := TaskDelivery.new()
	host.add_child(delivery)
	_check(delivery.configure(catalog, journal, state, state.get_warehouse_inventory()) == OK, "Business fixture uses the real delivery")
	var plan := {"session_id": session_id, "stages": [
		{"id": "s1", "ordinary_customers": [{"id": "human", "actor_ids": ["human_customer"], "order_ids": ["day1_human"]}]}]}
	var scheduler := Scheduler.new()
	host.add_child(scheduler)
	_check(scheduler.configure_session(plan, state, delivery, close_rule) == OK, "Business fixture binds the production adapters")
	_check(state.commit_day_phase("night"), "Fixture enters the authored source phase")
	scheduler.set_meta("state", state)
	return scheduler

func _test_business() -> void:
	var scheduler := _business_fixture("story_test.day1", RULE)
	var state: StateData = scheduler.get_meta("state")
	_adapter.set_business(scheduler)
	_check(_adapter.business("publish", "s1", "").ok, "Publication uses the real scheduler")
	_check(_adapter.business("publish", "s1", "").ok, "Repeated publication is idempotent")
	var closed := _adapter.business("close", "", "")
	_check(closed.ok and state.current_day == 2 and DayPhase.get_phase(state) == "day",
		"Closing commits the configured day boundary, not an invented one")
	_check(state.get_flag("story_test.closed"), "Closing publishes the authored completion fact")
	_check(_adapter.business("close", "", "").ok, "Repeated close stays idempotent")
	var pending := _business_fixture("story_test.pending", {})
	_adapter.set_business(pending)
	_check(pending.publish_stage("s1") == OK, "Session without close rules still publishes")
	var refused := _adapter.business("close", "", "")
	_check(not refused.ok and not refused.message.is_empty(), "Missing close rules keep closing pending")
	_adapter.set_business(scheduler)

func _test_director() -> void:
	var ui: DialogueUI = preload("res://src/UI/dialogue/dialogue_ui.tscn").instantiate()
	root.add_child(ui)
	var manager := DialogueManager.new()
	manager.name = "DialogueManager"
	root.add_child(manager)
	manager.configure(ui, Callable())
	_check(manager.is_inside_tree() and ui.is_inside_tree(), "Director fixture uses the real dialogue manager")
	var director := StoryDirector.new()
	root.add_child(director)
	director.configure(manager)
	director.set_business_adapter(_adapter)
	_check(director.load_events(EVENTS) == OK, "Business fixture events validate in the real Director")
	var finished: Array[Dictionary] = []
	director.event_finished.connect(func(id: String, ok: bool, reason: String) -> void:
		finished.append({"id": id, "ok": ok, "reason": reason}))
	_check(director.request_event("test.business.unlock") == OK, "Director starts the unlock sequence")
	await _until(func() -> bool: return not director.is_busy(), "Unlock sequence finishes")
	_check(finished.size() == 1 and finished[0].ok and _state.get_flag("test.business.unlock_done"),
		"Director continues past a successful business step")
	_check(_state.get_flag("ui.map.known.settlement.casino"), "Director unlock publishes the authored region")
	finished.clear()
	_check(director.request_event("test.business.purchase_unconfigured") == OK, "Director starts the refused purchase")
	await _until(func() -> bool: return not director.is_busy(), "Refused purchase finishes")
	_check(finished.size() == 1 and not finished[0].ok and "Business step" in finished[0].reason,
		"A refused business step stops the sequence with its reason")
	_check(not _state.get_flag("test.business.unreachable"), "Steps after a refused business step never run")
	finished.clear()
	_check(director.request_event("test.business.close") == OK, "Director starts the close sequence")
	await _until(func() -> bool: return not director.is_busy(), "Close sequence finishes")
	_check(finished.size() == 1 and finished[0].ok and _state.get_flag("test.business.closed_step"),
		"Director drives publication and closing in authored order")
	director.queue_free()
	await _frames()
