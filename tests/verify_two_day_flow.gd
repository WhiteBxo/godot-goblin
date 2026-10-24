extends SceneTree
## Real hosts and transactions; dialogue advancement is automated for regression.
var state: Node
var game: MainGame
var checks := 0
var failures: Array[String] = []
var event_errors: Array[String] = []
var fixture_directory := ""
var ordinary_order := false
var screenshots := ""

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count := 5) -> void:
	for i in range(count):
		await process_frame

func picture(id: String) -> void:
	if screenshots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(screenshots)
	check(root.get_texture().get_image().save_png(screenshots.path_join(id + ".png")) == OK, "Graphical capture " + id)

func capture(id: String) -> void:
	await picture(id)
	if fixture_directory.is_empty():
		return
	for i in range(240):
		await process_frame
		var loaded := GameEntry.create_save_store().load_save()
		if loaded.error != OK or loaded.data.game_state != state.to_dict():
			continue
		var destination := fixture_directory.path_join(id)
		DirAccess.make_dir_recursive_absolute(destination)
		check(DirAccess.copy_absolute(GameEntry.create_save_store().directory.path_join("autosave.dat"), destination.path_join("autosave.dat")) == OK, "Capture real autosave " + id)
		return
	check(false, "Autosave reaches current safe state: " + id + " / " + state.story_stage)

func attach() -> void:
	game = current_scene as MainGame
	game.get_story_director().event_finished.connect(func(id: String, ok: bool, reason: String) -> void:
		if not ok:
			event_errors.append(id + ": " + reason)
			push_error(event_errors.back())
	)

func wait_event(id: String) -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	var captured_dialogue := false
	while not event_completed(id) and Time.get_ticks_msec() < deadline and event_errors.is_empty():
		var dialogue := game.get_dialogue_manager()
		if dialogue.is_active():
			if not captured_dialogue:
				captured_dialogue = true
				check(not game.get_player().movement_enabled, "Dialogue retains the story movement lock: " + id)
				if not screenshots.is_empty() and DisplayServer.get_name() != "headless":
					dialogue.advance()
					await picture(id + "_dialogue")
			dialogue.advance()
			dialogue.select_choice(0)
		await process_frame
	check(event_completed(id), "Completes " + id + " at " + state.story_stage)
	if not event_completed(id):
		print("FLOW_ABORT ", event_errors, " director=", game.get_story_director().last_error, " chapter=", game.get_chapter_controller().last_error, " bridge=", game.get_gameplay_bridge().get_runtime_status())
		quit(1)
		return false
	# Back-to-back events (handover -> commission choice) hand over the camera
	# before this frame, so only judge follow state when the queue is quiet.
	if not game.get_story_director().is_busy():
		var camera := game.get_camera_director().get_camera()
		check(camera.mode == BoundedFollowCamera.Mode.FOLLOW and is_equal_approx(camera.get_directed_zoom(), camera.preferred_zoom), "Event restores gameplay camera follow and zoom: " + id)
	await frames()
	await picture(id)
	return true

func event_completed(id: String) -> bool:
	# Negotiation may be revisited after leaving; only the actual payment is durable.
	if id == "day1.s05.mansion_payment":
		return state.get_flag("day1.s05.guard_payment_completed") and not game.get_story_director().is_busy()
	return state.is_event_completed(id)

