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
			"settlement": ["prayer_man","prayer_woman","warehouse_guard_1","warehouse_guard_2","barracks_soldier","signature_philosopher","signature_drunk","market_mother","market_boy","village_child"],
			"tavern": ["signature_heartbroken_drinker"], "casino": ["casino_poet"]}[host]
		if day == 1:
			triggers = ["market_mother","market_boy","village_child"]
		if host == "settlement":
			# Stalls are goods, not chatter: no story route may answer for them.
			var vendor_point := game.get_delivery_point("market_vendor_2")
			check(vendor_point != null, "Vendor keeps an interaction point")
			if vendor_point != null and day == 1:
				check(not vendor_point.interaction_enabled, "Day one vendors are not worth talking to")
				check(game.get_chapter_gameplay().open_market_vendor(&"market_vendor_2") == ERR_UNAVAILABLE, "Day one stalls refuse to trade")
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
			check(gather.get_points().size() == 6,"All six source materials keep their patch")
			var harvested := 0
			for point: GatherPoint in gather.get_points():
				game.get_player().teleport_to(point.global_position + Vector2(0,24))
				await frames()
				if point.item_id == "insomnia_mushroom":
					# Story ingredient: only a purchase or a hired runner brings it in.
					check(not point.is_available(), "醒神菇 是剧情道具，主角自己采不到")
					var refused := gather.harvest(point.interaction_id)
					check(not refused.ok and refused.message == point.blocked_reason, "The locked patch explains who can reach it")
					continue
				check(point.is_available(), "Physically reach harvest: " + point.item_id)
				var before: int = state.get_warehouse_inventory().get_stock(point.item_id)
				var result := gather.harvest(point.interaction_id)
				check(result.ok and result.message.begins_with(point.success_description),"Source acquisition text follows committed harvest: " + point.item_id)
				check(state.get_warehouse_inventory().get_stock(point.item_id) == before + point.amount and not gather.harvest(point.interaction_id).ok,"Harvest pays once per day: " + point.item_id)
				harvested += 1
			check(harvested == 5,"The other five materials stay harvestable")
			check(not state.can_discover_signature("S06"),"Free mushroom harvesting never fabricates a Day2 purchase")
			state.commit_story_transaction("test.market_money",{},{},5000)
			var chapter := game.get_chapter_gameplay()
			check(chapter.can_trade_with_vendors(), "Second-day stalls open for trade")
			for index in range(1,4):
				var vendor_id := StringName("market_vendor_%d" % index)
				var view := chapter.get_vendor_view(vendor_id)
				var products: Array = view.get("products", [])
				check(products.size() == (4 if index == 3 else 3), "Each vendor offers its authored goods")
				if index == 3:
					check(products.any(func(product: Dictionary) -> bool: return product.id == "market_red_mottled_wood"), "The right stall supplies the recovery recipe's red mottled wood")
				for product: Dictionary in products:
					check(not str(product.get("pitch", "")).is_empty(), "Every good carries its own line: " + str(product.get("id", "")))
				if products.is_empty():
					continue
				var first: Dictionary = products[0]
				var quote: Dictionary = state.get_transactions().get_product_quote(str(first.id))
				var money: int = state.get_transactions().get_balance()
				var stock: int = state.get_warehouse_inventory().get_stock(str(quote.item_id))
				var bought: Dictionary = chapter.buy_from_vendor(str(first.id), 1)
				check(bought.get("ok", false), "Stall purchase settles through the shared wallet: " + str(first.id))
				check(state.get_transactions().get_balance() == money - int(quote.unit_price) and state.get_warehouse_inventory().get_stock(str(quote.item_id)) == stock + 1,"Stall purchase uses the real quote and inventory: " + str(first.id))
				# Recipe conversation is covered by verify_signature_interaction.
				if state.get_flag("day2.procurement.purchased"):
					state.complete_event("day2.procurement.recipe")
				await frames()
		game.free()
		await frames()
	print("SUPPLEMENT_CONTENT: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
