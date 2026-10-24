extends SceneTree
## Real actor visibility, travel, save recovery, walkable route and E-key delivery.

var state: Node
var game: MainGame
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func ticks(count := 8) -> void:
	for index in count:
		await physics_frame

func load_host(path: String) -> void:
	check(change_scene_to_file(path) == OK, "Load real host: " + path)
	await scene_changed
	game = current_scene as MainGame
	await ticks(20)

func guard() -> SettlementCharacter:
	return game.get_actor_director().get_actor(&"drunken_guard") as SettlementCharacter

func check_guard_visible(context: String) -> void:
	var actor := guard()
	var point := game.get_delivery_point(&"drunken_guard")
	check(actor != null and actor.is_visible_in_tree(), context + ": guard is visible")
	check(point != null and point.interaction_enabled, context + ": guard interaction is enabled")
	var target := game.get_quest_pointer().get_target()
	if point != null and not point.interaction_enabled:
		print("GUARD_DISABLED ", context, " day=", state.current_day, " stage=", state.story_stage, " actor=", actor.visible, " market_only=", game.get_active_level().market_only, " point_parent=", point.get_parent().name, " main_task=", game.get_task_journal().get_current_main_task().get("id"))
	check(target.get("source") == "actor" and target.get("node") == point and target.get("label") == "醉酒守卫", context + ": guidance tracks the named real NPC")

func travel(id: StringName) -> void:
	var selected: SceneExit
	for exit: SceneExit in game.get_active_level().get_scene_exits():
		if exit.interaction_id == id:
			selected = exit
	check(selected != null, "Travel exit exists: " + String(id))
	if selected == null:
		return
	game.get_player().teleport_to(selected.global_position + Vector2(0, 30))
	var travel_error := game.get_scene_travel().request_exit(selected)
	check(travel_error == OK, "Use real travel: " + String(id))
	if travel_error != OK:
		print("GUARD_TRAVEL_FAILURE ", error_string(travel_error), " stage=", state.story_stage, " access=", Day1Access.can_leave_shop(state), " movement=", game.get_player().movement_enabled, " modal=", game.get_ui_manager().has_modal(), " story=", game.get_story_director().is_busy(), " bridge=", game.get_gameplay_bridge().get_runtime_status(), " conditions=", selected.are_conditions_met(state))
		quit(1)
		return
	await scene_changed
	game = current_scene as MainGame
	while game.get_scene_travel().is_busy():
		await process_frame
	await ticks()

func finish_event(id: String) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while not state.is_event_completed(id) and Time.get_ticks_msec() < deadline:
		var dialogue := game.get_dialogue_manager()
		if dialogue.is_active():
			dialogue.advance()
			dialogue.select_choice(0)
		await process_frame
	check(state.is_event_completed(id), "Complete event: " + id)
	await ticks()

func press_e() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = &"interact"
		event.pressed = pressed
		Input.parse_input_event(event)
		await ticks(2)

