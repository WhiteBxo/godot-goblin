extends SceneTree

const PHASES := "res://src/resources/story/gameplay_bridge_demo_phases.json"
var _failures: Array[String] = []
var _checks := 0
var _demo: Node
var _game: MainGame
var _director: StoryDirector
var _bridge: GameplayBridge
var _tea: TeaMaking
var _shop: ShopUI
var _station: InteractionPoint
var _started: Array[String] = []
var _state: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames(count: int = 4) -> void:
	for index in range(count):
		await process_frame

func _until(predicate: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(predicate.call(), message)

func _new_demo(path: String = "res://src/debug/gameplay_bridge/gameplay_bridge_demo.tscn") -> void:
	_state.reset_state()
	_demo = load(path).instantiate()
	_demo.autoplay = false
	root.add_child(_demo)
	_game = _demo.game
	_director = _game.get_story_director()
	_bridge = _game.get_gameplay_bridge()
	_tea = _game.get_tea_making()
	_shop = _game.get_shop_ui()
	_started.clear()
	_director.event_started.connect(func(id: String) -> void: _started.append(id))
	for point in (_game.get_active_level() as MilkTeaShop).get_interaction_points():
		if point.interaction_id == &"tea_station":
			_station = point

func _advance() -> void:
	_game.get_node("PopupLayer/DialogueUI").reveal_all()
	_game.get_dialogue_manager().advance()

func _intro() -> void:
	_check(_director.request_event("bridge.intro") == OK, "Opening starts")
	await _until(_game.get_dialogue_manager().is_active, "Opening reaches dialogue")
	_check(not (_game.get_player() as PlayerController).movement_enabled, "Busy story retains input lock")
	_check(not _tea.is_active(), "No objective while opening busy")
	_advance()
	await _until(_tea.is_active, "Successful opening activates gameplay")

func _finish_recipe() -> void:
	var buttons := _game.get_node("PopupLayer/Modal/Center/Panel/Margin/Content/Ingredients")
	for button: Button in buttons.get_children():
		_check(not button.disabled, "Ingredient button enabled: " + button.text)
		button.pressed.emit() # Exercise the same UI callbacks as mouse/keyboard activation.
	_check(_state.get_flag("bridge.tea_done"), "Popup buttons complete the registered recipe")

func _dispose() -> void:
	_demo.queue_free()
	await _frames()

func _run() -> void:
	_state = root.get_node("GameState")
	var before: Dictionary = _state.to_dict()
	_test_authoring_artifacts()
	_test_authoring_artifacts("res://docs/story_authoring/order_bridge_demo_bridge.json")
	_new_demo()
	_check(_director.request_event("bridge.after_tea") == ERR_UNAUTHORIZED, "Cannot jump past gameplay")
	_shop.open(_station)
	_check(_tea.add_ingredient("tea") == ERR_BUSY, "Early production rejected")
	_shop.close()
	await _intro()
	var player := _game.get_player() as PlayerController
	_check(player.movement_enabled, "Idle gameplay restores host movement")
	_check(_director.request_event("bridge.intro") == ERR_BUSY, "Gameplay reservation prevents unrelated story reentry")
	_check(_tea.add_ingredient("tea") == ERR_BUSY, "Closed station rejects production")
	player.global_position = _station.global_position
	for index in range(4):
		await physics_frame
	_station.interact()
	_check(_shop.is_open(), "Real ShopInteraction opens the tea station")
	_check(_tea.add_ingredient("milk") == ERR_INVALID_DATA, "Wrong order resets cup")
	_check(not _state.get_flag("bridge.tea_done"), "Wrong order never completes objective")
	_check(_tea.add_ingredient("tea") == OK, "First ingredient accepted")
	_shop.close()
	await _frames()
	_check(_started == ["bridge.intro"], "Closing unfinished cup never starts continuation")
	_shop.open(_station)
	_check(_tea.add_ingredient("milk") == OK, "Closing and reopening preserves cup")
	_game.get_ui_manager().set_paused(true)
	_check(_tea.add_ingredient("pearls") == ERR_BUSY, "Pause blocks production")
	_game.get_ui_manager().set_paused(false)
	_check(_tea.add_ingredient("pearls") == OK, "Last ingredient finishes recipe")
	_check(_state.get_flag("bridge.tea_done"), "Completion signal writes GameState flag")
	_check(_tea.add_ingredient("pearls") == ERR_BUSY, "Duplicate production rejected")
	_tea.recipe_completed.emit("pearl_milk_tea", -1)
	await _frames()
	_check(_started == ["bridge.intro"] and not _director.is_busy(), "Completed recipe waits for open popup")
	_check(not player.movement_enabled, "Popup keeps host input locked")
	_check(_game.get_audio_manager().get_bgm_state().playing, "Story BGM survives event into gameplay")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/gameplay-bridge-popup.png")
	_shop.close()
	_game.get_ui_manager().set_paused(true)
	await _frames()
	_check(_started.size() == 1, "Pending continuation waits for pause popup")
	_game.get_ui_manager().set_paused(false)
	await _until(_game.get_dialogue_manager().is_active, "Closing all popups starts next story")
	_check(_started == ["bridge.intro", "bridge.after_tea"] and not player.movement_enabled, "Continuation starts exactly once and locks input")
	_advance()
	await _until(func() -> bool: return _state.story_stage == "bridge.finished" and not _director.is_busy(), "Continuation completes")
	await _frames()
	_check(_started.size() == 2 and player.movement_enabled, "Finished chain never repeats and restores movement")
	_check(_game.get_audio_manager().get_bgm_state().playing, "Music survives the full chain")
	await _dispose()

	# Failed opening must never arm gameplay even if its stage was partially written.
	_new_demo()
	_director.request_event("bridge.intro")
	await _until(_game.get_dialogue_manager().is_active, "Cancel fixture reaches opening")
	_state.set_story_stage("bridge.make_tea")
	_director.cancel_event()
	await _frames()
	_check(not _tea.is_active() and not _state.get_flag("bridge.tea_done"), "Cancelled predecessor cannot activate goal")
	_check((_game.get_player() as PlayerController).movement_enabled, "Cancel releases original host lock")
	await _dispose()

	# Restore/reset invalidate an in-flight gameplay session and pending callbacks.
	_new_demo()
	await _intro()
	_shop.open(_station)
	_finish_recipe()
	var snapshot: Dictionary = _state.to_dict()
	_state.set_flag("bridge.external")
	_state.restore_state(snapshot)
	_shop.close()
	await _frames()
	_check(_started.size() == 1 and not _tea.is_active(), "Restore disables automatic continuation")
	_check(_bridge.load_phases(PHASES) == OK, "Host can explicitly resume restored phase")
	await _until(_game.get_dialogue_manager().is_active, "Completed snapshot resumes after explicit configuration")
	_director.cancel_event()
	await _frames(12)
	_check(_started.size() == 2 and not _director.is_busy(), "Cancelled continuation never automatically retries")
	await _dispose()

	_new_demo()
	await _intro()
	_shop.open(_station)
	_finish_recipe()
	_state.reset_state()
	_tea.recipe_completed.emit("pearl_milk_tea", 1)
	_shop.close()
	await _frames()
	_check(_started.size() == 1 and not _state.get_flag("bridge.tea_done"), "Reset rejects stale completion and pending continuation")
	await _dispose()

	_new_demo()
	await _intro()
	_state.set_story_stage("bridge.external")
	await _frames()
	_check(not _tea.is_active(), "External stage change cancels active objective")
	await _dispose()

	for service: String in ["bridge", "director", "ui", "tea"]:
		_new_demo()
		await _intro()
		_shop.open(_station)
		_finish_recipe()
		match service:
			"bridge": _bridge.queue_free()
			"director": _director.queue_free()
			"ui": _game.get_ui_manager().queue_free()
			"tea": _tea.queue_free()
		await _frames()
		_check(not _state.is_event_completed("bridge.after_tea"), "Removing %s never starts stale story" % service)
		await _dispose()
	await _test_multiple_phases()
	await _test_continuation_errors()
	await _test_recipe_restart()
	await _test_real_orders()
	await _test_flag_waits()
	_state.restore_state(before)
	await create_timer(0.1).timeout # Let the audio mixer release stopped playback.
	print("GAMEPLAY_BRIDGE: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_authoring_artifacts(path: String = "res://docs/story_authoring/gameplay_bridge_demo_bridge.json") -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var source := FileAccess.get_file_as_string(manifest.source)
	_check(source.sha256_text() == manifest.source_sha256, "Authoring source SHA-256 matches generated artifacts")
	var story := StoryLibrary.new()
	var dialogue := DialogueLibrary.new()
	_check(story.load_file(manifest.story) == OK, "Original StoryLibrary validates generated events")
	_check(dialogue.load_file(manifest.dialogue) == OK, "Original DialogueLibrary validates generated dialogue")
	var dialogue_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest.dialogue))
	for entry: Dictionary in dialogue_data.dialogues.values():
		for line: Dictionary in entry.lines.values():
			_check(source.contains(line.text), "Generated dialogue is verbatim from Markdown")
	var phases: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest.phases))
	for beat: Dictionary in manifest.beats:
		_check(source.contains("## Beat " + beat.id), "Mapped Beat exists in Markdown")
		if beat.mode == "自动演出":
			_check(story.get_event(beat.event).steps.size() == beat.count and beat.start == 0, "Cinematic Beat covers generated event")
		elif beat.has("trigger"):
			_check(story.get_event(beat.expected_event).trigger == beat.trigger, "Interaction Beat maps to existing trigger route")
		else:
			var phase: Dictionary = beat.phase
			_check(phase in phases.phases, "Player Beat maps to exact runtime phase data")
			_check(not story.get_event(phase.after_event).is_empty() and not story.get_event(phase.next_event).is_empty(), "Phase references real neighboring events")
			var conditions: Dictionary = story.get_event(phase.next_event).conditions
			_check(conditions.stage == phase.stage and conditions.flags[phase.completion_flag] and phase.after_event in conditions.completed_events, "Continuation has all three GameState guards")