func make_order(order: String, target: String, accept := true) -> void:
	var delivery := game.get_task_delivery()
	if accept:
		check(delivery.accept_order(order) == OK, "Accepts " + order)
	var req := delivery.get_requirement(order)
	if req.is_empty():
		# Free-mixing order: no recipe exists, so the cup comes from 自由实验 with
		# its own confirmed price before it can be sold.
		var production := game.get_tea_production()
		var materials: Array[String] = ["creamer_milk_tea_base", "firefly_cap", "goblin_firebrew"]
		var request := "test-mix-" + order
		var quote := production.confirm_formula(materials, request)
		check(quote.get("ok", false), "Free mix is priced before crafting: " + order)
		var mixed := production.craft_formula(materials, 1, request)
		check(mixed.get("ok", false), "Free mix crafts the trial cup: " + order)
	else:
		var product: String = req.keys()[0]
		var recipe := game.get_tea_production().get_recipe_by_product(product)
		var result := game.get_tea_production().craft(recipe.materials)
		check(result.ok, "Crafts " + product + ": " + result.message)
	# Exercise the actual button -> page -> modal -> facade -> host -> atomic delivery.
	var ui := game.get_shop_ui()
	var point := InteractionPoint.new()
	point.interaction_id = &"orders"
	ui.open(point)
	point.free()
	var board := ui.get_popup().get_page().get_order_board_page()
	check(board.select_order(order), "Selects ready order immediately: " + order)
	check(board.get_ticket().get_primary_button().text in ["正在追踪", "追踪此单"], "A ready order only offers tracking: " + order)
	board.get_ticket().get_primary_button().pressed.emit()
	check(not state.get_flag("delivery." + order + ".completed"), "The order board never settles a cup by itself")
	# Handing the cup over is the counter interaction; it runs the same atomic call.
	var delivered := delivery.try_submit(order, target)
	check(delivered.ok and state.get_flag("delivery." + order + ".completed"), "Counter delivery settles " + order + " for " + target)
	var settled: Dictionary = state.to_dict()
	check(not delivery.try_submit(order, target).ok and state.to_dict() == settled, "Repeated delivery cannot consume or reward twice")
	ui.close()
	await frames()

func travel(exit_id: String) -> void:
	check(game.get_chapter_gameplay().last_error.is_empty(), "Chapter actions have no runtime error before travel")
	var exits: Array[SceneExit] = game.get_active_level().get_scene_exits()
	var point: SceneExit
	for candidate: SceneExit in exits:
		if String(candidate.interaction_id) == exit_id:
			point = candidate
	check(point != null, "Door exists " + exit_id)
	if point == null:
		quit(1)
		return
	# Actual SceneTravel creates and admits the destination, preserving session.
	game.get_player().teleport_to(point.global_position + Vector2(0, 36))
	var travel_error := game.get_scene_travel().request_exit(point)
	check(travel_error == OK, "Travels via " + exit_id)
	if travel_error != OK:
		quit(1)
		return
	await scene_changed
	attach()
	while game.get_scene_travel().is_busy():
		await process_frame
	await frames(5)
	await picture(exit_id)

func throw_coin() -> void:
	var service := game.get_stealth_service()
	var before: int = state.get_transactions().get_balance()
	check(service.select_throwable(&"coin") == OK, "Player selects actual coin")
	check(service.request_throw(game.get_player().global_position + Vector2(60, 20)) == OK, "Actual throw animation starts")
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if state.get_transactions().get_balance() == before - 10 and game.get_player().get_active_action().is_empty():
			break
	check(state.get_transactions().get_balance() == before - 10, "Animation release spends exactly 10G")
	await frames(10)

func use_service_point(id: StringName) -> void:
	var point: InteractionPoint
	for candidate: InteractionPoint in game.get_active_level().get_interaction_points():
		if candidate.interaction_id == id:
			point = candidate
	check(point != null, "Authored service object exists: " + String(id))
	if point == null:
		return
	game.get_player().teleport_to(point.global_position + (Vector2(24, 0) if id == &"tavern" else Vector2.ZERO))
	for tick in range(5):
		await physics_frame
	check(point.is_available(), "Service object is physically available in this stage")
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = &"interact"
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)

