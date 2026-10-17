extends SceneTree

const StateData = preload("res://src/core/game_state.gd")
const TASKS := "res://src/resources/tasks/tasks.json"
const RECIPE: Array[String] = ["black_tea", "creamer", "pearl", "syrup"]
var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	_test_schema()
	_test_transaction()
	_test_multiple_orders()
	await _test_host("res://src/debug/story/legacy_shop.tscn")
	await _test_host("res://src/core/settlement.tscn")
	print("TASK_DELIVERY: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_schema() -> void:
	var catalog := TaskCatalog.new()
	_check(catalog.load_file(TASKS) == OK, "Delivery task loads through existing catalog")
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TASKS))
	for field: String in ["order_id", "product_id", "target_object_id"]:
		for invalid: Variant in [null, "", "has space", 7, true]:
			var data := baseline.duplicate(true)
			data.tasks[0].delivery[field] = invalid
			_check(catalog.load_json(JSON.stringify(data)) == ERR_INVALID_DATA and field in catalog.last_error, "Reject invalid delivery ID: " + field)
		var missing := baseline.duplicate(true)
		missing.tasks[0].delivery.erase(field)
		_check(catalog.load_json(JSON.stringify(missing)) == ERR_INVALID_DATA, "Reject missing delivery field: " + field)
	for invalid: Variant in [null, [], {}, {"syrup": 0}, {"syrup": 1.5}, {"syrup": true}, {"syrup": 2147483648}, {"bad id": 1}]:
		var data := baseline.duplicate(true)
		data.tasks[0].rewards.items = invalid
		_check(catalog.load_json(JSON.stringify(data)) == ERR_INVALID_DATA, "Reject malformed item rewards")
	var duplicate := baseline.duplicate(true)
	duplicate.tasks.append(duplicate.tasks[0].duplicate(true))
	duplicate.tasks[duplicate.tasks.size() - 1].id = "shop.other_task"
	_check(catalog.load_json(JSON.stringify(duplicate)) == ERR_INVALID_DATA and "order_id" in catalog.last_error, "Order IDs are unique across tasks")
	_check(catalog.get_tasks() == baseline.tasks, "Invalid loads preserve delivery catalog")