func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))

func _test_multiple_phases() -> void:
	_new_demo()
	var prefix := "user://goblin-bridge-%d" % OS.get_process_id()
	var story_path := prefix + "-story.json"
	var phases_path := prefix + "-phases.json"
	var events: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/resources/story/gameplay_bridge_demo.json"))
	events.events["bridge.after_tea"].steps = [{"command": "set_stage", "value": "bridge.second_cup"}]
	events.events["bridge.final"] = {"conditions": {"stage": "bridge.second_cup", "completed_events": ["bridge.after_tea"], "flags": {"bridge.second_done": true}}, "steps": [{"command": "set_stage", "value": "bridge.finished"}]}
	_write_json(story_path, events)
	var phases: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PHASES))
	phases.phases.append({"id": "bridge.second_cup", "after_event": "bridge.after_tea", "stage": "bridge.second_cup", "recipe": "pearl_milk_tea", "completion_flag": "bridge.second_done", "next_event": "bridge.final"})
	_write_json(phases_path, phases)
	_check(_director.load_events(story_path) == OK and _bridge.load_phases(phases_path) == OK, "Data alone configures multiple gameplay phases")
	# Invalid reloads must retain the prior valid configuration.
	for bad: Dictionary in [{"version": true, "phases": []}, {"version": 1, "phases": [{"id": "bad"}]}]:
		_write_json(phases_path, bad)
		_check(_bridge.load_phases(phases_path) == ERR_INVALID_DATA, "Malformed phase rejected transactionally")
	var duplicate: Dictionary = phases.duplicate(true)
	duplicate.phases.append(duplicate.phases[0])
	_write_json(phases_path, duplicate)
	_check(_bridge.load_phases(phases_path) == ERR_INVALID_DATA, "Duplicate phase identities rejected")
	await _intro()
	_shop.open(_station)
	_finish_recipe()
	_shop.close()
	await _until(func() -> bool: return _state.story_stage == "bridge.second_cup" and _tea.is_active(), "First continuation activates second gameplay phase")
	_check(not _state.get_flag("bridge.second_done"), "Earlier cup cannot satisfy later objective")
	_tea.recipe_completed.emit("pearl_milk_tea", -1)
	_check(not _state.get_flag("bridge.second_done"), "Stale session completion ignored")
	_shop.open(_station)
	for button: Button in _game.get_node("PopupLayer/Modal/Center/Panel/Margin/Content/Ingredients").get_children():
		button.pressed.emit()
	_check(_state.get_flag("bridge.second_done"), "Second session completes its own flag")
	_shop.close()
	await _until(func() -> bool: return _state.is_event_completed("bridge.final"), "Second continuation finishes through original StoryDirector")
	_check(_started == ["bridge.intro", "bridge.after_tea", "bridge.final"], "Multiple phases preserve exact order without duplicates")
	await _dispose()
	DirAccess.remove_absolute(story_path)
	DirAccess.remove_absolute(phases_path)

