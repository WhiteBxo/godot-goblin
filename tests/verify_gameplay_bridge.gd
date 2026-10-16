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

func _new_demo() -> void:
	_state.reset_state()
	_demo = load("res://src/debug/gameplay_bridge/gameplay_bridge_demo.tscn").instantiate()
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
	_state.restore_state(before)
	await create_timer(0.1).timeout # Let the audio mixer release stopped playback.
	print("GAMEPLAY_BRIDGE: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_authoring_artifacts() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/story_authoring/gameplay_bridge_demo_bridge.json"))
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
	_check(manifest.beats[1].phase == phases.phases[0], "Player Beat maps to exact runtime phase data")
	for beat: Dictionary in manifest.beats:
		_check(source.contains("## Beat " + beat.id), "Mapped Beat exists in Markdown")
		if beat.mode == "自动演出":
			_check(story.get_event(beat.event).steps.size() == beat.count and beat.start == 0, "Cinematic Beat covers generated event")
		else:
			var phase: Dictionary = beat.phase
			_check(not story.get_event(phase.after_event).is_empty() and not story.get_event(phase.next_event).is_empty(), "Phase references real neighboring events")
			var conditions: Dictionary = story.get_event(phase.next_event).conditions
			_check(conditions.stage == phase.stage and conditions.flags[phase.completion_flag] and phase.after_event in conditions.completed_events, "Continuation has all three GameState guards")

func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))

func _test_multiple_phases() -> void:
	_new_demo()
	var prefix := "/private/tmp/goblin-bridge-%d" % OS.get_process_id()
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
	var path := "/private/tmp/goblin-bridge-error-%d.json" % OS.get_process_id()
	for failure: String in ["unknown_event", "synchronous_cancel"]:
		_new_demo()
		var errors: Array[int] = []
		_bridge.continuation_failed.connect(func(_event: String, error: Error) -> void: errors.append(error))
		if failure == "unknown_event":
			var phases: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PHASES))
			phases.phases[0].next_event = "bridge.missing"
			_write_json(path, phases)
			_check(_bridge.load_phases(path) == OK, "Unknown continuation has a valid phase schema")
		else:
			_director.event_started.connect(func(id: String) -> void:
				if id == "bridge.after_tea":
					_director.cancel_event("Synchronous listener cancellation")
				)
		await _intro()
		_shop.open(_station)
		_finish_recipe()
		_shop.close()
		await _frames(12)
		_check(not _director.is_busy() and (_game.get_player() as PlayerController).movement_enabled, "Continuation failure releases host lock: " + failure)
		if failure == "unknown_event":
			_check(errors == [ERR_DOES_NOT_EXIST] and not _bridge.last_error.is_empty(), "Rejected continuation reports once without retry spam")
		else:
			_check(_started == ["bridge.intro", "bridge.after_tea"] and _bridge.allows_story_start(), "Synchronous cancellation clears reservation without reentry")
		await _dispose()
	DirAccess.remove_absolute(path)
