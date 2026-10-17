extends SceneTree
## Actual Day 1 hosts: stage gates, phase actors, investigation, return and S06 delivery.

const BLOOD: Array[String] = ["day1_griffin_blood", "black_tea", "creamer", "syrup"]
var _failures: Array[String] = []
var _state: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames() -> void:
	for index in range(4):
		await physics_frame
	await process_frame

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	_state = root.get_node("GameState")
	_state.start_new_game()
	var inventory: WarehouseInventory = _state.get_warehouse_inventory()
	var wallet: WalletTransactions = _state.get_transactions()
	var tutorial_snapshot: Dictionary = _state.to_dict()
	_check(_state.select_business_profile("day1") == OK, "Select Day 1")
	_check(_state.get_warehouse_inventory() == inventory and _state.get_transactions() == wallet, "Profile selection preserves service identities")
	_check(inventory.get_definition("day1_griffin_blood") != null, "Real session catalog includes blood")
	var day1_snapshot: Dictionary = _state.to_dict()
	_check(_state.restore_state(tutorial_snapshot) == OK and _state.get_warehouse_inventory() == inventory, "Cross-profile restore preserves inventory identity")
	_check(_state.get_business_profile() == "tutorial", "Cross-profile restore selects the tutorial profile")
	_check(_state.restore_state(day1_snapshot) == OK and _state.get_business_profile() == "day1", "Cross-profile restore selects Day 1 with its menu")
	_state.set_story_stage("day1.s01")
	_check(not Day1Access.can_leave_shop(_state), "S01 cannot leave the shop")
	_state.set_flag("day1.stages_01_02_completed")
	_state.set_story_stage("day1.s03.explore")
	_check(Day1Access.can_leave_shop(_state), "S03 can explore")
	_state.set_story_stage("day1.s04")
	_check(not Day1Access.can_leave_shop(_state), "S04 waits for the mission")
	_state.set_story_stage("day1.s03.explore")
	var game: MainGame = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames()
	var elder := game.get_actor_director().get_actor(&"elder") as SettlementCharacter
	var tavern := game.get_actor_director().get_actor(&"tavern") as SettlementCharacter
	# Stable host names identify the actual saved NPC instances if their actor IDs differ.
	if tavern == null:
		for actor: Node in game.get_node("World/EntityRoot").get_children():
			if actor is SettlementCharacter and actor.active_phase == "night":
				tavern = actor
				break
	_check(elder != null and elder.visible and elder.get_collision_layer_value(3), "Day NPC is visible and solid")
	_check(tavern != null and not tavern.visible and not tavern.get_collision_layer_value(3), "Night NPC has no invisible collision during day")
	var map := game.get_active_level() as SettlementMap
	var gate := map.get_node("Districts/Elder/Walls/StoryGate") as StaticBody2D
	_check(gate.get_collision_layer_value(1), "Elder entrance is physically closed during exploration")
	_check(game.get_actor_director().get_position(&"elder_document") != null, "Host registers actual story anchors")
	var points := {}
	for point: InteractionPoint in map.get_interaction_points():
		points[point.interaction_id] = point
	var blood: StoryInteractionPoint = points[&"day1_blood_storage"]
	_check(not blood.conditions_met(), "Blood is unavailable during S03")
	_state.set_story_stage("day1.s05.search")
	_check(not Day1Access.can_leave_shop(_state), "Unaccepted S05 cannot depart")
	_state.set_flag("day1.s04.commission_accepted")
	await _frames()
	_check(DayPhase.is_night(_state) and _state.current_day == 1, "Accepted S05 enters night on the same day")
	_check(not elder.visible and not elder.get_collision_layer_value(3), "Day NPC disappears with collision disabled")
	_check(tavern.visible and tavern.get_collision_layer_value(3), "Night NPC becomes visible and solid")
	_check(not gate.get_collision_layer_value(1) and blood.conditions_met(), "S05 opens elder entrance and investigation")
	var document: StoryInteractionPoint = points[&"day1_elder_document"]
	game.get_player().teleport_to(document.global_position)
	await _frames()
	_check(game.call("_route_story_interaction", document.interaction_id) == OK, "Document uses the real interaction route")
	_check(not _state.get_flag("day1.s05.document_read"), "Opening document does not yet complete reading")
	game.get_shop_ui().close()
	_check(_state.get_flag("day1.s05.document_read"), "Closing displayed content commits the reading fact")
	game.get_player().teleport_to(blood.global_position)
	await _frames()
	_check(game.call("_route_story_interaction", blood.interaction_id) == OK, "Pickup uses the real interaction route")
	_check(inventory.get_stock("day1_griffin_blood") == 1 and _state.get_flag("day1.s05.blood_acquired"), "Actual host grants blood once with the unlock fact")
	_check(game.get_shop_ui().is_open(), "Successful pickup displays feedback")
	game.get_shop_ui().close()
	_check(_state.get_tea_production().preview_craft(BLOOD).code == "locked", "Picking up blood does not unlock S06 in the elder house")
	_check(not _state.get_flag("day1.s05.returned_shop"), "Before travel there is no return fact")
	var door: SceneExit = map.get_scene_exits()[0]
	game.get_scene_travel().fade_seconds = 0.0
	_check(game.get_scene_travel().request_exit(door) == OK, "Real return travel starts")
	var deadline := Time.get_ticks_msec() + 6000
	while (current_scene == game or (current_scene as MainGame).get_scene_travel().is_busy()) and Time.get_ticks_msec() < deadline:
		await process_frame
	game = current_scene as MainGame
	await _frames()
	_check(game.scene_file_path == "res://src/core/main.tscn", "Travel reaches the actual shop host")
	_check(_state.story_stage == "day1.s05.search", "Return does not reset later story to S02 checkpoints")
	_check(_state.get_flag("day1.s05.returned_shop"), "Actual arrival records returned_shop")
	_check(_state.get_warehouse_inventory() == inventory and inventory.get_stock("day1_griffin_blood") == 1, "Travel retains the shared inventory")
	_check(_state.get_tea_production().preview_craft(BLOOD).code == "locked", "S05 return still waits for S06")
	_state.set_story_stage("day1.s06.wait_blood_drink")
	await _frames()
	_check(_state.get_tea_production().craft(BLOOD).ok, "S06 crafts the blood drink into inventory")
	var delivery := game.get_task_delivery()
	_check(delivery.accept_order("day1_s06_blood_drink") == OK, "S06 has a dedicated acceptable order")
	_check(not delivery.try_submit("day1_s06_blood_drink", "guard").ok, "Wrong target cannot consume the special drink")
	_check(delivery.try_submit("day1_s06_blood_drink", "fat_goblin").ok, "Actual fat goblin accepts the special drink")
	_check(_state.get_flag("day1.s06.blood_drink_delivered") and inventory.get_stock("day1_blood_milk_tea") == 0, "Delivery consumes the real drink and writes completion")
	_check(not delivery.try_submit("day1_s06_blood_drink", "fat_goblin").ok, "Special order cannot deliver twice")
	_check(game.get_actor_director().get_actor(&"fat_goblin").visible, "S06 recipient is present in the shop")
	current_scene = null
	game.queue_free()
	await _frames()
	await _check_walkthrough()
	print("DAY1_WORLD_FLOW: ", "PASS" if _failures.is_empty() else "FAIL")
	quit(0 if _failures.is_empty() else 1)

