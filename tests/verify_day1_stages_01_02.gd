extends SceneTree

const StateData = preload("res://src/core/game_state.gd")
const MANIFEST := "res://docs/story_authoring/day1_stages_01_02_bridge.json"
var _checks := 0
var _failures: Array[String] = []
var _game: MainGame
var _state: StateData
var _lines := {}
var _authored_line_count := 0
var _events_failed: Array[String] = []
var _capture := false
var _expected_cancellation := false
var _waiting_snapshots: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func frames(count: int = 3) -> void:
	for index in range(count):
		await process_frame

func _record_line(_line: String) -> void:
	var manager := _game.get_dialogue_manager()
	_lines[manager.get("_dialogue_id") + "/" + manager.get_current_line_id()] = true

func _wait_event(id: String) -> void:
	var deadline := Time.get_ticks_msec() + 35000
	while not _state.is_event_completed(id) and Time.get_ticks_msec() < deadline and _events_failed.is_empty():
		var manager := _game.get_dialogue_manager()
		if manager.is_active():
			_record_line("")
			manager.advance()
		await process_frame
	check(_state.is_event_completed(id), "Real StoryDirector completes " + id)
	if not _state.is_event_completed(id):
		print("DAY1_ABORT ", _events_failed, " stage=", _state.story_stage)
		quit(1)
		return
	await frames()

func _press_e() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	Input.parse_input_event(event)
	await frames()
	event = InputEventAction.new()
	event.action = "interact"
	event.pressed = false
	Input.parse_input_event(event)
	await frames()

func _point(id: String) -> InteractionPoint:
	for point: InteractionPoint in _game.get_active_level().get_interaction_points():
		if String(point.interaction_id) == id:
			return point
	return _game.get("_npc_points").get(StringName(id))

func _interact(id: String) -> void:
	var point := _point(id)
	# Some customers stand next to the counter or the order board, so the nearest
	# target is not always the intended one. Try a few approach sides and keep the
	# first that really resolves to this point.
	var target_ok := false
	for offset: Vector2 in [Vector2(0, -40), Vector2(0, -56), Vector2(0, 40), Vector2(-40, 0), Vector2(40, 0), Vector2(0, -80)]:
		_game.get_player().teleport_to(point.global_position + offset)
		for index in range(4):
			await physics_frame
		await frames(2)
		# A teleport skips the walk-away that normally drops the old target, and the
		# sticky switch margin would otherwise keep the previous station selected.
		_game.get("_shop_interaction").call("_set_target", null)
		_game.get("_shop_interaction").refresh_target()
		if _game.get("_shop_interaction").get_target() == point:
			target_ok = true
			break
	check(target_ok, "Actual reach and focus select " + id)
	if _game.get("_shop_interaction").get_target() != point:
		print("INTERACT_DIAG ", id, " player=", _game.get_player().global_position, " point=", point.global_position, " visible=", point.is_visible_in_tree(), " bodies=", point.get("_bodies"), " overlap=", point.get_overlapping_bodies(), " layer=", _game.get_player().collision_layer, " available=", point.is_available(), " movement=", _game.get_player().movement_enabled, " input=", _game.get("_shop_interaction").is_input_enabled(), " modal=", _game.get_ui_manager().has_modal(), " target=", _game.get("_shop_interaction").get_target())
		quit(1)
	await _press_e()
	if _game.get_delivery_point(id) != null:
		check(not _game.get_shop_ui().is_open(), "E at customer uses nonmodal delivery feedback: " + id)
	else:
		check(_game.get_shop_ui().is_open(), "E opens business UI at " + id)

func _attach_observers() -> void:
	# The same dialogue/story services survive a scene reload, so reconnect only
	# when the callable is not already attached.
	var dialogue := _game.get_dialogue_manager()
	if not dialogue.line_changed.is_connected(_record_line):
		dialogue.line_changed.connect(_record_line)
	var director := _game.get_story_director()
	if not director.event_finished.is_connected(_event_finished):
		director.event_finished.connect(_event_finished)

