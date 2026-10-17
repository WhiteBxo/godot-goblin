extends SceneTree

var _checks: int = 0
var _failures: Array[String] = []
var _state: Node
var _game: MainGame
var _director: StoryDirector
var _manager: DialogueManager
var _ui: DialogueUI
var _steps: Array[String] = []
var _finished: Array[Dictionary] = []
var _skipped: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)


func _frames(count: int = 3) -> void:
	for index in range(count):
		await process_frame


func _tap(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await _frames()
	event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	Input.parse_input_event(event)
	await _frames()


func _until(predicate: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec() + 2500
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(predicate.call(), message)


func _new_game() -> void:
	_game = load("res://src/core/main.tscn").instantiate()
	root.add_child(_game)
	_director = _game.get_story_director()
	_manager = _game.get_dialogue_manager()
	_ui = _game.get_node("PopupLayer/DialogueUI")
	_director.step_started.connect(func(_id: String, _index: int, command: String) -> void: _steps.append(command))
	_director.event_finished.connect(func(id: String, ok: bool, reason: String) -> void: _finished.append({"id": id, "ok": ok, "reason": reason}))
	_director.step_skipped.connect(func(_id: String, _index: int, reason: String) -> void: _skipped.append(reason))
	_check(_director.load_events("res://tests/fixtures/story_events.json") == OK, "Test events load")


func _dispose() -> void:
	_game.queue_free()
	await _frames()


func _run() -> void:
	_state = root.get_node("GameState")
	var before: Dictionary = _state.to_dict()
	_test_library()
	_state.reset_state()
	_new_game()
	_test_unconfigured()
	await _test_conditions()
	await _test_sequence()
	await _test_cancel_and_errors()
	await _test_choices()
	await _test_reentry()
	await _dispose()
	await _test_lifecycle()
	await _test_demo_and_routes()
	await _test_stage_pages()
	_state.restore_state(before)
	print("STORY_DIRECTOR: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _test_library() -> void:
	var library := StoryLibrary.new()
	_check(library.load_file("res://missing_story.json") == ERR_FILE_NOT_FOUND, "Missing file returns error")
	_check(library.load_file("res://src/resources/story/day1_demo_events.json") == OK, "Day-one data validates")
	var copy := library.get_event("day1.intro")
	copy["steps"].clear()
	_check(not library.get_event("day1.intro")["steps"].is_empty(), "Catalogue returns deep copies")
	_check(library.load_json("{") == ERR_PARSE_ERROR and "line" in library.last_error, "Parse diagnostics include line")
	for invalid: Variant in [[], {"version": true, "events": {}}, {"version": 2, "events": {}}, {"version": 1, "events": {"bad": {"steps": []}}}]:
		_check(library.load_json(JSON.stringify(invalid)) == ERR_INVALID_DATA, "Invalid root rejected")
	for event: Dictionary in [
		{"steps": []}, {"steps": [{"command": "unknown"}]}, {"once": 1, "steps": [{"command": "wait", "seconds": 0}]},
		{"steps": [{"command": "wait", "seconds": -1}]}, {"steps": [{"command": "wait", "seconds": true}]},
		{"steps": [{"command": "dialogue", "id": ""}]}, {"steps": [{"command": "set_flag", "key": "bad"}]},
		{"steps": [{"command": "set_flag", "key": "test.ok", "value": 1}]}, {"steps": [{"command": "set_stage", "value": false}]},
		{"steps": [{"command": "play_sfx", "path": "user://bad.wav"}]}, {"steps": [{"command": "wait", "seconds": 0, "typo": 1}]},
		{"conditions": {"day": 1.5}, "steps": [{"command": "wait", "seconds": 0}]},
		{"conditions": {"flags": {"bad": true}}, "steps": [{"command": "wait", "seconds": 0}]},
		{"conditions": {"completed_events": "test.bad"}, "steps": [{"command": "wait", "seconds": 0}]},
		{"conditions": {"choice": {"dialogue": "x", "line": "y", "id": "z"}}, "steps": [{"command": "wait", "seconds": 0}]},
		{"conditions": {"typo": true}, "steps": [{"command": "wait", "seconds": 0}]},
		{"steps": [{"command": "wait", "seconds": 0, "when": {"choice": {"id": "x"}}}]}
	]:
		_check(library.load_json(JSON.stringify({"version": 1, "events": {"test.invalid": event}})) == ERR_INVALID_DATA and "test.invalid" in library.last_error, "Invalid event/step rejected with context")
		_check(not library.get_event("day1.intro").is_empty(), "Invalid loads retain prior catalogue")


func _test_unconfigured() -> void:
	var director := StoryDirector.new()
	_check(director.request_event("test.wait") == ERR_UNCONFIGURED, "Detached director cannot start")
	_check(director.request_interaction("orders") == ERR_UNCONFIGURED, "Detached interaction request is safe")
	root.add_child(director)
	_check(director.request_event("test.wait") == ERR_UNCONFIGURED, "Director requires manager configuration")
	director.configure(_manager)
	_check(director.request_interaction("orders") == ERR_DOES_NOT_EXIST, "Empty catalogue permits ShopUI fallback")
	director.event_file = "res://missing_story.json"
	_check(director.request_event("test.wait") == ERR_FILE_NOT_FOUND and not director.last_error.is_empty(), "Lazy load preserves resource error code")
	_check(director.request_interaction("orders") == ERR_FILE_NOT_FOUND, "Invalid catalogue reports error instead of silently opening ShopUI")
	director.free()


func _test_conditions() -> void:
	_check(_director.get_parent() == _game.get_node("Systems"), "MainGame owns director under Systems")
	_check(_director.request_event("missing.event") == ERR_DOES_NOT_EXIST and not _director.last_error.is_empty(), "Unknown event reports diagnostic")
	_check(_director.request_event("test.conditions") == ERR_UNAUTHORIZED, "Day/flags/stage gate event")
	_state.set_current_day(2)
	_state.set_story_stage("test.ready")
	_state.set_flag("test.ready")
	_check(_director.request_event("test.conditions") == ERR_UNAUTHORIZED, "Completed prerequisite required")
	_state.complete_event("test.prerequisite")
	_state.set_flag("test.blocked")
	_check(_director.request_event("test.conditions") == ERR_UNAUTHORIZED, "False flag condition blocks true flag")
	_state.set_flag("test.blocked", false)
	_state.complete_event("test.forbidden")
	_check(_director.request_event("test.conditions") == ERR_UNAUTHORIZED, "Forbidden completed event blocks trigger")
	var snapshot: Dictionary = _state.to_dict()
	snapshot["completed_events"].erase("test.forbidden")
	_state.restore_state(snapshot)
	_check(_director.request_event("test.conditions") == OK, "All conditions allow start")
	await _until(func() -> bool: return not _director.is_busy(), "Condition event completes")
	_check(_state.get_flag("test.passed") and _state.is_event_completed("test.conditions"), "Successful once event records completion")
	_check(_director.request_event("test.conditions") == ERR_ALREADY_EXISTS, "Completed once event cannot repeat")
	for index in range(2):
		_check(_director.request_event("test.repeat") == OK, "Repeatable event can run again")
		await _until(func() -> bool: return not _director.is_busy(), "Repeatable event completes")
	_check(not _state.is_event_completed("test.repeat"), "Repeatable events do not enter one-shot ledger")


func _test_sequence() -> void:
	_steps.clear()
	var player := _game.get_player() as PlayerController
	var interaction: ShopInteraction = _game.get_node("Systems/ShopInteraction")
	_check(_director.request_event("test.sequence") == OK and not player.movement_enabled and not interaction.is_input_enabled(), "Story start locks synchronously")
	_check(_director.request_event("test.sequence") == ERR_BUSY and _director.request_interaction("orders") == ERR_BUSY, "Concurrent event and interaction rejected")
	_check(_director.load_events() == ERR_BUSY, "Active catalogue cannot reload")
	await _frames(5)
	_check(_state.get_flag("test.first") and _state.story_stage != "test.waited", "Steps execute in order before wait")
	_check(_manager.start_dialogue("demo.greeting") == ERR_BUSY, "Host reserves dialogue manager during story wait")
	paused = true
	await create_timer(0.18, true).timeout
	_check(_state.story_stage != "test.waited", "Story wait pauses with Systems")
	paused = false
	await _until(_manager.is_active, "Sequence reaches dialogue after wait")
	await create_timer(0.08).timeout
	_check(not _state.get_flag("test.after_dialogue") and _director.is_busy(), "Sequence waits for actual dialogue completion")
	_ui.reveal_all()
	_manager.advance()
	_check(not player.movement_enabled and not interaction.is_input_enabled(), "Between-dialogue gap retains original story lock")
	await _until(func() -> bool: return not _director.is_busy(), "Sequence completes after dialogue")
	_check(_steps == ["set_flag", "wait", "set_stage", "dialogue", "set_flag"], "Exact JSON execution order")
	_check(_state.get_flag("test.after_dialogue") and player.movement_enabled and interaction.is_input_enabled(), "Completion applies trailing flag and restores controls")
	_check(_finished.back()["ok"] and _state.is_event_completed("test.sequence"), "Natural end records success")


func _test_cancel_and_errors() -> void:
	var player := _game.get_player() as PlayerController
	var interaction: ShopInteraction = _game.get_node("Systems/ShopInteraction")
	player.set_movement_enabled(false)
	interaction.set_input_enabled(false)
	_director.request_event("test.dialogue")
	await _until(_manager.is_active, "Cancellation event reaches dialogue")
	_manager.end_dialogue(true)
	_check(not _director.is_busy() and not _state.is_event_completed("test.dialogue") and not _state.get_flag("test.after_cancel"), "Cancelled dialogue never completes event or trailing steps")
	_check(not player.movement_enabled and not interaction.is_input_enabled(), "Cancel preserves already-disabled controls")
	player.set_movement_enabled(true)
	interaction.set_input_enabled(true)
	_director.request_event("test.wait")
	await _frames()
	_director.cancel_event()
	var count := _finished.size()
	_director.cancel_event()
	await create_timer(0.2).timeout
	_check(not _state.get_flag("test.after_wait") and _finished.size() == count, "Wait cancel stops timer and finishes exactly once")
	_check(player.movement_enabled and not _state.is_event_completed("test.wait"), "Wait cancel restores controls without recording success")
	_director.request_event("test.missing_dialogue")
	await _until(func() -> bool: return not _director.is_busy(), "Missing dialogue aborts")
	_check(not _state.is_event_completed("test.missing_dialogue") and not _state.get_flag("test.after_error") and "steps[0]" in _director.last_error, "Dialogue resource failure has event/step diagnostic and no success")
	_check(_director.load_events("res://missing.json") == ERR_FILE_NOT_FOUND, "Failed reload reports error")
	_skipped.clear()
	_director.request_event("test.sfx")
	await _until(func() -> bool: return not _director.is_busy(), "Optional sound failures do not block sequence")
	_check(_skipped.size() == 2 and _state.is_event_completed("test.sfx"), "Missing and wrong-type audio skip safely")
	_director.request_event("test.wait")
	await _frames()
	var restored: Dictionary = _state.to_dict()
	restored["story_stage"] = "test.restored"
	_state.restore_state(restored)
	_check(not _director.is_busy(), "State restoration cancels active wait")
	_director.request_event("test.wait")
	await _frames()
	_state.reset_state()
	_check(not _director.is_busy() and not _state.is_event_completed("test.wait"), "State reset cancels active sequence")


func _test_choices() -> void:
	_check(_manager.load_dialogues("res://tests/fixtures/dialogue_edge_cases.json") == OK, "Choice test catalogue loads")
	_director.request_event("test.choice")
	await _until(_manager.is_active, "Choice event waits on dialogue")
	var line := _manager.get_current_line_id()
	_manager.select_choice(0)
	_check(not _director.get_choice("test.immediate_choice", line).is_empty(), "Director receives terminal choice before dialogue ends")
	await _until(func() -> bool: return not _director.is_busy(), "Choice event completes")
	_check(_state.get_flag("test.chosen") and not _state.get_flag("test.wrong"), "JSON when conditions consume stable choice IDs")
	_manager.load_dialogues()


func _test_reentry() -> void:
	var cancel_on_step := func(_id: String, _index: int, _command: String) -> void: _director.cancel_event("Listener cancelled")
	_director.step_started.connect(cancel_on_step)
	_director.request_event("test.wait")
	await _frames()
	_check(not _director.is_busy() and not _state.get_flag("test.after_wait"), "Synchronous step callback can cancel without executing command")
	_director.step_started.disconnect(cancel_on_step)
	var on_finish := func(_id: String, _ok: bool, _reason: String) -> void: _check(_director.request_event("test.wait") == ERR_BUSY, "Finish callback cannot recursively start another event")
	_director.event_finished.connect(on_finish)
	_director.request_event("test.wait")
	_director.cancel_event()
	_director.event_finished.disconnect(on_finish)
	var on_complete := func(_id: String) -> void: _check(_director.request_event("test.wait") == ERR_BUSY, "Success callback cannot recursively start another event")
	_director.event_completed.connect(on_complete)
	_director.request_event("test.repeat")
	await _until(func() -> bool: return not _director.is_busy(), "Success callback test completes")
	_check(_finished.back()["ok"] and _finished.back()["reason"].is_empty(), "Rejected callback request cannot corrupt successful finish payload")
	_director.event_completed.disconnect(on_complete)


func _test_lifecycle() -> void:
	for removed: String in ["ui", "manager", "manager_wait", "director", "scene"]:
		_state.reset_state()
		_new_game()
		_director.request_event("test.dialogue" if removed in ["ui", "manager"] else "test.wait")
		if removed in ["ui", "manager"]:
			await _until(_manager.is_active, "Lifecycle test reaches dialogue")
		else:
			await _frames()
		var count := _finished.size()
		match removed:
			"ui": _ui.queue_free()
			"manager", "manager_wait": _manager.queue_free()
			"director": _director.queue_free()
			"scene": _game.queue_free()
		await _frames(5)
		_check(_finished.size() == count + 1 and not _finished.back()["ok"], "Removing %s cancels once" % removed)
		_check(not _state.is_event_completed("test.dialogue") and not _state.is_event_completed("test.wait"), "Scene lifecycle never records false completion")
		if removed != "scene":
			_check((_game.get_player() as PlayerController).movement_enabled, "Removing %s releases host lock" % removed)
			await _dispose()
		await create_timer(0.17).timeout
		_check(not _state.get_flag("test.after_wait"), "No stale timer mutates state after scene removal")


func _test_demo_and_routes() -> void:
	_state.reset_state()
	var demo: Node = load("res://src/debug/story/story_demo.tscn").instantiate()
	root.add_child(demo)
	_game = demo.get_node("MainGame")
	_director = _game.get_story_director()
	_manager = _game.get_dialogue_manager()
	_ui = _game.get_node("PopupLayer/DialogueUI")
	var player := _game.get_player() as PlayerController
	var shop_ui: ShopUI = _game.get_node("HudLayer/ShopUI")
	await _until(_manager.is_active, "Standalone demo auto-starts opening")
	_check(not player.movement_enabled and not shop_ui.is_open(), "Demo uses MainGame lock without competing ShopUI")
	if "--capture" in OS.get_cmdline_user_args():
		_ui.reveal_all()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/story-demo-intro.png")
	_manager.end_dialogue(true)
	var orders: InteractionPoint
	var other: Array[InteractionPoint] = []
	for point in (_game.get_active_level() as MilkTeaShop).get_interaction_points():
		if point.interaction_id == &"orders":
			orders = point
		else:
			other.append(point)
	player.global_position = orders.global_position
	for index in range(4):
		await physics_frame
	orders.interact()
	await _until(_manager.is_active, "Existing orders point routes to story")
	orders.interact()
	_check(_manager.get_current_line_id() == "board" and not shop_ui.is_open(), "Orders before intro opens exactly one dialogue despite duplicate signal")
	_ui.reveal_all()
	_manager.advance()
	await _until(func() -> bool: return not _director.is_busy(), "Before-intro route completes")
	_check(_director.request_event("day1.intro") == OK, "Cancelled opening may retry")
	await _until(_manager.is_active, "Opening dialogue starts again")
	_ui.reveal_all()
	_manager.advance()
	await create_timer(0.25).timeout
	_check(not _manager.is_active() and not player.movement_enabled, "Demo keeps control locked through 0.8 second pause")
	await _until(_manager.is_active, "Demo plays reaction after pause and sound")
	_ui.reveal_all()
	_manager.advance()
	await _until(func() -> bool: return not _director.is_busy(), "Demo intro finishes")
	_check(_state.get_flag("day1.intro_finished") and _state.is_event_completed("day1.intro") and player.movement_enabled, "Demo updates flag and one-shot completion and restores movement")
	_check(_director.request_event("day1.intro") == ERR_ALREADY_EXISTS, "Demo cannot replay completed intro")
	await _tap(KEY_E)
	await _until(_manager.is_active, "E on orders after intro routes to different dialogue")
	_ui.reveal_all()
	if "--capture" in OS.get_cmdline_user_args():
		await _frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/story-demo-orders.png")
	_manager.select_choice(0)
	await _until(func() -> bool: return not _director.is_busy(), "After-intro choice completes")
	_check(_director.get_choice("day1.orders_after", "board") == "investigate" and _state.get_flag("day1.order_checked"), "Demo choice drives JSON flag step")
	_check(not shop_ui.is_open(), "Story routes never open shop popup")
	for point in other:
		player.global_position = point.global_position
		for index in range(4):
			await physics_frame
		point.interact()
		_check(shop_ui.is_open() and not _manager.is_active(), "Unmapped %s retains ShopUI" % point.interaction_id)
		_check(_director.request_event("day1.orders_after") == ERR_BUSY, "ShopUI blocks story start")
		shop_ui.close()
	demo.queue_free()
	await _frames()
	# Fresh production MainGame must never load or autoplay demo data.
	_new_game()
	_check(not _director.is_busy() and not _manager.is_active(), "Production scene never auto-plays unfinished story")
	await _dispose()

func _test_stage_pages() -> void:
	_state.reset_state()
	_new_game()
	_director.load_events("res://src/resources/story/order_bridge_demo.json")
	_manager.load_dialogues("res://src/resources/dialogue/order_bridge_demo.json")
	_state.set_story_stage("day1.before_order")
	_check(_director.request_interaction("orders") == ERR_DOES_NOT_EXIST, "Page route requires completed opening")
	_state.complete_event("order_demo.intro")
	_check(_director.request_interaction("orders") == OK, "Before-order page selects tutorial")
	await _until(_manager.is_active, "Tutorial page reaches dialogue")
	_ui.reveal_all()
	_manager.advance()
	await _until(func() -> bool: return not _director.is_busy(), "Tutorial page finishes")
	_check(_state.story_stage == "day1.waiting_order" and _director.request_interaction("orders") == ERR_DOES_NOT_EXIST, "Waiting stage leaves order board to ShopUI fallback")
	_state.set_story_stage("day1.after_order")
	_check(_director.request_interaction("orders") == ERR_DOES_NOT_EXIST, "After-order page requires real delivery and continuation")
	_state.complete_event("order_demo.after_order")
	_state.set_flag("shop.order_001_delivered")
	_check(_director.request_interaction("orders") == OK, "After-order page selects special dialogue")
	await _until(_manager.is_active, "Special page reaches dialogue")
	_ui.reveal_all()
	_manager.advance()
	await _until(func() -> bool: return not _director.is_busy(), "Special page finishes")
	_check(_director.request_interaction("orders") == ERR_DOES_NOT_EXIST, "Consumed once page falls back")
	_check(_director.request_interaction("storage") == ERR_DOES_NOT_EXIST, "Unmapped point keeps fallback")
	# Document/test first-match priority instead of changing runtime routing semantics.
	var path := "user://route-overlap-%d.json" % OS.get_process_id()
	var data := {"version": 1, "events": {
		"route.broad": {"once": false, "trigger": "orders", "conditions": {"stage": "route.overlap"}, "steps": [{"command": "set_flag", "key": "route.broad"}]},
		"route.special": {"once": false, "trigger": "orders", "conditions": {"stage": "route.overlap", "flags": {"route.special_enabled": true}}, "steps": [{"command": "set_flag", "key": "route.special"}]}
	}}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	_director.load_events(path)
	_state.set_story_stage("route.overlap")
	_state.set_flag("route.special_enabled")
	_director.request_interaction("orders")
	await _until(func() -> bool: return not _director.is_busy(), "Overlapping fixture completes")
	_check(_state.get_flag("route.broad") and not _state.get_flag("route.special"), "Earlier broad event masks later specific event")
	data.events["route.broad"].conditions["flags"] = {"route.special_enabled": false}
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	_director.load_events(path)
	_director.request_interaction("orders")
	await _until(func() -> bool: return not _director.is_busy(), "Disjoint route fixture completes")
	_check(_state.get_flag("route.special"), "Mutually exclusive flags fix route shadowing through data")
	DirAccess.remove_absolute(path)
	await _dispose()
