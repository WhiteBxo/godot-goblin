extends SceneTree
## Real purchase conversations, deferred clue visibility and NPC conversation lifetime.

var checks := 0
var failures: Array[String] = []
var state: Node
var game: MainGame

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count := 8) -> void:
	for index in range(count):
		await physics_frame

func _new_host(path: String, stage: String) -> void:
	state.reset_state()
	state.select_business_profile("day1")
	DayPhase.advance_to(state, 1, "night")
	DayPhase.advance_to(state, 2, "day")
	DayPhase.advance_to(state, 2, "night")
	state.set_story_stage(stage)
	state.set_flag("day1.s04.commission_accepted")
	game = load(path).instantiate()
	root.add_child(game)
	current_scene = game
	await frames(16)

func _clear_host() -> void:
	game.free()
	game = null
	await frames(2)

func _finish_dialogue(choice := 0) -> void:
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		var manager := game.get_dialogue_manager()
		if manager.is_active():
			manager.advance()
			manager.select_choice(choice)
		elif not game.get_story_director().is_busy():
			await frames(2)
			if not manager.is_active() and not game.get_story_director().is_busy():
				return
		await process_frame
	check(false, "Conversation completes before its deadline")

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/story_feedback_%d" % OS.get_process_id())
	state = root.get_node("GameState")
	await _check_sentry()
	for vendor: String in ["market_vendor_2", "market_vendor_3"]:
		await _check_vendor(vendor)
	await _check_clue_and_festival()
	print("STORY_FEEDBACK: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_sentry() -> void:
	await _new_host("res://src/core/casino.tscn", "day2.s04.travel_casino")
	var sentry := game.get_actor_director().get_actor(&"casino_sentry")
	check(sentry != null, "Casino host registers its speaking sentry")
	if sentry != null:
		var origin := sentry.global_position
		for choice in range(3):
			check(game.get_story_director().request_interaction("casino_sentry") == OK, "Sentry dialogue starts for choice %d" % choice)
			await _finish_dialogue(choice)
			check(is_instance_valid(sentry) and sentry.is_visible_in_tree() and sentry.collision_layer == 4, "Sentry remains visible and solid after choice %d" % choice)
			check(sentry.global_position == origin, "Dialogue leaves sentry at his post")
			check(sentry.animated_sprite.get_parent().is_visible_in_tree() and sentry.animated_sprite.modulate.a > 0.0, "Sentry artwork remains visible")
	await _clear_host()

func _check_vendor(vendor: String) -> void:
	await _new_host("res://src/core/settlement.tscn", "day2.s03.travel_tavern")
	var chapter := game.get_chapter_gameplay()
	state.commit_story_transaction("test.vendor_wallet", {}, {}, 500)
	check(chapter.open_market_vendor(StringName(vendor)) == OK, "Open actual stall " + vendor)
	await frames(2)
	var popup: MarketVendorPopup = game.get_node("PopupLayer/MarketVendorPopup")
	check(popup.select_product("market_insomnia_mushroom"), "Seller offers the mushroom")
	var spoken: Array[String] = []
	game.get_dialogue_manager().dialogue_started.connect(func(id: String) -> void: spoken.append(id))
	popup._buy.pressed.emit()
	await frames(8)
	check(state.get_flag("day2.procurement.seller." + vendor), "Atomic sale records the actual keeper")
	await _finish_dialogue()
	var expected := "day2.procurement.recipe.vendor_" + vendor.right(1)
	check(expected in spoken and not "day2.procurement.recipe" in spoken, "Recipe exchange uses the purchasing stall instead of the errand runner")
	check(state.is_event_completed("day2.procurement.recipe"), "Actual purchase completes recipe discovery event")
	var dialogues: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/resources/dialogue/day2_stages_01_05.json")).dialogues
	var line: Dictionary = dialogues[expected].lines.line_2
	check(line.speaker == chapter.get_vendor_view(StringName(vendor)).title and line.portrait == "res://assets/characters/npc/%s/portrait.png" % vendor, "Seller name and portrait match the stall")
	await _clear_host()

func _check_clue_and_festival() -> void:
	await _new_host("res://src/core/settlement.tscn", "day2.s03.travel_tavern")
	var chapter := game.get_chapter_gameplay()
	state.set_flag("day2.s03.festival_accepted")
	await frames(2)
	var notice := chapter.get_gathering_notice()
	check("明天" in notice and not "苔痕青" in notice and not "萤火伞" in notice and not "窟窟糖芋" in notice, "Day two menu does not disclose tomorrow's ingredient list")
	check("等待明日" in chapter.get_optional_summary(), "Optional summary keeps the same reveal timing")
	check(not game.get_task_journal().get_task("day3.festival").get("revealed", true), "Task journal hides the detailed list on day two")
	var elder: SceneExit
	var clue: StoryInteractionPoint
	for exit: SceneExit in game.get_active_level().get_scene_exits():
		if exit.interaction_id == &"elder_enter": elder = exit
	for point: InteractionPoint in game.get_active_level().get_interaction_points():
		if point.interaction_id == &"signature_s08": clue = point
	state.set_flag("day1.s05.drunken_paid")
	state.set_flag("day1.s05.guard_payment_completed")
	check(elder != null and not elder.are_conditions_met(state), "Prior payments do not reopen the elder house on day two")
	check(game.get_scene_travel().request_exit(elder) == ERR_UNAVAILABLE and not game.get_scene_travel().is_busy(), "The elder door rejects travel before fading or switching scenes")
	game.get_ui_manager().close_screen(game.get_ui_manager().get_top_screen_id())
	await frames(2)
	state.commit_story_transaction("test.rainbow", {}, {}, 0, {"rainbow_cube": 1}, {"day2.s04.casino_reward_received": true})
	game.get_player().teleport_to(clue.global_position)
	await frames(2)
	check(clue != null and not clue.is_available() and not clue.is_world_marker_visible(), "Tavern note stays hidden before the conversation")
	check(game.get_story_director().request_interaction("signature_philosopher") == OK, "Philosopher conversation starts")
	await frames(2)
	game.get_story_director().cancel_event("test cancellation")
	await frames(2)
	check(not state.get_flag("supplement.philosopher.heard") and not clue.is_available(), "Cancelling the conversation does not reveal its note")
	check(game.get_story_director().request_interaction("signature_drunk") == OK, "The drunk provides the same conversation")
	await _finish_dialogue()
	check(state.get_flag("supplement.philosopher.heard") and clue.is_available() and clue.is_world_marker_visible(), "The note appears after the completed conversation")
	await _clear_host()
