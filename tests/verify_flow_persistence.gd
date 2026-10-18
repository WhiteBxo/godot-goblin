extends SceneTree
## Native file snapshots only at quiescent business boundaries; no formal save policy.
signal action_released
const Host = preload("res://src/debug/flow_playtest/flow_playtest.gd")
const Session = preload("res://src/debug/flow_playtest/flow_session.gd")
const Fixture = preload("res://src/debug/flow_playtest/flow_fixture.gd")
const SCENE := "res://src/debug/flow_playtest/flow_playtest.tscn"
const IDS := ["delivered", "closed", "purchased", "round_one", "round_two", "waived", "new_game"]
const BALANCES := [60, 60, 51, 63, 56, 56, 40]
# Boundary probe only: the existing playable fixture's second round remains -7.
const SECOND_REWARD := "test_flow_second_reward_probe"
const SECOND_REWARD_MONEY := 5
const STAGES := [Session.Stage.CLOSE, Session.Stage.TAVERN, Session.Stage.ROUND_ONE,
	Session.Stage.ROUND_TWO, Session.Stage.DEBT, Session.Stage.COMPLETE, Session.Stage.READY]
var _host: Host
var _directory: String
var _checks := 0
var _failures: Array[String] = []
var _formal: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _wait_stage(stage: Session.Stage) -> void:
	for frame in range(420):
		if _host.session.stage == stage:
			return
		await physics_frame
	_check(false, "Timed out waiting for stage %s" % stage)

func _write(id: String) -> void:
	# Called after the service returns, never from an in-flight notification.
	var state := _host.session.state
	_check(not state.get_transactions().is_busy() and not state.get_tea_production().is_submitting(), id + ": idle save boundary")
	var file := FileAccess.open(_directory.path_join(id + ".save"), FileAccess.WRITE)
	_check(file != null, id + ": open real file")
	if file == null:
		return
	file.store_var(state.to_dict(), false)
	file.flush()
	_check(file.get_error() == OK, id + ": write complete Variant snapshot")
	file.close()

func _blocked_action() -> bool:
	await action_released
	return true

func _check_inflight_cancellation() -> void:
	var session := Session.new()
	root.add_child(session)
	session.configure(_blocked_action, _blocked_action)
	var defaults := session.state.to_dict()
	session.start_business()
	_check(session.stage == Session.Stage.ARRIVING, "Arrival is pending before new game")
	_check(session.state.start_new_game() == OK, "New game while arrival awaits")
	action_released.emit()
	_check(session.stage == Session.Stage.READY and session.state.to_dict() == defaults, "Old arrival cannot write into new game")
	session.free()
	session = Session.new()
	root.add_child(session)
	session.configure(func() -> bool: return true, _blocked_action)
	session.start_business()
	session.accept_order(Fixture.ORDER)
	var materials: Array[String] = ["black_tea", "creamer", "pearl", "syrup"]
	_check(session.craft(materials, 1).ok, "Prepare pending departure")
	session.submit_delivery()
	_check(session.stage == Session.Stage.DEPARTING, "Departure awaits after committed delivery")
	_check(DayPhase.enter_night(session.state), "Prepare an already closed business snapshot")
	var closed := session.state.to_dict()
	_check(session.state.restore_state(defaults) == OK and session.state.restore_state(closed) == OK, "Replace state while old departure awaits")
	_check(session.stage == Session.Stage.TAVERN, "Restored closure needs no departure replay")
	action_released.emit()
	_check(session.stage == Session.Stage.TAVERN and session.state.to_dict() == closed, "Old departure cannot overwrite recovered business")
	session.free()

