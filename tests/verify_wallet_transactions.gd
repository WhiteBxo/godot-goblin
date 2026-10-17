extends SceneTree

const StateData = preload("res://src/core/game_state.gd")
var _checks := 0
var _failures: Array[String] = []

class RefusingInventory extends WarehouseInventory:
	func restore_state(_data: Variant, _notify: bool = true) -> Error:
		return FAILED

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _menu() -> TeaMenu:
	var menu: TeaMenu = WarehouseInventory.CATALOG.duplicate(true)
	menu.initial_balance = 100
	menu.products = {
		"tea": {"item_id": "black_tea", "price": 7, "stock": 5},
		"milk": {"item_id": "creamer", "price": 2},
		"free": {"item_id": "pearl", "price": 0},
		"bad_price": {"item_id": "black_tea", "price": -1},
		"bad_item": {"item_id": "missing", "price": 2},
		"bad_stock": {"item_id": "black_tea", "price": 2, "stock": 1.5}}
	menu.transaction_rewards = {
		"gift": {"money": 20, "items": {"green_tea": 2, "pearl": 3}},
		"bad_gift": {"money": 20, "items": {"green_tea": 2, "missing": 3}},
		"task_gift": {"money": 10, "items": {"black_tea": 1}, "task_id": "test.progress"},
		"task_alias": {"money": 10, "items": {}, "task_id": "test.progress"}}
	return menu

func _unchanged(service: WalletTransactions, invoke: Callable, code: String) -> void:
	var before := service.to_dict()
	var notifications: Array[bool] = []
	var listener := func() -> void: notifications.append(true)
	service.changed.connect(listener)
	var result: Dictionary = invoke.call()
	service.changed.disconnect(listener)
	_check(not result.ok and result.code == code, "Expected failure: " + code)
	_check(service.to_dict() == before and notifications.is_empty(), "Failure is silent and atomic: " + code)