func _test_continuation_errors() -> void:
	var path := "user://goblin-bridge-error-%d.json" % OS.get_process_id()
	for failure: String in ["unknown_event", "synchronous_cancel", "busy_reject"]:
		_new_demo()
		var errors: Array[int] = []
		_bridge.continuation_failed.connect(func(_event: String, error: Error) -> void: errors.append(error))
		if failure == "unknown_event":
			var phases: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PHASES))
			phases.phases[0].next_event = "bridge.missing"
			_write_json(path, phases)
			_check(_bridge.load_phases(path) == OK, "Unknown continuation has a valid phase schema")
		elif failure == "synchronous_cancel":
			_director.event_started.connect(func(id: String) -> void:
				if id == "bridge.after_tea":
					_director.cancel_event("Synchronous listener cancellation")
				)
		await _intro()
		if failure == "busy_reject":
			_director.configure(_game.get_dialogue_manager(), func() -> bool: return false)
		_shop.open(_station)
		_finish_recipe()
		_shop.close()
		await _frames(12)
		_check(not _director.is_busy() and (_game.get_player() as PlayerController).movement_enabled, "Continuation failure releases host lock: " + failure)
		if failure == "unknown_event":
			_check(errors == [ERR_DOES_NOT_EXIST] and not _bridge.last_error.is_empty(), "Rejected continuation reports once without retry spam")
		elif failure == "busy_reject":
			_check(errors == [ERR_BUSY] and _bridge.allows_story_start(), "Unexpected BUSY rejection reports once and stops automatic retries")
		else:
			_check(_started == ["bridge.intro", "bridge.after_tea"] and _bridge.allows_story_start(), "Synchronous cancellation clears reservation without reentry")
		await _dispose()
	DirAccess.remove_absolute(path)