func _reward_probe(write: bool) -> void:
	# Inject a second winning settlement only into this business-boundary test.
	# The playable +12/-7 flow and all formal Resources remain unchanged.
	var menu := Fixture.menu()
	menu.transaction_rewards[SECOND_REWARD] = {"money": SECOND_REWARD_MONEY, "items": {"syrup": 1}}
	var state := Session.StateData.new(menu)
	root.add_child(state)
	var journal := TaskJournal.new()
	state.add_child(journal)
	var delivery := TaskDelivery.new()
	state.add_child(delivery)
	_check(journal.configure(Fixture.catalog(), state) == OK, "Reward probe journal uses real tasks")
	_check(delivery.configure(Fixture.catalog(), journal, state, state.get_warehouse_inventory()) == OK, "Reward probe uses shared real delivery")
	var file := FileAccess.open(_directory.path_join("round_one.save" if write else "second_reward.save"), FileAccess.READ)
	_check(file != null, "Reward probe opens real snapshot")
	if file == null:
		state.free()
		return
	var snapshot: Dictionary = file.get_var(false)
	file.close()
	var signals_seen: Array[String] = []
	var wallet := state.get_transactions()
	wallet.transaction_finished.connect(func(_result: Dictionary) -> void: signals_seen.append("transaction"))
	delivery.delivered.connect(func(_order: String) -> void: signals_seen.append("delivery"))
	_check(state.restore_state(snapshot) == OK and state.to_dict() == snapshot and signals_seen.is_empty(), "Reward probe restores silently without changing task terminal state")
	if write:
		_check(wallet.claim_reward(SECOND_REWARD, "test.flow.second_reward").ok, "Commit second reward before any waiver")
		file = FileAccess.open(_directory.path_join("second_reward.save"), FileAccess.WRITE)
		_check(file != null and not wallet.is_busy(), "Second reward saved only after commit returns")
		if file != null:
			file.store_var(state.to_dict(), false)
			file.flush()
			_check(file.get_error() == OK, "Second reward snapshot flushed")
			file.close()
	else:
		var inventory := state.get_warehouse_inventory()
		_check(wallet.get_balance() == 63 + SECOND_REWARD_MONEY and inventory.get_stock("syrup") == 3, "Second money and item reward survive exactly once")
		_check(inventory.get_stock(Fixture.WINE) == 1 and wallet.get_product_quote(Fixture.TAVERN_PRODUCT).stock == 0, "Purchased wine and merchant remainder survive second reward")
		_check(DayPhase.is_night(state) and state.get_flag("delivery." + Fixture.ORDER + ".completed") and journal.get_task("test.flow.tea").status == "completed", "Business closure and tea terminal task survive second reward")
		for item: String in ["black_tea", "creamer", "pearl"]:
			_check(inventory.get_stock(item) == 1, "Second reward preserves ingredient remainder: " + item)
		_check(not state.get_flag(Fixture.WAIVED) and not state.get_flag("delivery." + Fixture.DEBT_ORDER + ".completed"), "Second reward never waives debt implicitly")
		_check(wallet.to_dict().claimed.has("reward:" + SECOND_REWARD) and wallet.to_dict().requests.has("test.flow.second_reward"), "Second reward has persistent claim and request receipts")
		_check(not wallet.claim_reward(SECOND_REWARD, "test.flow.second_reward").ok and not wallet.claim_reward(SECOND_REWARD, "other.second_reward").ok, "Second reward refuses duplicate and renamed retries")
		_check(state.to_dict() == snapshot, "Duplicate second reward does not change balance, stock or tasks")
		# Resume from the receipt query, not a transaction_finished replay.
		if wallet.to_dict().requests.has("test.flow.second_reward"):
			_check(delivery.accept_order(Fixture.DEBT_ORDER) == OK and delivery.try_submit(Fixture.DEBT_ORDER, Fixture.CREDITOR).ok, "Continue to waiver by querying committed second reward")
		var complete := state.to_dict()
		_check(wallet.get_balance() == 68 and inventory.get_stock(Fixture.WINE) == 0 and journal.get_task("test.flow.debt").status == "completed", "Waiver consumes wine without overwriting rewards or task terminal state")
		_check(not delivery.try_submit(Fixture.DEBT_ORDER, Fixture.CREDITOR).ok and state.to_dict() == complete, "Waiver stays idempotent after second reward")
		_check(state.start_new_game() == OK and wallet.to_dict().requests.is_empty() and wallet.to_dict().claimed.is_empty(), "New game also clears alternative second reward receipts")
	state.free()

