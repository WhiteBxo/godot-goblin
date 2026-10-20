extends SceneTree
## Real RPG elder-house interaction routes. Travel, retry and S06 are covered by
## verify_two_day_flow.gd; this checks document close and both investigation orders.

const BLOOD: Array[String] = ["creamer_milk_tea_base", "day1_griffin_blood"]
var _failures: Array[String] = []
var _checks := 0
var _state: Node
var _game: MainGame
var _inventory: WarehouseInventory

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames() -> void:
	for index in range(4):
		await physics_frame
	await process_frame

func _read_document(point: StoryInteractionPoint) -> void:
	_game.get_player().teleport_to(point.global_position)
	await _frames()
	_check(_game.call("_route_story_interaction", point.interaction_id) == OK, "Document uses the real interaction route")
	_check(_game.get_shop_ui().is_open(), "Reading displays the document")
	_check(not _state.get_flag("day1.s05.document_read") and _inventory.get_stock("day1_elder_document") == 0, "Opening content does not grant the document or reading fact")
	_game.get_shop_ui().close()
	await _frames()
	_check(_state.get_flag("day1.s05.document_read") and _inventory.get_stock("day1_elder_document") == 1, "Closing content atomically records reading and takes one document")
	var before: Dictionary = _state.to_dict()
	_check(_game.call("_route_story_interaction", point.interaction_id) == OK, "Taken document remains readable")
	_game.get_shop_ui().close()
	await _frames()
	_check(_state.to_dict() == before, "Rereading never grants another document")

func _take_blood(point: StoryInteractionPoint) -> void:
	_game.get_player().teleport_to(point.global_position)
	await _frames()
	_check(_game.call("_route_story_interaction", point.interaction_id) == OK, "Blood uses the real interaction route")
	_check(_inventory.get_uses("day1_griffin_blood") == 3 and _state.get_flag("day1.s05.blood_acquired"), "Pickup grants three uses and its completion fact together")
	_check(_game.get_shop_ui().is_open(), "Pickup displays real feedback")
	_game.get_shop_ui().close()
	var before: Dictionary = _state.to_dict()
	_check(_game.call("_route_story_interaction", point.interaction_id) == ERR_UNAVAILABLE and _state.to_dict() == before, "Repeated pickup cannot duplicate blood")

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	ProjectSettings.set_setting("persistence/save_directory", "/tmp/goblin_world_flow_%d" % OS.get_process_id())
	_state = root.get_node("GameState")
	_state.start_new_game()
	_inventory = _state.get_warehouse_inventory()
	var wallet: WalletTransactions = _state.get_transactions()
	var tutorial_snapshot: Dictionary = _state.to_dict()
	_check(_state.select_business_profile("day1") == OK, "Select Day 1")
	_check(_state.get_warehouse_inventory() == _inventory and _state.get_transactions() == wallet, "Profile selection preserves service identities")
	_check(_inventory.get_definition("day1_griffin_blood") != null, "Real session catalog includes blood")
	var day1_snapshot: Dictionary = _state.to_dict()
	_check(_state.restore_state(tutorial_snapshot) == OK and _state.get_warehouse_inventory() == _inventory, "Cross-profile restore preserves inventory identity")
	_check(_state.get_business_profile() == "tutorial", "Cross-profile restore selects tutorial")
	_check(_state.restore_state(day1_snapshot) == OK and _state.get_business_profile() == "day1", "Cross-profile restore selects Day 1 with its menu")
	_state.set_story_stage("day1.s01")
	_check(not Day1Access.can_leave_shop(_state), "S01 cannot leave the shop")
	_state.set_flag("day1.stages_01_02_completed")
	_state.set_story_stage("day1.s03.explore")
	_check(Day1Access.can_leave_shop(_state), "S03 can explore")
	_check(not Day1Access.can_enter_elder(_state), "Exploration does not authorize entry into the elder house")
	_game = load("res://src/core/elder_house.tscn").instantiate()
	root.add_child(_game)
	current_scene = _game
	await _frames()
	var map := _game.get_active_level() as RpgChapterMap
	_check(map != null and map.get_chapter_host() == "elder_house", "Formal indoor host uses the RPG chapter map")
	_check(map.scene_file_path == "res://src/levels/rpg_maker/chapter_elder_house.tscn", "Actual host instantiates the inherited RPG elder-house scene")
	_check(_game.get_actor_director().get_position(&"elder_document") != null, "Host registers the real document anchor")
	var points := {}
	for point: InteractionPoint in map.get_interaction_points():
		points[point.interaction_id] = point
	var blood: StoryInteractionPoint = points[&"day1_blood_storage"]
	var document: StoryInteractionPoint = points[&"day1_elder_document"]
	_check((document.global_position + document.feedback_rect.position) == Vector2(490, 246), "Document bracket aligns with the visible paper on the desk")
	_check((blood.global_position + blood.feedback_rect.position) == Vector2(206, 336), "Blood bracket aligns with the visible small vial")
	_check(map.can_stand_at(blood.global_position, Vector2(8.5, 5)), "Blood interaction stands on reachable floor beside its actual table")
	var before: Dictionary = _state.to_dict()
	_check(not blood.conditions_met() and not document.conditions_met(), "Daytime exploration cannot investigate either night objective")
	_check(_game.call("_route_story_interaction", document.interaction_id) == ERR_UNAVAILABLE and not blood.resolve().ok and _state.to_dict() == before, "Unavailable investigation leaves inventory and story unchanged")
	_state.set_story_stage("day1.s05.search")
	_check(not Day1Access.can_leave_shop(_state), "Unaccepted night mission cannot depart")
	_state.set_flag("day1.s04.commission_accepted")
	await _frames()
	_check(DayPhase.is_night(_state) and _state.current_day == 1, "Accepted mission enters night on the same day")
	_check(Day1Access.can_enter_elder(_state) and blood.conditions_met() and document.conditions_met(), "Accepted S05 unlocks both actual indoor objectives")
	_check(map.get_stealth_setup() == null and _game.get_stealth_service() == null, "Elder house has no stealth setup, detection service or stealth HUD")
	_check(map.get_chapter_characters().is_empty(), "Indoor patrol guards are removed")
	var checkpoint: Dictionary = _state.to_dict()
	for document_first: bool in [true, false]:
		_check(_state.restore_state(checkpoint) == OK, "Restore investigation baseline")
		await _frames()
		if document_first:
			await _read_document(document)
			await _take_blood(blood)
		else:
			await _take_blood(blood)
			await _read_document(document)
		_check(_inventory.get_uses("day1_griffin_blood") == 3 and _inventory.get_stock("day1_elder_document") == 1, "Both investigation orders grant exactly the approved items")
		_check(_state.get_flag("day1.s05.document_read") and _state.get_flag("day1.s05.blood_acquired"), "Indoor investigation preserves both facts without a stealth service")
		_check(_state.get_tea_production().preview_craft(BLOOD).code == "locked", "Taking blood inside the house does not unlock the S06 recipe")
		_check(not _state.get_flag("day1.s05.returned_shop"), "Indoor inspection never invents a return-to-shop fact")
	current_scene = null
	_game.queue_free()
	await _frames()
	print("DAY1_WORLD_FLOW: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
