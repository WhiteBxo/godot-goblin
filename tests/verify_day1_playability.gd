extends "res://tests/verify_two_day_flow.gd"
## Reproduces the player's counter and exterior interactions, including walking
## through the market. Never calls resolve() to advance exploration.

func _run() -> void:
	Engine.time_scale = 4.0
	screenshots = "/tmp/goblin_playability_captures" if "--capture" in OS.get_cmdline_user_args() else ""
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/playability_%d" % OS.get_process_id())
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	state = root.get_node("GameState")
	check(GameEntry.start_new_game(self) == OK, "Starts the formal new game")
	await scene_changed
	attach()
	await wait_event("day1.opening")
	var board := shop_point(&"orders")
	# Stand behind the counter, where customer and register reach circles overlap.
	await stand_at(board.global_position + Vector2(0, -35))
	check(game.get_delivery_point("human_customer").is_available() and board.is_available(), "Counter genuinely overlaps the customer and order point")
	check("收银台" in game.get_shop_ui().get_prompt_text(), "An unaccepted customer cannot steal the counter prompt")
	await tap(&"interact")
	var ui := game.get_shop_ui()
	check(ui.is_open(), "Physical E opens the order board at the crowded counter")
	var page := ui.get_popup().get_page().get_order_board_page()
	check(page.select_order("day1_human"), "First human order is selectable")
	page.get_ticket().get_primary_button().grab_focus()
	await tap(&"ui_accept")
	check(game.get_task_delivery().is_order_accepted("day1_human"), "Keyboard acceptance commits the first order")
	await tap(&"ui_cancel")
	var station := shop_point(&"tea_station")
	await stand_at(station.global_position + Vector2(0, 40))
	await tap(&"interact")
	var crafting := ui.get_popup().get_page().get_order_crafting_page()
	crafting.get_ticket().get_primary_button().grab_focus()
	await tap(&"ui_accept")
	check(game.get_warehouse_inventory().get_stock("classic_boba_milk_tea") == 1, "Keyboard crafting carries the first cup")
	await tap(&"ui_cancel")
	await stand_at(station.global_position + Vector2(0, 65))
	await tap(&"move_up")
	check("制作台" in ui.get_prompt_text(), "Facing the nearby station still selects it while a customer can receive a cup")
	await stand_at(board.global_position + Vector2(0, -35))
	check("交付" in ui.get_prompt_text(), "The same counter position now prioritizes real delivery")
	await picture("counter_delivery")
	await tap(&"interact")
	check(state.get_flag("day1.human_settled"), "Physical E delivers to the overlapping customer")
	await wait_event("day1.first_goblin")
	await make_order("day1_goblin", "goblin_customer")
	await wait_event("day1.group_arrival")
	for id: String in ["a", "c", "d", "e"]:
		if id != "a":
			await wait_event("day1.customer_" + id)
		await make_order("day1_group_" + id, "goblin_" + id)
	await wait_event("day1.ending")
	await wait_event("day1.s03.coin_inspect")
	check(game.get_task_journal().get_current_main_task().id == "day1.s03.explore", "Exploration task exists before leaving the shop")
	var exit_point: SceneExit = game.get_active_level().get_scene_exits()[0]
	await stand_at(exit_point.global_position + Vector2(0, -35))
	await tap(&"interact")
	await await_travel()
	await wait_event("day1.s03.street_gone")
	Engine.time_scale = 1.0
	var map := game.get_active_level() as RpgChapterMap
	for id: String in ["a", "b", "c"]:
		var actor := game.get_actor_director().get_actor(StringName("goblin_" + id))
		check(actor != null and actor.is_visible_in_tree(), "Returning goblin is visible in the daytime exterior: " + id)
		check(map.can_stand_at(actor.global_position, Vector2(7, 4)), "Returning goblin stands on walkable floor with its RPG footprint: " + id)
	var payment: InteractionPoint = map.get_node("Interactions/MansionPayment")
	check(payment.required_actors.size() == 2, "Shared guard point keeps both actor references after reparenting")
	# Range alone cannot make a hidden actor's point selectable.
	payment._on_body_entered(game.get_player())
	check(not payment.is_available(), "Invisible guards have no available payment interaction")
	payment._on_body_exited(game.get_player())
	var task_hud := game.find_children("*", "TaskHUD", true, false)[0] as TaskHUD
	check(task_hud.is_visible_in_tree(), "Exterior has a visible objective card")
	await picture("exterior_objective")
	check(map.market_only, "First outing keeps exploration within the market")
	if not await walk_to(map, Vector2(1320, 2424)):
		finish()
		return
	check(state.get_flag("day1.s03.exploration_completed"), "Real walking observes market without E or NPC tasks")
	check(game.get_task_journal().get_current_main_task().current_objective.id == "return", "Walking through market directs the player back to the shop")
	await picture("return_objective")
	if await walk_to(map, map.get_scene_entrance(&"shop_door").global_position):
		await wait_event("day1.s03.back_to_door")
		await tap(&"interact")
		await await_travel()
		check(state.get_flag("day1.s03.returned_shop"), "Walking home and E finish exploration through real travel")
		await wait_event("day1.s04.commission")
		var fat_record := game.get_character_journal().get_character("characters.fat_goblin")
		check(fat_record.get("title") == "胖哥布林", "The first introduction unlocks the fat goblin before the milk tea order")
		var fat_records: Array = fat_record.get("records", [])
		check(fat_records.size() == 1 and fat_records[0].content == "有点话多、贪吃的哥布林。", "The completed introduction immediately records the known description")
		await make_order("day1_s04_fat", "fat_goblin")
		await wait_event("day1.s04.after_order")
		check(game.get_tea_production().get_recipe_by_product("day1_trial_milk_tea") == null, "The trial cup has no ready-made recipe to click")
		await make_order("day1_s04_taste", "fat_goblin")
		await wait_event("day1.s04.after_taste")
		# 胖哥布林边讲边补词条：信仰段这三条、格里芬之血讲解后这一条。
		var journal := game.get_chronicle_journal()
		for entry_id: String in ["chronicle.griffin", "chronicle.elder", "chronicle.emissary", "chronicle.griffin_blood"]:
			check(not journal.get_entry(entry_id).get("records", []).is_empty(), "讲解后见闻录有正文: " + entry_id)
	game.queue_free()
	await frames(10)
	finish()