func _produce() -> void:
	var session := _host.session
	var state := session.state
	session.start_business()
	await _wait_stage(Session.Stage.ORDER)
	session.accept_order(Fixture.ORDER)
	var materials: Array[String] = ["black_tea", "creamer", "pearl", "syrup"]
	_check(session.craft(materials, 1).ok, "Real production before delivery")
	session.submit_delivery()
	_check(session.stage == Session.Stage.DEPARTING, "Capture committed delivery before actual departure")
	_write("delivered")
	await _wait_stage(Session.Stage.CLOSE)
	session.close_business()
	_write("closed")
	# Commit using the public business service, before any success presentation.
	var wallet := state.get_transactions()
	_check(wallet.purchase(Fixture.TAVERN_PRODUCT, 1, "test.flow.purchase").ok, "Commit purchase without presenting success")
	_check(session.stage == Session.Stage.TAVERN, "Purchase snapshot precedes local presentation advance")
	_write("purchased")
	_check(wallet.claim_reward(Fixture.WIN_REWARD, "test.flow.round_one").ok, "Commit first fixed settlement")
	_write("round_one")
	_check(wallet.spend_money(Fixture.LOSS, "test.flow.round_two").ok, "Commit second fixed settlement (loss fixture)")
	_write("round_two")
	_check(session.delivery.accept_order(Fixture.DEBT_ORDER) == OK, "Accept real material waiver")
	_check(session.delivery.try_submit(Fixture.DEBT_ORDER, Fixture.CREDITOR).ok, "Commit waiver through real delivery")
	_write("waived")
	_check(state.start_new_game() == OK, "Explicit new game resets the isolated session")
	_write("new_game")
	await _reward_probe(true)
	await _check_inflight_cancellation()

func _assert_business(index: int) -> void:
	var session := _host.session
	var state := session.state
	var inventory := state.get_warehouse_inventory()
	var economy := state.get_transactions().to_dict()
	var fresh := index == 6
	_check(economy.balance == BALANCES[index], "Exact restored balance")
	_check(inventory.get_stock(Fixture.PRODUCT) == 0, "No delivered cup respawns")
	for item: String in ["black_tea", "creamer", "pearl"]:
		_check(inventory.get_stock(item) == (2 if fresh else 1), "Exact remaining material: " + item)
	_check(inventory.get_stock("syrup") == (2 if fresh or index >= 3 else 1), "Exact sugar including first reward")
	_check(inventory.get_stock(Fixture.WINE) == (1 if index in [2, 3, 4] else 0), "Wine bought/consumed exactly once")
	_check(economy.merchant_stock[Fixture.TAVERN_PRODUCT] == (1 if fresh or index < 2 else 0), "Merchant remainder survives")
	_check(DayPhase.is_night(state) == (not fresh and index >= 1), "Business closure survives scene rebuild")
	_check(state.get_flag("delivery." + Fixture.ORDER + ".completed") == not fresh, "Tea delivery receipt survives")
	_check(state.get_flag("delivery." + Fixture.DEBT_ORDER + ".completed") == (index == 5), "Debt delivery receipt survives")
	_check(state.get_variable("shop.orders_completed", 0) == (0 if fresh else (2 if index == 5 else 1)), "Delivery counter is not recounted")
	_check(session.journal.get_task("test.flow.tea").status == ("inactive" if fresh else "completed"), "Tea task terminal state preserved")
	_check(session.journal.get_task("test.flow.debt").status == ("completed" if index == 5 else "inactive"), "Debt task terminal state preserved")
	_check(session.get_test_debt() == (0 if index == 5 else Fixture.TEST_DEBT), "Debt derives from persistent delivery receipt")
	for pair: Array in [["test.flow.purchase", 2], ["test.flow.round_one", 3], ["test.flow.round_two", 4]]:
		_check(economy.requests.has(pair[0]) == (not fresh and index >= pair[1]), "Transaction receipt: " + pair[0])
	_check(economy.claimed.has("reward:" + Fixture.WIN_REWARD) == (not fresh and index >= 3), "Reward claim receipt survives")

