extends SceneTree
## Real shared state and settlement; close rules and recovery boundaries are fixtures.

const StateData = preload("res://src/core/game_state.gd")
const SESSION_RULES = preload("res://src/gameplay/milk_tea/business_session_rules.gd")
const SESSION := "business_test.day1"
var _checks := 0
var _failures: Array[String] = []
var _host: Node
var _state: StateData
var _delivery: TaskDelivery
var _scheduler: BusinessScheduler
var _plan: Dictionary
var _rule: Dictionary
var _directory := "user://verification/business_persistence_%d" % OS.get_process_id()
var _completed: Array[String] = []
var _served: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames() -> void:
	for index in range(3):
		await process_frame

func _setup() -> void:
	_host = Node.new()
	root.add_child(_host)
	_state = StateData.new()
	_host.add_child(_state)
	check(_state.select_business_profile("day1") == OK, "Reuse actual shared inventory/production profile")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/resources/tasks/day1_stages_01_02.json"))
	data.tasks.append({"id": "business_test.deadline", "type": "commission", "title": "独立期限夹具", "description": "不定义正式关店条件",
		"activate_when": {"type": "flag", "key": "business_test.active"},
		"complete_when": {"type": "flag", "key": "business_test.deadline_done"},
		"deadline": {"day": 1, "phase": "night", "boundary": "at"},
		"objectives": [{"id": "goal", "text": "测试", "complete_when": {"type": "flag", "key": "business_test.deadline_done"}}]})
	var catalog := TaskCatalog.new()
	check(catalog.load_json(JSON.stringify(data)) == OK, "Load full real order catalog plus isolated deadline")
	var journal := TaskJournal.new()
	_host.add_child(journal)
	check(journal.configure(catalog, _state) == OK, "Bind full task catalog to shared state")
	_delivery = TaskDelivery.new()
	_host.add_child(_delivery)
	check(_delivery.configure(catalog, journal, _state, _state.get_warehouse_inventory()) == OK, "Use real TaskDelivery")
	_plan = {"session_id": SESSION, "stages": [
		{"id": "ordinary", "ordinary_customers": [{"id": "human", "actor_ids": ["human_customer"], "order_ids": ["day1_human"]}]},
		{"id": "story", "story_customers": [{"id": "goblin", "actor_ids": ["goblin_customer"], "order_ids": ["day1_goblin"]}]}]}
	_rule = {"from": {"day": 1, "phase": "day"}, "to": {"day": 1, "phase": "night"},
		"required_stages": ["ordinary", "story"], "served_groups": ["human", "goblin"],
		"departed_groups": ["human", "goblin"], "required_flags": ["business_test.close_allowed"], "completed_flag": "business_test.closed"}

func _configure(close_rule: Dictionary) -> void:
	_scheduler = BusinessScheduler.new()
	_host.add_child(_scheduler)
	check(_scheduler.configure_session(_plan, _state, _delivery, close_rule) == OK, "Production scheduler binds GameState adapters")
	_scheduler.business_completed.connect(func(id: String) -> void: _completed.append(id))
	_scheduler.group_served.connect(func(id: String) -> void: _served.append(id))

