extends SceneTree
## Consecutive stall purchases and the real cup handoff before the two-day ending.

const RECIPE: Array[String] = ["insomnia_mushroom", "mint_syrup", "red_mottled_wood"]
const DEBT_TEXT := "赌场的十杯奶茶还没还"

var checks := 0
var failures: Array[String] = []
var state: Node
var game: MainGame
var spoken: Array[String] = []
var capture_enabled := false
var captured := {}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count := 6) -> void:
	for index in range(count):
		await physics_frame

func _capture(id: String) -> void:
	if not capture_enabled or captured.has(id):
		return
	await frames(18)
	await RenderingServer.frame_post_draw
	var directory := "res://.godot/mushroom_recovery"
	DirAccess.make_dir_recursive_absolute(directory)
	check(root.get_texture().get_image().save_png(directory.path_join(id + ".png")) == OK, "Rendered capture: " + id)
	captured[id] = true

func _new_host(path: String, stage: String, day := 2) -> bool:
	state.reset_state()
	state.select_business_profile("day1")
	DayPhase.advance_to(state, 1, "night")
	DayPhase.advance_to(state, 2, "day")
	DayPhase.advance_to(state, 2, "night")
	if day == 3:
		DayPhase.advance_to(state, 3, "day")
		DayPhase.advance_to(state, 3, "night")
	state.set_story_stage(stage)
	state.set_flag("day1.s04.commission_accepted")
	spoken.clear()
	game = load(path).instantiate() as MainGame
	if game == null:
		check(false, "Real host instantiates: " + path)
		return false
	root.add_child(game)
	current_scene = game
	game.get_dialogue_manager().dialogue_started.connect(func(id: String) -> void: spoken.append(id))
	await frames(16)
	check(game.get_chapter_controller().is_loaded(), "Chapter data loads in " + path)
	return game.get_chapter_controller().is_loaded()

func _clear_host() -> void:
	if is_instance_valid(game):
		game.free()
	game = null
	await frames(2)

func _finish_conversations() -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	var quiet_frames := 0
	while Time.get_ticks_msec() < deadline:
		var dialogue := game.get_dialogue_manager()
		if dialogue.is_active():
			quiet_frames = 0
			if capture_enabled and not spoken.is_empty():
				var current: String = spoken.back()
				var capture_id := ""
				if current.begins_with("day2.procurement.recipe.vendor_") and dialogue.get_current_line_id() == "line_2":
					capture_id = current.get_slice(".", 3)
				elif current == "day2.procurement.before_rest":
					capture_id = "before_rest"
				if not capture_id.is_empty() and not captured.has(capture_id):
					dialogue.advance()
					await frames(12)
					check(not game.get_player().movement_enabled, "Rendered conversation keeps movement locked: " + capture_id)
					await _capture(capture_id)
			dialogue.advance()
			dialogue.select_choice(0)
		elif not game.get_story_director().is_busy():
			quiet_frames += 1
			if quiet_frames >= 8:
				return true
		else:
			quiet_frames = 0
		await process_frame
	check(false, "Authored conversations finish within their deadline")
	return false

func _buy(vendor: String) -> bool:
	var chapter := game.get_chapter_gameplay()
	var opened := chapter.open_market_vendor(StringName(vendor))
	check(opened == OK, "Actual stall opens: " + vendor)
	if opened != OK:
		return false
	await frames(2)
	var popup := game.get_node("PopupLayer/MarketVendorPopup") as MarketVendorPopup
	if popup == null or not popup.select_product("market_insomnia_mushroom"):
		check(false, "Actual stall offers the mushroom: " + vendor)
		return false
	popup._buy.pressed.emit()
	await frames(4)
	return await _finish_conversations()