func _consume(id: String) -> void:
	var index := IDS.find(id)
	var file := FileAccess.open(_directory.path_join(id + ".save"), FileAccess.READ)
	_check(file != null, "Reader process opens writer's file")
	if file == null:
		return
	var snapshot: Variant = file.get_var(false)
	file.close()
	_check(snapshot is Dictionary, "Native file decodes to dictionary")
	if not snapshot is Dictionary:
		return
	var session := _host.session
	var state := session.state
	var signals_seen: Array[String] = []
	state.get_transactions().transaction_finished.connect(func(_result: Dictionary) -> void: signals_seen.append("transaction"))
	session.delivery.delivered.connect(func(_order: String) -> void: signals_seen.append("delivery"))
	state.event_completed.connect(func(_event: String) -> void: signals_seen.append("event"))
	_check(state.restore_state(snapshot) == OK, "Restore complete state in fresh process")
	_check(state.to_dict() == snapshot, "Recovery never rewrites committed facts or terminal tasks")
	_check(signals_seen.is_empty(), "Recovery replays no transaction, delivery or event success signal")
	_assert_business(index)
	_check(session.stage == STAGES[index], "Recovered business stage for " + id)
	# Baseline failure must not cascade into misleading money/task assertions.
	if session.stage != STAGES[index]:
		return
	var before := state.to_dict()
	_check(state.restore_state(snapshot) == OK and state.to_dict() == before, "Repeated restore is inert")
	var wallet := state.get_transactions()
	if index != 6:
		_check(not session.delivery.try_submit(Fixture.ORDER, Fixture.CUSTOMER).ok, "Restored tea cannot deliver twice")
	if index in [2, 3, 4, 5]:
		_check(not wallet.purchase(Fixture.TAVERN_PRODUCT, 1, "test.flow.purchase").ok, "Restored purchase cannot charge twice")
	if index in [3, 4, 5]:
		_check(not wallet.claim_reward(Fixture.WIN_REWARD, "test.flow.round_one").ok and not wallet.claim_reward(Fixture.WIN_REWARD, "different.retry").ok, "Restored reward refuses same and different request IDs")
	if index in [4, 5]:
		_check(not wallet.spend_money(Fixture.LOSS, "test.flow.round_two").ok, "Restored second settlement cannot debit twice")
	if index == 5:
		_check(not session.delivery.try_submit(Fixture.DEBT_ORDER, Fixture.CREDITOR).ok, "Restored waiver cannot consume another wine")
	_check(state.to_dict() == before, "All duplicate retries preserve the entire snapshot")
	if index == 6:
		var fresh := Session.StateData.new(Fixture.menu())
		_check(state.to_dict() == fresh.to_dict(), "New game contains no prior facts or receipts")
		fresh.free()
		return
	# Continue by querying recovered stage; no success signals are replayed.
	if session.stage == Session.Stage.CLOSE:
		session.close_business()
	if session.stage == Session.Stage.TAVERN:
		session.purchase()
	if session.stage == Session.Stage.ROUND_ONE:
		session.settle_round(1)
	if session.stage == Session.Stage.ROUND_TWO:
		session.settle_round(2)
	if session.stage == Session.Stage.DEBT:
		session.waive_debt()
	_check(session.stage == Session.Stage.COMPLETE, "Restored flow continues to completion")
	_assert_business(5)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or not args[1].is_absolute_path() or not DirAccess.dir_exists_absolute(args[1]):
		push_error("Use verify_flow_persistence.py: MODE ABSOLUTE_TEMP_DIRECTORY [checkpoint]")
		quit(2)
		return
	_directory = args[1]
	_formal = root.get_node("GameState").to_dict()
	_check(change_scene_to_file(SCENE) == OK, "Reuse isolated F6 host")
	await scene_changed
	_host = current_scene as Host
	if args[0] == "write":
		await _produce()
	elif args[2] == "second_reward":
		await _reward_probe(false)
	else:
		await _consume(args[2])
	_check(root.get_node("GameState").to_dict() == _formal, "Formal autoload remains untouched")
	print("FLOW_PERSISTENCE ", args[0], " ", args[2] if args.size() > 2 else "all", ": ", _checks, " checks, ", _failures.size(), " failures; pid=", OS.get_process_id())
	quit(0 if _failures.is_empty() else 1)
