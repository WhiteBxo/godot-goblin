extends SceneTree
## Gift quantities and cancellation through the formal order-board route.

const SHOP = preload("res://src/core/main.tscn")
var _state: Node
var _game: MainGame
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)

func frames(count := 4) -> void:
	for index in range(count):
		await process_frame

func wait_group(scheduler: BusinessScheduler, group: String, status: String) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while scheduler.get_group(group).get("status") != status and Time.get_ticks_msec() < deadline:
		await process_frame
	return scheduler.get_group(group).get("status") == status

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	ProjectSettings.set_setting("persistence/save_directory", "/tmp/goblin_cancel_%d" % OS.get_process_id())
	_state = root.get_node("GameState")
	_state.start_new_game()
	_state.select_business_profile("day1")
	_state.set_story_stage("day1.s04.wait_taste")
	_game = SHOP.instantiate()
	root.add_child(_game)
	current_scene = _game
	await frames(8)
	var inventory: WarehouseInventory = _state.get_warehouse_inventory()
	check(_game.get_chapter_gameplay().execute("day1.s04.gift").ok, "Fat goblin gives the actual chapter gift")
	var gift := inventory.get_ingredient_view("goblin_firebrew")
	check(gift.quantity == 1 and gift.uses == 5 and gift.current_portion_uses == 5, "Gift is one full five-use firebrew portion")
	check(inventory.get_uses("firefly_cap") == 2, "Other gift quantities stay unchanged")
	check(_game.get_shop_ui().get_feedback_text().contains("5 次用量"), "Gift feedback states five actual uses")
	_game.get_chapter_gameplay().execute("day1.s04.gift")
	check(inventory.get_uses("goblin_firebrew") == 5, "Gift replay cannot duplicate the full portion")
	current_scene = null
	_game.queue_free()
	await frames()
	_state.start_new_game()
	_state.select_business_profile("day1")
	_state.current_day = 2
	_state.set_story_stage("day2.s02.wait_close")
	_state.set_flag("day2.s02.open")
	_game = SHOP.instantiate()
	root.add_child(_game)
	current_scene = _game
	await frames(8)
	inventory = _state.get_warehouse_inventory()
	var delivery := _game.get_task_delivery()
	var model := _game.get_order_board()
	var scheduler := _game.get_chapter_gameplay().get_scheduler()
	check(scheduler != null, "Formal second-day customer scheduler loads")
	if scheduler == null:
		quit(1)
		return
	check(scheduler.publish_stage("festival") == OK, "Publish ordinary customers alongside the first story group")
	check(await wait_group(scheduler, "ordinary_b", "waiting"), "Ordinary customer actually arrives")
	check(delivery.cancel_order("day2_ordinary_b") != OK, "An unaccepted order cannot be cancelled")
	check(delivery.accept_order("day2_ordinary_b") == OK, "Accept ordinary customer order")
	check(delivery.accept_order("day2_special_spicy") == OK, "Accept the same customer's optional special")
	var ui := _game.get_shop_ui()
	for point: InteractionPoint in _game.get_active_level().get_interaction_points():
		if point.interaction_id == &"orders":
			ui.open(point)
	await frames()
	var page := ui.get_popup().get_page().get_order_board_page()
	check(page.select_order("day2_ordinary_b"), "Select the ordinary order on the actual board")
	var secondary := page.get_ticket().get_node("%Secondary") as Button
	check(secondary.is_visible_in_tree() and secondary.text == "取消订单", "Ordinary order displays its cancel action")
	var before := inventory.to_dict()
	var balance: int = _state.get_transactions().get_balance()
	var completed := delivery.get_completed_count()
	secondary.pressed.emit()
	await frames()
	check(model.get_entry("day2_ordinary_b").status == "cancelled", "Board button stores the ordinary order cancellation")
	check(scheduler.get_group("ordinary_b").status == "waiting", "Customer waits while their accepted special is still pending")
	check(inventory.to_dict() == before and _state.get_transactions().get_balance() == balance, "Cancel does not change inventory or money")
	check(delivery.get_completed_count() == completed and not _state.get_flag("delivery.day2_ordinary_b.completed"), "Cancellation never creates sales or completion receipts")
	check(not delivery.try_submit("day2_ordinary_b", "day2_ordinary_b").ok and not delivery.can_accept_order("day2_ordinary_b"), "Cancelled orders cannot be delivered or accepted again")
	check(delivery.cancel_order("day2_ordinary_b") != OK, "Duplicate cancellation is rejected")
	for id: String in ["goblin_firebrew", "scorch_tongue_pepper"]:
		inventory.add_ingredient(id, 1)
	var materials: Array[String] = ["goblin_firebrew", "scorch_tongue_pepper"]
	check(_state.confirm_formula(materials, "cancel.price").ok, "Price the optional spicy drink")
	var cup := _game.get_tea_production().craft_formula(materials, 1, "cancel.craft")
	check(cup.get("ok", false) and model.get_entry("day2_special_spicy").ready, "Prepare a real matching cup before cancelling")
	check(page.select_order("day2_special_spicy"), "Select the prepared special")
	check(secondary.is_visible_in_tree(), "Ready orders keep their cancel action")
	before = inventory.to_dict()
	secondary.pressed.emit()
	await frames()
	check(delivery.is_order_cancelled("day2_special_spicy") and inventory.to_dict() == before, "Cancelling a prepared special preserves the cup and its ingredients")
	check(scheduler.get_group("ordinary_b").status in ["leaving", "departed"], "Customer can leave after all their orders are resolved")
	ui.close()
	check(await wait_group(scheduler, "ordinary_b", "departed"), "Cancelled customer finishes the actual departure route")
	# A cancelled errand must read as settled for the counter too: the remaining
	# blocker is the guests still waiting, not the order the player gave up.
	var reason: String = _game.get_chapter_gameplay().get_close_block_reason()
	check(reason.contains("招待好") and not reason.contains("没有交付"), "Cancelled errand no longer blocks the counter: " + reason)
	# day2_taste is not part of any close rule order set; it gates the day through
	# the departure guard. The counter no longer checks it locally, so prove the
	# guard still holds a customer with a pending slip.
	check(await wait_group(scheduler, "ordinary_c", "waiting"), "Ordinary customer C is waiting")
	check(delivery.accept_order("day2_ordinary_c") == OK and delivery.cancel_order("day2_ordinary_c") == OK,
		"Settle C's own cup so only the optional tasting remains")
	check(delivery.accept_order("day2_taste") == OK, "Accept the optional tasting")
	check(scheduler.request_departure("ordinary_c") != OK, "A pending tasting keeps its customer from leaving")
	check(delivery.cancel_order("day2_taste") == OK, "Cancel the optional tasting")
	check(scheduler.request_departure("ordinary_c") == OK, "Cancelled tasting releases the customer")
	var saved: Dictionary = _state.to_dict()
	var invalid := saved.duplicate(true)
	invalid.task_results = []
	check(_state.restore_state(invalid) != OK and _state.to_dict() == saved, "Malformed cancellation results reject the entire snapshot")
	_state.start_new_game()
	check(_state.restore_state(saved) == OK and delivery.is_order_cancelled("day2_ordinary_b"), "Cancellation persists through snapshot restore")
	var task: Dictionary = {}
	for entry: Dictionary in _game.get_task_catalog().get_tasks():
		if entry.id == "day1.s04.taste":
			task = entry
	check(not task.get("allow_cancel", false) and delivery.cancel_order("day1_s04_taste") != OK, "Story-required orders remain protected")
	current_scene = null
	_game.queue_free()
	await frames()
	print("ORDER_CANCELLATION: %s (%d checks, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)