func _run() -> void:
	_test_purchases()
	_test_rewards()
	_test_commit_failure()
	_test_snapshots()
	await _test_session()
	print("WALLET_TRANSACTIONS: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_purchases() -> void:
	var service := WalletTransactions.new(_menu())
	var inventory := service.get_inventory()
	var observations: Array[Dictionary] = []
	var nested: Array[Dictionary] = []
	inventory.changed.connect(func() -> void:
		observations.append(service.to_dict())
		nested.append(service.purchase("milk", 1, "nested")))
	service.transaction_finished.connect(func(_result: Dictionary) -> void:
		nested.append(service.spend_money(1, "nested_result")))
	var result := service.purchase("tea", 2, "click_1")
	_check(result.ok and result.money_delta == -14 and result.balance == 86 and result.items == {"black_tea": 2}, "Purchase returns a complete UI result")
	_check(inventory.get_stock("black_tea") == 14 and service.to_dict().merchant_stock.tea == 3, "Purchase adds inventory and consumes finite merchant stock")
	_check(observations.size() == 1 and observations[0] == service.to_dict(), "Inventory observer sees committed wallet, stock and receipt together")
	_check(nested.size() == 2 and nested[0].code == "busy" and nested[1].code == "busy", "Inventory/result callbacks cannot reenter transactions")
	_unchanged(service, func(): return service.purchase("tea", 2, "click_1"), "duplicate_transaction")
	_unchanged(service, func(): return service.purchase("milk", 1, "click_1"), "duplicate_transaction")
	_unchanged(service, func(): return service.add_money(1, "click_1"), "duplicate_transaction")
	_unchanged(service, func(): return service.purchase("tea", 4, "stock"), "out_of_stock")
	_unchanged(service, func(): return service.purchase("milk", 100, "poor"), "insufficient_funds")
	_unchanged(service, func(): return service.purchase("absent", 1, "absent"), "unknown_product")
	for id: String in ["bad_price", "bad_item", "bad_stock"]:
		_unchanged(service, func(): return service.purchase(id, 1, id), "invalid_configuration")
	for bad: Variant in [0, -1, 1.0, 1.5, true, "1", null, [], {}, WalletTransactions.LIMIT + 1]:
		_unchanged(service, func(): return service.purchase("milk", bad, "bad"), "invalid_parameter")
	for bad: Variant in ["", "  ", 1, null]:
		_unchanged(service, func(): return service.purchase("milk", 1, bad), "invalid_parameter")
	_unchanged(service, func(): return service.purchase("milk", WalletTransactions.LIMIT, "overflow"), "amount_overflow")
	_check(service.purchase("free", 1, "free").ok and service.get_balance() == 86, "Explicitly configured free products work")
	_check(service.add_money(4, "income").ok and service.spend_money(90, "all").ok and service.get_balance() == 0, "Wallet credits/debits allow exact zero")
	_unchanged(service, func(): return service.spend_money(1, "negative"), "insufficient_funds")
	_check(service.add_money(WalletTransactions.LIMIT, "max").ok, "Maximum wallet amount is accepted")
	_unchanged(service, func(): return service.add_money(1, "excess"), "amount_overflow")
	service.free()

func _test_rewards() -> void:
	var menu := _menu()
	menu.initial_stock.erase("green_tea")
	menu.initial_discovery.erase("green_tea")
	var service := WalletTransactions.new(menu)
	_unchanged(service, func(): return service.claim_reward("bad_gift", "broken"), "invalid_item")
	_check(not service.get_inventory().is_discovered("green_tea"), "Failed multi-item reward never leaks discovery")
	_unchanged(service, func(): return service.claim_reward("missing", "missing"), "unknown_reward")
	_check(service.claim_reward("gift", "gift_1").ok and service.get_balance() == 120 and service.get_inventory().get_stock("pearl") == 11, "Multi-item and currency reward commits together")
	_unchanged(service, func(): return service.claim_reward("gift", "gift_2"), "already_claimed")
	_unchanged(service, func(): return service.claim_reward("task_gift", "task"), "task_unavailable")
	var state := StateData.new()
	var catalog := TaskCatalog.new()
	_check(catalog.load_file("res://tests/fixtures/tasks.json", {"events": ["task_test.review", "task_test.accept", "task_test.finish"], "locations": ["test.underground"]}) == OK, "Use real task loader for reward eligibility")
	var journal := TaskJournal.new()
	_check(journal.configure(catalog, state) == OK, "Real task projection configures")
	service.set_task_lookup(journal.get_task)
	_unchanged(service, func(): return service.claim_reward("task_gift", "task"), "task_incomplete")
	state.set_flag("task.test.active")
	state.set_flag("task.test.completed")
	journal.refresh()
	_check(service.claim_reward("task_gift", "task").ok, "Completed task can explicitly claim configured rewards")
	_unchanged(service, func(): return service.claim_reward("task_alias", "alias"), "already_claimed")
	journal.free()
	state.free()
	service.free()
	service = WalletTransactions.new(_menu())
	var inventory := service.get_inventory()
	inventory.add_ingredient("pearl", WalletTransactions.LIMIT - inventory.get_stock("pearl"))
	_unchanged(service, func(): return service.claim_reward("gift", "capacity"), "inventory_full")
	inventory.try_consume({"pearl": 3})
	_check(service.claim_reward("gift", "capacity").ok, "Failed reward does not mark request or reward as claimed; retry succeeds")
	_unchanged(service, func(): return service.purchase("free", 1, "full"), "inventory_full")
	service.free()

func _test_commit_failure() -> void:
	var service := WalletTransactions.new(_menu())
	# Fault injection at the existing inventory commit boundary, after validation.
	service.get_inventory().free()
	service._inventory = RefusingInventory.new(_menu())
	service.add_child(service._inventory)
	_unchanged(service, func(): return service.purchase("tea", 1, "refused"), "commit_failed")
	_unchanged(service, func(): return service.claim_reward("gift", "refused_reward"), "commit_failed")
	service._inventory.free()
	service._inventory = WarehouseInventory.new(_menu())
	service.add_child(service._inventory)
	_check(service.purchase("tea", 1, "refused").ok and service.claim_reward("gift", "refused_reward").ok, "Commit failure leaves purchase/reward IDs available for successful retry")
	service.free()

func _test_snapshots() -> void:
	var service := WalletTransactions.new(_menu())
	service.purchase("tea", 2, "saved_purchase")
	service.claim_reward("gift", "saved_reward")
	var saved := service.to_dict()
	var detached := service.to_dict()
	detached.inventory.ingredients.black_tea.quantity = 0
	detached.requests.clear()
	_check(service.to_dict() == saved, "Returned containers cannot mutate live economic state")
	var copy := WalletTransactions.new(_menu())
	var replayed: Array[Dictionary] = []
	copy.transaction_finished.connect(func(result: Dictionary) -> void: replayed.append(result))
	_check(copy.restore_state(JSON.parse_string(JSON.stringify(saved))) == OK and copy.to_dict() == saved, "Economy supports JSON numeric round trip")
	_check(replayed.is_empty(), "Loading economy never emits or replays reward transactions")
	_unchanged(copy, func(): return copy.purchase("tea", 1, "saved_purchase"), "duplicate_transaction")
	_unchanged(copy, func(): return copy.claim_reward("gift", "new_reward_request"), "already_claimed")
	for bad: Variant in [-1, 1.5, true, WalletTransactions.LIMIT + 1]:
		var broken := saved.duplicate(true)
		broken.balance = bad
		_check(copy.restore_state(broken) == ERR_INVALID_DATA and copy.to_dict() == saved, "Malformed wallet snapshot rejected atomically")
	var state := StateData.new()
	var economy := state.get_transactions()
	economy.add_money(40, "story_credit")
	economy.get_inventory().add_ingredient("black_tea", 3)
	state.set_flag("test.saved")
	var full := state.to_dict()
	# Use the existing native Variant snapshot contract with real file I/O.
	var path := "user://verify_wallet_transactions.tmp"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(full)
	file.close()
	var restored := StateData.new()
	file = FileAccess.open(path, FileAccess.READ)
	var disk: Dictionary = file.get_var()
	file.close()
	DirAccess.remove_absolute(path)
	_check(restored.restore_state(disk) == OK and restored.to_dict() == full, "GameState file round trip preserves story, wallet, inventory and receipts")
	_unchanged(restored.get_transactions(), func(): return restored.get_transactions().add_money(40, "story_credit"), "duplicate_transaction")
	var broken := full.duplicate(true)
	broken.flags["test.saved"] = false
	broken.economy.inventory.ingredients.black_tea.quantity = -1
	_check(restored.restore_state(broken) == ERR_INVALID_DATA and restored.to_dict() == full, "Corrupt inventory rejects entire GameState restore including story")
	var seen: Array[Dictionary] = []
	restored.state_changed.connect(func() -> void: seen.append(restored.to_dict()))
	var defaults := StateData.new()
	_check(restored.reset_state() and seen.size() == 1 and restored.to_dict() == defaults.to_dict(), "Reset publishes one complete default snapshot")
	defaults.free()
	var legacy := full.duplicate(true)
	legacy.erase("economy")
	legacy.schema_version = 1
	var before_legacy := restored.to_dict()
	_check(restored.restore_state(legacy) == ERR_INVALID_DATA and restored.to_dict() == before_legacy, "Legacy partial snapshot cannot erase the combined business/economy session")
	service.free()
	copy.free()
	state.free()
	restored.free()

func _test_session() -> void:
	var state := root.get_node("GameState")
	state.reset_state()
	var service: WalletTransactions = state.get_transactions()
	service.add_money(15, "cross_scene")
	var previous_inventory: WarehouseInventory
	for scene: String in ["res://src/debug/story/legacy_shop.tscn", "res://src/core/settlement.tscn"]:
		var main: MainGame = load(scene).instantiate()
		root.add_child(main)
		await process_frame
		await process_frame
		_check(main.get_transactions() == service and main.get_warehouse_inventory() == service.get_inventory(), "Scene shares GameState wallet/inventory: " + scene)
		_check(main.get_tea_production().get_inventory() == service.get_inventory(), "Production uses transaction inventory")
		if previous_inventory != null:
			_check(previous_inventory == service.get_inventory() and service.get_inventory().get_stock("black_tea") == 11 and service.get_balance() == 15, "Scene switch preserves wallet and production consumption")
		else:
			main.get_tea_production().make_drink(["black_tea", "creamer", "pearl", "syrup"], "order_001")
		previous_inventory = service.get_inventory()
		main.queue_free()
		await process_frame
		await process_frame
	state.reset_state()
