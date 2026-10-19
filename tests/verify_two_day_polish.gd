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
	var detail := "代购专款 35G · 跑腿途中\n\n七日祭食材\n苔痕青 2/2 · 缺0\n已齐备，第三天交付。"
	var summary := "代购 · 跑腿途中\n七日祭 · 已齐备，第三天交付"
	hud.show_actions([], detail, true, summary)
	check(hud.get_node("Content/NoticePanel/Notice").text == summary, "Optional HUD starts compact")
	hud.get_node("Content/Details").pressed.emit()
	check(hud.get_node("Content/NoticePanel/Notice").text == detail, "Details remain available on demand")
	hud.show_actions([], detail, false, summary)
	check(hud.get_node("Content/Details").disabled, "World HUD cannot change while a modal owns input")
	hud.show_actions([], "", true)
	check(not hud.get_node("Content/NoticePanel").visible and not hud.get_node("Content/Details").visible, "Finished optional work leaves no empty card")
	hud.show_actions([], detail, true, summary)
	hud.get_node("Content/Details").pressed.emit()
	await frames()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.godot/two_day_polish")
		root.get_texture().get_image().save_png("res://.godot/two_day_polish/hud.png")
	hud.free()
	_test_taste()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--fixtures="):
			await _test_live_recap(argument.trim_prefix("--fixtures="))
	print("TWO_DAY_POLISH: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_taste() -> void:
	var state: Node = load("res://src/core/game_state.gd").new()
	var catalog := TaskCatalog.new()
	check(catalog.load_file("res://src/resources/tasks/day2_stages_01_05.json") == OK, "Published optional order loads through the strict catalogue")
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
	check(state.get_flag("ui.two_day_recap_seen") and game.get_player().movement_enabled, "Closing acknowledges recap and releases player input")
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
