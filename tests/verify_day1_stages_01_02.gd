extends SceneTree

const StateData = preload("res://src/core/game_state.gd")
const MANIFEST := "res://docs/story_authoring/day1_stages_01_02_bridge.json"
var _checks := 0
var _failures: Array[String] = []
var _game: MainGame
var _state: StateData
var _lines := {}
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
	_game.get_player().teleport_to(point.global_position + Vector2(0, -40))
	for index in range(4):
		await physics_frame
	await frames(2)
	_game.get("_shop_interaction").refresh_target()
	check(_game.get("_shop_interaction").get_target() == point, "Actual reach and focus select " + id)
	if _game.get("_shop_interaction").get_target() != point:
		print("INTERACT_DIAG ", id, " player=", _game.get_player().global_position, " point=", point.global_position, " visible=", point.is_visible_in_tree(), " bodies=", point.get("_bodies"), " overlap=", point.get_overlapping_bodies(), " layer=", _game.get_player().collision_layer, " available=", point.is_available(), " movement=", _game.get_player().movement_enabled, " input=", _game.get("_shop_interaction").is_input_enabled(), " modal=", _game.get_ui_manager().has_modal(), " target=", _game.get("_shop_interaction").get_target())
		quit(1)
	await _press_e()
	check(_game.get_shop_ui().is_open(), "E opens business UI at " + id)

func _attach_observers() -> void:
	_game.get_dialogue_manager().line_changed.connect(_record_line)
	_game.get_story_director().event_finished.connect(_event_finished)

func _event_finished(id: String, ok: bool, reason: String) -> void:
	if not ok and reason != "Resume checkpoint" and not reason.contains("GameState") and not (_expected_cancellation and reason.ends_with("Player cancellation")):
		_events_failed.append(id + ": " + reason)

func _reload(snapshot: Dictionary) -> void:
	check(reload_current_scene() == OK, "Real scene reload starts")
	await scene_changed
	_game = current_scene as MainGame
	_attach_observers()
	await frames(8)
	check(_state.to_dict() == snapshot, "Scene reload preserves exact story and economy results")
	check(not _game.get_story_director().is_busy() and _game.get_player().movement_enabled and not _game.get_ui_manager().has_modal(), "Scene reload restores an idle gameplay boundary and input")
	check(_game.get_day1_controller().last_error.is_empty(), "Recreated host reloads Bridge successfully")

func _snapshot(name: String) -> void:
	if not _capture or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/day1_" + name + ".png")

func _accept() -> void:
	await _interact("orders")
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
	var panel: CraftingPanel = _game.get_node("PopupLayer/Modal/Center/Panel/Margin/Content/ProductionPanel")
	var before := _state.to_dict()
	panel.clear_selection()
	panel.submit()
	check(_state.to_dict() == before, "Incomplete recipe changes no participant")
	if production.get_completed_count() == 0:
		_game.get_shop_ui().close()
		await frames()
		check(_state.to_dict() == before, "Closing an unfinished production screen never completes an order")
		await _interact("tea_station")
		panel = _game.get_node("PopupLayer/Modal/Center/Panel/Margin/Content/ProductionPanel")
	panel.clear_selection()
	for id: String in order.recipe:
		panel.add_material(id)
	if production.get_completed_count() == 0:
		var ingredient := "syrup"
		var stock := production.get_stock(ingredient)
		_game.get_warehouse_inventory().try_consume({ingredient: stock})
		before = _state.to_dict()
		panel.submit()
		check(_state.to_dict() == before, "Correct recipe with missing ingredients changes no participant")
		_game.get_warehouse_inventory().add_ingredient(ingredient, stock)
	var sound_handle: int = _game.get_audio_manager().get("_next_handle")
	var notices: Array[bool] = []
	var observe := func() -> void: notices.append(_state.get_variable("shop.drinks_made") == production.get_completed_count())
	_state.state_changed.connect(observe)
	panel.submit()
	_state.state_changed.disconnect(observe)
	check(not notices.is_empty() and not notices.has(false), "Craft notification snapshots contain production and task progress together")
	check(_game.get_audio_manager().get("_next_handle") == sound_handle + 1, "Each successful production triggers exactly one pour sound")
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
	check(_game.get_shop_ui().is_open(), "Settlement remains visible until explicitly closed")
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
	check(source.sha256_text() == manifest.source_sha256, "Source hash matches authoring products")
	var story := StoryLibrary.new()
	var dialogue := DialogueLibrary.new()
	check(story.load_file(manifest.story) == OK, "Original Story v1 loader accepts all events")
	check(dialogue.load_file(manifest.dialogue) == OK, "Original Dialogue v1 loader accepts all lines")
	var expected_lines := 0
	for id: String in dialogue.get("_dialogues"):
		for line: Dictionary in dialogue.get_dialogue(id).lines.values():
			expected_lines += 1
			check(('「' + line.text + '」') in source, "Every displayed sentence is verbatim from source")
	check(expected_lines == 21, "All 21 original lines and system hints are included")
	check(dialogue.get_dialogue("day1.coins_raise_suspicion").lines.line_2.portrait == "res://assets/characters/apron_man/player_bad_laugh.png", "Authored ending expression uses the supplied portrait")
	for id: String in manifest.actors:
		check(ResourceLoader.exists(manifest.actors[id]), "Bound actor scene exists: " + id)
	check(manifest.beats.size() == 12, "All 12 Beats have execution mappings")
	for beat: Dictionary in manifest.beats:
		check(source.contains("### Beat " + beat.id), "Mapped Beat exists: " + beat.id)
		if beat.has("event"):
			var steps: Array = story.get_event(beat.event).steps
			check(beat.start >= 0 and beat.count > 0 and beat.start + beat.count <= steps.size(), "Beat owns an actual step range")

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

