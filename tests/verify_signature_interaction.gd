extends SceneTree
## Real host selection and document-close reward routing, including nearby NPCs.
var checks := 0
var failures := 0

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

func tap(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	var state := root.get_node("GameState")
	state.reset_state()
	state.set_flag("day2.s04.casino_reward_received")
	state.get_warehouse_inventory().add_ingredient("rainbow_cube", 1)
	for entry: Array in [["tavern", "S04", "SignatureS04"], ["casino", "S07", "SignatureS07"], ["elder_house", "S10", "SignatureS10"], ["settlement", "S08", "SignatureS08"]]:
		var game: MainGame = load("res://src/core/" + entry[0] + ".tscn").instantiate()
		root.add_child(game)
		await frames()
		var point: SignatureDiscoveryPoint = game.get_active_level().get_node("Interactions/" + entry[2])
		var player: PlayerController = game.get_player()
		player.teleport_to(point.global_position + Vector2(0, 20))
		await frames()
		check(point.is_available(), "Physical overlap opens source clue: " + entry[1])
		var before: int = state.get_transactions().get_balance()
		await tap(&"interact")
		await frames()
		check(game.get_shop_ui().is_open() and state.get_transactions().get_balance() == before, "E opens a document before paying its reward: " + entry[1])
		check(game.get_shop_ui().get_popup().is_visible_in_tree(), "Discovery content is visible: " + entry[1])
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/signature_" + entry[1] + "_document.png")
		game.get_shop_ui().close()
		await frames()
		check(state.get_transactions().is_signature_discovered(entry[1]) and state.get_transactions().get_balance() == before + 150, "Closing the actual host document commits exactly one bounty: " + entry[1])
		game.queue_free()
		await process_frame
	await verify_rescue_menu(state)
	print("SIGNATURE_INTERACTION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func verify_rescue_menu(state: Node) -> void:
	state.reset_state()
	state.select_business_profile("day1")
	state.current_day = 2
	state.set_story_stage("signature.playtest")
	state.commit_story_transaction("signature.test_money", {}, {}, 100)
	var game: MainGame = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(game)
	await frames(12)
	var market: InteractionPoint
	for point: InteractionPoint in game.get_active_level().get_interaction_points():
		if point.interaction_id == &"day1_s03_yard": market = point
	check(market != null, "Market exposes the existing public location")
	if market == null:
		game.free()
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
	game.queue_free()
	await process_frame
	state.set_story_stage("day2.s03.travel_tavern")
	game = load("res://src/core/main.tscn").instantiate()
	root.add_child(game)
	await frames(12)
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
	game.queue_free()
	await process_frame