func _test_transaction() -> void:
	var state := StateData.new()
	var catalog := TaskCatalog.new()
	catalog.load_file(TASKS)
	var journal := TaskJournal.new()
	journal.configure(catalog, state)
	var inventory := WarehouseInventory.new()
	var production := TeaProduction.new()
	production.configure(inventory)
	var delivery := TaskDelivery.new()
	_check(delivery.configure(catalog, journal, state, inventory) == OK, "Coordinator reuses existing task/state/inventory")
	var before := state.to_dict()
	_check(state.apply_flags({"valid.key": true, "invalid": true}) == ERR_INVALID_DATA and state.to_dict() == before, "Invalid batch facts do not partially commit")
	inventory.add_ingredient("pearl_milk_tea", WarehouseInventory.MAX_QUANTITY)
	var full_stock := inventory.to_dict()
	_check(not production.make_drink(RECIPE, "order_001").ok and inventory.to_dict() == full_stock and production.get_completed_count() == 0, "Full product inventory rejects crafting without consuming ingredients or advancing queue")
	inventory.try_consume({"pearl_milk_tea": WarehouseInventory.MAX_QUANTITY})
	_check(production.make_drink(RECIPE, "order_001").ok and inventory.get_stock("pearl_milk_tea") == 1, "Crafting puts a finished cup in inventory")
	_check(not state.get_flag("shop.order_001_delivered") and state.to_dict() == before, "Crafting never writes delivery, task or reward facts")
	var stock := inventory.to_dict()
	_check(not delivery.try_deliver("order_001", "pearl_milk_tea", "fat_goblin").ok, "Inactive task rejects a carried cup")
	_check(state.to_dict() == before and inventory.to_dict() == stock, "Inactive rejection changes nothing")
	_check(delivery.accept_order("order_001") == OK and journal.get_task("shop.first_order").status == "active", "Explicit acceptance uses existing activation fact")
	before = state.to_dict()
	for attempt: Array in [["order_001", "pearl_milk_tea", "elder"], ["order_001", "plain_milk_tea", "fat_goblin"], ["unknown", "pearl_milk_tea", "fat_goblin"]]:
		_check(not delivery.try_deliver(attempt[0], attempt[1], attempt[2]).ok and inventory.to_dict() == stock and state.to_dict() == before, "Wrong NPC/product/order leaves all state unchanged")
	inventory.try_consume({"pearl_milk_tea": 1})
	stock = inventory.to_dict()
	_check(not delivery.deliver_to("fat_goblin").ok and inventory.to_dict() == stock and state.to_dict() == before, "Missing cup rejects without reward or completion")
	inventory.add_ingredient("pearl_milk_tea", 2)
	inventory.add_ingredient("syrup", WarehouseInventory.MAX_QUANTITY - inventory.get_stock("syrup"))
	stock = inventory.to_dict()
	_check(not delivery.deliver_to("fat_goblin").ok and inventory.to_dict() == stock and state.to_dict() == before, "Reward overflow cannot consume cup or complete task")
	inventory.try_consume({"syrup": WarehouseInventory.MAX_QUANTITY - 9})
	var observations: Array[bool] = []
	var reentries: Array[bool] = []
	var observer := func() -> void:
		observations.append(inventory.get_stock("pearl_milk_tea") == 1 and inventory.get_stock("syrup") == 10 and state.get_flag("shop.order_001_delivered") and state.get_flag("delivery.order_001.completed") and journal.get_task("shop.first_order").status == "completed")
		reentries.append(delivery.deliver_to("fat_goblin").ok)
	state.state_changed.connect(observer)
	inventory.changed.connect(observer)
	var payouts: Array[String] = []
	delivery.delivered.connect(func(id: String) -> void:
		payouts.append(id)
		reentries.append(delivery.deliver_to("fat_goblin").ok))
	_check(delivery.deliver_to("fat_goblin").ok, "Matching active task consumes one cup and awards inventory items")
	_check(observations == [true, true] and not true in reentries and payouts == ["order_001"], "All synchronous observers see full commit; every reentry rejects")
	state.state_changed.disconnect(observer)
	inventory.changed.disconnect(observer)
	before = state.to_dict()
	stock = inventory.to_dict()
	_check(not delivery.deliver_to("fat_goblin").ok and delivery.accept_order("order_001") == ERR_ALREADY_EXISTS and state.to_dict() == before and inventory.to_dict() == stock, "Completed task cannot deliver or collect a second reward")
	var rebuilt := TaskDelivery.new()
	rebuilt.configure(catalog, journal, state, inventory)
	_check(not rebuilt.deliver_to("fat_goblin").ok, "Coordinator replacement cannot replay a completed order")
	state.set_flag("shop.order_001_delivered", false)
	_check(not rebuilt.deliver_to("fat_goblin").ok, "Receipt prevents replay even if a task completion flag is cleared")
	state.restore_state(before)
	inventory.restore_state(stock)
	_check(not rebuilt.deliver_to("fat_goblin").ok and inventory.to_dict() == stock, "Snapshot restore never replays payouts")
	var invalid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TASKS))
	invalid.tasks[0].delivery.product_id = "black_tea"
	catalog.load_json(JSON.stringify(invalid))
	_check(rebuilt.configure(catalog, journal, state, inventory) == ERR_INVALID_DATA, "Ingredient cannot masquerade as finished product")
	invalid.tasks[0].delivery.product_id = "pearl_milk_tea"
	invalid.tasks[0].rewards.items = {"missing_item": 1}
	catalog.load_json(JSON.stringify(invalid))
	_check(rebuilt.configure(catalog, journal, state, inventory) == ERR_INVALID_DATA, "Unknown reward fails configuration before gameplay")
	rebuilt.free()
	delivery.free()
	production.free()
	inventory.free()
	journal.free()
	state.free()