func _event_finished(id: String, ok: bool, reason: String) -> void:
	if not ok and reason != "Resume checkpoint" and not reason.contains("GameState") and not (_expected_cancellation and reason.ends_with("Player cancellation")):
		_events_failed.append(id + ": " + reason)

func _await_scene(previous: Node, context: String, seconds: float = 10.0) -> bool:
	# scene_changed never fires when the reload or travel is rejected, so bound it;
	# an unbounded await would leave the whole regression hanging.
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while (current_scene == previous or not current_scene is MainGame) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not current_scene is MainGame:
		var landed := "nothing" if current_scene == null else str(current_scene.scene_file_path)
		check(false, context + ": landed on " + landed + " instead of MainGame")
		quit(1)
		return false
	return true

func _reload(snapshot: Dictionary) -> void:
	var previous := current_scene
	check(reload_current_scene() == OK, "Real scene reload starts")
	if not await _await_scene(previous, "Real scene reload"):
		return
	_game = current_scene as MainGame
	_attach_observers()
	await frames(8)
	check(_state.to_dict() == snapshot, "Scene reload preserves exact story and economy results")
	var director := _game.get_story_director()
	check(not director.is_busy() and _game.get_player().movement_enabled and not _game.get_ui_manager().has_modal(), "Scene reload restores an idle gameplay boundary and input")
	check(_game.get_day1_controller().last_error.is_empty(), "Recreated host reloads Bridge successfully")

func _snapshot(name: String) -> void:
	if not _capture or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/day1_" + name + ".png")

func _accept() -> void:
	await _interact("orders")
	var page := _game.get_shop_ui().get_popup().get_page().get_order_board_page()
	for entry: Dictionary in _game.get_order_board().get_entries():
		if entry.status == "available":
			page.select_order(entry.order_id)
			page.get_ticket().get_primary_button().pressed.emit()
	await _snapshot("orders")
	_game.get_shop_ui().close()
	await frames()

func _make() -> void:
	var production := _game.get_tea_production()
	var order := production.get_order()
	check(not order.is_empty(), "An accepted order is available")
	if order.is_empty():
		return
	await _interact("tea_station")
	_game.get_shop_ui().get_popup().get_page().select_crafting_mode(true)
	var panel: CraftingPanel = _game.get_shop_ui().get_popup().get_crafting_panel()
	var before := _state.to_dict()
	panel.clear_selection()
	panel.submit()
	check(_state.to_dict() == before, "Incomplete recipe changes no participant")
	if production.get_completed_count() == 0:
		_game.get_shop_ui().close()
		await frames()
		check(_state.to_dict() == before, "Closing an unfinished production screen never completes an order")
		await _interact("tea_station")
		panel = _game.get_shop_ui().get_popup().get_crafting_panel()
	panel.clear_selection()
	for id: String in order.recipe:
		panel.add_material(id)
	if production.get_completed_count() == 0:
		# Starve one material the order actually asks for; the day-1 recipes changed
		# and syrup is no longer part of them.
		var ingredient: String = order.recipe[0]
		var stock := production.get_stock(ingredient)
		_game.get_warehouse_inventory().try_consume({ingredient: stock})
		before = _state.to_dict()
		panel.submit()
		check(_state.to_dict() == before, "Correct recipe with missing ingredients changes no participant")
		_game.get_warehouse_inventory().add_ingredient(ingredient, stock)
	var audio := _game.get_audio_manager()
	# The mixer drops optional sounds once every pool voice is busy. Simulated time
	# runs many actions per wall-clock second, so drain a slot before measuring;
	# otherwise this check reports pool pressure instead of the craft contract.
	for _wait in range(240):
		if audio.get_active_sound_count() < audio.pool_size:
			break
		await process_frame
	var sound_handle: int = audio.get("_next_handle")
	var notices: Array[bool] = []
	var observe := func() -> void: notices.append(_state.get_variable("shop.drinks_made") == production.get_completed_count())
	_state.state_changed.connect(observe)
	panel.submit()
	_state.state_changed.disconnect(observe)
	check(not notices.is_empty() and not notices.has(false), "Craft notification snapshots contain production and task progress together")
	check(audio.get("_next_handle") == sound_handle + 1, "Each successful production triggers exactly one pour sound")
	check(production.get_stock(order.product_id) > 0, "Real production button creates " + order.product_id)
	check(_state.get_variable("shop.drinks_made") == production.get_completed_count(), "Task crafting objective follows actual successful production")
	before = _state.to_dict()
	var recipe: Array[String] = []
	recipe.assign(order.recipe)
	check(not production.make_drink(recipe, order.id).ok and _state.to_dict() == before, "Submitting the displayed order twice never consumes more ingredients")
	check(_game.get_audio_manager().get_bgm_state().id == "music.daily_milk_tea", "Scene music persists throughout production")
	await _snapshot("production")
	_game.get_shop_ui().close()
	await frames()