func finish() -> void:
	print("DAY1_PLAYABILITY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func tap(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)

func stand_at(position: Vector2) -> void:
	game.get_player().teleport_to(position)
	for i in range(5):
		await physics_frame
	await frames()

func shop_point(id: StringName) -> InteractionPoint:
	for point: InteractionPoint in game.get_active_level().get_interaction_points():
		if point.interaction_id == id:
			return point
	return null

func await_travel() -> void:
	var previous_id := game.get_instance_id() if is_instance_valid(game) else 0
	var deadline := Time.get_ticks_msec() + 10000
	while (not is_instance_valid(current_scene) or current_scene.get_instance_id() == previous_id) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(is_instance_valid(current_scene) and current_scene.get_instance_id() != previous_id, "Physical door interaction changes the formal host")
	attach()
	while game.get_scene_travel().is_busy():
		await process_frame
	await frames()

func walk_to(map: RpgChapterMap, destination: Vector2) -> bool:
	var start := map.world_to_cell(game.get_player().global_position)
	var goal := map.world_to_cell(destination)
	var previous := {start: start}
	var occupied: Dictionary = {}
	for actor: Node in game.get_node("World/EntityRoot").get_children():
		if actor is SettlementCharacter and actor.is_visible_in_tree():
			occupied[map.world_to_cell(actor.global_position)] = true
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty() and not previous.has(goal):
		var cell: Vector2i = queue.pop_front()
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
			var next := cell + direction
			if not previous.has(next) and not occupied.has(next) and map.can_cross_edge(cell, direction):
				previous[next] = cell
				queue.append(next)
	check(previous.has(goal), "Native floor route exists to " + str(destination))
	if not previous.has(goal):
		return false
	var route: Array[Vector2i] = [goal]
	while route[0] != start:
		route.push_front(previous[route[0]])
	for cell: Vector2i in route:
		var target := map.cell_to_world(cell)
		var deadline := Time.get_ticks_msec() + 2500
		while game.get_player().global_position.distance_to(target) > 5 and Time.get_ticks_msec() < deadline:
			if game.get_dialogue_manager().is_active():
				game.get_dialogue_manager().advance()
			for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
				Input.action_release(action)
			var offset := target - game.get_player().global_position
			var action := (&"move_right" if offset.x > 0 else &"move_left") if absf(offset.x) > absf(offset.y) else (&"move_down" if offset.y > 0 else &"move_up")
			Input.action_press(action)
			await physics_frame
		for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
			Input.action_release(action)
		if game.get_player().global_position.distance_to(target) > 10:
			check(false, "Real movement blocked at %s toward %s" % [game.get_player().global_position, target])
			await picture("walk_blocked")
			return false
	await frames(8)
	return true
