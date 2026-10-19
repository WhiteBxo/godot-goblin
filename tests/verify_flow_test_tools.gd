extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", description)

func _run() -> void:
	var state := root.get_node("GameState")
	state.start_new_game()
	state.select_business_profile("day1")
	var tools := FlowTestTools.new()
	var guard := {"allowed": true}
	var context := {"state": state, "transactions": state.get_transactions(),
		"inventory": state.get_warehouse_inventory(), "production": state.get_tea_production(),
		"can_control": func() -> bool: return guard.allowed, "log": root.get_node("DevLog")}
	tools.configure(context)
	var before: Dictionary = state.to_dict()
	check(not tools.get_items().is_empty(), "Reads complete real inventory catalogue")
	check(not tools.get_recipes().is_empty(), "Reads available recipes")
	check(tools.report().contains("save_directory") and state.to_dict() == before, "Report reads a snapshot without modifying state")
	var wallet: WalletTransactions = state.get_transactions()
	var balance := wallet.get_balance()
	check(tools.add_money(100) and tools.add_money(100) and wallet.get_balance() == balance + 200, "Repeated clicks use distinct real transaction receipts")
	var inventory: WarehouseInventory = state.get_warehouse_inventory()
	var id: String = tools.get_items()[0].id
	var stock := inventory.get_stock(id)
	check(tools.add_item(id, 3) and inventory.get_stock(id) == stock + 3, "Item grant uses shared inventory")
	before = state.to_dict()
	check(not tools.add_item("missing", 3) and not tools.add_money(-1) and not tools.add_item(id, 101) and state.to_dict() == before, "Invalid grants leave the entire session unchanged")
	guard.allowed = false
	check(not tools.add_money(100) and not tools.add_item(id, 3) and not tools.craft("human_h01") and not tools.locate("cashier") and state.to_dict() == before, "Busy guard protects every cheat API")
	guard.allowed = true
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	check(not tools.add_money(100) and not tools.add_item(id, 3) and not tools.launch("") and not tools.generate() and not tools.export_report() and state.to_dict() == before, "Disabled tools neither mutate state nor launch or export")
	ProjectSettings.set_setting("debug/developer_tools/enabled", null)
	check(root.get_node("DevLog").get_lines(DebugLog.SOURCE_DEBUG).size() >= 8, "Accepted and refused cheats have attributable log entries")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture="):
			await _verify_host(argument.trim_prefix("--fixture="))
	print("Flow test tools: %d checks; %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _verify_host(directory: String) -> void:
	var job_path := "res://.godot/flow_registry_test.json"
	var job_file := FileAccess.open(job_path, FileAccess.WRITE)
	job_file.store_string(JSON.stringify({"directory": directory.get_base_dir(), "pid": -1}))
	job_file.close()
	var registry := FlowTestTools.new(job_path)
	var rows := registry.get_fixtures()
	check(rows.size() == 26, "Registry admits 8 Day1 and 18 Day2 real fixtures, excluding Day3/4")
	var day1 := 0
	for row: Dictionary in rows:
		if row.day == 1:
			day1 += 1
	check(day1 == 8, "Registry includes every new Day1 checkpoint")
	check(not registry.launch("res://not_a_fixture"), "Launch rejects paths outside the verified catalogue")
	var source := SaveStore.new(directory).load_save()
	check(source.error == OK, "Real fixture validates")
	if source.error != OK:
		return
	var scratch := "user://verification/flow_tools_%d" % OS.get_process_id()
	check(SaveStore.new(scratch).save(source.data.game_state, source.data.checkpoint_id) == OK, "Copies fixture into a disposable session")
	ProjectSettings.set_setting("persistence/save_directory", scratch)
	check(GameEntry.continue_game(self) == OK, "Official continue path restores fixture")
	for frame in range(600):
		await process_frame
		if current_scene is MainGame and not current_scene.is_session_initializing():
			break
	var game := current_scene as MainGame
	check(game != null and not game.is_session_initializing(), "Restored host finishes startup")
	if game == null or game.is_session_initializing():
		return
	var controller := game.get_debug_tools()
	var panel := controller.get_panel()
	controller.toggle_panel()
	var tabs := panel.flow_test_panel.get_parent() as TabContainer
	tabs.current_tab = panel.flow_test_panel.get_index()
	await process_frame
	check(panel.visible and not game.get_player().movement_enabled, "Flow page participates in modal movement lock")
	var service := controller.flow_test_tools
	var original: Dictionary = root.get_node("GameState").to_dict()
	check(not service.get_targets().is_empty(), "Host exposes visible interaction targets")
	var located := false
	for row: Dictionary in service.get_targets():
		if service.locate(row.id):
			located = true
			break
	check(located, "At least one real interaction target has a collision-safe landing")
	check(root.get_node("GameState").to_dict() == original, "Locating never writes a travel or completion fact")
	var production := game.get_tea_production()
	var recipes := production.get_available_recipes()
	if not recipes.is_empty():
		var recipe: TeaRecipe = recipes[0]
		var inventory := game.get_warehouse_inventory()
		for material: String in recipe.materials:
			service.add_item(material, 10)
		var stock := inventory.get_stock(recipe.product_id)
		check(service.craft(recipe.product_id) and inventory.get_stock(recipe.product_id) == stock + 1, "Quick craft executes real recipe and produces a cup")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://.godot/flow_test_panel.png") == OK, "Capture rendered flow page")
		for section: TabContainer in panel.flow_test_panel.find_children("*", "TabContainer", true, false):
			for index in range(1, section.get_tab_count()):
				section.current_tab = index
				await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png("res://.godot/flow_test_page_%d.png" % index) == OK, "Capture checkpoint and cheat subpages")
	controller.close_panel()
	check(not panel.visible and game.get_player().movement_enabled, "Closing restores the original player lock")
