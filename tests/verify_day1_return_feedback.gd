extends SceneTree
## Actual document close feedback and optional-document mission return.

const EXTERIOR = preload("res://src/levels/rpg_maker/chapter_cave.tscn")
const SHOP = preload("res://src/core/main.tscn")

var _failures := 0
var _checks := 0
var _state: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)

func _frames() -> void:
	for index in range(4):
		await physics_frame
	await process_frame

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	ProjectSettings.set_setting("persistence/save_directory", "/tmp/goblin_return_feedback_%d" % OS.get_process_id())
	_state = root.get_node("GameState")
	_state.start_new_game()
	_state.select_business_profile("day1")
	_state.set_story_stage("day1.s05.ready")
	_state.set_flag("day1.s04.commission_accepted")
	DayPhase.enter_night(_state)
	var game: MainGame = load("res://src/core/elder_house.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames()
	var clue: SignatureDiscoveryPoint
	var blood: StoryInteractionPoint
	for point: InteractionPoint in game.get_active_level().get_interaction_points():
		if point is SignatureDiscoveryPoint and point.signature_id == "S10":
			clue = point
		if point.interaction_id == &"day1_blood_storage":
			blood = point
	_check(clue != null and blood != null, "Real elder house exposes clue and blood")
	if clue == null or blood == null:
		quit(1)
		return
	var wallet: WalletTransactions = _state.get_transactions()
	var balance := wallet.get_balance()
	game.get_player().teleport_to(clue.global_position)
	await _frames()
	_check(game._route_story_interaction(clue.interaction_id) == OK, "Clue opens through the normal document route")
	_check(wallet.get_balance() == balance, "Opening the clue does not pay before closing")
	game.get_shop_ui().close()
	await _frames()
	_check(wallet.get_balance() == balance + 150, "Closing the clue pays the first discovery bounty")
	_check(game.get_shop_ui().get_feedback_text().contains("150G"), "Closing the clue visibly reports the actual 150G bounty")
	game._route_story_interaction(clue.interaction_id)
	game.get_shop_ui().close()
	await _frames()
	_check(wallet.get_balance() == balance + 150, "Rereading never pays again")
	_check(not game.get_shop_ui().get_feedback_text().contains("150G"), "Rereading does not announce a new 150G bounty")
	var world := Day1WorldController.new()
	root.add_child(world)
	world.configure(_state, game.get_active_level(), [], {})
	world.record_shop_arrival()
	_check(not _state.get_flag("day1.s05.escape_completed") and not _state.get_flag("day1.s05.returned_shop"), "Returning without blood cannot finish the mission")
	_check(blood.resolve().ok, "Collect actual blood without reading the optional document")
	world.record_shop_arrival()
	_check(not _state.get_flag("day1.s05.escape_completed"), "Blood alone does not bypass the guard payments")
	_state.set_flag("day1.s05.drunken_paid")
	_state.set_flag("day1.s05.guard_payment_completed")
	_state.complete_event("day1.s05.drunken_guard")
	world.queue_free()
	current_scene = null
	game.queue_free()
	await _frames()
	game = SHOP.instantiate()
	_check(game.prepare_scene_arrival(&"street_door") == OK, "Shop accepts the real return entrance")
	root.add_child(game)
	current_scene = game
	await _frames()
	_check(_state.get_flag("day1.s05.escape_completed") and _state.get_flag("day1.s05.returned_shop"), "Actual shop arrival completes escape and return without an exterior tick")
	_check(not _state.get_flag("day1.s05.document_read"), "Return preserves the optional document as unread")
	_check(game.get_task_journal().get_task("day1.s05.infiltration").status == "completed", "Task journal completes the leave-and-return objective")
	# The exterior must use the same optional-document contract at its door zone.
	var exterior: RpgChapterMap = EXTERIOR.instantiate()
	var setup := exterior.get_stealth_setup()
	_check(&"day1.s05.document_read" not in setup.required_flags and not setup.required_items.has("day1_elder_document"), "Exterior escape does not require the optional document")
	_check(&"day1.s05.blood_acquired" in setup.required_flags and setup.required_items.get("day1_griffin_blood") == 3, "Exterior escape still requires actual mission blood")
	exterior.free()
	current_scene = null
	game.queue_free()
	await _frames()
	print("DAY1_RETURN_FEEDBACK: %s (%d checks, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)