func _deliver(id: String) -> void:
	await _interact(id)
	check(not _game.get_shop_ui().is_open() and not _game.get_shop_ui().get_feedback_text().is_empty(), "Settlement reports its real result without a modal")
	await _snapshot("delivery")

func _restore(snapshot: Dictionary) -> void:
	_state.set_flag("test.force_restore")
	check(_state.restore_state(snapshot) == OK, "Complete snapshot restores")
	await frames(5)
	check(_state.get_transactions().get_balance() == snapshot.economy.balance, "Restore does not repay income")
	check(_state.get_warehouse_inventory().to_dict() == snapshot.business.inventory, "Restore retains exact inventory")
	check(_game.get_day1_controller().last_error.is_empty(), "Restored host and bridge load successfully")

func _validate_authoring() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var source := FileAccess.get_file_as_string(manifest.source)
	var structured: bool = manifest.has("authoring_project")
	if structured:
		var project := StoryProject.new()
		check(project.open_project(manifest.authoring_project) == OK, "Structured authoring project loads")
		check(FileAccess.get_sha256(manifest.authoring_project) == manifest.authoring_sha256, "Project hash matches generated products")
		var products := project.compile()
		check(not products.is_empty(), "Structured project validates with original loaders")
		if not products.is_empty():
			check(JSON.parse_string(FileAccess.get_file_as_string(manifest.story)) == JSON.parse_string(JSON.stringify(products.story)), "Story matches canonical project")
			check(JSON.parse_string(FileAccess.get_file_as_string(manifest.dialogue)) == JSON.parse_string(JSON.stringify(products.dialogue)), "Dialogue matches canonical project")
	else:
		check(source.sha256_text() == manifest.source_sha256, "Source hash matches authoring products")
	var story := StoryLibrary.new()
	var dialogue := DialogueLibrary.new()
	check(story.load_file(manifest.story) == OK, "Original Story v1 loader accepts all events")
	check(dialogue.load_file(manifest.dialogue) == OK, "Original Dialogue v1 loader accepts all lines")
	var expected_lines := 0
	for id: String in dialogue.get("_dialogues"):
		for line: Dictionary in dialogue.get_dialogue(id).lines.values():
			expected_lines += 1
			if not structured:
				check(('「' + line.text + '」') in source, "Every displayed sentence is verbatim from source")
	check(expected_lines > 0 if structured else expected_lines == 21, "Authored dialogue lines are included")
	_authored_line_count = expected_lines
	if not structured:
		check(dialogue.get_dialogue("day1.coins_raise_suspicion").lines.line_2.portrait == "res://assets/characters/apron_man/player_bad_laugh.png", "Authored ending expression uses the supplied portrait")
	for id: String in manifest.actors:
		check(ResourceLoader.exists(manifest.actors[id]), "Bound actor scene exists: " + id)
	check(not manifest.beats.is_empty() if structured else manifest.beats.size() == 12, "Beats have execution mappings")
	for beat: Dictionary in manifest.beats:
		if not structured:
			check(source.contains("### Beat " + beat.id), "Mapped Beat exists: " + beat.id)
		if beat.has("event"):
			var steps: Array = story.get_event(beat.event).steps
			check(beat.start >= 0 and beat.count >= 0 and beat.start + beat.count <= steps.size(), "Beat owns an actual step range")

