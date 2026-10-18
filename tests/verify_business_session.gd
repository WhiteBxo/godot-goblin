extends SceneTree

const StateData = preload("res://src/core/game_state.gd")
const SHOP := "res://src/debug/story/legacy_shop.tscn"
const SETTLEMENT := "res://src/core/settlement.tscn"
const RECIPE: Array[String] = ["black_tea", "creamer", "pearl", "syrup"]
var _checks := 0
var _failures: Array[String] = []
var _state: StateData

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames() -> void:
	for index in range(3):
		await process_frame

func _switch(path: String) -> MainGame:
	_check(change_scene_to_file(path) == OK, "Switch actual scene: " + path)
	await scene_changed
	await _frames()
	return current_scene as MainGame

func _open(game: MainGame, id: StringName) -> ShopPopup:
	game.get_shop_ui().close()
	for point: InteractionPoint in game.get_active_level().get_interaction_points():
		if point.interaction_id == id:
			game.get_shop_ui().open(point)
			return game.get_node("PopupLayer/Modal") as ShopPopup
	_check(false, "Interaction exists: " + String(id))
	return null

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	root.size = Vector2i(1280, 720)
	_state = root.get_node("GameState")
	_check(_state.start_new_game() == OK, "Explicit new game initializes the complete session")
	var defaults := _state.to_dict()
	var game := await _switch(SHOP)
	var inventory := game.get_warehouse_inventory()
	var production := game.get_tea_production()
	_check(inventory.get_parent() == _state.get_transactions() and _state.get_transactions().get_parent() == _state and production.get_parent() == _state, "Existing autoload owns wallet inventory and production services")
	_open(game, &"orders")
	var order_page := game.get_shop_ui().get_popup().get_page().get_order_board_page()
	order_page.select_order("order_001")
	order_page.get_ticket().get_primary_button().pressed.emit()
	_state.set_story_stage("session.test")
	_state.set_current_day(2)
	_state.complete_event("session.arrival")
	var reentries: Array[bool] = []
	var observer := func() -> void:
		reentries.append(_state.start_new_game() == ERR_BUSY and not _state.reset_state() and _state.restore_state(defaults) == ERR_BUSY and _state.get_transactions().add_money(1, "craft_reentry").code == "busy")
	production.changed.connect(observer)
	_check(production.make_drink(RECIPE, "order_001").ok, "Crafting commits a carried cup")
	production.changed.disconnect(observer)
	_check(reentries == [true], "Crafting notification cannot reset or restore the session")
	_check(not production.make_drink(RECIPE, "order_001").ok, "Duplicate production ID rejects")
	var popup := _open(game, &"storage")
	_check(inventory.add_ingredient("black_tea", 2) and "红茶  13" in popup.get_warehouse_panel().get_list().get_item_text(0), "Shared inventory mutation refreshes the open warehouse")
	_check(_state.get_transactions().get_inventory() == inventory, "Wallet and production share the same cross-scene inventory")
	_check(_state.get_transactions().add_money(25, "session_credit").ok, "Wallet commits credit in the business session")
	var carried := _state.to_dict()
	# Leave the entire MainGame, including every scene-local coordinator/UI.
	var empty := PackedScene.new()
	var empty_root := Node.new()
	empty.pack(empty_root)
	empty_root.free()
	_check(change_scene_to_packed(empty) == OK, "Leave shop for an unrelated scene")
	await scene_changed
	await _frames()
	_check(_state.to_dict() == carried and inventory.get_stock("pearl_milk_tea") == 1, "Leaving keeps stock, finished cups, orders and story facts")
	game = await _switch(SHOP)
	_check(game.get_warehouse_inventory() == inventory and game.get_tea_production() == production, "Reentry reuses services instead of rebuilding defaults")
	popup = _open(game, &"tea_station")
	_check("椰果茉莉奶茶" in popup.get_crafting_panel().order_text() and production.get_completed_count() == 1, "Reentered production UI restores order #002")
	_check(_state.to_dict() == carried, "Reentry never overwrites story or creates cups")
	_check(reload_current_scene() == OK, "Reload the real shop scene")
	await scene_changed
	await _frames()
	game = current_scene as MainGame
	_check(game.get_warehouse_inventory() == inventory and _state.to_dict() == carried, "Reload preserves the complete session and service identity")
	popup = _open(game, &"storage")
	_check("红茶  13" in popup.get_warehouse_panel().get_list().get_item_text(0) and inventory.get_stock("pearl_milk_tea") == 1, "Reloaded warehouse matches actual stock without duplication")
	game = await _switch(SETTLEMENT)
	_check(game.get_tea_production() == production and _state.to_dict() == carried, "Settlement uses the same operating session")
	var delivery := game.get_task_delivery()
	var delivery_observations: Array[bool] = []
	observer = func() -> void:
		delivery_observations.append(_state.start_new_game() == ERR_BUSY and _state.restore_state(carried) == ERR_BUSY and _state.get_variable("shop.orders_completed") == 1 and inventory.get_stock("pearl_milk_tea") == 0 and _state.get_flag("delivery.order_001.completed"))
	_state.state_changed.connect(observer)
	_check(delivery.deliver_to("fat_goblin").ok, "Carried cup delivers after crossing scenes")
	_state.state_changed.disconnect(observer)
	_check(delivery_observations == [true], "Delivery publishes inventory, counter and receipts together and rejects reset reentry")
	_check(inventory.get_stock("syrup") == 10 and inventory.get_stock("pearl_milk_tea") == 0, "Delivery consumes one cup and rewards once")
	var delivered := _state.to_dict()
	game = await _switch(SHOP)
	_check(not game.get_task_delivery().deliver_to("fat_goblin").ok and _state.to_dict() == delivered, "Rebuilt delivery cannot replay a receipt")
	production.changed.emit()
	inventory.changed.emit()
	_check(_state.to_dict() == delivered, "Duplicate notifications never create orders or rewards")
	_test_snapshots(delivered)
	popup = _open(game, &"orders")
	var restore_observations: Array[bool] = []
	observer = func() -> void:
		restore_observations.append(_state.to_dict() == carried and _state.start_new_game() == ERR_BUSY and not inventory.add_ingredient("syrup", 1) and not production.make_drink(RECIPE, "order_001").ok and not game.get_task_delivery().deliver_to("fat_goblin").ok and game.get_task_delivery().accept_order("order_001") != OK and not _state.set_flag("session.overwrite") and _state.get_transactions().add_money(1, "restore_reentry").code == "busy" and _state.get_transactions().restore_state(carried.economy) == ERR_BUSY)
	_state.state_changed.connect(observer)
	_check(_state.restore_state(carried) == OK, "Restore carried state as one complete session")
	_state.state_changed.disconnect(observer)
	_check(restore_observations == [true], "Restore observers see complete state and cannot mutate it")
	_check(game.get_task_journal().get_task("shop.first_order").status == "active" and game.get_order_board().get_entry("order_001").ready, "Restoring receipts refreshes the open order board and task projection")
	_check(_state.start_new_game() == OK and _state.to_dict() == defaults, "New game clears inventory progress, products, receipts and story together")
	_check(game.get_warehouse_inventory() == inventory and production.get_completed_count() == 0 and inventory.get_stock("pearl_milk_tea") == 0, "New game keeps UI subscriptions and resets the existing services")
	_check("珍珠奶茶" in popup.get_page().get_description_text() and "当前没有待交付订单" in popup.get_page().get_description_text(), "Open order board reflects new game without cached delivery requirements")
	popup = _open(game, &"storage")
	_check("红茶  12" in popup.get_warehouse_panel().get_list().get_item_text(0), "New game warehouse shows initial stock")
	var fresh := StateData.new()
	_check(fresh.to_dict() == defaults, "Fresh process/session defaults do not inherit the old run")
	_check(fresh.get_tea_production().make_drink(RECIPE, "order_001").ok and fresh.reset_state() and fresh.to_dict() == defaults, "Compatibility reset also clears business-only progress without story facts")
	var resets: Array[bool] = []
	fresh.state_reset.connect(func() -> void: resets.append(true))
	_check(fresh.start_new_game() == OK and resets == [true] and not fresh.reset_state(), "Explicit new game signals cancellation even at defaults; redundant compatibility reset is silent")
	fresh.free()
	print("BUSINESS_SESSION: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_snapshots(baseline: Dictionary) -> void:
	var restored := StateData.new()
	# Native Variant round trip exercises the existing snapshot boundary, not a new save system.
	var round_trip: Variant = bytes_to_var(var_to_bytes(baseline))
	_check(restored.restore_state(round_trip) == OK and restored.to_dict() == baseline, "Native snapshot round trip includes all business and story data")
	restored.free()
	var notifications: Array[bool] = []
	var observer := func() -> void: notifications.append(true)
	_state.state_changed.connect(observer)
	_check(_state.restore_state(baseline) == OK and notifications.is_empty(), "Identical complete restore is silent")
	var invalid: Array[Dictionary] = []
	var data := baseline.duplicate(true)
	data.schema_version = 1
	invalid.append(data)
	data = baseline.duplicate(true)
	data.erase("business")
	invalid.append(data)
	for ids: Variant in [null, ["unknown"], ["order_002"], ["order_001", "order_001"], [1]]:
		data = baseline.duplicate(true)
		data.business.production.completed_order_ids = ids
		invalid.append(data)
	data = baseline.duplicate(true)
	data.business.inventory.ingredients.syrup.quantity += 1
	invalid.append(data)
	data = baseline.duplicate(true)
	data.business.inventory.ingredients.syrup.quantity = -1
	data.flags["session.partial_write"] = true
	invalid.append(data)
	for snapshot: Dictionary in invalid:
		_check(_state.restore_state(snapshot) == ERR_INVALID_DATA and _state.to_dict() == baseline, "Invalid/partial/legacy snapshot rejects atomically")
	_check(notifications.is_empty(), "Rejected restores produce no notifications")
	_state.state_changed.disconnect(observer)