func _run() -> void:
	var reader := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--business-directory="):
			_directory = argument.trim_prefix("--business-directory=")
		if argument.begins_with("--business-expect="):
			reader = argument.trim_prefix("--business-expect=")
	_setup()
	if not reader.is_empty():
		_read_saved(reader)
		_finish()
		return
	_test_configuration()
	_configure({})
	check(_scheduler.get_progress().persistence_ready and not _scheduler.get_progress().close_ready, "Persistence works while missing close rules remain pending")
	check(_scheduler.publish_stage("ordinary") == OK, "Production store publishes without a close rule")
	var pending := _state.to_dict()
	check(_scheduler.request_close() == ERR_UNAVAILABLE and _state.to_dict() == pending, "Missing close rule cannot invent a business result")
	check(_state.close_business_session(SESSION, _state.load_business_session(SESSION), _closed_next()) == ERR_UNCONFIGURED, "Direct close also requires authored rules")
	check(_state.start_new_game() == OK and _state.load_business_session(SESSION).is_empty(), "New game clears durable visits")
	_scheduler.free()
	_configure(_rule)
	_state.apply_flags({"day1.human_open": true, "day1.goblin_open": true, "business_test.active": true})
	var cold := _state.to_dict()
	check(_scheduler.request_close() == ERR_UNAVAILABLE and cold == _state.to_dict(), "Cannot close before required publication/service")
	check(_scheduler.publish_stage("ordinary") == OK, "Stage and ordinary entry commit together")
	_test_compare_and_swap()
	_test_notification_guard()
	check(_scheduler.get_group("human").status == "waiting", "Real arrival survives guarded notification")
	var copy := _state.load_business_session(SESSION)
	copy.groups.human = "departed"
	check(_state.load_business_session(SESSION).groups.human == "waiting", "Reads return independent nested containers")
	_save_and_read("waiting")
	var before_rebuild := _state.to_dict()
	_scheduler.free()
	_configure(_rule)
	check(_state.to_dict() == before_rebuild and _scheduler.get_group("human").status == "waiting", "Scene reconstruction rebinds without resetting visits")
	check(_served.is_empty() and _completed.is_empty(), "Reconstruction does not replay gameplay signals")
	_craft_and_deliver("day1_human", "human_customer")
	await _frames()
	check(_scheduler.get_group("human").status == "leaving", "Ordinary departure persists after atomic payment")
	check(_scheduler.confirm_departure("human") == OK, "Actual ordinary departure persists")
	check(_scheduler.publish_stage("story") == OK and _scheduler.get_group("goblin").status == "dormant", "Story publication preserves explicit arrival timing")
	check(_scheduler.request_arrival("goblin") == OK and _scheduler.confirm_arrival("goblin") == OK, "Story arrival uses production commits")
	_craft_and_deliver("day1_goblin", "goblin_customer")
	await _frames()
	check(_scheduler.get_group("goblin").status == "waiting", "Real receipt keeps story customer available for dialogue")
	check(_scheduler.request_departure("goblin") == OK and _scheduler.confirm_departure("goblin") == OK, "Story explicitly confirms departure")
	check(_state.get_transactions().get_balance() == 10 and _state.get_warehouse_inventory().get_stock("strange_coin") == 1, "Orders preserve real wallet and inventory rewards")
	check(_scheduler.request_close() == ERR_UNAVAILABLE and not DayPhase.is_night(_state), "All orders alone do not override explicit story gate")
	_state.set_flag("business_test.close_allowed")
	_test_restore_validation()
	_test_close()
	_state.set_flag("business_test.close_allowed", false)
	check(_state.validate_snapshot(_state.to_dict()) == OK, "Historical closure survives later changes to temporary permission")
	_save_and_read("closed")
	var saved := _state.to_dict()
	check(_state.start_new_game() == OK and _state.load_business_session(SESSION).is_empty(), "New game clears closure, visits and results together")
	check(_state.restore_state(saved) == OK and _scheduler.get_progress().closed, "Full restore projects closed session")
	var settled_count := _completed.size()
	check(_scheduler.request_close() == OK and _completed.size() == settled_count and _state.to_dict() == saved, "Restored closure never advances or completes twice")
	_cleanup_files()
	_finish()

func _closed_next() -> Dictionary:
	var next := _state.load_business_session(SESSION)
	if next.is_empty():
		next = SESSION_RULES.empty_snapshot()
	next.closed = true
	return next