func _run() -> void:
	capture_enabled = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/mushroom_recovery_%d" % OS.get_process_id())
	state = root.get_node("GameState")
	for order: Array in [["market_vendor_2", "market_vendor_3"], ["market_vendor_3", "market_vendor_2"]]:
		await _check_stalls(order)
	await _check_late_purchase()
	await _check_recovery()
	await _clear_host()
	print("MUSHROOM_RECOVERY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_stalls(order: Array) -> void:
	if not await _new_host("res://src/core/settlement.tscn", "day2.s03.travel_tavern"):
		await _clear_host()
		return
	var chapter := game.get_chapter_gameplay()
	var balance: int = state.get_transactions().get_balance()
	if balance > 0:
		state.commit_story_transaction("test.empty_wallet", {}, {}, -balance)
	check(chapter.open_market_vendor(StringName(order[0])) == OK, "An empty-wallet buyer can inspect the stall")
	await frames(2)
	var before: Dictionary = state.to_dict()
	var failed := chapter.buy_from_vendor("market_insomnia_mushroom", 1)
	check(not failed.ok and state.to_dict() == before, "Rejected purchase leaves stock, money and seller facts untouched")
	game.get_ui_manager().close_screen(ScreenIds.MARKET_VENDOR)
	await frames(8)
	check(spoken.is_empty() and not state.get_flag("day2.procurement.purchased"), "Failed purchase triggers neither clue nor recipe")
	state.commit_story_transaction("test.stall_money", {}, {}, 500)
	for index in range(order.size()):
		var vendor: String = order[index]
		if not await _buy(vendor):
			await _clear_host()
			return
		var dialogue_id := "day2.procurement.recipe.vendor_" + vendor.right(1)
		check(spoken.count(dialogue_id) == 1, "Each actual seller speaks its clue once: " + vendor)
		check(state.get_flag("day2.procurement." + vendor + ".heard"), "The completed clue remembers its seller: " + vendor)
		check(state.get_transactions().get_balance() == 500 - 50 * (index + 1) + 150, "Both stalls share one 150G discovery reward")
		check(state.get_warehouse_inventory().get_uses("insomnia_mushroom") == 5 * (index + 1), "Each paid portion adds five real uses")
		if index == 1:
			check(state.is_event_completed("day2.procurement.recipe." + vendor), "Second stall uses its independent authored event")
	check(not "day2.procurement.recipe" in spoken, "Market purchases do not borrow the errand runner's dialogue")
	for vendor: String in order:
		await _buy(vendor)
		check(spoken.count("day2.procurement.recipe.vendor_" + vendor.right(1)) == 1, "Repeat purchase does not replay the seller clue: " + vendor)
	check(state.get_transactions().get_balance() == 500 - 200 + 150, "Repeat purchases cannot pay another discovery reward")
	var wood_offered := false
	for product: Dictionary in chapter.get_vendor_view(&"market_vendor_3").products:
		wood_offered = wood_offered or product.id == "market_red_mottled_wood"
	check(wood_offered, "The right stall exposes the recipe's existing red wood product")
	if order[0] == "market_vendor_2":
		_check_recap_debt()
	await _clear_host()

func _check_recap_debt() -> void:
	var chapter := game.get_chapter_gameplay()
	var casino := FixedStoryCasino.new()
	game.add_child(casino)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ChapterGameplay.ACTIONS))
	var config: Dictionary = data.day2.casino.duplicate(true)
	for id: String in config.reward_items:
		config.reward_items[id] = int(config.reward_items[id])
	check(casino.configure(state, game.get_task_catalog(), config) == OK, "Recap test binds real casino settlement")
	check(casino.settle_first_loss().ok, "First loss establishes an unsettled debt")
	check(DEBT_TEXT in chapter.get_recap_text(), "Active debt without a terminal result remains in the recap")
	var active: Dictionary = state.to_dict()
	check(casino.settle_second_win().ok and casino.waive_debt("老板免除债务").ok, "Actual second-round waiver cancels the debt")
	check(not DEBT_TEXT in chapter.get_recap_text(), "Cancelled debt disappears from the recap")
	var cancelled: Dictionary = state.to_dict()
	check(state.restore_state(active) == OK and DEBT_TEXT in chapter.get_recap_text(), "Restoring an unsettled debt restores its handoff")
	check(state.restore_state(cancelled) == OK and not DEBT_TEXT in chapter.get_recap_text(), "Restored cancellation remains absent from the recap")
	check(state.restore_state(active) == OK, "Restore the active debt for actual repayment")
	state.commit_story_transaction("test.repay_stock", {}, {}, 0, {"classic_boba_milk_tea": 10})
	check(game.get_task_delivery().try_submit("day3_casino_debt", "casino").ok, "Ten real cups repay the debt")
	check(not DEBT_TEXT in chapter.get_recap_text(), "Paid debt disappears from the recap")
	var paid: Dictionary = state.to_dict()
	check(state.restore_state(paid) == OK and not DEBT_TEXT in chapter.get_recap_text(), "Restored repayment remains absent from the recap")
	casino.free()