func _test_settlement_failures() -> void:
	var state := StateData.new()
	var inventory := state.get_warehouse_inventory()
	var wallet := state.get_transactions()
	var costs := {"pearl_milk_tea": 1}
	var facts := {"test.settled": true}
	var before := state.to_dict()
	check(state.commit_delivery(costs, {}, 10, facts, 1, "test_payment") != OK and state.to_dict() == before, "Missing product cannot pay or write facts")
	inventory.add_ingredient("pearl_milk_tea", 1)
	wallet.add_money(WarehouseInventory.MAX_QUANTITY, "fill_wallet")
	before = state.to_dict()
	check(state.commit_delivery(costs, {}, 10, facts, 1, "test_payment") != OK and state.to_dict() == before, "Wallet overflow rejects entire delivery")
	wallet.spend_money(WarehouseInventory.MAX_QUANTITY, "empty_wallet")
	inventory.add_ingredient("strange_coin", WarehouseInventory.MAX_QUANTITY)
	before = state.to_dict()
	check(state.commit_delivery(costs, {"strange_coin": 1}, 0, facts, 1, "test_payment") != OK and state.to_dict() == before, "Coin capacity failure leaves product and facts intact")
	inventory.try_consume({"strange_coin": WarehouseInventory.MAX_QUANTITY})
	before = state.to_dict()
	inventory.set_session_locked(true)
	check(state.commit_delivery(costs, {}, 10, facts, 1, "test_payment") != OK and state.to_dict() == before, "Silent inventory commit failure leaves all participants intact")
	inventory.set_session_locked(false)
	var notices: Array[bool] = []
	var observer := func() -> void:
		notices.append(state.get_flag("test.settled") and wallet.get_balance() == 10 and inventory.get_stock("pearl_milk_tea") == 0 and state.start_new_game() == ERR_BUSY)
	state.state_changed.connect(observer)
	check(state.commit_delivery(costs, {}, 10, facts, 1, "test_payment") == OK, "Valid settlement succeeds after failed attempts")
	check(notices == [true], "Only successful complete settlement notifies once")
	before = state.to_dict()
	check(state.commit_delivery(costs, {}, 10, facts, 1, "test_payment") != OK and state.to_dict() == before, "Stable payment ID cannot be replayed")
	state.free()

## Arriving after Day 1 legitimately starts the next story beat (S03). Wait it out
## and advance dialogue the way a player would instead of asserting into a locked
## host; the check afterwards is that control does come back.
func _settle_story(timeout_ms: int = 20000) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while (_game.get_story_director().is_busy() or not _game.get_player().movement_enabled) and Time.get_ticks_msec() < deadline:
		var manager := _game.get_dialogue_manager()
		if manager.is_active():
			manager.advance()
		await process_frame

