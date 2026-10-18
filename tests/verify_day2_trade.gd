extends SceneTree
## All economic figures here are isolated fixtures, never formal Day 2 design.

const StateData = preload("res://src/core/game_state.gd")
const Purchase = preload("res://src/core/economy/tavern_purchase.gd")
const Casino = preload("res://src/core/economy/fixed_story_casino.gd")
const POPUP = preload("res://src/UI/trade/tavern_purchase_popup.tscn")

var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _offers() -> Dictionary:
	return {"test_wine": {"item_id": "griffin_amber_wine", "price": 10, "discounted_price": 8, "stock": 2},
		"test_tea": {"item_id": "black_tea", "price": 3}}

func _menu() -> TeaMenu:
	var menu: TeaMenu = WarehouseInventory.CATALOG.duplicate(true)
	menu.initial_balance = 12
	menu.products = Purchase.compile_products(_offers()).products
	return menu

func _task(allow_cancel: bool = true) -> Dictionary:
	return {"id": "trade_test.debt", "type": "commission", "title": "测试债务", "description": "隔离配置，不代表正式债务期限。",
		"activate_when": {"type": "flag", "key": "trade_test.debt_active"},
		"complete_when": {"type": "flag", "key": "trade_test.debt_paid"}, "allow_cancel": allow_cancel,
		"delivery": {"order_id": "test_debt", "items": {"black_tea": 1}, "target_object_id": "test_boss", "accepted_flag": "trade_test.debt_accepted"},
		"objectives": [{"id": "pay", "text": "测试交付", "complete_when": {"type": "flag", "key": "trade_test.debt_paid"}}]}

func _catalog(allow_cancel: bool = true) -> TaskCatalog:
	var catalog := TaskCatalog.new()
	_check(catalog.load_json(JSON.stringify({"version": 1, "tasks": [_task(allow_cancel)]})) == OK, "Debt fixture passes the actual TaskCatalog schema")
	return catalog

func _settings() -> Dictionary:
	return {"debt_task_id": "trade_test.debt", "loss_receipt": "trade_test.first_loss", "win_receipt": "trade_test.second_win",
		"reward_items": {"phantom_gold_mushroom": 2, "rainbow_cube": 1}}