func _test_configuration() -> void:
	var before := _state.to_dict()
	for field: String in ["to", "required_flags", "completed_flag"]:
		var invalid := _rule.duplicate(true)
		invalid.erase(field)
		check(_state.bind_business_session(_plan, invalid) == ERR_INVALID_DATA, "Reject missing explicit rule: " + field)
	var invalid := _rule.duplicate(true)
	invalid.to.day = 2
	check(_state.bind_business_session(_plan, invalid) == ERR_INVALID_DATA, "Reject a skipped date/phase")
	invalid = _rule.duplicate(true)
	invalid.served_groups = ["unknown"]
	check(_state.bind_business_session(_plan, invalid) == ERR_INVALID_DATA, "Reject unknown required group")
	invalid = _rule.duplicate(true)
	invalid.completed_flag = DayPhase.NIGHT_FLAG
	check(_state.bind_business_session(_plan, invalid) == ERR_INVALID_DATA, "Completion cannot overwrite the phase mirror")
	invalid = _rule.duplicate(true)
	invalid.required_stages.append("ordinary")
	check(_state.bind_business_session(_plan, invalid) == ERR_INVALID_DATA, "Reject duplicate close requirements")
	invalid = _rule.duplicate(true)
	invalid.to.day = 1.5
	check(_state.bind_business_session(_plan, invalid) == ERR_INVALID_DATA, "Reject fractional day configuration")
	var plan := _plan.duplicate(true)
	plan.session_id = "invalid session"
	check(_state.bind_business_session(plan, _rule) == ERR_INVALID_DATA, "Reject IDs unsuitable for durable keys")
	plan = _plan.duplicate(true)
	plan.stages[0].ordinary_customers[0].order_ids = ["unknown_order"]
	check(_state.bind_business_session(plan, _rule) == ERR_INVALID_DATA, "Orders must exist in the shared task catalog")
	check(_state.to_dict() == before, "Invalid binding leaves all session facts untouched")

func _test_compare_and_swap() -> void:
	var before := _state.load_business_session(SESSION)
	var next := before.duplicate(true)
	next.groups.human = "departed"
	check(_state.commit_business_session(SESSION, before, next) == ERR_UNAVAILABLE, "Cannot invent a departure without receipt or arrival")
	next = before.duplicate(true)
	next.closed = true
	check(_state.commit_business_session(SESSION, before, next) == ERR_UNAVAILABLE, "Ordinary commits cannot bypass close validation")
	next = before.duplicate(true)
	next.groups.human = "waiting"
	var saved := _state.to_dict()
	check(_state.commit_business_session(SESSION, SESSION_RULES.empty_snapshot(), next) == ERR_BUSY and _state.to_dict() == saved, "Stale compare/replace cannot overwrite live visits")
	check(not _state.set_variable(SESSION_RULES.PREFIX + SESSION, next), "Generic variable setter cannot bypass business transactions")
	check(_state.begin_business_transaction(), "Hold existing delivery guard")
	check(_state.commit_business_session(SESSION, before, next) == ERR_BUSY, "Existing business guard blocks visit commits")
	_state.end_business_transaction()
	paused = true
	check(_scheduler.confirm_arrival("human") == ERR_BUSY and _state.to_dict() == saved, "Paused world cannot commit visits")
	paused = false
	var alias := _plan.duplicate(true)
	alias.stages[0].ordinary_customers[0].actor_ids = ["wrong_actor"]
	check(_state.bind_business_session(alias, _rule) == ERR_INVALID_DATA, "Binding validates the actual order recipient")

func _test_notification_guard() -> void:
	var other := _plan.duplicate(true)
	other.session_id = "business_test.other"
	check(_state.bind_business_session(other) == OK, "Bind a second component to the same shared guard")
	var observed: Array[bool] = []
	var listener := func() -> void:
		var live := _state.load_business_session(SESSION)
		observed.append(live.groups.human == "waiting")
		var another := SESSION_RULES.empty_snapshot()
		another.published_stages = ["ordinary"]
		another.groups = {"human": "entering"}
		check(_state.commit_business_session("business_test.other", SESSION_RULES.empty_snapshot(), another) == ERR_BUSY, "Synchronous observer cannot mutate another session")
		check(_state.commit_business_session(SESSION, live, live) == ERR_BUSY, "Synchronous observer cannot reenter current session")
		check(not _state.set_flag("business_test.reentered") and not _state.set_variable("business_test.reentered", true), "Notification blocks generic state writes")
		check(_state.start_new_game() == ERR_BUSY and not _state.reset_state(), "Notification blocks reset/new game")
		check(_state.restore_state(_state.to_dict()) == ERR_BUSY, "Notification blocks full restore")
		check(_state.get_transactions().add_money(1, "business_reentry").code == "busy", "Notification blocks wallet writes")
		check(not _state.get_warehouse_inventory().try_consume({"black_tea": 1}), "Notification blocks direct inventory writes")
		check(not _state.get_tea_production().craft([]).ok, "Notification blocks production")
		check(DayPhase.advance_to(_state, 1, "night") == ERR_BUSY, "Notification blocks phase advancement")
		check(_state.bind_business_session(other) == ERR_BUSY and not _state.can_take_snapshot(), "Notification blocks rebinding and unsafe save capture")
	_state.state_changed.connect(listener)
	check(_scheduler.confirm_arrival("human") == OK, "Arrival publishes exactly one guarded shared commit")
	_state.state_changed.disconnect(listener)
	check(observed == [true] and _state.load_business_session("business_test.other").is_empty(), "Observers see complete state and no reentry can persist")