func _order_opening() -> void:
	_director.request_event("order_demo.intro")
	await _until(_game.get_dialogue_manager().is_active, "Order opening reaches dialogue")
	_advance()
	await _until(func() -> bool: return not _director.is_busy(), "Order opening completes")

func _order_board() -> InteractionPoint:
	for point in (_game.get_active_level() as MilkTeaShop).get_interaction_points():
		if point.interaction_id == &"orders":
			return point
	return null

func _interact(point: InteractionPoint) -> void:
	_game.get_player().global_position = point.global_position
	for index in range(4):
		await physics_frame
	point.interact()

func _test_real_orders() -> void:
	var order_scene := "res://src/debug/gameplay_bridge/order_bridge_demo.tscn"
	_new_demo(order_scene)
	var production := _game.get_tea_production()
	await _order_opening()
	await _interact(_order_board())
	await _until(_game.get_dialogue_manager().is_active, "Real order board routes to tutorial")
	_check(not _shop.is_open(), "Before-order route never opens competing ShopUI")
	_advance()
	await _until(func() -> bool: return not _director.is_busy(), "Tutorial finishes before player gameplay")
	await _frames()
	_check(not _tea.is_active(), "Real order phase never starts demonstration recipe")
	await _interact(_order_board())
	_check(_shop.is_open() and not _director.is_busy(), "Waiting-order stage falls back to real order UI")
	_shop.close()
	await _interact(_station)
	var panel: CraftingPanel = _game.get_node("PopupLayer/Modal/Center/Panel/Margin/Content/ProductionPanel")
	panel.clear_selection()
	panel.submit()
	_check(production.get_completed_count() == 0 and not _state.get_flag("shop.order_001_delivered"), "Failed UI recipe cannot satisfy production fact")
	production.get_inventory().try_consume({"pearl": 8})
	_check(not production.make_drink(["black_tea", "creamer", "pearl", "syrup"]).ok and not _state.get_flag("shop.order_001_delivered"), "Insufficient stock never records delivery")
	production.get_inventory().add_ingredient("pearl", 8)
	_tea.recipe_completed.emit("pearl_milk_tea", 1)
	_check(not _state.get_flag("order_demo.delivery_done"), "TeaMaking signal cannot satisfy real order phase")
	panel.clear_selection()
	for id: String in ["black_tea", "creamer", "pearl", "syrup"]:
		panel.add_material(id)
	panel.submit()
	_check(production.get_completed_count() == 1 and not _state.get_flag("shop.order_001_delivered"), "UI crafting creates a carried cup without delivery facts")
	_check(_game.get_task_delivery().try_deliver("order_001", "pearl_milk_tea", "fat_goblin").ok, "Actual NPC delivery records unique order fact")
	var business_before: Dictionary = _state.to_dict()
	production.changed.emit()
	production.changed.emit()
	_check(_state.to_dict() == business_before, "Repeated production notifications never recount a delivery")
	await _frames()
	_check(_state.get_flag("order_demo.delivery_done") and _started.size() == 2, "Flag wait records objective while shop popup delays continuation")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/order-bridge-popup.png")
	_game.get_ui_manager().set_paused(true)
	_shop.close()
	await _frames()
	_check(_started.size() == 2, "Real order completion waits through pause modal")
	_game.get_ui_manager().set_paused(false)
	await _until(_game.get_dialogue_manager().is_active, "Delivery continues story after UI and pause close")
	_check(not (_game.get_player() as PlayerController).movement_enabled, "Continuation retains MainGame input lock")
	_advance()
	await _until(func() -> bool: return not _director.is_busy(), "Real order continuation completes")
	await _interact(_order_board())
	await _until(_game.get_dialogue_manager().is_active, "Same board routes to after-order dialogue")
	_advance()
	await _until(func() -> bool: return not _director.is_busy(), "After-order once dialogue finishes")
	await _interact(_order_board())
	_check(_shop.is_open() and _started == ["order_demo.intro", "order_demo.tutorial", "order_demo.after_order", "order_demo.board_after"], "Consumed once route falls back without duplicate events")
	_shop.close()
	_check((_game.get_player() as PlayerController).movement_enabled, "Whole flow restores movement")
	await _dispose()
	# This unique fixed order explicitly accepts historical deliveries.
	_new_demo(order_scene)
	_check(_game.get_tea_production().make_drink(["black_tea", "creamer", "pearl", "syrup"]).ok, "Early crafting succeeds as gameplay")
	_check(_game.get_task_delivery().accept_order("order_001") == OK and _game.get_task_delivery().deliver_to("fat_goblin").ok, "Early active order is actually delivered before the bridge phase")
	await _order_opening()
	await _interact(_order_board())
	await _until(_game.get_dialogue_manager().is_active, "Early delivery still requires board tutorial")
	_check(not _state.get_flag("order_demo.delivery_done"), "Historical result cannot skip predecessor")
	_advance()
	await _until(func() -> bool: return _started.has("order_demo.after_order"), "allow_existing accepts previously delivered order only after phase activation")
	_director.cancel_event()
	await _frames()
	_check(_started.count("order_demo.after_order") == 1, "Cancelled flag continuation is never retried")
	await _dispose()