func _run() -> void:
	Engine.time_scale = 6.0
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/drunken_guard_%d" % OS.get_process_id())
	state = root.get_node("GameState")
	state.reset_state()
	state.select_business_profile("day1")
	state.set_story_stage("day1.s03.explore")
	await load_host("res://src/core/settlement.tscn")
	check(not guard().is_visible_in_tree(), "Guard stays absent before the first-day mission")
	state.set_flag("day1.s04.commission_accepted")
	state.set_story_stage("day1.s05.ready")
	await ticks()
	check_guard_visible("First-day negotiation")
	state.set_flag("day1.s05.drunken_paid")
	game.get_chapter_controller().apply_scene_setup()
	await ticks()
	check(not guard().is_visible_in_tree(), "First-day paid guard keeps his authored departure")
	check(not game.get_quest_pointer().is_actor_name_visible(), "Departed guard has no identity marker")
	var target := game.get_quest_pointer().get_target()
	check(target.get("source") == "anchor", "First-day guidance advances to the mansion pair")
	game.queue_free()
	await process_frame
	state.reset_state()
	state.select_business_profile("day1")
	check(DayPhase.advance_to(state, 1, "night") == OK and DayPhase.advance_to(state, 2, "day") == OK, "Enter the second day through legal phase transitions")
	# This fixture starts after the casino: prior main quests are already done.
	for path: String in ["day1_stages_01_02", "day1_stages_03_06", "day2_stages_01_05"]:
		var tasks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/resources/tasks/%s.json" % path))
		for task: Dictionary in tasks.tasks:
			if task.type == "main" and task.id != "day2.main.guard" and task.complete_when.type == "flag":
				state.set_flag(task.complete_when.key)
	for flag: String in ["day1.stages_01_02_completed", "day1.s04.commission_accepted", "day1.s04.map_received", "day1.s05.drunken_paid", "day2.s04.casino_reward_received", "day2.travel.casino_exited", "day2.travel.shop_returned", "day2.s05.special_recipe_available"]:
		state.set_flag(flag)
	state.set_story_stage("day2.s05.return_shop")
	var inventory: WarehouseInventory = state.get_warehouse_inventory()
	inventory.add_ingredient("griffin_amber_wine", 1)
	inventory.add_ingredient("phantom_gold_mushroom", 1)
	await load_host(GameEntry.GAME_SCENE)
	await finish_event("day2.s05.special_before")
	var result := game.get_tea_production().craft_free(["creamer_milk_tea_base", "griffin_amber_wine", "phantom_gold_mushroom"])
	check(result.ok, "Actually craft the guard's special")
	await finish_event("day2.s05.special_after")
	await travel(&"shop_exit")
	check(DayPhase.get_phase(state) == "day", "Delivery does not artificially force nighttime")
	check_guard_visible("After leaving the shop in daylight")
	await travel(&"shop_enter")
	await travel(&"shop_exit")
	check_guard_visible("After a real round trip")
	var store := GameEntry.create_save_store()
	var checkpoint := store.checkpoints.find_checkpoint(state.to_dict(), "res://src/core/settlement.tscn")
	check(not checkpoint.is_empty() and checkpoint.phase == "day", "Daylight delivery has a recoverable checkpoint")
	if checkpoint.is_empty():
		quit(1)
		return
	check(store.save(state.to_dict(), checkpoint.id) == OK, "Write an actual daylight save")
	check(GameEntry.continue_game(self) == OK, "Continue from the actual saved document")
	await scene_changed
	game = current_scene as MainGame
	await ticks(30)
	inventory = state.get_warehouse_inventory()
	check_guard_visible("After file save and continue")
	var player := game.get_player()
	var goal := guard().global_position + Vector2(-30, 0)
	var route: PackedVector2Array = game.get_active_level().get_navigation_path(player.global_position, goal)
	check(not route.is_empty(), "Saved floor passages connect the shop entrance to the guard")
	if route.is_empty():
		for offset: Vector2 in [Vector2.LEFT * 30, Vector2.RIGHT * 30, Vector2.UP * 30]:
			print("GUARD_ROUTE ", player.global_position, " -> ", guard().global_position + offset, " count=", game.get_active_level().get_navigation_path(player.global_position, guard().global_position + offset).size())
	for waypoint: Vector2 in route:
		var action := game.get_actor_director().actor_move(&"player", waypoint, 500.0, 2.0)
		await action.wait()
		if not action.succeeded:
			check(false, "The player walks the route without wall or NPC blockage")
			quit(1)
			return
	var approach := game.get_actor_director().actor_move(&"player", goal, 100.0, 2.0)
	await approach.wait()
	check(approach.succeeded, "Walk into real interaction range")
	await ticks()
	var point := game.get_delivery_point(&"drunken_guard")
	check(point.is_available() and game.get_shop_interaction().get_target() == point, "Real collision range and selector find the guard")
	check(game.get_quest_pointer().is_actor_name_visible(), "Visible quest identity remains readable at interaction distance")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.godot/drunken_guard")
		check(root.get_texture().get_image().save_png("res://.godot/drunken_guard/identity.png") == OK, "Capture real guard name and E prompt")
	await press_e()
	await finish_event("day2.s05.guard_greet")
	check_guard_visible("While waiting for the cup")
	var before: int = inventory.get_stock("day2_guard_milk_tea")
	var balance: int = state.get_transactions().get_balance()
	await press_e()
	await finish_event("day2.s05.guard_after")
	check(inventory.get_stock("day2_guard_milk_tea") == before - 1, "Real E delivery consumes exactly one special")
	check(state.get_transactions().get_balance() == balance, "Guard hospitality does not change the wallet")
	check(not game.get_task_delivery().try_submit("day2_guard_special", "drunken_guard").ok, "Repeated submission cannot consume a second cup")
	check(not game.get_quest_pointer().is_actor_name_visible(), "Identity label retires once the guard objective ends")
	var shop_door: SceneExit
	for exit: SceneExit in game.get_active_level().get_scene_exits():
		if exit.interaction_id == &"shop_enter":
			shop_door = exit
	check(shop_door != null and game.get_quest_pointer().get_target().get("position") == shop_door.global_position, "After delivery, guidance points back to the shop")
	game.queue_free()
	await process_frame
	print("DRUNKEN_GUARD: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
