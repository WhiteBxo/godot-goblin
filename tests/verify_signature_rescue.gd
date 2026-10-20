extends SceneTree
## The signature rescue path from a clean process: market purchase, the shared
## recipe conversation and the rescue menu. Split from verify_signature_interaction
## because a fifth host boot in one process crashes this engine build on teardown.
var checks := 0
var failures := 0
var _game: MainGame

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 6) -> void:
	for i in range(count):
		await physics_frame

func open_scene(scene_name: String) -> bool:
	if change_scene_to_file("res://src/core/" + scene_name + ".tscn") != OK:
		return false
	await scene_changed
	await frames(2)
	_game = current_scene as MainGame
	return _game != null

func run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	var state := root.get_node("GameState")
	state.reset_state()
	state.select_business_profile("day1")
	state.current_day = 2
	state.set_story_stage("signature.playtest")
	state.commit_story_transaction("signature.test_money", {}, {}, 100)
	if not await open_scene("settlement"):
		check(false, "Settlement host opens")
		print("SIGNATURE_RESCUE: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	var game := _game
	var market: InteractionPoint
	for point: InteractionPoint in game.get_active_level().get_interaction_points():
		if point.interaction_id == &"day1_s03_yard":
			market = point
	check(market != null, "Market exposes the existing public location")
	if market == null:
		print("SIGNATURE_RESCUE: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	game.get_player().teleport_to(market.global_position)
	await frames()
	check(game.open_game_menu() == OK, "Player opens the actual market game menu")
	await frames()
	var button := game.get_game_menu().get_action_button("signature_buy_mushroom")
	check(button != null and not button.disabled, "Nearby market offers a real purchase button")
	if button != null:
		button.pressed.emit()
	await frames()
	check(state.get_warehouse_inventory().get_uses("insomnia_mushroom") == 5 and state.get_transactions().get_balance() == 50, "Market button pays 50G and buys five uses")
	state.set_story_stage("day2.s03.travel_tavern")
	if not await open_scene("main"):
		check(false, "Shop host opens")
		print("SIGNATURE_RESCUE: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	game = _game
	await frames(10)
	for i in range(600):
		var dialogue := game.get_dialogue_manager()
		if dialogue.is_active():
			dialogue.advance()
			dialogue.select_choice(0)
		if state.is_event_completed("day2.procurement.recipe"):
			break
		await process_frame
	await frames()
	check(state.is_event_completed("day2.procurement.recipe") and state.get_transactions().is_signature_discovered("S06"), "Real Day2 purchase automatically plays the shared recipe conversation")
	check(state.get_transactions().get_balance() == 200, "Recipe discovery pays the existing 150G bounty once")
	check(game.get_story_director().request_event("day2.procurement.recipe") == ERR_ALREADY_EXISTS and state.get_transactions().get_balance() == 200, "Replaying the purchase dialogue cannot duplicate the recipe bounty")
	var patient := game.get_actor_director().get_actor(&"fat_goblin")
	check(patient != null and patient.visible, "Patient remains visible in the real day-two shop")
	if patient != null:
		game.get_player().teleport_to(patient.global_position + Vector2(0, 30))
	await frames()
	check(game.open_game_menu() == OK, "Player opens the actual rescue menu")
	await frames()
	button = game.get_game_menu().get_action_button("signature_rescue")
	check(button != null and not button.disabled, "Patient proximity offers the rescue button")
	if button != null:
		button.pressed.emit()
	await frames()
	check(state.get_flag("signature.S06.rescued_in_time") and state.get_warehouse_inventory().get_uses("insomnia_mushroom") == 4, "Actual menu rescues once and keeps four uses")
	print("SIGNATURE_RESCUE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