func _check_late_purchase() -> void:
	if not await _new_host("res://src/core/settlement.tscn", "day3.handoff", 3):
		await _clear_host()
		return
	var chapter := game.get_chapter_gameplay()
	check(chapter.get_procurement().fund() == OK, "Late purchase retains the original procurement task")
	state.commit_story_transaction("test.late_money", {}, {}, 100)
	await _buy("market_vendor_3")
	check(not state.get_flag("day2.procurement.purchased") and not state.get_flag("signature.S06.discovered"), "Day-three purchase does not forge a timely recipe clue")
	check(not state.is_event_completed("day2.procurement.recipe"), "Late purchase does not start the day-two discovery event")
	check(game.get_task_delivery().is_order_available("day3_procurement"), "The late buyer keeps access to raw-mushroom handoff")
	check(game.get_task_delivery().try_submit("day3_procurement", "fat_goblin").ok, "Late raw delivery remains valid before its deadline")
	check(state.get_flag("day3.procurement.delivered") and state.get_warehouse_inventory().get_uses("insomnia_mushroom") == 4, "Late delivery consumes exactly one raw use")
	await _clear_host()

func _menu_action(id: String) -> bool:
	check(game.open_game_menu() == OK, "Open the actual game menu for " + id)
	await frames(2)
	var button := game.get_game_menu().get_action_button(id)
	check(button != null and not button.disabled, "Menu exposes an enabled action: " + id)
	if button == null or button.disabled:
		game.get_ui_manager().close_screen(ScreenIds.CHAPTER_ACTIONS)
		return false
	if id == "recovery_resupply":
		await _capture("recovery_supplies_menu")
	button.pressed.emit()
	await frames(2)
	return true

func _has_action(id: String) -> bool:
	for action: Dictionary in game.get_chapter_gameplay().get_user_actions():
		if action.id == id:
			return true
	return false

