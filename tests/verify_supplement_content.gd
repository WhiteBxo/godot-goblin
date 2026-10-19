extends SceneTree
## Supplied NPCs, real story routes, nearby market purchases and six harvests.
var checks := 0
var failures: Array[String] = []
var state: Node
var game: MainGame

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count := 8) -> void:
	for i in range(count): await physics_frame

func conversation(trigger: String, choice := 0) -> void:
	var point := game.get_delivery_point(trigger)
	check(point != null, "Host exposes the NPC interaction: " + trigger)
	if point == null: return
	game.get_player().teleport_to(point.global_position + Vector2(0,28))
	await frames()
	check(point.is_available(), "NPC is physically available: " + trigger)
	point.interact()
	await frames(2)
	check(game.get_story_director().is_busy(), "Actual NPC signal starts the story route: " + trigger)
	for i in range(600):
		var dialogue := game.get_dialogue_manager()
		if dialogue.is_active():
			dialogue.advance()
			dialogue.select_choice(choice)
		await process_frame
		if not game.get_story_director().is_busy(): break
	check(not game.get_story_director().is_busy() and game.get_story_director().last_error.is_empty(), "Conversation and choice return control: " + trigger)
	await frames()

func run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled",false)
	ProjectSettings.set_setting("persistence/save_directory","user://verification/supplement_%d" % OS.get_process_id())
	state = root.get_node("GameState")
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://src/gameplay/characters/supplement_npc_catalog.json"))
	for entry: Dictionary in catalog:
		if entry.id in ["tavern_drunk", "tavern_drinker"]:
			check(entry.active_archive == "酒鬼（改后(1).zip", "Formal drunk uses the revised attachment: " + entry.id)
		var character: SettlementCharacter = load("res://src/gameplay/characters/rpg_" + entry.id + ".tscn").instantiate()
		root.add_child(character)
		for animation: StringName in character.animated_sprite.sprite_frames.get_animation_names():
			var sprite_frames := character.animated_sprite.sprite_frames
			for i in range(sprite_frames.get_frame_count(animation)):
				var texture := sprite_frames.get_frame_texture(animation,i)
				check(texture != null and texture.get_image().get_used_rect().has_area(), "Nonempty supplied frame: %s/%s/%d" % [entry.id, animation,i])
		character.free()
	for visit: Array in [["settlement",1],["settlement",2],["tavern",2],["casino",2]]:
		var host: String = visit[0]
		var day: int = visit[1]
		state.reset_state()
		state.select_business_profile("day1")
		if day == 2:
			check(DayPhase.advance_to(state,1,"night") == OK and DayPhase.advance_to(state,2,"day") == OK and DayPhase.advance_to(state,2,"night") == OK,"Reach Day2 night through actual phase transitions")
		state.set_story_stage("day1.s04.wait_taste" if day == 1 else "day2.s03.travel_tavern")
		game = load("res://src/core/" + host + ".tscn").instantiate()
		root.add_child(game)
		await frames(16)
		if day == 1:
			check(game.get_story_director().request_interaction("market_boy") != OK and not game.get_story_director().is_busy(),"Family dialogue does not spoil the restricted first market visit")
		state.set_flag("day1.s04.commission_accepted")
		await frames()
		var triggers: Array = {
			"settlement": ["prayer_man","prayer_woman","warehouse_guard_1","warehouse_guard_2","barracks_soldier","signature_philosopher","signature_drunk","market_vendor_1","market_vendor_2","market_vendor_3","market_mother","market_boy","village_child"],
			"tavern": ["signature_heartbroken_drinker"], "casino": ["casino_poet"]}[host]
		if day == 1:
			triggers = ["market_mother","market_boy","village_child"]
		if host == "settlement":
			var mother := game.get_actor_director().get_actor(&"market_mother")
			check(mother != game.get_actor_director().get_actor(&"prayer_woman"),"Mother and prayer companion have independent actor identities")
			for id: StringName in [&"market_boy",&"village_child"]:
				var child := game.get_actor_director().get_actor(id)
				var map := game.get_active_level() as RpgChapterMap
				check(map.can_stand_at(child.global_position,Vector2(7,4)) and not map.get_navigation_path(game.get_player().global_position,child.global_position + Vector2(0,28)).is_empty(),"Child has a real walkable approach: " + String(id))
				check(child.get_interaction_feedback_rect().size.y < mother.get_interaction_feedback_rect().size.y,"Child keeps a smaller visible scale: " + String(id))
		for trigger: String in triggers: await conversation(trigger)
		if host == "casino":
			for choice in range(3): await conversation("casino_sentry",choice)
		if host == "settlement" and day == 2:
			var gather := game.get_gathering_service()
			check(gather.get_points().size() == 6,"All six source materials have real gather points")
			for point: GatherPoint in gather.get_points():
				game.get_player().teleport_to(point.global_position + Vector2(0,24))
				await frames()
				check(point.is_available(), "Physically reach harvest: " + point.item_id)
				var before: int = state.get_warehouse_inventory().get_stock(point.item_id)
				var result := gather.harvest(point.interaction_id)
				check(result.ok and result.message.begins_with(point.success_description),"Source acquisition text follows committed harvest: " + point.item_id)
				check(state.get_warehouse_inventory().get_stock(point.item_id) == before + point.amount and not gather.harvest(point.interaction_id).ok,"Harvest pays once per day: " + point.item_id)
			check(not state.can_discover_signature("S06"),"Free mushroom harvesting never fabricates a Day2 purchase")
			state.commit_story_transaction("test.market_money",{},{},5000)
			for index in range(1,4):
				var actor := game.get_actor_director().get_actor(StringName("market_vendor_%d" % index))
				game.get_player().teleport_to(actor.global_position + Vector2(0,28))
				await frames()
				var actions := game.get_chapter_gameplay().get_user_actions()
				var available := 0
				for action: Dictionary in actions:
					if action.get("kind") != "market_buy":continue
					available += 1
					var quote: Dictionary = state.get_transactions().get_product_quote(action.product)
					var money: int = state.get_transactions().get_balance()
					var stock: int = state.get_warehouse_inventory().get_stock(quote.item_id)
					game.get_chapter_gameplay().perform_user_action(action.id)
					check(state.get_transactions().get_balance() == money - int(quote.unit_price) and state.get_warehouse_inventory().get_stock(quote.item_id) == stock + 1,"Nearby vendor uses the existing quote and real inventory: " + action.product)
					# Recipe conversation is covered by verify_signature_interaction.
					if state.get_flag("day2.procurement.purchased"):
						state.complete_event("day2.procurement.recipe")
					await frames()
				check(available >= 3,"Each vendor offers its three authored goods")
		game.free()
		await frames()
	print("SUPPLEMENT_CONTENT: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
