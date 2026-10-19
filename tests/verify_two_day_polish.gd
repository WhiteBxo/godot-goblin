extends SceneTree
## Presentation and optional play must leave the mandatory two-day route intact.

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count := 3) -> void:
	for index in range(count):
		await process_frame

func _run() -> void:
	var hud: ChapterActionsHUD = load("res://src/UI/hud/chapter_actions_hud.tscn").instantiate()
	root.add_child(hud)
	await frames()
	var detail := "代购专款 35G · 跑腿途中\n七日祭食材\n苔痕青 2/2 · 缺0"
	hud.hide()
	hud.show_actions([{"id": "close", "text": "关店", "kind": "close"}], detail, true)
	check(not hud.visible, "Menu data updates never create a persistent sidebar")
	check(hud.get_action_button("close") != null, "Chapter actions remain available inside the menu")
	hud.show_actions([{"id": "close", "text": "关店", "kind": "close"}], detail, false)
	check(hud.get_action_button("close").disabled, "Blocked actions remain disabled")
	hud.show_actions([], "", true)
	check(hud.get_action_button("close") == null, "Obsolete chapter actions are removed")
	hud.free()
	_test_taste()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--fixtures="):
			await _test_live_taste(argument.trim_prefix("--fixtures="))
			await _test_live_casino(argument.trim_prefix("--fixtures="))
			await _test_live_return(argument.trim_prefix("--fixtures="))
			await _test_live_recap(argument.trim_prefix("--fixtures="))
	print("TWO_DAY_POLISH: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_taste() -> void:
	var state: Node = load("res://src/core/game_state.gd").new()
	var catalog := TaskCatalog.new()
	check(catalog.load_file("res://src/resources/tasks/day2_stages_01_05.json", {"locations": RpgWorldMapData.location_ids()}) == OK, "Published optional order loads through the strict catalogue")
	var journal := TaskJournal.new()
	root.add_child(journal)
	check(journal.configure(catalog, state) == OK, "Optional task binds to the existing state")
	var delivery := TaskDelivery.new()
	root.add_child(delivery)
	var inventory: WarehouseInventory = state.get_warehouse_inventory()
	check(delivery.configure(catalog, journal, state, inventory) == OK, "Real delivery validates the spicy requirement")
	state.set_flag("day2.s02.open")
	check(delivery.accept_order("day2_taste") == OK, "Player explicitly accepts optional tasting")
	var before: Dictionary = state.to_dict()
	check(not delivery.try_submit("day2_taste", "day2_ordinary_c").ok and state.to_dict() == before, "Missing drink rejects without changing the session")
	inventory.add_ingredient("creamer_milk_tea_base", 1)
	inventory.add_ingredient("goblin_firebrew", 1)
	var materials: Array[String] = ["creamer_milk_tea_base", "goblin_firebrew"]
	check(state.confirm_formula(materials, "polish.price").ok, "Experiment confirms a real permanent price")
	var result: Dictionary = state.get_tea_production().craft_formula(materials, 1, "polish.craft")
	check(result.ok and delivery.has_matching_drink("day2_taste"), "A player-created spicy milk tea meets the order")
	var model := OrderBoardModel.new()
	root.add_child(model)
	model.configure(catalog, journal, state, inventory, state.get_tea_production(), delivery)
	var entry := model.get_entry("day2_taste")
	check(entry.get("ready", false) and not str(entry.get("title", "")).is_empty(), "Order board names dynamic requirements and shows actual readiness")
	var saved: Dictionary = state.to_dict()
	check(state.restore_state(saved) == OK and delivery.has_matching_drink("day2_taste"), "Accepted order and prepared cup survive restore")
	var balance: int = state.get_transactions().get_balance()
	var price: int = state.get_transactions().get_formula_price(materials).selling_price
	check(delivery.try_submit("day2_taste", "day2_ordinary_c").ok, "Matching cup is actually delivered")
	check(state.get_transactions().get_balance() == balance + price and inventory.get_drink_stock(result.id) == 0, "Delivery consumes one cup and pays exactly the confirmed price")
	before = state.to_dict()
	check(not delivery.try_submit("day2_taste", "day2_ordinary_c").ok and state.to_dict() == before, "Repeat tasting cannot consume or pay twice")
	model.free()
	delivery.free()
	journal.free()
	state.free()

func _test_live_recap(directory: String) -> void:
	var target := OS.get_cache_dir().path_join("goblin_polish_recap_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(target)
	DirAccess.copy_absolute(directory.path_join("day3_handoff/autosave.dat"), target.path_join("autosave.dat"))
	ProjectSettings.set_setting("persistence/save_directory", target)
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	check(GameEntry.continue_game(self) == OK, "Real chapter-end checkpoint resumes")
	await scene_changed
	var game := current_scene as MainGame
	while game.is_session_initializing():
		await process_frame
	await frames(20)
	var state := root.get_node("GameState")
	var before: Dictionary = state.to_dict()
	check(game.get_ui_manager().is_open(ScreenIds.CHAPTER_RECAP) and not game.get_player().movement_enabled, "Recap is modal at a completed chapter boundary")
	var text := game.get_chapter_gameplay().get_recap_text()
	check("28G" in text and "订单" in text, "Recap projects the actual saved wallet and deliveries")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/two_day_polish/recap.png")
	game.get_ui_manager().close_screen(ScreenIds.CHAPTER_RECAP)
	await frames(5)
	check(state.get_flag("ui.two_day_recap_seen"), "Closing the recap acknowledges it")
	check(game.get_ui_manager().is_open(ScreenIds.TWO_DAYS_END), "The chapter ends on the end card")
	game.get_ui_manager().close_screen(ScreenIds.TWO_DAYS_END)
	await frames(5)
	check(game.get_player().movement_enabled, "Leaving the end card releases player input")
	before.flags["ui.two_day_recap_seen"] = true
	check(state.to_dict() == before, "Acknowledging results changes only its presentation flag")
	var manager := game.get_ui_manager()
	manager.set_paused(true)
	check(manager.open_screen(ScreenIds.SETTINGS) == OK, "Paused game opens the shared settings view")
	manager.request_back()
	check(paused and manager.is_open(ScreenIds.PAUSE), "Leaving settings preserves the underlying pause")
	manager.open_screen(ScreenIds.SETTINGS)
	manager.set_paused(false)
	check(not paused and not manager.is_open(ScreenIds.SETTINGS) and not manager.has_modal(), "Unpausing cannot leave hidden settings owning input")
	game.free()

func _load_fixture(directory: String, checkpoint: String) -> MainGame:
	var target := OS.get_cache_dir().path_join("goblin_polish_%s_%d" % [checkpoint, OS.get_process_id()])
	DirAccess.make_dir_recursive_absolute(target)
	DirAccess.copy_absolute(directory.path_join(checkpoint + "/autosave.dat"), target.path_join("autosave.dat"))
	ProjectSettings.set_setting("persistence/save_directory", target)
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	check(GameEntry.continue_game(self) == OK, "Restore real operation boundary: " + checkpoint)
	await scene_changed
	var game := current_scene as MainGame
	while game.is_session_initializing():
		await process_frame
	await frames(20)
	return game

func _test_live_taste(directory: String) -> void:
	Engine.time_scale = 6.0
	var game := await _load_fixture(directory, "wait_festival")
	var actions := game.get_chapter_gameplay()
	var scheduler := actions.get_scheduler()
	var state := root.get_node("GameState")
	var delivery := game.get_task_delivery()
	var deadline := Time.get_ticks_msec() + 10000
	while scheduler.get_group("ordinary_c").get("status") != "waiting" and Time.get_ticks_msec() < deadline:
		await process_frame
	check(delivery.accept_order("day2_taste") == OK, "A real waiting customer accepts the optional taste order")
	check(actions.close_business() == ERR_UNAVAILABLE, "Accepted extra order prevents premature closing")
	check(delivery.accept_order("day2_ordinary_c") == OK, "Customer's original H01 order is preserved")
	var recipe := game.get_tea_production().get_recipe_by_product("classic_boba_milk_tea")
	check(game.get_tea_production().craft(recipe.materials).ok and delivery.try_submit("day2_ordinary_c", "day2_ordinary_c").ok, "Customer receives the original H01 through real services")
	await frames(15)
	check(scheduler.get_group("ordinary_c").status == "waiting", "Customer waits for the already accepted tasting after receiving H01")
	var materials: Array[String] = ["creamer_milk_tea_base", "goblin_firebrew"]
	check(state.confirm_formula(materials, "live.taste.price").ok and game.get_tea_production().craft_formula(materials, 1, "live.taste.craft").ok, "Yesterday's actual gift can supply a spicy experiment")
	check(delivery.try_submit("day2_taste", "day2_ordinary_c").ok, "Optional cup reaches the real waiting customer")
	await frames(15)
	check(scheduler.get_group("ordinary_c").status in ["leaving", "departed"], "Customer departs after both accepted orders settle")
	game.free()
	game = await _load_fixture(directory, "wait_festival")
	delivery = game.get_task_delivery()
	deadline = Time.get_ticks_msec() + 10000
	while not delivery.can_accept_order("day2_taste") and Time.get_ticks_msec() < deadline:
		await process_frame
	check(delivery.accept_order("day2_taste") == OK, "Cancellation branch accepts a real tasting")
	game.get_chapter_gameplay().perform_user_action("cancel_taste")
	check(state.get_task_result("day2.orders.taste").get("status") == "cancelled", "Cancel resolves optional tasting if the player changes plans or lacks ingredients")
	game.free()

func _test_live_return(directory: String) -> void:
	var game := await _load_fixture(directory, "delivered_guard")
	var state := root.get_node("GameState")
	var level := game.get_active_level()
	var point := level.get_node("Exits/GuardReturn") as SceneExit
	check(level.get_node("Wayfinding/FestivalPreparation").visible, "Second-day festival dressing is visible on the familiar route")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		game.get_player().teleport_to(Vector2(1176, 2220))
		await frames(40)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/two_day_polish/festival.png")
	check(point.visible and point.are_conditions_met(state), "Convenient return becomes available only after guard hospitality")
	var balance: int = state.get_transactions().get_balance()
	check(game.get_scene_travel().request_exit(point) == OK, "Convenient return uses the actual SceneTravel entry point")
	await scene_changed
	game = current_scene as MainGame
	var deadline := Time.get_ticks_msec() + 15000
	while state.story_stage != "day3.handoff" and Time.get_ticks_msec() < deadline:
		if game.get_dialogue_manager().is_active():
			game.get_dialogue_manager().advance()
		await process_frame
	check(state.story_stage == "day3.handoff" and state.get_transactions().get_balance() == balance, "Actual arrival finishes the chapter without changing the wallet")
	game.get_ui_manager().close_screen(ScreenIds.CHAPTER_RECAP)
	game.free()

func _test_live_casino(directory: String) -> void:
	var game := await _load_fixture(directory, "wait_first")
	var state := root.get_node("GameState")
	var seen: Array[String] = []
	for event: String in ["day2.s04.first_round", "day2.s04.second_round"]:
		check(game.get_story_director().request_interaction("casino_table") == OK, "Player explicitly starts the authored round at the table")
		var deadline := Time.get_ticks_msec() + 15000
		while not state.is_event_completed(event) and Time.get_ticks_msec() < deadline:
			if game.get_dialogue_manager().is_active():
				game.get_dialogue_manager().advance()
			var card := game.get_title_card()
			var title: String = card.get_node("Center/Lines/Title").text
			if card.is_showing() and card.modulate.a > 0.9 and title not in seen:
				seen.append(title)
				if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("res://.godot/two_day_polish/casino_%d.png" % seen.size())
			await process_frame
		check(state.is_event_completed(event), "Round finishes through the existing director and settlement service")
	check(seen.size() == 5 and state.get_task_result("day2.casino.debt").get("status") == "cancelled", "Five presentation cards accompany real loss, win and debt waiver")
	game.free()