func _check_walkthrough() -> void:
	var game: MainGame = load("res://src/debug/story/day1_world_flow_demo.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames()
	_check(Day1Access.at_stage(_state, "day1.s05") and DayPhase.is_night(_state), "F6 walkthrough seeds the accepted night mission")
	for point: InteractionPoint in (game.get_active_level() as SettlementMap).get_interaction_points():
		if point.interaction_id == &"day1_blood_storage":
			_check((point as StoryInteractionPoint).resolve().ok, "Walkthrough still requires a real pickup")
	game.get_scene_travel().fade_seconds = 0.0
	_check(game.get_scene_travel().request_exit(game.get_active_level().get_scene_exits()[0]) == OK, "Walkthrough returns through the real door")
	var deadline := Time.get_ticks_msec() + 6000
	while current_scene == game and Time.get_ticks_msec() < deadline:
		await process_frame
	game = current_scene as MainGame
	await _frames()
	_check(Day1Access.at_stage(_state, "day1.s06") and _state.get_flag("day1.s05.returned_shop"), "Debug handoff enters S06 only after actual arrival")
	_check(_state.get_tea_production().preview_craft(BLOOD).code == "ok", "Walkthrough arrives with a usable S06 recipe")
	current_scene = null
	game.queue_free()
	await _frames()
