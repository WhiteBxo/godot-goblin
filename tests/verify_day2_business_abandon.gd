extends SceneTree
## Day 2 business: giving up an accepted optional slip must not break the authored
## departure step. The festival group waits while a special slip is open, so the
## player's only way out is 放弃此单; that release used to move the group to
## "leaving" before day2.s02.festival_after ran, the step then failed, and the day
## stopped with no next customer group.

var state: Node
var game: MainGame
var checks := 0
var failures: Array[String] = []
var failed_events: Array[String] = []

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

func wait_event(id: String, ms := 20000) -> bool:
	var deadline := Time.get_ticks_msec() + ms
	while not state.is_event_completed(id) and Time.get_ticks_msec() < deadline and failed_events.is_empty():
		var dialogue := game.get_dialogue_manager()
		if dialogue.is_active():
			dialogue.advance()
			dialogue.select_choice(0)
		await process_frame
	await frames()
	return state.is_event_completed(id)

func _run() -> void:
	Engine.time_scale = 6.0
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/day2_abandon_%d" % OS.get_process_id())
	state = root.get_node("GameState")
	state.start_new_game()
	state.select_business_profile("day1")
	state.current_day = 2
	state.set_story_stage("day2.s02.open")
	state.set_flag("day2.s02.open")
	state.set_flag("day1.s06.completed")
	change_scene_to_file("res://src/core/main.tscn")
	await scene_changed
	await frames(10)
	game = current_scene as MainGame
	check(game != null, "Day 2 shop host loads")
	if game == null:
		print("DAY2_ABANDON: %d checks, %d failures" % [checks, failures.size()])
		quit(1)
		return
	game.get_story_director().event_finished.connect(func(id: String, ok: bool, reason: String) -> void:
		if not ok:
			failed_events.append(id + ": " + reason))
	var chapter := game.get_chapter_gameplay()
	var scheduler := chapter.get_scheduler()
	var delivery := game.get_task_delivery()
	check(scheduler != null, "Day 2 business session is configured")
	if scheduler == null:
		print("DAY2_ABANDON: %d checks, %d failures" % [checks, failures.size()])
		quit(1)
		return
	check(await wait_event("day2.s02.business_open"), "Opening publishes the festival group")
	check(await wait_event("day2.s02.festival_order"), "The first customer orders at the counter")
	# A visitor's special slip and the planned drink share one group.
	var optional := "day2_special_sour"
	var planned := "day2_s02_festival_0"
	check(delivery.accept_order(optional) == OK, "The player accepts the visitor's special slip: " + optional)
	check(delivery.accept_order(planned) == OK, "The player accepts the planned order: " + planned)
	var production := game.get_tea_production()
	var recipe := production.get_recipe_by_product("classic_boba_milk_tea")
	check(recipe != null and production.craft(recipe.materials).ok, "The planned cup is made")
	check(delivery.try_submit(planned, "day2_festival_0").ok, "The planned drink is handed over")
	await frames(20)
	check(scheduler.is_group_served("festival") == false, "An open special slip still holds the group at the counter")
	check(not state.get_flag("day2.business.festival.served"), "Served fact waits for the special slip to settle")
	check("特殊订单待交付" in chapter.get_slip_notice(), "The menu notice names the hold instead of looking stuck")
	# The board's 放弃此单 is the only way out of that hold.
	check(chapter.cancel_optional_order(optional) == OK, "The player gives up the special slip from the board")
	await frames(30)
	check(scheduler.get_group("festival").status == "waiting", "The abandoned group stays for its own departure beat")
	check(state.get_flag("day2.business.festival.served"), "Giving up the slip releases the served fact")
	check(await wait_event("day2.s02.festival_after"), "The story beat still completes after the slip is abandoned")
	check(state.story_stage == "day2.s02.elder.arriving", "The next customer group's stage is reached")
	check(scheduler.get_group("festival").status in ["leaving", "departed"], "The authored beat is what walks the group out")
	check(scheduler.request_departure("festival") == OK, "Asking an already leaving group again is a replay")
	# The other way out of the same hold: the player finishes the special slip.
	# This save never played Day 1, so the chronicle entry its beat appends to
	# must exist first; the abandon case above does not need it.
	check(game.get_chronicle_journal().unlock_entry("chronicle.griffin", "伟大的格里芬") == OK,
		"Day 1 chronicle entry is available to the later beats")
	var inventory: WarehouseInventory = state.get_warehouse_inventory()
	inventory.add_ingredient("creamer_milk_tea_base", 2)
	inventory.add_ingredient("insomnia_mushroom", 2)
	check(await wait_event("day2.s02.elder_order"), "The second customer group orders")
	var elder_optional := "day2_special_herbal"
	var elder_planned := "day2_s02_elder_0"
	check(delivery.accept_order(elder_optional) == OK, "The player accepts the second group's special slip")
	check(delivery.accept_order(elder_planned) == OK, "The player accepts the second planned order")
	var elder_recipe := production.get_recipe_by_product("mint_choc_milk_tea")
	check(elder_recipe != null and production.craft(elder_recipe.materials).ok, "The second planned cup is made")
	check(delivery.try_submit(elder_planned, "day2_elder_0").ok, "The second planned drink is handed over")
	await frames(20)
	check(not state.get_flag("day2.business.elder.served"), "The second group also waits on its special slip")
	var materials: Array[String] = ["creamer_milk_tea_base", "insomnia_mushroom"]
	check(state.confirm_formula(materials, "day2_abandon.herbal").get("ok", false), "The herbal cup is priced")
	var mixed: Dictionary = production.craft_formula(materials, 1, "day2_abandon.herbal.craft")
	check(mixed.get("ok", false), "The herbal cup is mixed")
	if mixed.get("ok", false):
		check(delivery.try_submit(elder_optional, "day2_elder_1", str(mixed.id)).ok, "The special slip is handed over")
	await frames(30)
	check(scheduler.get_group("elder").status == "waiting", "A finished slip still leaves the departure to the story beat")
	check(state.get_flag("day2.business.elder.served"), "Finishing the slip releases the served fact")
	check(await wait_event("day2.s02.elder_after"), "The second beat completes when the slip is finished")
	check(state.story_stage == "day2.s02.emissary.arriving", "The third customer group's stage is reached")
	check(failed_events.is_empty(), "No story event failed: " + str(failed_events))
	print("DAY2_ABANDON: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