func _run() -> void:
	_test_purchase()
	_test_casino()
	await _test_ui()
	print("DAY2_TRADE: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_purchase() -> void:
	for bad: Variant in [null, -1, 1.5, true, "8", WalletTransactions.LIMIT + 1]:
		var offers := _offers()
		offers.test_wine.discounted_price = bad
		_check(not Purchase.compile_products(offers).ok, "Invalid discount is rejected without coercion: " + str(bad))
	var offers := _offers()
	offers.test_wine.discount_price = 8
	_check(not Purchase.compile_products(offers).ok, "Misspelled discount field cannot silently fall back to full price")
	offers.test_wine.erase("discount_price")
	offers.test_wine.discounted_price = 11
	_check(not Purchase.compile_products(offers).ok, "Discount cannot exceed base price")
	var wallet := WalletTransactions.new(_menu())
	var service := Purchase.new()
	root.add_child(service)
	_check(service.configure(wallet, offers) == ERR_INVALID_DATA, "Invalid offers do not bind")
	_check(service.configure(wallet, _offers()) == OK, "Purchase component binds existing session wallet")
	var before := wallet.to_dict()
	var result := service.purchase("test_wine", 2, "test:poor")
	_check(result.code == "insufficient_funds" and wallet.to_dict() == before, "Insufficient balance changes no money, item, stock or receipt")
	var observations: Array[Dictionary] = []
	var nested: Array[Dictionary] = []
	wallet.get_inventory().changed.connect(func() -> void:
		observations.append(wallet.to_dict())
		nested.append(service.purchase("test_wine", 1, "test:nested")))
	result = service.purchase("test_wine", 1, "test:buy")
	_check(result.ok and result.money_delta == -8 and result.items == {"griffin_amber_wine": 1}, "Explicit discounted price charges once and issues real wine")
	_check(result.balance == 4 and wallet.to_dict().merchant_stock.test_wine == 1 and wallet.to_dict().requests.has("test:buy"), "Balance, merchant stock and successful receipt agree")
	_check(observations.size() == 1 and observations[0] == wallet.to_dict() and nested[0].code == "busy", "Synchronous observers see complete purchase and reject reentry")
	before = wallet.to_dict()
	_check(service.purchase("test_wine", 1, "test:buy").code == "duplicate_transaction" and wallet.to_dict() == before, "Repeated request does not charge or issue items twice")
	_check(service.purchase("test_tea", 2, "test:buy").code == "duplicate_transaction", "Reusing a successful request for another product is rejected")
	wallet.add_money(20, "test:fund")
	_check(service.purchase("test_wine", 1, "test:poor").ok, "Failed request remains retryable after funding")
	before = wallet.to_dict()
	_check(service.purchase("test_wine", 1, "test:sold").code == "out_of_stock" and wallet.to_dict() == before, "Sold out inventory refuses atomically")
	var copy := WalletTransactions.new(_menu())
	_check(copy.restore_state(before) == OK, "Wallet snapshot restores merchant stock, inventory and receipts")
	service.configure(copy, _offers())
	_check(service.get_offers()[0].remaining == 0 and service.get_balance() == copy.get_balance(), "Rebinding projects restored stock and balance")
	_check(service.purchase("test_wine", 1, "test:buy").code == "duplicate_transaction", "Receipt still prevents replay after restore")
	_check(service.purchase("test_wine", 1, "test:fresh").code == "out_of_stock", "Fresh request cannot bypass restored sold-out stock")
	_check(service.purchase("test_tea", 1, "test:unlimited").ok, "Unlimited configured product remains purchasable")
	var projected := service.get_offers()
	projected[0].remaining = 999
	_check(service.get_offers()[0].remaining == 0, "Offer projections do not expose mutable stock")
	service.free()
	wallet.free()
	copy.free()

func _test_casino() -> void:
	var state := StateData.new()
	root.add_child(state)
	var catalog := _catalog()
	_check(state.bind_task_catalog(catalog) == OK, "Host binds A's full catalog")
	var casino := Casino.new()
	root.add_child(casino)
	_check(casino.configure(state, catalog, {}) == ERR_UNCONFIGURED, "Missing reward/configuration stays pending")
	_check(casino.configure(state, catalog, _settings()) == OK, "Fixed rounds accept a resolved, explicit reward bundle")
	var collision := _settings()
	collision.win_receipt = "trade_test.debt_paid"
	_check(casino.configure(state, catalog, collision) == ERR_INVALID_DATA, "Win receipt cannot accidentally complete the debt")
	var before := state.to_dict()
	_check(not casino.settle_second_win().ok and not casino.waive_debt("测试免除").ok and state.to_dict() == before, "No win or waiver before the first fixed round")
	var notices: Array[bool] = []
	state.state_changed.connect(func() -> void:
		if state.get_flag("trade_test.first_loss"):
			notices.append(state.get_flag("trade_test.debt_active") and state.get_flag("trade_test.debt_accepted")))
	_check(casino.settle_first_loss().ok, "First loss establishes configured task activation and receipt")
	_check(notices == [true] and state.get_task_result("trade_test.debt").is_empty(), "Debt is active, with no invented failure or terminal result")
	before = state.to_dict()
	_check(casino.settle_first_loss().code == "duplicate_transaction" and state.to_dict() == before, "First loss cannot establish or charge twice")
	var after_loss := state.to_dict()
	casino.free()
	casino = Casino.new()
	root.add_child(casino)
	casino.configure(state, catalog, _settings())
	_check(casino.get_status().first_settled and not casino.get_status().second_settled, "Component reconstruction projects the persistent first result")
	var inventory := state.get_warehouse_inventory()
	inventory.add_ingredient("rainbow_cube", WalletTransactions.LIMIT - inventory.get_stock("rainbow_cube"))
	before = state.to_dict()
	_check(casino.settle_second_win().code == "inventory_full" and state.to_dict() == before, "A full second reward item prevents all rewards and win receipt")
	_check(state.restore_state(after_loss) == OK, "Full session restores the pre-win boundary")
	var mushroom_before := inventory.get_stock("phantom_gold_mushroom")
	var cube_before := inventory.get_stock("rainbow_cube")
	var win_observations: Array[bool] = []
	var nested: Array[bool] = []
	inventory.changed.connect(func() -> void:
		if state.get_flag("trade_test.second_win"):
			win_observations.append(inventory.get_stock("phantom_gold_mushroom") == mushroom_before + 2 and inventory.get_stock("rainbow_cube") == cube_before + 1)
			nested.append(not casino.settle_second_win().ok and not casino.waive_debt("同步重入").ok))
	var result := casino.settle_second_win()
	_check(result.ok and result.items == _settings().reward_items and win_observations == [true], "Win atomically commits actual configured items and durable receipt")
	_check(nested == [true], "Reward observers cannot reenter fixed settlement or waive debt during commit")
	_check(state.get_task_result("trade_test.debt").is_empty(), "Winning leaves waiver to its separate authored action")
	var after_win := state.to_dict()
	_check(casino.settle_second_win().code == "duplicate_transaction" and state.to_dict() == after_win, "Repeated win issues no reward")
	var settled: Array[String] = []
	state.task_settled.connect(func(id: String, _outcome: Dictionary) -> void: settled.append(id))
	_check(casino.waive_debt("测试免除").ok, "Waiver uses A's explicit cancellation interface")
	var status := casino.get_status()
	_check(status.debt_result.status == "cancelled" and status.debt_result.reason == "测试免除" and settled == ["trade_test.debt"], "A owns the single durable cancellation result")
	before = state.to_dict()
	_check(casino.waive_debt("重复").code == "already_settled" and state.to_dict() == before, "Duplicate waiver cannot overwrite the result")
	var file := FileAccess.open("user://verify_day2_trade.tmp", FileAccess.WRITE)
	file.store_var(before)
	file.close()
	file = FileAccess.open("user://verify_day2_trade.tmp", FileAccess.READ)
	var saved: Dictionary = file.get_var()
	file.close()
	DirAccess.remove_absolute("user://verify_day2_trade.tmp")
	var fresh := StateData.new()
	root.add_child(fresh)
	fresh.bind_task_catalog(catalog)
	var restore_events: Array[bool] = []
	fresh.task_settled.connect(func(_id: String, _result: Dictionary) -> void: restore_events.append(true))
	_check(fresh.restore_state(saved) == OK, "Full native file round trip restores casino and task outcomes")
	casino.configure(fresh, catalog, _settings())
	_check(casino.get_status() == status and restore_events.is_empty(), "Restored outcome is identical without replaying task settlement")
	before = fresh.to_dict()
	_check(not casino.settle_first_loss().ok and not casino.settle_second_win().ok and not casino.waive_debt("重复").ok and fresh.to_dict() == before, "All fixed outcomes remain replay-safe in a restored fresh session")
	_check(fresh.restore_state(after_win) == OK and casino.waive_debt("恢复后免除").ok, "Win-before-waiver boundary resumes only the remaining cancellation")
	_check(fresh.start_new_game() == OK and not casino.get_status().first_settled, "New game clears fixed-round facts with the shared session")
	var no_cancel := _catalog(false)
	fresh.bind_task_catalog(no_cancel)
	casino.configure(fresh, no_cancel, _settings())
	casino.settle_first_loss()
	casino.settle_second_win()
	before = fresh.to_dict()
	_check(not casino.waive_debt("不允许").ok and fresh.to_dict() == before, "Missing cancellation permission stays pending without inventing a waiver")
	casino.free()
	state.free()
	fresh.free()

func _test_ui() -> void:
	root.size = Vector2i(640, 360)
	var wallet := WalletTransactions.new(_menu())
	var service := Purchase.new()
	root.add_child(service)
	service.configure(wallet, _offers())
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var manager := UIManager.new()
	root.add_child(manager)
	manager.configure({&"popup": layer})
	var popup := POPUP.instantiate() as TavernPurchasePopup
	popup.configure(service)
	_check(manager.register_screen(ScreenIds.TAVERN_PURCHASE, popup, &"popup", true) == OK, "Purchase screen registers as a native modal")
	_check(manager.open_screen(ScreenIds.TAVERN_PURCHASE) == OK and manager.has_modal(), "Purchase screen opens and reports the modal lock")
	await process_frame
	var page := (popup.get_node("ModalShell") as ModalShell).get_content()
	var buy: Button = page.get_node("%Buy")
	var again: Button = page.get_node("%Again")
	var quantity: SpinBox = page.get_node("%Quantity")
	var feedback: Label = page.get_node("%Feedback")
	var quote: Label = page.get_node("%Quote")
	_check(quote.text.contains("原价 10G → 折后 8G") and popup.get_default_focus() != null, "Purchase screen shows the configured discount and keyboard focus")
	_check(root.gui_get_focus_owner() == popup.get_default_focus(), "UIManager focuses the purchase list on opening")
	quantity.get_line_edit().text = "2"
	buy.pressed.emit()
	_check(feedback.text.contains("余额不足") and wallet.get_balance() == 12 and quantity.value == 2, "UI applies unsubmitted quantity text and exposes real insufficient-funds feedback")
	quantity.get_line_edit().text = "1"
	buy.pressed.emit()
	var after := wallet.to_dict()
	buy.pressed.emit()
	_check(buy.disabled and again.visible and wallet.to_dict() == after, "Repeated confirmation callback stays the same completed intent")
	_check(feedback.text.contains("成功") and quote.text.contains("已完成") and not quote.text.contains("余额不足"), "Completed confirmation displays its receipt without a next-purchase shortage")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _capture("success")
	again.pressed.emit()
	buy.pressed.emit()
	_check(feedback.text.contains("余额不足"), "Explicit next purchase rechecks balance")
	wallet.add_money(20, "ui:fund")
	buy.pressed.emit()
	again.pressed.emit()
	buy.pressed.emit()
	_check(feedback.text.contains("库存不足") and quote.text.contains("售罄"), "UI exposes exhausted stock and the wallet refusal")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _capture("sold_out")
	manager.request_back()
	_check(not manager.has_modal() and not popup.visible, "Cancel closes through UIManager and releases its modal state")
	manager.open_screen(ScreenIds.TAVERN_PURCHASE)
	_check(popup.visible and quote.text.contains("售罄"), "Reopening projects existing session stock")
	(popup.get_node("ModalShell") as ModalShell).get_close_button().pressed.emit()
	_check(not manager.has_modal(), "Mouse close follows the same modal lifecycle")
	layer.free()
	manager.free()
	service.free()
	wallet.free()

func _capture(label: String) -> void:
	for size: Vector2i in [Vector2i(640, 360), Vector2i(320, 360)]:
		root.content_scale_size = size
		root.size = size
		for frame in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/day2_trade_%s_%d.png" % [label, size.x])