func _craft_and_deliver(order_id: String, target: String) -> void:
	var order := {}
	for candidate: Dictionary in _delivery.get_orders():
		if candidate.order_id == order_id:
			order = candidate
	check(_delivery.accept_order(order_id) == OK, "Accept the arrived customer's real order: " + order_id)
	var recipe := _state.get_tea_production().get_recipe_by_product(order.product_id)
	check(_state.get_tea_production().craft(recipe.materials).ok, "Produce a real inventory cup: " + order_id)
	var before := _state.to_dict()
	check(not _delivery.try_submit(order_id, "wrong_actor").ok and _state.to_dict() == before, "Wrong recipient leaves business and economics unchanged")
	check(_delivery.try_submit(order_id, target).ok, "Delivery settles inventory, rewards and receipt together")
	before = _state.to_dict()
	check(not _delivery.try_submit(order_id, target).ok and _state.to_dict() == before, "Duplicate delivery never rewards twice")

func _test_restore_validation() -> void:
	var before := _state.to_dict()
	for fault: String in ["version", "duplicate_stage", "unknown_group", "missing_receipt", "false_closure", "premature_closure", "missing_departure"]:
		var invalid := before.duplicate(true)
		var visit: Dictionary = invalid.variables[SESSION_RULES.PREFIX + SESSION]
		match fault:
			"version": visit.version = 99
			"duplicate_stage": visit.published_stages.append("ordinary")
			"unknown_group": visit.groups.unknown = "waiting"
			"missing_receipt": invalid.flags.erase("delivery.day1_human.completed")
			"false_closure": visit.closed = true
			"premature_closure":
				visit.closed = true
				invalid.flags["business_test.closed"] = true
			"missing_departure":
				visit.closed = true
				invalid.flags["business_test.closed"] = true
				invalid.variables[DayPhase.PHASE_VARIABLE] = "night"
				invalid.flags[DayPhase.NIGHT_FLAG] = true
				visit.groups.goblin = "waiting"
		check(_state.restore_state(invalid) == ERR_INVALID_DATA and _state.to_dict() == before, "Invalid full snapshot is rejected atomically: " + fault)
	var changed_rule := _rule.duplicate(true)
	changed_rule.required_flags = []
	check(_state.bind_business_session(_plan, changed_rule) == ERR_ALREADY_EXISTS, "Cannot silently replace rules of an existing session")