func _travel_completed_run(snapshot: Dictionary) -> void:
	var inventory := _game.get_warehouse_inventory()
	var production := _game.get_tea_production()
	# The day-ending beat hands straight into the next story step, and the door
	# refuses travel while the director owns the frame. Wait it out the way a
	# player would instead of asserting into a locked host.
	await _settle_story()
	# Compare against the state the door is actually left in, after the follow-up
	# beat has settled; the caller's snapshot predates that beat.
	snapshot = _state.to_dict()
	for path: String in ["res://src/core/settlement.tscn", "res://src/core/main.tscn"]:
		var exit: SceneExit = _game.get_active_level().get_scene_exits()[0]
		var previous := current_scene
		check(_game.get_scene_travel().request_exit(exit) == OK, "Completed Day 1 can travel to " + path)
		if not await _await_scene(previous, "Day 1 travel to " + path):
			return
		_game = current_scene as MainGame
		var deadline := Time.get_ticks_msec() + 5000
		while _game.get_scene_travel().is_busy() and Time.get_ticks_msec() < deadline:
			await process_frame
		await frames()
		check(_game.scene_file_path == path and not _game.get_scene_travel().is_busy(), "Day 1 door transition finishes")
		var arrived: Dictionary = _state.to_dict()
		# Using the door records the arrival fact and nothing else; compare the rest
		# with that one flag removed instead of rejecting the fact travel creates.
		check(bool(arrived.get("flags", {}).get("day1.s03.exited_shop", false)), "Door travel records the shop exit")
		var comparable: Dictionary = arrived.duplicate(true)
		(comparable["flags"] as Dictionary).erase("day1.s03.exited_shop")
		var expected_state: Dictionary = snapshot.duplicate(true)
		(expected_state["flags"] as Dictionary).erase("day1.s03.exited_shop")
		check(comparable == expected_state, "Door travel preserves Day 1 profile, income, coins, receipts and story")
		check(_game.get_warehouse_inventory() == inventory and _game.get_tea_production() == production, "Day 1 travel retains service identities")
		await _settle_story()
		check(_game.get_player().movement_enabled and not _game.get_story_director().is_busy() and not _game.get_ui_manager().has_modal(), "Arrival releases travel input without replaying story")
	var entrance: SceneEntrance = _game.get_active_level().get_scene_entrance(&"street_door")
	check(_game.get_player().global_position.is_equal_approx(entrance.global_position), "Day 1 checkpoint projection preserves the named door landing")
	check(_game.get_player().facing == entrance.facing, "Day 1 arrival preserves entrance facing")
	_attach_observers()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_capture = "--capture" in OS.get_cmdline_user_args()
	Engine.time_scale = 4.0
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	_state = root.get_node("GameState")
	_validate_authoring()
	_test_settlement_failures()
	_game = load("res://src/core/main.tscn").instantiate()
	root.add_child(_game)
	current_scene = _game
	_attach_observers()
	await frames()
	check(_state.get_business_profile() == "day1", "Official host selects the formal profile")
	check(not _game.get_tea_production().make_drink(["black_tea", "creamer", "pearl", "syrup"], "day1_human").ok, "Cannot craft ahead of acceptance")
	await _wait_event("day1.opening")
	check(_state.story_stage == "day1.wait_human" and _game.get_player().movement_enabled, "First gameplay handoff releases input")
	# Ask once the opening event has handed control back: while it plays the host
	# answers ERR_BUSY, which says nothing about whether the review is locked.
	check(_game.open_chronicle() == ERR_UNAVAILABLE and _game.get_node("PopupLayer/HandbookPanel").get_pages().is_tab_hidden(1), "Chronicle is inaccessible before unlock")
	check(_game.open_tasks() == OK, "First order gameplay phase allows read-only handbook review")
	_game.get_ui_manager().close_screen(&"handbook")
	check(_game.get_audio_manager().get_bgm_state().id == "music.daily_milk_tea", "Opening starts registered scene music")
	check(_game.get_scene_travel().request_exit(_game.get_active_level().get_scene_exits()[0]) == ERR_BUSY, "Active gameplay phase retains its scene-travel guard")
	_waiting_snapshots.append(_state.to_dict())
	var counter: Node2D = _game.get_active_level().get_node("EquipmentForeground/Counter")
	var human := _game.get_actor_director().get_actor(&"human_customer")
	check(_game.get_player().z_index < counter.z_index and human.z_index > counter.z_index, "Formal customer draws in front of counter while player stands behind")
	await _snapshot("human_wait")
	await _restore(_state.to_dict())
	await _reload(_state.to_dict())
	await _accept()
	await _make()
	var before := _state.to_dict()
	check(not _game.get_task_delivery().try_submit("day1_human", "goblin_customer").ok and _state.to_dict() == before, "Wrong recipient cannot consume or settle")
	await _restore(before)
	# Pay and product come from the task data: the day-1 menu was rebalanced to
	# 经典珍珠奶茶 at 3G, so a pinned 10 no longer describes this order.
	var human_task: Dictionary = _game.get_task_delivery().get("_orders")["day1_human"]
	var human_reward := int(human_task.get("rewards", {}).get("money", 0))
	var human_product := str(human_task.get("delivery", {}).get("product_id", ""))
	var observations: Array[bool] = []
	var observe := func() -> void:
		if observations.is_empty() and _state.get_flag("day1.human_settled"):
			observations.append(_state.get_transactions().get_balance() == human_reward and _state.get_warehouse_inventory().get_stock(human_product) == 0 and _state.start_new_game() == ERR_BUSY and not _state.set_flag("test.reentry"))
	_state.state_changed.connect(observe)
	await _deliver("human_customer")
	_state.state_changed.disconnect(observe)
	check(observations == [true], "Synchronous settlement observers see complete results and cannot reset or overwrite")
	check(human_reward > 0 and _state.get_transactions().get_balance() == human_reward, "Human first order really pays " + str(human_reward))
	check(not _game.get_ui_manager().is_open(ScreenIds.SHOP), "Delivery feedback adds no modal that delays continuation")
	before = _state.to_dict()
	check(not _game.get_task_delivery().try_submit("day1_human", "human_customer").ok and _state.to_dict() == before, "Repeated delivery cannot pay twice")
	_game.get_shop_ui().close()
	_game.get_ui_manager().set_paused(true)
	await frames(8)
	check(not _state.is_event_completed("day1.first_goblin"), "Paused tree prevents continuation from completing")
	_game.get_ui_manager().set_paused(false)
	await _wait_event("day1.first_goblin")
	_waiting_snapshots.append(_state.to_dict())
	await _restore(_state.to_dict())
	await _reload(_state.to_dict())
	await _accept()
	await _make()
	var balance_before_goblin := _state.get_transactions().get_balance()
	await _deliver("goblin_customer")
	var goblin_task: Dictionary = _game.get_task_delivery().get("_orders")["day1_goblin"]
	var goblin_reward := int(goblin_task.get("rewards", {}).get("money", 0))
	check(goblin_reward > 0 and _state.get_transactions().get_balance() == balance_before_goblin + goblin_reward, "First goblin pays the authored reward")
	_game.get_shop_ui().close()
	await _wait_event("day1.group_arrival")
	_waiting_snapshots.append(_state.to_dict())
	var group_counter: Node2D = _game.get_active_level().get_node("EquipmentForeground/Counter")
	for id: StringName in [&"goblin_a", &"goblin_b", &"goblin_c"]:
		check(_game.get_actor_director().get_actor(id).z_index > group_counter.z_index, "Group customer is fully visible in front of counter: " + id)
	await _snapshot("group_wait")
	await _restore(_state.to_dict())
	await _reload(_state.to_dict())
	check(_game.get_chronicle_journal().get_entries().size() == 2, "Chronicle opens only the entries the group actually names")
	for entry in _game.get_chronicle_journal().get_entries():
		# 血 is only named by 胖哥布林 in S04, so no entry may open as an empty page.
		check(not entry.records.is_empty(), "Every unlocked lore entry already reads as something")
	check(_game.open_chronicle() == OK, "Unlocked chronicle uses real UI")
	await _snapshot("chronicle")
	_game.get_ui_manager().close_screen(&"chronicle")
	await _accept()
	# The group hands over one order per goblin, and every hand-off is its own story
	# beat: goblin_a, then goblin_c (customer_c), goblin_d (customer_d) and goblin_e
	# (customer_e). The next customer only steps up once the previous one settles.
	var group_sequence: Array[Dictionary] = [
		{"id": "goblin_a", "next_event": "day1.customer_c"},
		{"id": "goblin_c", "next_event": "day1.customer_d"},
		{"id": "goblin_d", "next_event": "day1.customer_e"},
		{"id": "goblin_e", "next_event": ""},
	]
	for index in range(group_sequence.size()):
		var step: Dictionary = group_sequence[index]
		if index > 0:
			await _wait_event(str(group_sequence[index - 1].next_event))
			await _accept()
		await _make()
		await _deliver(str(step.id))
		if index < group_sequence.size() - 1:
			check(not _state.get_flag("day1.group_settled"), "Partial batch never advances story")
		_game.get_shop_ui().close()
		if index == 0:
			# Let the hand-off beat finish first: reloading mid-event tears the story
			# director down and aborts the beat we are about to assert on.
			await _wait_event("day1.customer_c")
			await _restore(_state.to_dict())
			await _reload(_state.to_dict())
	await _wait_event("day1.ending")
	check(_lines.size() == _authored_line_count and _events_failed.is_empty(), "All authored dialogue lines execute without actor or audio failure")
	# Six authored orders today: human, goblin, then group_a/c/d/e one after another.
	check(_state.get_variable("shop.orders_completed") == 6 and _game.get_tea_production().get_completed_count() == 6, "Six crafted and independently settled orders")
	# Income comes from the task rewards instead of a pinned total.
	var expected_income := 0
	for order_id: String in ["day1_human", "day1_goblin", "day1_group_a", "day1_group_c", "day1_group_d", "day1_group_e"]:
		expected_income += int(_game.get_task_delivery().get("_orders")[order_id].get("rewards", {}).get("money", 0))
	check(expected_income > 0 and _game.get_transactions().get_balance() == expected_income
		and _game.get_warehouse_inventory().get_stock("strange_coin") == 0, "Final totals are income " + str(expected_income) + " and no loose coins")
	check(_game.get_wallet_hud().get_balance_text() == str(expected_income) + "G" and _game.get_business_hud().get_node("BusinessBalance").visible == false, "Wallet chip owns the balance and the business line stays quiet without a change")
	check(_state.current_day == 1 and _state.story_stage == "day1.investigate_coins", "Stops at same-day investigation intent")
	check(_game.get_chronicle_journal().get_unread_count() == 2, "Opening the list does not falsely mark entries read")
	var final := _state.to_dict()
	await _restore(final)
	check(_state.to_dict() == final, "Completed snapshot restoration has no business or story side effects")
	await _snapshot("finished")
	await _reload(final)
	await _travel_completed_run(final)
	for snapshot: Dictionary in _waiting_snapshots:
		await _restore(snapshot)
		check(_state.story_stage == snapshot.story_stage and not _game.get_story_director().is_busy(), "Every gameplay checkpoint restores idle and operable")
	await _restore(final)
	var legacy := StateData.new()
	var v2 := legacy.to_dict()
	v2.schema_version = 2
	v2.business.erase("profile_id")
	v2.business.inventory.ingredients.erase("strange_coin")
	v2.economy.inventory.ingredients.erase("strange_coin")
	check(legacy.restore_state(v2) == OK and legacy.get_business_profile() == "tutorial", "Old complete v2 snapshots migrate to tutorial without inventing coins")
	legacy.free()
	var services: Array[Node] = [_game.get_tea_production(), _game.get_transactions(), _game.get_warehouse_inventory()]
	check(_state.select_business_profile("tutorial") == ERR_ALREADY_IN_USE, "Live Day 1 progress cannot silently switch profiles")
	check(_state.start_new_game() == OK, "Explicit new game resets the formal session")
	await frames(6)
	check(_state.get_business_profile() == "day1" and _game.get_transactions().get_balance() == 0 and _game.get_warehouse_inventory().get_stock("strange_coin") == 0, "New game keeps selected profile and clears payouts")
	check(services == [_game.get_tea_production(), _game.get_transactions(), _game.get_warehouse_inventory()], "New game preserves live service objects and UI subscriptions")
	_expected_cancellation = true
	_game.get_story_director().cancel_event("Player cancellation")
	await frames()
	_expected_cancellation = false
	check(_game.get_node("HudLayer/Day1BusinessHUD/ResumeStory").visible, "Cancelled presentation offers explicit recovery")
	_game.get_node("HudLayer/Day1BusinessHUD/ResumeStory").pressed.emit()
	await _wait_event("day1.opening")
	check(_state.get_transactions().get_balance() == 0 and _state.get_variable("shop.orders_completed", 0) == 0, "Restarting unfinished presentation invents no payouts")
	_game.queue_free()
	await frames()
	Engine.time_scale = 1.0
	print("DAY1_STAGES_01_02: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