func _test_multiple_orders() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TASKS))
	var second: Dictionary = data.tasks[0].duplicate(true)
	second.id = "shop.second_delivery"
	second.delivery.order_id = "order_002"
	second.delivery.product_id = "coconut_milk_tea"
	second.complete_when.key = "shop.order_002_delivered"
	second.objectives[1].complete_when.key = "shop.order_002_delivered"
	second.rewards.items = {"black_tea": 2, "syrup": 2}
	data.tasks.append(second)
	var catalog := TaskCatalog.new()
	_check(catalog.load_json(JSON.stringify(data)) == OK, "Three delivery fields configure a second product/order")
	var state := StateData.new()
	var journal := TaskJournal.new()
	journal.configure(catalog, state)
	var inventory := WarehouseInventory.new()
	inventory.add_ingredient("coconut_milk_tea", 1)
	var delivery := TaskDelivery.new()
	_check(delivery.configure(catalog, journal, state, inventory) == OK and delivery.accept_order("order_002") == OK, "Reusable coordinator accepts additional order data")
	_check(delivery.deliver_to("fat_goblin").ok and state.get_flag("shop.order_002_delivered") and not state.get_flag("shop.order_001_delivered"), "Missing first cup does not block a matching second order at the same NPC")
	_check(inventory.get_stock("coconut_milk_tea") == 0 and inventory.get_stock("black_tea") == 14 and inventory.get_stock("syrup") == 12, "Multiple item rewards commit together for the correct product")
	var before := inventory.to_dict()
	_check(not delivery.deliver_to("fat_goblin").ok and inventory.to_dict() == before, "Completed second order cannot pay again while first is incomplete")
	delivery.free()
	inventory.free()
	journal.free()
	state.free()

func _frames() -> void:
	for index in range(4):
		await physics_frame
	await process_frame

func _capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/" + name + ".png")

func _press_interact() -> void:
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventAction.new()
	event.action = &"interact"
	Input.parse_input_event(event)
	await process_frame

func _test_host(path: String) -> void:
	var state: StateData = root.get_node("GameState")
	state.reset_state()
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	var game: MainGame = load(path).instantiate()
	if path.ends_with("legacy_shop.tscn"):
		var wrong: SettlementCharacter = load("res://src/gameplay/characters/elder.tscn").instantiate()
		wrong.position = Vector2(1100, 750)
		game.get_node("World/EntityRoot").add_child(wrong)
	root.add_child(game)
	current_scene = game
	await _frames()
	var board: InteractionPoint
	var station: InteractionPoint
	for point: InteractionPoint in game.get_active_level().get_interaction_points():
		if point.interaction_id == &"orders":
			board = point
		if point.interaction_id == &"tea_station":
			station = point
	var player := game.get_player()
	var ui := game.get_shop_ui()
	player.global_position = board.global_position + Vector2(0, -55)
	await _frames()
	await _press_interact()
	_check(ui.is_open() and game.get_task_journal().get_task("shop.first_order").status == "active", "E on order board accepts task: " + path)
	_check("胖哥布林" in game.get_node("PopupLayer/Modal/Center/Panel/Margin/Content/DescriptionScroll/Description").text, "Board displays delivery recipient")
	await _capture("delivery_" + path.get_file().get_basename() + "_board")
	ui.close()
	player.global_position = station.global_position
	await _frames()
	await _press_interact()
	var panel: CraftingPanel = game.get_node("PopupLayer/Modal/Center/Panel/Margin/Content/ProductionPanel")
	panel.clear_selection()
	for id: String in ["black_tea", "creamer", "pearl", "syrup"]:
		panel.add_material(id)
	panel.submit()
	var inventory := game.get_warehouse_inventory()
	_check(inventory.get_stock("pearl_milk_tea") == 1 and not state.get_flag("shop.order_001_delivered"), "Real production UI leaves cup carried and task active")
	ui.close()
	var before := inventory.to_dict()
	player.global_position = game.get_node("World/EntityRoot/Elder").global_position
	await _frames()
	await _press_interact()
	_check(ui.is_open() and inventory.to_dict() == before and not state.get_flag("shop.order_001_delivered"), "E at wrong real NPC safely refuses delivery")
	ui.close()
	player.global_position = game.get_node("World/EntityRoot/FatGoblin").global_position
	await _frames()
	await _press_interact()
	_check(ui.is_open() and inventory.get_stock("pearl_milk_tea") == 0 and inventory.get_stock("syrup") == 10 and game.get_task_journal().get_task("shop.first_order").status == "completed", "E at target NPC completes task and pays once: " + path)
	_check(state.get_variable("shop.orders_completed") == 1, "Existing business counter advances only on NPC delivery")
	await _capture("delivery_" + path.get_file().get_basename() + "_success")
	before = inventory.to_dict()
	ui.close()
	await _frames()
	await _press_interact()
	_check(ui.is_open() and inventory.to_dict() == before, "Repeated E cannot consume or award again")
	ui.close()
	game.free()
	await _frames()
	state.reset_state()