func _test_close() -> void:
	var observations: Array[bool] = []
	var signals_seen: Array[String] = []
	var listener := func() -> void:
		observations.append(_state.load_business_session(SESSION).closed and _state.get_flag("business_test.closed") and DayPhase.is_night(_state) and _state.get_flag(DayPhase.NIGHT_FLAG) and _state.current_day == 1 and _state.get_task_result("business_test.deadline").get("status") == "expired")
	var result_listener := func(id: String, _result: Dictionary) -> void:
		signals_seen.append(id)
		check(_state.close_business_session(SESSION, _state.load_business_session(SESSION), _closed_next()) == ERR_BUSY, "Task result notification cannot reenter closure")
	paused = true
	var before := _state.to_dict()
	check(_scheduler.request_close() == ERR_BUSY and _state.to_dict() == before, "Pause blocks closure and its phase change")
	paused = false
	_state.state_changed.connect(listener)
	_state.task_settled.connect(result_listener)
	check(_scheduler.request_close() == OK, "Authored gates atomically close business and enter night")
	_state.state_changed.disconnect(listener)
	_state.task_settled.disconnect(result_listener)
	check(observations == [true] and signals_seen == ["business_test.deadline"], "Observers see closure, phase and deadline outcome in one notification")
	check(_completed == [SESSION], "Real business completion emits once after durable commit")
	before = _state.to_dict()
	check(_scheduler.request_close() == OK and _completed == [SESSION] and _state.to_dict() == before, "Repeat close is silent and does not advance a day")
	check(_scheduler.request_arrival("goblin") == ERR_ALREADY_EXISTS and _scheduler.get_progress().closed, "Closed session cannot regenerate guests")
	check(not _delivery.is_order_available("day1_human"), "Closing disables canonical order gate")

func _store() -> SaveStore:
	var checkpoints := SaveCheckpoints.new()
	var entries: Array[Dictionary] = []
	for phase: String in ["day", "night"]:
		entries.append({"id": "business_test." + phase, "scene": "res://src/core/main.tscn", "entrance": "", "stage": "business_test.fixture", "day": 1, "phase": phase,
			"after_event": "", "before_event": "", "required_flags": [], "recovery": "chapter"})
	check(checkpoints.load_data({"version": 1, "checkpoints": entries}) == OK, "Use isolated save boundaries, never publish formal Day 2 checkpoints")
	return SaveStore.new(_directory, checkpoints)

func _save_and_read(expect: String) -> void:
	_state.set_story_stage("business_test.fixture")
	var store := _store()
	check(store.save(_state.to_dict(), "business_test." + DayPhase.get_phase(_state)) == OK, "Complete native save includes visits and economics: " + expect)
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/verify_business_persistence.gd", "--",
		"--business-directory=" + _directory, "--business-expect=" + expect], output, true)
	var clean := code == 0 and str(output).contains("BUSINESS_PERSISTENCE: PASS") and not str(output).contains("SCRIPT ERROR")
	check(clean, "Independent engine restores production session: " + expect)
	if not clean:
		print(output)

func _read_saved(expect: String) -> void:
	var store := _store()
	var loaded := store.load_save()
	check(loaded.error == OK, "Fresh process preflights save before business binding")
	if loaded.error != OK:
		return
	check(_state.restore_state(loaded.data.game_state) == OK, "Restore facts before binding scene-local scheduler")
	_configure(_rule)
	check(_served.is_empty() and _completed.is_empty(), "Cold restore never replays business events")
	if expect == "closed":
		check(_scheduler.get_progress().closed and DayPhase.is_night(_state) and _state.get_task_result("business_test.deadline").get("status") == "expired", "Closed session and terminal result survive process restart")
		check(_state.get_transactions().get_balance() == 10 and _state.get_warehouse_inventory().get_stock("strange_coin") == 1, "Cold restore retains rewards exactly once")
		check(_scheduler.request_close() == OK and not _delivery.try_submit("day1_human", "human_customer").ok, "Cold restore cannot pay or close twice")
	else:
		check(_scheduler.get_group("human").status == "waiting" and not _scheduler.get_progress().closed and not DayPhase.is_night(_state), "Waiting guest and daylight survive process restart")
		check(_delivery.can_accept_order("day1_human"), "Restored actual arrival reopens canonical acceptance")
	var before := _state.to_dict()
	check(_state.restore_state(loaded.data.game_state) == OK and _state.to_dict() == before and _completed.is_empty(), "Repeated restore is silent and idempotent")

func _cleanup_files() -> void:
	for name: String in ["autosave.dat", "autosave.bak", "autosave.tmp", "autosave.bak.tmp"]:
		if FileAccess.file_exists(_directory.path_join(name)):
			DirAccess.remove_absolute(_directory.path_join(name))
	DirAccess.remove_absolute(_directory)

func _finish() -> void:
	_host.free()
	print("BUSINESS_PERSISTENCE: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