func _run() -> void:
	Engine.time_scale = 6.0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--save-fixtures="):
			fixture_directory = argument.trim_prefix("--save-fixtures=")
		if argument.begins_with("--captures="):
			screenshots = argument.trim_prefix("--captures=")
		ordinary_order = ordinary_order or argument == "--ordinary-order"
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/two_day_%d" % OS.get_process_id())
	state = root.get_node("GameState")
	check(change_scene_to_file(GameEntry.TITLE_SCENE) == OK, "Loads title")
	await scene_changed
	check(GameEntry.start_new_game(self) == OK, "Title new game")
	await scene_changed
	attach()
	await wait_event("day1.opening")
	await capture("day1_01_human")
	await make_order("day1_human", "human_customer")
	await wait_event("day1.first_goblin")
	await capture("day1_02_goblin")
	await make_order("day1_goblin", "goblin_customer")
	await wait_event("day1.group_arrival")
	await capture("day1_03_group")
	for id: String in ["a", "c", "d", "e"]:
		if id != "a":
			await wait_event("day1.customer_" + id)
		# 第二次来客是赌徒、说教的、爱收集的一起进门，之后仍是逐位接待。
		var expected_customers := 3 if id == "a" else 1
		var visible_customers := 0
		for actor_id: String in ["goblin_customer", "goblin_a", "goblin_b", "goblin_c", "goblin_d", "goblin_e"]:
			visible_customers += 1 if game.get_actor_director().get_actor(StringName(actor_id)).visible else 0
		check(visible_customers == expected_customers, "Only the intended customers occupy the shop")
		await capture("day1_03_customer_" + id)
		await make_order("day1_group_" + id, "goblin_" + id)
	await wait_event("day1.ending")
	await wait_event("day1.s03.coin_inspect")
	await capture("day1_04_coin")
	check(state.get_transactions().get_balance() == 18, "One human and five goblins pay 18G")
	check(state.get_warehouse_inventory().get_stock("strange_coin") == 0, "No duplicate coin inventory")
	await travel("shop_exit")
	await wait_event("day1.s03.street_gone")
	await capture("day1_05_market")
	var market := game.get_active_level() as RpgChapterMap
	check(market.market_only, "First outing restricts exploration to the market")
	var gather := game.get_gathering_service()
	var unopened: Dictionary = state.to_dict()
	check(not gather.harvest(&"night_gather_0").ok and state.to_dict() == unopened, "First outing cannot harvest or consume a gathering opportunity")
	check(not market.can_stand_at(Vector2(1176, 2112), Vector2(4, 3)), "Cannot walk north out of market")
	check(not market.can_stand_at(Vector2(1512, 1896), Vector2(4, 3)), "Cannot walk toward tavern during first visit")
	check(game.get_shop_ui().get_feedback_text().contains("黑灯瞎火"), "Boundary explains the protagonist's refusal")
	check(get_nodes_in_group("wayfinding").is_empty(), "Removed road signs leave no interactive targets")
	game.get_player().teleport_to(Vector2(1320, 2424))
	await frames(30)
	check(state.get_flag("day1.s03.exploration_completed"), "Walking through market completes observation without interacting")
	check(not state.is_event_completed("day1.s03.back_to_door"), "Observation does not interrupt exploration before returning")
	check(not state.get_flag("day1.s03.observed_street") and not state.get_flag("day1.s03.observed_path"), "No investigation checklist required")
	await picture("first_market_visit")
	game.get_player().teleport_to(Vector2(1608, 2568))
	await wait_event("day1.s03.back_to_door")
	await travel("shop_enter")
	await wait_event("day1.s04.commission")
	check(game.get_character_journal().get_character("characters.fat_goblin").get("title") == "胖哥布林", "First conversation already opens the fat goblin record")
	await capture("day1_06_commission")
	await make_order("day1_s04_fat", "fat_goblin")
	await wait_event("day1.s04.after_order")
	check(state.story_stage == "day1.s04.wait_taste", "The new gift dialogue returns control for real trial crafting")
	check(not state.is_event_completed("day1.s04.after_taste"), "Dialogue alone does not complete the trial")
	await capture("day1_06_trial_taste")
	await make_order("day1_s04_taste", "fat_goblin")
	await wait_event("day1.s04.after_taste")
	# The handover leads straight into the choice: reading the map is optional now.
	await wait_event("day1.s04.commission_choice")
	check(state.get_flag("day1.s04.map_available"), "Handover still unlocks the real map")
	check(not state.get_flag("day1.s04.map_opened") and not state.get_flag("day1.s04.map_closed"), "Commission choice never waits on the map screen")
	check(game.open_map() == OK, "Player can still open the map in shop")
	game.get_ui_manager().close_screen(ScreenIds.MAP)
	await capture("day1_07_before_stealth")
	check(state.get_transactions().get_balance() == 71, "Seven paid cups and once-only 50G funding")
	var gameplay: ChapterGameplay = game.get("_chapter_gameplay")
	check(gameplay.execute("day1.s04.funding").ok and state.get_transactions().get_balance() == 71, "Funding replay pays no duplicate")
	check(state.get_warehouse_inventory().get_uses("firefly_cap") == 1 and state.get_warehouse_inventory().get_uses("goblin_firebrew") == 4, "Trial consumes one use from the five-use firebrew gift")
	await travel("shop_exit")
	check(not (game.get_active_level() as RpgChapterMap).market_only, "Accepted commission removes first-visit movement restrictions")
	check(game.get_gathering_service().is_harvestable(game.get_gathering_service().get_point(&"night_gather_0")), "Accepted commission opens real gathering")
	# Exercise whole-attempt inventory, wallet and investigation rollback across room travel.
	await frames(10)
	var baseline: Dictionary = state.to_dict()
	for i in range(3):
		await throw_coin()
	game.get_player().teleport_to(Vector2(1416, 456))
	await wait_event("day1.s05.drunken_guard")
	check(game.get_story_director().request_interaction("mansion_payment") == OK, "Player pays mansion pair")
	await wait_event("day1.s05.mansion_payment")
	check(state.get_transactions().get_balance() == 21, "First night spends full 50G")
	await travel("elder_enter")
	var blood: StoryInteractionPoint
	var document: StoryInteractionPoint
	for point: InteractionPoint in game.get_active_level().get_interaction_points():
		if point is StoryInteractionPoint:
			if point.kind == StoryInteractionPoint.Kind.DOCUMENT:
				document = point
			else:
				blood = point
	check(blood.resolve().ok and document.resolve().ok, "Blood then document works")
	check(game.get_stealth_service() == null, "Indoor collection has no stealth or retry flow")
	await travel("elder_exit")
	var retry_error := game.get_stealth_service().retry_attempt()
	check(retry_error == OK, "Exterior retry restores the whole attempt after leaving the house")
	if retry_error != OK:
		quit(1)
		return
	await frames(5)
	check(state.to_dict() == baseline, "Retry restores full coins, inventory, facts and events")
	for i in range(3):
		await throw_coin()
	game.get_player().teleport_to(Vector2(1416, 456))
	await wait_event("day1.s05.drunken_guard")
	check(game.get_story_director().request_interaction("mansion_payment") == OK, "Pair can be paid after retry")
	await wait_event("day1.s05.mansion_payment")
	await travel("elder_enter")
	for point: InteractionPoint in game.get_active_level().get_interaction_points():
		if point is StoryInteractionPoint and point.kind == StoryInteractionPoint.Kind.DOCUMENT:
			document = point
		if point is StoryInteractionPoint and point.kind == StoryInteractionPoint.Kind.PICKUP:
			blood = point
	check(document.resolve().ok and blood.resolve().ok, "Document then blood works")
	var stock: int = state.get_warehouse_inventory().get_stock("day1_elder_document")
	check(document.resolve().ok and state.get_warehouse_inventory().get_stock("day1_elder_document") == stock, "Document reread grants once")
	check(state.get_warehouse_inventory().get_uses("day1_griffin_blood") == 3, "Blood pickup grants three uses")
	check(game.open_tasks() == OK, "Task log opens inside the elder house")
	await picture("day1_07_elder_task_log")
	game.get_ui_manager().close_screen(&"tasks")
	await frames()
	await travel("elder_exit")
	game.get_player().teleport_to(Vector2(1176, 648))
	await frames(40)
	check(not state.get_flag("day1.s05.escape_completed"), "Northern observation no longer completes the return route")
	game.get_player().teleport_to(game.get_active_level().get_scene_entrance(&"shop_door").global_position)
	await frames(40)
	check(state.get_flag("day1.s05.escape_completed"), "Return route completes at the shop door")
	await travel("shop_enter")
	await wait_event("day1.s06.pondering")
	await capture("day1_08_blood_recipe")
	var recipe := game.get_tea_production().get_recipe_by_product("day1_blood_milk_tea")
	# 委托特调只能手调：制作台不给一键成品，而是把人送到自由实验。
	await use_service_point(&"tea_station")
	var shop_ui := game.get_shop_ui()
	var page := shop_ui.get_popup().get_page()
	var crafting := page.get_order_crafting_page()
	check(crafting.visible and crafting.get_ticket().get_primary_button().text == "去自由实验手调", "Blood special waits for hand mixing instead of one click")
	await picture("day1_09_blood_order_guide")
	crafting.get_ticket().get_primary_button().pressed.emit()
	await frames()
	var formula := page.get_formula_panel()
	check(formula.is_visible_in_tree() and formula.get_materials() == recipe.materials, "Guidance opens 自由实验 with the special already assembled")
	await picture("day1_10_blood_handmix")
	shop_ui.close()
	await frames()
	check(game.get_tea_production().craft(recipe.materials).ok, "C01+blood crafts task special")
	await wait_event("day1.s06.customer")
	check(game.get_task_delivery().try_submit("day1_s06_blood_drink", "fat_goblin").ok, "Blood drink pays its task")
	await wait_event("day1.s06.reaction")
	check(state.current_day == 2 and state.story_stage == "day2.s01", "Automatic Day2 morning")
	check(state.get_transactions().get_balance() == 121, "Reward is prepaid at the commission, delivery never pays twice")
	check(state.get_warehouse_inventory().get_uses("day1_griffin_blood") == 2, "Blood remains two uses")
	await wait_event("day2.s01.morning")
	check(state.get_transactions().get_balance() == 156, "The 35G errand bag lands in the real purse")
	check(game.get_chapter_gameplay().get_procurement().get_status().escrow == 35, "The errand ledger records the same 35G")
	for group: String in ["festival", "elder", "emissary", "rumor"]:
		await wait_event("day2.s02." + group + "_order")
		if group == "festival":
			check(state.confirm_formula(["creamer_milk_tea_base", "goblin_firebrew"], "two-day.price").ok, "Confirm a permanent quote at a safe wait boundary")
		await capture("wait_" + group)
		var count := 2 if group == "rumor" else 1
		for i in range(count):
			await make_order("day2_s02_%s_%d" % [group, i], "day2_%s_%d" % [group, i])
		await wait_event("day2.s02." + group + "_after")
	check(state.get_transactions().get_balance() == 171, "Mandatory path has 171G before the 100G wine")
	var scheduler := game.get_chapter_gameplay().get_scheduler()
	var deadline := Time.get_ticks_msec() + 10000
	while scheduler.get_group("rumor").status != "departed" and Time.get_ticks_msec() < deadline:
		await process_frame
	if ordinary_order:
		check(game.get_task_delivery().accept_order("day2_ordinary_a") == OK, "Accept one optional ordinary order")
		check(game.get_chapter_gameplay().close_business() == ERR_UNAVAILABLE, "Accepted optional order prevents closing")
		await make_order("day2_ordinary_a", "day2_ordinary_a", false)
	await capture("wait_close")
	check(game.get_chapter_gameplay().close_business() == OK, "May close without accepting ordinary orders or hiring")
	await wait_event("day2.s02.stage_end")
	await capture("closed")
	await travel("shop_exit")
	await capture("tavern_exterior")
	await travel("tavern_enter")
	await frames(30)
	check(not game.get_story_director().is_busy() and not state.is_event_completed("day2.s03.amber_wine"), "Tavern arrival leaves observation and movement to the player")
	await use_service_point(&"tavern")
	await wait_event("day2.s03.amber_wine")
	await capture("wait_wine")
	await use_service_point(&"tavern")
	await wait_event("day2.s03.purchase")
	check(state.get_transactions().get_balance() == (94 if ordinary_order else 91), "Wine actually costs the discounted 80G")
	check(state.get_warehouse_inventory().get_uses("griffin_amber_wine") == 5, "One purchased portion has five uses")
	check(not state.is_event_completed("day2.s03.commission_token"), "Commission waits for another counter interaction")
	await use_service_point(&"tavern")
	await wait_event("day2.s03.commission_token")
	var gathering_notice := game.get_chapter_gameplay().get_gathering_notice()
	check("明天" in gathering_notice and not "苔痕青" in gathering_notice, "Day two commission waits for tomorrow's ingredient list")
	await capture("purchased")
	await travel("tavern_exit")
	await capture("casino_exterior")
	await travel("casino_enter")
	await frames(30)
	check(not game.get_story_director().is_busy() and not state.is_event_completed("day2.s04.casino"), "Casino arrival does not consume the table interaction")
	await use_service_point(&"casino_table")
	await wait_event("day2.s04.casino")
	await capture("wait_first")
	check(not state.get_flag("day2.s04.first_loss"), "First round waits for a player click")
	await use_service_point(&"casino_table")
	await wait_event("day2.s04.first_round")
	await capture("first_round")
	check(state.get_flag("day2.casino.debt.active") and state.get_task_result("day2.casino.debt").is_empty(), "First loss creates a real unsettled ten-cup debt")
	check(not state.get_flag("day2.s04.casino_reward_received"), "Second round waits for another click")
	await use_service_point(&"casino_table")
	await wait_event("day2.s04.second_round")
	await capture("second_round")
	check(state.get_task_result("day2.casino.debt").get("status") == "cancelled", "Second round really cancels the debt")
	check(not "赌场的十杯奶茶还没还" in game.get_chapter_gameplay().get_recap_text(), "A waived debt is absent from the journey recap")
	for item: String in ["phantom_gold_mushroom", "rainbow_cube", "honey_amber_crystal"]:
		check(state.get_warehouse_inventory().get_uses(item) == 5, "Casino awards exactly one portion of " + item)
	await travel("casino_exit")
	await wait_event("day2.s05.street")
	await capture("return_shop")
	await travel("shop_enter")
	await wait_event("day2.s05.special_before")
	await capture("wait_special")
	var special := game.get_tea_production().get_recipe_by_product("day2_guard_milk_tea")
	check(special.materials == ["creamer_milk_tea_base", "griffin_amber_wine", "phantom_gold_mushroom"], "Guard recipe excludes blood")
	check(special.experiment_only, "Guard special is mixed in 自由实验, not listed as a known recipe")
	check(game.get_tea_production().craft_free(special.materials).ok, "Player assembles the guard special from free materials")
	check(state.get_warehouse_inventory().get_uses("griffin_amber_wine") == 4 and state.get_warehouse_inventory().get_uses("phantom_gold_mushroom") == 4, "Wine and mushroom remain four uses each")
	await wait_event("day2.s05.special_after")
	await capture("crafted_special")
	check(state.get_warehouse_inventory().get_uses("day1_griffin_blood") == 2, "Blood remains excluded from the later special")
	await travel("shop_exit")
	check(not game.get_task_delivery().try_submit("day2_guard_special", "drunken_guard").ok, "Cannot hand over before the three greeting lines")
	var guard := game.get_actor_director().get_actor(&"drunken_guard")
	var guard_point := game.get_delivery_point(&"drunken_guard")
	check(guard != null and guard.is_visible_in_tree(), "Delivery guard is actually visible after leaving the shop")
	check(guard_point != null and guard_point.interaction_enabled, "Delivery guard has an enabled player interaction")
	if guard == null or guard_point == null or not guard.is_visible_in_tree():
		quit(1)
		return
	game.get_player().teleport_to(guard.global_position + Vector2(0, 30))
	for tick in range(5):
		await physics_frame
	check(guard_point.is_available(), "The player can physically approach the guard")
	check(game.get_shop_interaction().get_target() == guard_point, "The real selector targets the guard")
	for pressed: bool in [true, false]:
		var interact := InputEventAction.new()
		interact.action = &"interact"
		interact.pressed = pressed
		Input.parse_input_event(interact)
		await frames(2)
	await wait_event("day2.s05.guard_greet")
	await capture("wait_guard")
	check(not game.get_task_delivery().try_submit("day2_guard_special", "casino").ok, "Wrong recipient cannot consume the special")
	check(game.get_task_delivery().try_submit("day2_guard_special", "drunken_guard").ok, "Real guard receives the special")
	check(state.get_transactions().get_balance() == (94 if ordinary_order else 91), "Guard hospitality pays zero G")
	await wait_event("day2.s05.guard_after")
	var journal := game.get_character_journal()
	var guard_record := journal.get_character("characters.drunken_guard")
	var fat_record := journal.get_character("characters.fat_goblin")
	var fat_records: Array = fat_record.get("records", [])
	check(guard_record.get("title") == "醉酒守卫" and fat_record.get("title") == "胖哥布林", "Guard delivery adds the guard while preserving the earlier fat goblin record")
	check(fat_records.size() == 1 and fat_records[0].content == "有点话多、贪吃的哥布林。", "Fat goblin entry carries its description")
	await capture("delivered_guard")
	await travel("shop_enter")
	await frames(12)
	check(state.current_day == 2 and not state.get_flag("day2.completed"), "Final return waits for the patient's last cup even without a purchase")
	await travel("shop_exit")
	check(game.get_chapter_gameplay().get_procurement().purchase_direct() == OK, "The final errand buys a real mushroom before the ending")
	await wait_event("day2.procurement.recipe")
	await travel("shop_enter")
	await wait_event("day2.procurement.before_rest")
	game.get_chapter_gameplay().perform_user_action("recovery_resupply")
	await frames()
	var recovery_recipe: Array[String] = ["insomnia_mushroom", "mint_syrup", "red_mottled_wood"]
	check(game.get_tea_production().craft_free(recovery_recipe, 1, true).ok, "Craft the final iced cup for the patient")
	await frames()
	check(not state.get_flag("day2.completed"), "Making the final cup alone cannot finish the second day")
	var patient := game.get_actor_director().get_actor(&"fat_goblin")
	game.get_player().teleport_to(patient.global_position + Vector2(0, 40))
	for tick in range(6):
		await physics_frame
	check(game.get_shop_interaction().get_target() == game.get_delivery_point("fat_goblin"), "Final cup focuses the resting patient")
	var handoff := InputEventAction.new()
	handoff.action = &"interact"
	handoff.pressed = true
	Input.parse_input_event(handoff)
	await frames(2)
	handoff = InputEventAction.new()
	handoff.action = &"interact"
	Input.parse_input_event(handoff)
	check(state.get_flag("day3.procurement.delivered"), "World interaction gives the last cup to the patient")
	await wait_event("day2.s05.unsolved")
	check(state.current_day == 3 and state.story_stage == "day3.handoff", "Real return to shop ends chapter at Day3 handoff")
	await frames()
	check(game.get_ui_manager().is_open(ScreenIds.CHAPTER_RECAP), "Two-day results appear only after the chapter finishes")
	await picture("two_day_recap")
	game.get_ui_manager().close_screen(ScreenIds.CHAPTER_RECAP)
	check(state.get_flag("ui.two_day_recap_seen"), "Closing the recap acknowledges it for future saves")
	await frames(10)
	check(game.get_ui_manager().is_open(ScreenIds.TWO_DAYS_END), "Closing the recap ends the build on the end card")
	# The switch lands after the outgoing track has faded; the card is up by then.
	await frames(140)
	check(game.get_audio_manager().get_bgm_state().id == "music.two_days_end", "The end card plays its own cue")
	await picture("two_days_end")
	# Dismiss the card without finishing it: the handoff state still has to be
	# captured for the persistence pass, and the task clock exercised below.
	game.get_ui_manager().close_screen(ScreenIds.TWO_DAYS_END)
	check(not state.get_flag("ui.two_days_end_seen"), "Leaving the card early does not mark the run finished")
	await frames(5)
	await capture("day3_handoff")
	check(DayPhase.advance_to(state, 3, "night") == OK, "Wait through the allowed third evening")
	check(DayPhase.advance_to(state, 4, "day") == OK, "End the permitted handoff period")
	await frames(12)
	check(game.get_chapter_gameplay().get_procurement().get_status().status == "delivered", "The final cup keeps the fulfilled errand complete on Day4")
	await capture("day4_expired")
	var entries: Dictionary = state.get_variable("chronicle.entries", {})
	check(entries.has_all(["chronicle.tavern", "chronicle.griffin_festival", "chronicle.griffin_token"]), "Original Day2 journal entries are actually unlocked")
	check(state.validate_snapshot(state.to_dict()) == OK, "Complete two-day snapshot validates")
	check(game.get_chapter_gameplay().last_error.is_empty(), "Chapter actions finish without runtime error")
	print("TWO_DAY_FLOW: ", checks, " checks, ", failures.size(), " failures")
	if not fixture_directory.is_empty():
		var completion := FileAccess.open(fixture_directory.path_join("complete.json"), FileAccess.WRITE)
		if completion != null:
			completion.store_string(JSON.stringify({"checks": checks, "failures": failures.size()}))
	quit(0 if failures.is_empty() else 1)