func _travel_completed_run(snapshot: Dictionary) -> void:
	var inventory := _game.get_warehouse_inventory()
	var production := _game.get_tea_production()
	for path: String in ["res://src/core/settlement.tscn", "res://src/core/main.tscn"]:
		var exit: SceneExit = _game.get_active_level().get_scene_exits()[0]
		check(_game.get_scene_travel().request_exit(exit) == OK, "Completed Day 1 can travel to " + path)
		await scene_changed
		_game = current_scene as MainGame
		var deadline := Time.get_ticks_msec() + 5000
		while _game.get_scene_travel().is_busy() and Time.get_ticks_msec() < deadline:
			await process_frame
		await frames()
		check(_game.scene_file_path == path and not _game.get_scene_travel().is_busy(), "Day 1 door transition finishes")
		check(_state.to_dict() == snapshot, "Door travel preserves Day 1 profile, income, coins, receipts and story")
		check(_game.get_warehouse_inventory() == inventory and _game.get_tea_production() == production, "Day 1 travel retains service identities")
		check(_game.get_player().movement_enabled and not _game.get_story_director().is_busy(), "Arrival releases travel input without replaying story")
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
	check(_game.open_chronicle() == ERR_UNAVAILABLE and not _game.get_node("HudLayer/ChronicleHUD").visible, "Chronicle is inaccessible before unlock")
	check(not _game.get_tea_production().make_drink(["black_tea", "creamer", "pearl", "syrup"], "day1_human").ok, "Cannot craft ahead of acceptance")
	await _wait_event("day1.opening")
	check(_state.story_stage == "day1.wait_human" and _game.get_player().movement_enabled, "First gameplay handoff releases input")
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
	var observations: Array[bool] = []
	var observe := func() -> void:
		if observations.is_empty() and _state.get_flag("day1.human_settled"):
			observations.append(_state.get_transactions().get_balance() == 10 and _state.get_warehouse_inventory().get_stock("pearl_milk_tea") == 0 and _state.start_new_game() == ERR_BUSY and not _state.set_flag("test.reentry"))
	_state.state_changed.connect(observe)
	await _deliver("human_customer")
	_state.state_changed.disconnect(observe)
	check(observations == [true], "Synchronous settlement observers see complete results and cannot reset or overwrite")
	check(_state.get_transactions().get_balance() == 10, "Human first order really pays 10")
	check(not _state.is_event_completed("day1.first_goblin"), "Open delivery modal blocks continuation")
	before = _state.to_dict()
	check(not _game.get_task_delivery().try_submit("day1_human", "human_customer").ok and _state.to_dict() == before, "Repeated delivery cannot pay twice")
	_game.get_shop_ui().close()
	_game.get_ui_manager().set_paused(true)
	await frames(8)
	check(not _game.get_story_director().is_busy(), "Paused tree blocks continuation")
	_game.get_ui_manager().set_paused(false)
	await _wait_event("day1.first_goblin")
	_waiting_snapshots.append(_state.to_dict())
	await _restore(_state.to_dict())
	await _reload(_state.to_dict())
	await _accept()
	await _make()
	await _deliver("goblin_customer")
	check(_state.get_warehouse_inventory().get_stock("strange_coin") == 1, "First goblin pays a real inventory coin")
	_game.get_shop_ui().close()
	await _wait_event("day1.group_arrival")
	_waiting_snapshots.append(_state.to_dict())
	var group_counter: Node2D = _game.get_active_level().get_node("EquipmentForeground/Counter")
	for id: StringName in [&"goblin_a", &"goblin_b", &"goblin_c"]:
		check(_game.get_actor_director().get_actor(id).z_index > group_counter.z_index, "Group customer is fully visible in front of counter: " + id)
	await _snapshot("group_wait")
	await _restore(_state.to_dict())
	await _reload(_state.to_dict())
	check(_game.get_chronicle_journal().get_entries().size() == 3, "Chronicle unlocks exactly three entries")
	for entry in _game.get_chronicle_journal().get_entries():
		check(entry.records.is_empty(), "New lore entry contains no invented explanation")
	check(_game.open_chronicle() == OK, "Unlocked chronicle uses real UI")
	await _snapshot("chronicle")
	_game.get_ui_manager().close_screen(&"chronicle")
	await _accept()
	for id: String in ["goblin_a", "goblin_b", "goblin_c"]:
		await _make()
		await _deliver(id)
		if id != "goblin_c":
			check(not _state.get_flag("day1.group_settled"), "Partial batch never advances story")
		_game.get_shop_ui().close()
		if id == "goblin_a":
			await _restore(_state.to_dict())
			await _reload(_state.to_dict())
	await _wait_event("day1.ending")
	check(_lines.size() == 21 and _events_failed.is_empty(), "All authored dialogue lines execute without actor or audio failure")
	check(_state.get_variable("shop.orders_completed") == 5 and _game.get_tea_production().get_completed_count() == 5, "Five crafted and independently settled orders")
	check(_game.get_transactions().get_balance() == 10 and _game.get_warehouse_inventory().get_stock("strange_coin") == 4, "Final totals are income 10 and four strange coins")
	check(_game.get_business_hud().get_node("BusinessBalance").text == "营业收入 10    古怪金币 4", "HUD follows the actual committed wallet and story-item balance")
	check(_state.current_day == 1 and _state.story_stage == "day1.investigate_coins", "Stops at same-day investigation intent")
	check(_game.get_chronicle_journal().get_unread_count() == 3, "Opening the list does not falsely mark entries read")
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