func _test_flag_waits() -> void:
	_state.reset_state()
	_demo = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(_demo)
	_game = _demo as MainGame
	_director = _game.get_story_director()
	_bridge = _game.get_gameplay_bridge()
	_check(_bridge != null and _game.get_tea_making() == null and _game.get_tea_production() != null and _game.get_tea_production().get_inventory() == _game.get_warehouse_inventory(), "Production settlement assembles shared business inventory and flag bridge without demonstration dependencies")
	_check(not _director.is_busy(), "Formal settlement never starts demo story")
	var prefix := "user://flag-bridge-%d" % OS.get_process_id()
	var story_path := prefix + "-events.json"
	var phases_path := prefix + "-phases.json"
	var first := {"id": "flag.first", "after_event": "flag.before", "stage": "flag.first", "completion": {"flag": "game.first_done", "allow_existing": false}, "completion_flag": "flag.first_done", "next_event": "flag.between"}
	var second := {"id": "flag.second", "after_event": "flag.between", "stage": "flag.second", "completion": {"flag": "game.second_done", "allow_existing": false}, "completion_flag": "flag.second_done", "next_event": "flag.end"}
	var phases := {"version": 2, "phases": [first, second]}
	_write_json(phases_path, phases)
	_write_json(story_path, {"version": 1, "events": {
		"flag.before": {"steps": [{"command": "set_stage", "value": "flag.first"}]},
		"flag.between": {"conditions": {"stage": "flag.first", "completed_events": ["flag.before"], "flags": {"flag.first_done": true}}, "steps": [{"command": "set_stage", "value": "flag.second"}]},
		"flag.end": {"conditions": {"stage": "flag.second", "completed_events": ["flag.between"], "flags": {"flag.second_done": true}}, "steps": [{"command": "set_stage", "value": "flag.finished"}]}
	}})
	_check(_director.load_events(story_path) == OK and _bridge.load_phases(phases_path) == OK, "Flag-only phases configure in real settlement")
	for malformed: Dictionary in [{"flag": "game.first_done"}, {"flag": "flag.first_done", "allow_existing": true}, {"flag": "game.first_done", "allow_existing": 1}, {"flag": "game.first_done", "allow_existing": true, "expression": "x"}]:
		var invalid: Dictionary = phases.duplicate(true)
		invalid.phases[0].completion = malformed
		_write_json(phases_path, invalid)
		_check(_bridge.load_phases(phases_path) == ERR_INVALID_DATA, "V2 rejects ambiguous/unknown completion schema")
	_write_json(phases_path, phases)
	_state.set_flag("game.first_done")
	_state.set_flag("game.second_done")
	_director.request_event("flag.before")
	await _frames(8)
	_check(not _state.get_flag("flag.first_done") and not _state.is_event_completed("flag.between"), "Early true cannot satisfy current-phase condition")
	_state.set_flag("game.first_done", false)
	await _frames()
	var snapshot: Dictionary = _state.to_dict()
	_state.set_flag("game.first_done")
	await _frames()
	_check(_state.is_event_completed("flag.between") and not _state.get_flag("flag.second_done"), "New flag edge advances first phase without satisfying second")
	_state.restore_state(snapshot)
	_check(_state.to_dict() == snapshot, "Restore callbacks never mutate the restored snapshot")
	_state.set_flag("game.first_done")
	await _frames()
	_check(not _state.is_event_completed("flag.between"), "Restored wait requires explicit rebuild")
	_check(_bridge.load_phases(phases_path) == OK, "Explicit rebuild accepts saved armed wait")
	await _frames(8)
	_check(_state.is_event_completed("flag.between") and not _state.get_flag("flag.second_done"), "Saved arming accepts result without replaying completed opening")
	_state.set_flag("game.second_done", false)
	await _frames()
	_state.set_flag("game.second_done")
	_state.state_changed.emit()
	await _frames(8)
	_check(_state.is_event_completed("flag.end") and _state.story_stage == "flag.finished", "Two flag phases progress in exact order")
	# Reset and stage changes must not allow saved arming to leak across sessions.
	_state.reset_state()
	_bridge.load_phases(phases_path)
	_director.request_event("flag.before")
	await _frames(8)
	_state.set_story_stage("flag.external")
	_state.set_flag("game.first_done")
	await _frames()
	_check(not _state.is_event_completed("flag.between") and _bridge.allows_story_start(), "External stage change invalidates flag wait and reservation")
	_state.set_story_stage("flag.first")
	await _frames()
	_check(not _state.is_event_completed("flag.between"), "Reentering stage without explicit rebuild cannot revive canceled wait")
	await _dispose()
	_state.set_flag("game.first_done")
	await _frames()
	_check(not _state.is_event_completed("flag.between"), "Destroyed scene leaves no continuation callbacks")
	DirAccess.remove_absolute(story_path)
	DirAccess.remove_absolute(phases_path)

func _test_recipe_restart() -> void:
	_new_demo()
	await _intro()
	var old_session: int = _tea._session
	_tea.recipe_completed.emit("pearl_milk_tea", old_session)
	_check(not _state.get_flag("bridge.tea_done"), "Matching token alone cannot spoof actual recipe completion")
	_tea.begin("pearl_milk_tea")
	_tea.recipe_completed.emit("pearl_milk_tea", old_session)
	_check(not _state.get_flag("bridge.tea_done"), "Restarted gameplay invalidates the previously armed token")
	_bridge.load_phases(PHASES)
	await _frames()
	_tea.recipe_completed.emit("pearl_milk_tea", old_session)
	_check(not _state.get_flag("bridge.tea_done"), "Rebuilt gameplay rejects stale prior session")
	_shop.open(_station)
	_finish_recipe()
	_shop.close()
	await _until(_game.get_dialogue_manager().is_active, "New recipe session continues normally after rebuild")
	_director.cancel_event()
	await _dispose()