func _check_recovery() -> void:
	if not await _new_host("res://src/core/main.tscn", "day2.s05.return_final"):
		return
	var chapter := game.get_chapter_gameplay()
	var procurement := chapter.get_procurement()
	state.set_flag("day2.travel.final_shop_returned")
	state.set_flag("day2.procurement.rest_ready")
	await frames(12)
	check(state.current_day == 2 and not state.get_flag("day2.completed"), "Even an old rest-ready flag cannot skip the last cup before purchase")
	check(procurement.fund() == OK and procurement.purchase_direct() == OK, "A real direct purchase creates the recovery obligation")
	state.set_flag("day2.travel.final_shop_returned")
	var inventory := state.get_warehouse_inventory() as WarehouseInventory
	var delivery := game.get_task_delivery()
	var before: Dictionary = inventory.to_dict()
	check(not delivery.try_submit("day3_procurement", "fat_goblin").ok and inventory.to_dict() == before, "A purchase blocks raw handoff even before recipe discovery finishes")
	if not await _finish_conversations():
		return
	check(state.is_event_completed("day2.procurement.recipe") and state.is_event_completed("day2.procurement.before_rest"), "Final return discovers the recipe and explains the unfinished treatment")
	check(spoken.find("day2.procurement.recipe") >= 0 and spoken.find("day2.procurement.recipe") < spoken.find("day2.procurement.before_rest"), "The recipe exchange precedes the rest reminder")
	check(state.current_day == 2 and state.story_stage == "day2.s05.return_final" and not state.get_flag("day2.completed"), "Purchased mushrooms prevent the chapter from ending early")
	check(game.get_player().movement_enabled and game.get_gameplay_bridge().allows_scene_travel(), "Recovery wait preserves movement and supply trips")
	check(not game.get_ui_manager().is_open(ScreenIds.CHAPTER_RECAP), "The recap stays closed before treatment")
	check(delivery.is_order_accepted("day2_recovery_drink") and not delivery.is_order_available("day3_procurement"), "Only the recovery cup can fulfill the purchased-mushroom request")
	var costs := {}
	for id: String in RECIPE:
		var uses := inventory.get_uses(id)
		if uses > 0:
			costs[id] = uses
	check(state.commit_story_transaction("test.exhaust_recovery", costs) == OK, "Exercise an empty treatment inventory")
	await frames()
	check(_has_action("recovery_resupply"), "Empty treatment stock exposes the recovery supply action")
	await _menu_action("recovery_resupply")
	for id: String in RECIPE:
		check(inventory.get_uses(id) == 1, "Supply restores exactly one missing use: " + id)
	check(not _has_action("recovery_resupply"), "Sufficient materials cannot be claimed repeatedly")
	var warm := game.get_tea_production().craft_free(RECIPE, 1, false)
	check(warm.ok, "A real uniced trial cup can be crafted")
	before = inventory.to_dict()
	check(not delivery.try_submit("day2_recovery_drink", "fat_goblin").ok and inventory.to_dict() == before, "The uniced cup is rejected without consuming it")
	check(not state.get_flag("day3.procurement.delivered"), "Making the wrong cup does not complete treatment")
	await frames()
	await _menu_action("recovery_resupply")
	var cold := game.get_tea_production().craft_free(RECIPE, 1, true)
	check(cold.ok, "The actual crafting service makes the iced recovery drink")
	if not cold.ok:
		return
	check(inventory.get_drink_stock(cold.id) == 1 and not state.get_flag("day3.procurement.delivered"), "Successful manufacture creates a carried cup, not a completed delivery")
	await frames()
	check(not _has_action("recovery_resupply"), "A carried correct cup suppresses supply even when all ingredients are spent")
	check(state.current_day == 2 and not state.get_flag("day2.completed"), "The chapter still waits after manufacture")
	var patient := game.get_actor_director().get_actor(&"fat_goblin")
	game.get_player().teleport_to(patient.global_position + Vector2(0, 40))
	await frames()
	# Reproduce the ordering after a saved waiting state is restored: both world
	# and chapter projections must leave the patient's real Area2D usable.
	var waiting: Dictionary = state.to_dict()
	check(state.restore_state(waiting) == OK, "Restore the final-cup waiting state")
	await frames()
	var interaction := game.get_shop_interaction()
	var point := game.get_delivery_point("fat_goblin")
	check(point.is_available(), "The resting patient's real interaction area is available")
	check(interaction.get_target() == point, "The patient is selected from reachable bedroom floor")
	await _capture("recovery_handoff_prompt")
	before = inventory.to_dict()
	check(not delivery.try_submit("day2_recovery_drink", "casino").ok and inventory.to_dict() == before, "The wrong recipient cannot consume the recovery cup")
	var observations: Array[bool] = []
	var observe := func() -> void:
		if state.get_flag("day3.procurement.delivered"):
			observations.append(state.get_flag("signature.S06.rescued_in_time") and inventory.get_drink_stock(cold.id) == 0)
	state.state_changed.connect(observe)
	var press := InputEventAction.new()
	press.action = &"interact"
	press.pressed = true
	Input.parse_input_event(press)
	await frames(1)
	var release := InputEventAction.new()
	release.action = &"interact"
	Input.parse_input_event(release)
	await frames(1)
	state.state_changed.disconnect(observe)
	check(state.get_flag("day3.procurement.delivered"), "The real interaction action hands the cup to the resting patient")
	check(not observations.is_empty() and observations.all(func(value: bool) -> bool: return value), "Delivery, patient recovery and cup deduction publish atomically")
	check(state.get_flag("signature.S06.rescued_in_time") and inventory.get_drink_stock(cold.id) == 0, "Exactly one correct cup treats the patient")
	before = inventory.to_dict()
	check(not delivery.try_submit("day2_recovery_drink", "fat_goblin").ok and inventory.to_dict() == before, "Repeated treatment cannot consume another cup")
	await _finish_conversations()
	await frames(8)
	check(state.is_event_completed("day2.s05.unsolved") and state.current_day == 3 and state.story_stage == "day3.handoff", "Real treatment releases the normal chapter ending")
	check(game.get_ui_manager().is_open(ScreenIds.CHAPTER_RECAP), "The normal two-day recap appears after treatment")
	check(not "醒神菇还没交到胖哥布林手里" in chapter.get_recap_text(), "The recap no longer lists the fulfilled recovery request")
	check(chapter.last_error.is_empty(), "Recovery leaves no chapter runtime error")
