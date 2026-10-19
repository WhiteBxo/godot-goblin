extends "res://tests/verify_day1_playability.gd"
## Continue a real wait_festival autosave from verify_two_day_flow --save-fixtures.
## Progress uses actual E / keyboard UI; direct delivery probes only test rejection.

func _run() -> void:
	Engine.time_scale = 6.0
	root.size = Vector2i(1280, 720)
	var source := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--from-save="):
			source = argument.trim_prefix("--from-save=")
		if argument.begins_with("--captures="):
			screenshots = argument.trim_prefix("--captures=")
	if source.is_empty():
		push_error("Provide --from-save=<real wait_festival fixture directory>")
		quit(2)
		return
	var directory := OS.get_cache_dir().path_join("goblin_day2_playability_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(directory)
	check(DirAccess.copy_absolute(source.path_join("autosave.dat"), directory.path_join("autosave.dat")) == OK, "Copy a real save into an isolated test directory")
	ProjectSettings.set_setting("persistence/save_directory", directory)
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	state = root.get_node("GameState")
	var loaded := GameEntry.create_save_store().load_save(GameEntry.preflight_save)
	check(loaded.error == OK, "Validate the real checkpoint before continuing")
	if loaded.error != OK:
		finish()
		return
	var original := FileAccess.get_file_as_bytes(directory.path_join("autosave.dat"))
	check(GameEntry.continue_game(self) == OK, "Continue the actual Day 2 checkpoint through GameEntry")
	await scene_changed
	attach()
	while game.is_session_initializing():
		await process_frame
	await frames(12)
	check(state.current_day == 2 and state.story_stage == "day2.s02.wait_festival", "Real checkpoint enters the first Day 2 customer group")
	var restored: Dictionary = state.to_dict()
	if not loaded.data.game_state.task_results.has("day2.main.morning"):
		check(state.get_task_result("day2.main.morning") == {"status": "completed", "day": 2, "phase": "day", "reason": ""}, "Legacy saves backfill the completed morning task without rewards")
		restored.task_results.erase("day2.main.morning")
	check(restored == loaded.data.game_state, "Restoring preserves every saved fact, balance, item, receipt and existing task result")
	check(FileAccess.get_file_as_bytes(directory.path_join("autosave.dat")) == original, "Continuing never rewrites the original checkpoint")
	assert_main("day2.main.business", "festival")
	check(not game.get_task_delivery().try_submit("day2_guard_special", "drunken_guard").ok, "Early guard delivery stays locked")
	for group: String in ["festival", "elder", "emissary", "rumor"]:
		await wait_event("day2.s02." + group + "_order")
		var count := 2 if group == "rumor" else 1
		for index in range(count):
			await serve_order("day2_s02_%s_%d" % [group, index])
		await wait_event("day2.s02." + group + "_after")
	assert_main("day2.main.business", "close")
	var scheduler := game.get_chapter_gameplay().get_scheduler()
	var deadline := Time.get_ticks_msec() + 10000
	while scheduler.get_group("rumor").status != "departed" and Time.get_ticks_msec() < deadline:
		await process_frame
	await picture("day2_close_objective")
	await press_chapter_action("hire:day2_ordinary_a")
	check(game.get_chapter_gameplay().get_procurement().get_status().get("status") == "hired", "A real HUD button hires a runner from isolated escrow")
	await press_chapter_action("day2.close")
	await wait_event("day2.s02.stage_end")
	check(DayPhase.is_night(state), "The close button enters the actual night schedule")
	assert_main("day2.main.tavern", "arrive")
	await use_door("shop_exit")
	await picture("day2_tavern_objective")
	if not await harvest_commercial_route():
		finish()
		return
	await use_door("tavern_enter")
	await frames(20)
	check(not game.get_story_director().is_busy() and game.get_player().movement_enabled, "Entering tavern preserves free observation")
	if not await walk_to_service(&"tavern"):
		finish()
		return
	await tap(&"interact")
	await wait_event("day2.s03.amber_wine")
	assert_main("day2.main.tavern", "buy")
	var balance: int = game.get_transactions().get_balance()
	await tap(&"interact")
	await wait_event("day2.s03.purchase")
	check(not state.is_event_completed("day2.s03.commission_token"), "Purchase returns control before the commission")
	var commission_dialogues: Array[String] = []
	game.get_dialogue_manager().dialogue_started.connect(func(id: String) -> void: commission_dialogues.append(id))
	await tap(&"interact")
	await wait_event("day2.s03.commission_token")
	check("day2.s03.tavern_commission_gathered" in commission_dialogues and "day2.s03.tavern_commission_not_gathered" not in commission_dialogues, "The real commission acknowledges gathering done along the route")
	check("已齐备" in game.get_chapter_gameplay().get_gathering_notice(), "Accepted commission reads the already collected stock")
	check(game.get_transactions().get_balance() == balance - 48, "The purchase button pays the real discounted price")
	check(game.get_warehouse_inventory().get_uses("griffin_amber_wine") == 5, "The UI purchase grants exactly five uses")
	assert_main("day2.main.casino", "arrive")
	await use_door("tavern_exit")
	await use_door("casino_enter")
	await frames(20)
	check(not game.get_story_director().is_busy(), "Casino entrance gives time to recognize the table")
	if not await walk_to_service(&"casino_table"):
		finish()
		return
	await tap(&"interact")
	await wait_event("day2.s04.casino")
	assert_main("day2.main.casino", "first")
	await picture("day2_casino_objective")
	await tap(&"interact")
	await wait_event("day2.s04.first_round")
	assert_main("day2.main.casino", "second")
	await tap(&"interact")
	await wait_event("day2.s04.second_round")
	check(state.get_task_result("day2.casino.debt").get("status") == "cancelled", "Keyboard round buttons really cancel the ten-cup debt")
	assert_main("day2.main.guard", "leave")
	await use_door("casino_exit")
	await wait_event("day2.s05.street")
	await use_door("shop_enter")
	await wait_event("day2.s05.special_before")
	assert_main("day2.main.guard", "craft")
	var station := shop_point(&"tea_station")
	await stand_at(station.global_position + Vector2(0, 40))
	await tap(&"interact")
	var page := game.get_shop_ui().get_popup().get_page()
	var crafting := page.get_crafting_panel()
	check(crafting.is_visible_in_tree() and not page.get_order_crafting_page().is_visible_in_tree(), "Without an accepted drink order E opens the available recipes")
	check(crafting.select_recipe("day2_guard_milk_tea"), "The real station offers the unlocked guard recipe")
	check(page.uses_native_gui_input(), "Recipe confirmation uses native button input instead of the empty screen callback")
	check(not game.get_task_delivery().try_submit("day2_guard_special", "drunken_guard").ok, "Opening a recipe cannot bypass the guard greeting")
	var craft_button: Button = crafting.get_node("Body/Right/CraftButton")
	craft_button.grab_focus()
	await frames(3)
	check((crafting.get_parent() as ScrollContainer).get_global_rect().encloses(craft_button.get_global_rect()), "Recipe confirmation scrolls fully into the visible content area")
	check(root.get_visible_rect().encloses(craft_button.get_global_rect()), "The actual guard confirmation remains inside the viewport")
	await picture("day2_guard_recipe")
	await tap(&"ui_accept")
	check(game.get_warehouse_inventory().get_stock("day2_guard_milk_tea") == 1, "Keyboard confirmation produces the carried guard drink")
	check(not state.get_flag("day2.s05.special_drink_delivered"), "Making the drink never delivers it")
	await tap(&"ui_cancel")
	await wait_event("day2.s05.special_after")
	assert_main("day2.main.guard", "greet")
	await use_door("shop_exit")
	var guard := game.get_delivery_point("drunken_guard")
	await stand_at(guard.global_position + Vector2(0, 36))
	await tap(&"interact")
	await wait_event("day2.s05.guard_greet")
	assert_main("day2.main.guard", "deliver")
	await picture("day2_guard_delivery")
	balance = game.get_transactions().get_balance()
	await tap(&"interact")
	check(state.get_flag("day2.s05.special_drink_delivered"), "A second E after the greeting submits the actual guard order")
	check(game.get_transactions().get_balance() == balance, "Guard hospitality remains free")
	await wait_event("day2.s05.guard_after")
	assert_main("day2.main.guard", "return")
	await use_door("shop_enter")
	await wait_event("day2.s05.unsolved")
	check(state.current_day == 3 and state.story_stage == "day3.handoff", "Actual E return completes Day 2 and reaches the next morning")
	for id: String in ["morning", "business", "tavern", "casino", "guard"]:
		check(game.get_task_journal().get_task("day2.main." + id).status == "completed", "Day 2 task finishes from real facts: " + id)
	check(game.get_chapter_gameplay().get_procurement().get_status().get("status") == "returned", "The hired runner returns on the next morning")
	check(game.get_warehouse_inventory().get_uses("day1_griffin_blood") == 2, "Guard preparation preserves the remaining blood")
	check(game.get_warehouse_inventory().get_uses("griffin_amber_wine") == 4 and game.get_warehouse_inventory().get_uses("phantom_gold_mushroom") == 4, "The real recipe consumes one use of each special ingredient")
	await picture("day2_complete")
	game.queue_free()
	await frames(10)
	finish()

func assert_main(task_id: String, objective_id: String) -> void:
	var task := game.get_task_journal().get_current_main_task()
	check(task.get("id") == task_id and task.get("current_objective", {}).get("id") == objective_id, "Current objective is %s / %s" % [task_id, objective_id])
	var hud := game.find_children("*", "TaskHUD", true, false)[0] as TaskHUD
	check(hud.is_visible_in_tree() and hud.get_node("Margin/Content/Objective").text == task.get("current_objective", {}).get("text", ""), "The player sees the current objective on the actual HUD")

func serve_order(order: String) -> void:
	var board := shop_point(&"orders")
	await stand_at(board.global_position + Vector2(0, -35))
	await tap(&"interact")
	var ui := game.get_shop_ui()
	check(ui.is_open(), "E opens the Day 2 counter for " + order)
	var page := ui.get_popup().get_page().get_order_board_page()
	check(page.select_order(order), "The current group order appears on the actual board: " + order)
	page.get_ticket().get_primary_button().grab_focus()
	await tap(&"ui_accept")
	check(game.get_task_delivery().is_order_accepted(order), "Keyboard acceptance commits " + order)
	await tap(&"ui_cancel")
	var station := shop_point(&"tea_station")
	await stand_at(station.global_position + Vector2(0, 40))
	await tap(&"interact")
	var crafting := ui.get_popup().get_page().get_order_crafting_page()
	check(crafting.is_visible_in_tree(), "An accepted Day 2 order opens order crafting")
	crafting.get_ticket().get_primary_button().grab_focus()
	await tap(&"ui_accept")
	await tap(&"ui_cancel")
	var target := game.get_delivery_point(game.get_order_board().get_entry(order).target_id)
	await stand_at(target.global_position + Vector2(0, -35))
	check("交付" in ui.get_prompt_text(), "The counter selects the customer with a real carried cup")
	await tap(&"interact")
	check(state.get_flag("delivery." + order + ".completed"), "Actual E delivers the selected customer's order: " + order)

func press_chapter_action(id: String) -> void:
	await frames(6)
	var label := ""
	for action: Dictionary in game.get_chapter_gameplay().get_user_actions():
		if action.id == id:
			label = action.text
	var hud := game.find_children("*", "ChapterActionsHUD", true, false)[0] as ChapterActionsHUD
	if id.begins_with("hire:") and not hud.get_node("Scroll/Content/OptionalButtons").visible:
		hud.get_node("Scroll/Content/Details").grab_focus()
		await tap(&"ui_accept")
	var button: Button
	for child: Node in hud.get_node("Scroll/Content/Buttons").get_children() + hud.get_node("Scroll/Content/OptionalButtons").get_children():
		if child is Button and child.text == label:
			button = child
	check(button != null and not button.disabled and button.is_visible_in_tree(), "A usable chapter button exists: " + id)
	if button == null or button.disabled:
		finish()
		return
	button.grab_focus()
	await tap(&"ui_accept")

func use_door(id: String) -> void:
	var point: SceneExit
	for candidate: SceneExit in game.get_active_level().get_scene_exits():
		if String(candidate.interaction_id) == id:
			point = candidate
	check(point != null, "The physical door exists: " + id)
	if point == null:
		finish()
		return
	await stand_at(point.global_position + Vector2(0, 36))
	await tap(&"interact")
	await await_travel()
	await picture(id)

func walk_to_service(id: StringName) -> bool:
	var point := shop_point(id)
	check(point != null, "Formal room exposes the active service object")
	if point == null:
		return false
	var old_scale := Engine.time_scale
	Engine.time_scale = 1.0
	var reached := await walk_to(game.get_active_level() as RpgChapterMap, point.global_position)
	Engine.time_scale = old_scale
	check(reached and point.is_available(), "Player can walk from the entrance to the service side")
	await picture(String(id) + "_approach")
	return reached and point.is_available()

func harvest_commercial_route() -> bool:
	var previous_scale := Engine.time_scale
	Engine.time_scale = 1.0
	for point: GatherPoint in game.get_gathering_service().get_points():
		if not await walk_to(game.get_active_level() as RpgChapterMap, point.global_position):
			Engine.time_scale = previous_scale
			return false
		await picture(String(point.interaction_id) + "_before")
		await tap(&"interact")
		check(game.get_shop_ui().is_open(), "Walking and E open the real harvest result")
		await tap(&"ui_cancel")
		check(not point.is_available() and not point.get_node("HarvestVisual").visible, "Harvested artwork is consumed with its target")
	Engine.time_scale = previous_scale
	return true

func finish() -> void:
	print("DAY2_PLAYABILITY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
