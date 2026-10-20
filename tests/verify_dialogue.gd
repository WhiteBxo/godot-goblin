extends SceneTree

var _checks: int = 0
var _failures: Array[String] = []
var _starts: Array[String] = []
var _ends: Array[Dictionary] = []
var _selections: Array[String] = []
var _ui: DialogueUI
var _manager: DialogueManager


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)


func _frames(count: int = 2) -> void:
	for index in range(count):
		await physics_frame
	await process_frame
	await process_frame


func _tap(key: Key, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	await process_frame
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func _click(button: Control) -> void:
	await _click_position(button.get_global_rect().get_center())


func _click_position(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
		await process_frame


func _run() -> void:
	var state_before: Dictionary = root.get_node("GameState").call("to_dict")
	_test_library()
	await _test_flow()
	await _test_adhoc_lines()
	await _test_mouse_advance()
	await _test_presentation_timing()
	await _test_story_skip()
	await _test_fast_forward_and_auto()
	await _test_compact_ui()
	_test_edge_cases()
	await _test_choice_handoff()
	await _test_ui_unavailable()
	await _test_speaker_portraits()
	await _test_runtime_portraits()
	_test_portrait_facing()
	await _test_lifecycle()
	await _test_demo()
	_check(root.get_node("GameState").call("to_dict") == state_before, "Dialogue components never change GameState")
	await _test_main_input_lock()
	state_before.flags["shop.orders_viewed"] = true
	_check(root.get_node("GameState").call("to_dict") == state_before, "Opening the order board records viewing without implicitly accepting an order")
	print("DIALOGUE: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _test_library() -> void:
	var library := DialogueLibrary.new()
	_check(library.load_file("res://missing_dialogue.json") == ERR_FILE_NOT_FOUND, "Missing JSON file returns a useful error")
	_check(library.load_file("res://src/resources/dialogue/example_dialogues.json") == OK, "Example JSON loads")
	var font: Font = load("res://assets/fonts/fusion_pixel/fusion-pixel-12px-monospaced-zh_hans.otf.woff2")
	var missing_glyphs: Array[String] = []
	for id: String in ["demo.greeting", "demo.first_shift"]:
		for line: Dictionary in library.get_dialogue(id)["lines"].values():
			var characters: String = line["speaker"] + line["text"]
			for choice: Dictionary in line.get("choices", []):
				characters += choice["text"]
			for character in characters:
				if not font.has_char(character.unicode_at(0)):
					missing_glyphs.append(character)
	_check(missing_glyphs.is_empty(), "Bundled font covers every character in the example JSON")
	var copy := library.get_dialogue("demo.greeting")
	copy["lines"].clear()
	_check(not library.get_dialogue("demo.greeting")["lines"].is_empty(), "Library returns independent data")
	_check(library.load_json("{") == ERR_PARSE_ERROR and not library.last_error.is_empty(), "Malformed JSON reports its parse error")
	for text: String in [
		"[]", '{"version": 2, "dialogues": {}}', '{"version": true, "dialogues": {}}',
		'{"version": 1, "dialogues": {"bad": {"start": "missing", "lines": {}}}}',
		'{"version": 1, "dialogues": {"bad": {"start": "a", "lines": {"a": {"speaker": "A", "text": "x", "next": "missing"}}}}}',
		'{"version": 1, "dialogues": {"bad": {"start": "a", "lines": {"a": {"speaker": "A", "text": "x", "portrait": "res://missing.png"}}}}}',
		'{"version": 1, "dialogues": {"bad": {"start": "a", "lines": {"a": {"speaker": "A", "text": "x", "choices": [{"id": "a", "text": "A"}, {"id": "a", "text": "B"}]}}}}}',
		'{"version": 1, "dialogues": {"bad": {"start": "a", "lines": {"a": {"speaker": "A", "text": 3}}}}}',
	]:
		_check(library.load_json(text) == ERR_INVALID_DATA, "Invalid dialogue schema is rejected")
		_check(library.has_dialogue("demo.greeting"), "Failed loads preserve the previous catalogue")


func _test_flow() -> void:
	_manager = DialogueManager.new()
	root.add_child(_manager)
	_check(_manager.start_dialogue("demo.greeting") == ERR_UNCONFIGURED, "Manager requires a configured UI")
	_ui = load("res://src/UI/dialogue/dialogue_ui.tscn").instantiate()
	root.add_child(_ui)
	_manager.configure(_ui)
	_manager.dialogue_started.connect(func(id: String) -> void: _starts.append(id))
	_manager.dialogue_ended.connect(func(id: String, cancelled: bool) -> void: _ends.append({"id": id, "cancelled": cancelled}))
	_manager.choice_selected.connect(func(id: String, line: String, choice: String) -> void: _selections.append(id + "/" + line + "/" + choice))
	_check(_manager.start_dialogue("missing.id") == ERR_DOES_NOT_EXIST and not _manager.is_active(), "Unknown ID does not start a session")
	_check(_starts.is_empty() and _ends.is_empty(), "Failed starts emit no lifecycle signals")
	_check(_manager.start_dialogue("demo.first_shift") == OK, "Start dialogue by ID")
	_check(_starts == ["demo.first_shift"] and _manager.get_current_line_id() == "welcome", "Start signal and first line are correct")
	_check(_ui.visible and _ui.is_revealing(), "Dialogue opens with typewriter animation")
	_check(_ui.get_node("Panel/Margin/Content/Speaker").text == "店员" and _ui.get_node("Portrait").visible, "Speaker name and optional portrait are displayed")
	_check(_manager.start_dialogue("demo.greeting") == ERR_BUSY and _manager.load_dialogues() == ERR_BUSY, "Active dialogue cannot be replaced or reloaded")
	await create_timer(0.12).timeout
	var text: RichTextLabel = _ui.get_node("Panel/Margin/Content/Line/Text")
	_check(text.visible_characters > 0 and text.visible_characters < text.get_total_character_count(), "Text reveals incrementally over real frames")
	await _tap(KEY_E)
	_check(not _ui.is_revealing() and _manager.get_current_line_id() == "welcome", "First E skips typing without advancing")
	await _tap(KEY_E, true)
	_check(_manager.get_current_line_id() == "welcome", "Key echo cannot advance a dialogue")
	await _tap(KEY_SPACE)
	_check(_manager.get_current_line_id() == "explain" and not _ui.get_node("Portrait").visible, "Space advances to a consecutive line without a portrait")
	await _tap(KEY_ENTER)
	await _tap(KEY_E)
	_check(_manager.get_current_line_id() == "question", "Consecutive lines reach the choice prompt")
	_manager.select_choice(0)
	_check(_selections.is_empty(), "Choices cannot be selected while typing")
	await _tap(KEY_E)
	var buttons: VBoxContainer = _ui.get_node("Panel/Margin/Content/ChoiceScroll/Choices")
	_check(buttons.get_child_count() == 2 and buttons.is_visible_in_tree(), "Two choices appear only after the text is complete")
	_manager.advance()
	_manager.select_choice(-1)
	_manager.select_choice(2)
	_check(_manager.get_current_line_id() == "question" and _selections.is_empty(), "Advance and invalid choice indices cannot bypass a choice")
	await _tap(KEY_DOWN)
	await _tap(KEY_ENTER)
	_check(_manager.get_current_line_id() == "ready_result", "Keyboard selects the second JSON branch")
	_check(_selections == ["demo.first_shift/question/ready"], "Choice signal carries dialogue, line and stable choice IDs exactly once")
	await _tap(KEY_E)
	await _tap(KEY_E)
	_check(not _manager.is_active() and not _ui.visible and _ends == [{"id": "demo.first_shift", "cancelled": false}], "Last line completes and emits exactly one end signal")
	_manager.end_dialogue()
	_check(_ends.size() == 1, "Repeated end is silent")
	_manager.start_dialogue("demo.first_shift")
	for index in range(2):
		_ui.reveal_all()
		_manager.advance()
	_ui.reveal_all()
	buttons.get_child(0).pressed.emit()
	_check(_manager.get_current_line_id() == "learn_result" and _selections.back() == "demo.first_shift/question/learn", "First button dispatches the other branch")
	await _frames()
	await _tap(KEY_ESCAPE)
	_check(not _manager.is_active() and _ends.back()["cancelled"], "Esc cancels during typing and emits a cancelled end")
	_manager.start_dialogue("demo.greeting")
	_ui.characters_per_second = 200.0
	await create_timer(0.3).timeout
	_check(not _ui.is_revealing(), "Typewriter can finish naturally without a skip")
	await _tap(KEY_ENTER)
	_check(not _manager.is_active() and not _ends.back()["cancelled"], "Single-line dialogue ends normally")


## 摊主成交这类一次性对白：台词不进目录文件，播完即弃。
func _test_adhoc_lines() -> void:
	var manager := DialogueManager.new()
	root.add_child(manager)
	var ui: DialogueUI = load("res://src/UI/dialogue/dialogue_ui.tscn").instantiate()
	root.add_child(ui)
	manager.configure(ui)
	var started: Array[String] = []
	manager.dialogue_started.connect(func(id: String) -> void: started.append(id))
	_check(manager.start_lines([]) == ERR_INVALID_DATA, "Ad-hoc exchange needs at least one line")
	_check(manager.start_lines([{"speaker": "摊主", "text": " "}]) == ERR_INVALID_DATA, "Ad-hoc line needs real text")
	_check(not manager.is_active() and started.is_empty(), "Rejected ad-hoc lines open nothing")
	var lines: Array = [
		{"speaker": "吆喝的摊主", "text": "拿好！"},
		{"speaker": "主角", "text": "……谢了。"},
	]
	_check(manager.start_lines(lines, "market_vendor.farewell.test") == OK, "Ad-hoc exchange starts from memory")
	_check(started == ["market_vendor.farewell.test"] and manager.get_current_line_id() == "line_0", "Ad-hoc session reports its own ID")
	var speaker: Label = ui.get_node("Panel/Margin/Content/Speaker")
	var text: RichTextLabel = ui.get_node("Panel/Margin/Content/Line/Text")
	_check(speaker.text == "吆喝的摊主" and text.text == "拿好！", "First ad-hoc line reaches the window")
	ui.reveal_all()
	manager.advance()
	_check(manager.get_current_line_id() == "line_1" and speaker.text == "主角" and text.text == "……谢了。", "Second ad-hoc line follows the first")
	ui.reveal_all()
	manager.advance()
	_check(not manager.is_active() and not ui.visible, "Ad-hoc exchange closes itself after the last line")
	_check(manager.load_dialogues("res://src/resources/dialogue/example_dialogues.json") == OK
		and manager.start_dialogue("market_vendor.farewell.test") == ERR_DOES_NOT_EXIST,
		"Ad-hoc lines never enter the catalogue")
	ui.queue_free()
	manager.queue_free()
	await _frames()


func _test_mouse_advance() -> void:
	var manager := DialogueManager.new()
	root.add_child(manager)
	var ui: DialogueUI = load("res://src/UI/dialogue/dialogue_ui.tscn").instantiate()
	root.add_child(ui)
	manager.configure(ui)
	_check(manager.start_dialogue("demo.first_shift") == OK, "Mouse test starts a real dialogue")
	await _frames(2)
	var text: RichTextLabel = ui.get_node("Panel/Margin/Content/Line/Text")
	var center: Vector2 = (ui.get_node("Panel") as Control).get_global_rect().get_center()
	# The first click completes the typewriter instead of skipping the line.
	await _click_position(center)
	_check(not ui.is_revealing() and manager.get_current_line_id() == "welcome", "Left click reveals the current line first")
	await _click_position(center)
	_check(manager.get_current_line_id() == "explain", "A second left click advances the line")
	# A click on a waiting choice belongs to the native button, not the line.
	ui.reveal_all()
	manager.advance()
	ui.reveal_all()
	manager.advance()
	ui.reveal_all()
	_check(manager.get_current_line_id() == "question", "Mouse test reaches the authored choice")
	var choices: VBoxContainer = ui.get_node("Panel/Margin/Content/ChoiceScroll/Choices")
	_check(choices.is_visible_in_tree() and choices.get_child_count() == 2, "Choice buttons are ready for native mouse input")
	await _frames(2)
	await _click(choices.get_child(0) as Button)
	_check(manager.get_current_line_id() == "learn_result", "Clicking a choice selects it without double-advancing")
	manager.end_dialogue()
	ui.queue_free()
	manager.queue_free()
	await _frames(2)


func _test_presentation_timing() -> void:
	var ui: DialogueUI = load("res://src/UI/dialogue/dialogue_ui.tscn").instantiate()
	root.add_child(ui)
	ui.set_process(false)
	ui.characters_per_second = 10.0
	var text: RichTextLabel = ui.get_node("Panel/Margin/Content/Line/Text")
	ui.present_line("主角", "甲，乙", null, [])
	ui._process(0.201)
	_check(text.visible_characters == 2, "Comma is visible before its reading pause")
	ui._process(0.1)
	_check(text.visible_characters == 2, "Comma adds a short pause before the next character")
	ui.reveal_all()
	_check(not ui.is_revealing() and text.visible_characters == -1, "Reveal all immediately clears punctuation delay")
	ui.present_line("主角", "甲乙", null, [])
	ui._process(0.201)
	_check(not ui.is_revealing(), "A new line does not inherit the previous punctuation delay")
	ui.characters_per_second = 100.0
	ui.present_line("主角", "甲……？！乙", null, ["继续"])
	ui._process(0.051)
	_check(text.visible_characters == 5, "Consecutive punctuation is revealed without repeated pauses")
	ui._process(0.17)
	_check(text.visible_characters == 5 and ui.get_default_focus() == null, "Mixed punctuation uses one ellipsis pause and keeps choices hidden")
	ui._process(0.02)
	_check(not ui.is_revealing() and ui.get_default_focus() == root.gui_get_focus_owner(), "Choices receive focus when natural reveal completes")
	ui.present_line("主角", "甲？！”", null, [])
	ui._process(0.041)
	_check(not ui.is_revealing(), "Line-ending punctuation before a closing quote adds no pause")
	ui.present_line("主角", "甲？乙", null, [])
	ui._process(0.021)
	ui._process(0.1)
	_check(text.visible_characters == 2, "Sentence punctuation adds its own pause")
	ui.close_dialogue()
	ui.present_line("系统", "", null, ["确认"])
	_check(not ui.is_revealing() and ui.get_default_focus() == root.gui_get_focus_owner(), "An empty line exposes choices immediately after close and reopen")
	var image: Texture2D = load("res://src/resources/dialogue/demo_portrait.tres")
	var portrait: TextureRect = ui.get_node("Portrait")
	ui.present_line("主角", "甲乙", image, [])
	_check(is_zero_approx(portrait.modulate.a), "The first portrait fades in without moving")
	var placement := portrait.get_rect()
	await create_timer(0.18).timeout
	_check(is_equal_approx(portrait.modulate.a, 1.0) and portrait.get_rect() == placement, "Portrait fade finishes at the original placement")
	ui.present_line("主角", "下一句", image, [])
	_check(is_equal_approx(portrait.modulate.a, 1.0), "Consecutive lines from the same speaker do not restart the fade")
	ui.present_line("客人", "回答", image, [])
	_check(is_zero_approx(portrait.modulate.a), "Changing speakers fades even when the image is shared")
	ui.reveal_all()
	_check(is_equal_approx(portrait.modulate.a, 1.0), "Fast-forward also completes the portrait fade")
	ui.present_line("主角", "回来", image, [])
	ui.close_dialogue()
	ui.present_line("系统", "提示", null, [])
	await create_timer(0.18).timeout
	_check(not portrait.visible and portrait.texture == null and is_equal_approx(portrait.modulate.a, 1.0), "Closing and reopening cannot revive the previous portrait tween")
	ui.queue_free()
	await _frames()


func _test_story_skip() -> void:
	var changed: Array[String] = []
	var ends: Array[bool] = []
	var on_line := func(id: String) -> void: changed.append(id)
	var on_end := func(_id: String, cancelled: bool) -> void: ends.append(cancelled)
	_manager.line_changed.connect(on_line)
	_manager.dialogue_ended.connect(on_end)
	var hint: Label = _ui.get_node("Panel/Margin/Content/Hint")
	_check(_manager.start_dialogue("demo.first_shift", true) == OK, "Story dialogue starts with cancellation protection")
	_check(_ui.is_cancel_protected() and "跳过本段" in hint.text, "Protected dialogue tells the player Esc skips this segment")
	_manager.skip_to_end()
	_check(_manager.is_active() and _manager.get_current_line_id() == "question", "Skip stops on the next choice instead of choosing for the player")
	_check(changed == ["welcome", "question"], "Skip notifies the opening and landing lines, not every skipped line")
	await _frames()
	var choices: VBoxContainer = _ui.get_node("Panel/Margin/Content/ChoiceScroll/Choices")
	_check(choices.get_child_count() == 2 and choices.is_visible_in_tree(), "Skipped dialogue exposes its real choice")
	await _tap(KEY_ESCAPE)
	_check(_manager.is_active() and ends.is_empty(), "Esc on a protected choice neither cancels nor closes it")
	_manager.select_choice(0)
	_check(_manager.get_current_line_id() == "learn_result" and _ui.is_cancel_protected(), "Protection lasts until the story dialogue actually ends")
	_manager.skip_to_end()
	_check(not _manager.is_active() and ends == [false] and not _ui.is_cancel_protected(), "Skipping the final line completes the story dialogue without cancelling")
	_check(_manager.start_dialogue("demo.player_expressions", true) == OK, "Second protected dialogue starts")
	await _frames()
	await _tap(KEY_ESCAPE)
	_check(not _manager.is_active() and ends.back() == false, "Esc on a protected linear dialogue finishes it instead of cancelling the event")
	_manager.line_changed.disconnect(on_line)
	_manager.dialogue_ended.disconnect(on_end)


func _test_fast_forward_and_auto() -> void:
	_check(_manager.start_dialogue("demo.first_shift") == OK, "Fast-forward fixture starts")
	_ui.reveal_all()
	await _frames()
	Input.action_press("interact")
	await create_timer(0.9).timeout
	Input.action_release("interact")
	_check(_manager.get_current_line_id() == "question", "Holding confirm fast-forwards several lines and stops at the choice")
	_manager.end_dialogue(true)
	_check(_manager.start_dialogue("demo.greeting") == OK, "Auto-play fixture starts with a completed line")
	_ui.reveal_all()
	_ui._auto_seconds = 0.1
	await create_timer(0.35).timeout
	_check(not _manager.is_active(), "Auto-play advances a fully revealed line")
	_check(_manager.start_dialogue("demo.first_shift") == OK, "Auto-play choice fixture starts")
	for index in range(2):
		_ui.reveal_all()
		_manager.advance()
	_ui.reveal_all()
	_check(_manager.get_current_line_id() == "question", "Fixture reaches its choice")
	_ui._auto_seconds = 0.1
	await create_timer(0.35).timeout
	_check(_manager.is_active() and _manager.get_current_line_id() == "question", "Auto-play never picks a choice for the player")
	_manager.end_dialogue(true)


func _test_compact_ui() -> void:
	var paragraphs: PackedStringArray = []
	for index in range(30):
		paragraphs.append("第 %d 行：长对话可以滚动阅读，面板保持固定大小。" % index)
	var choices: Array[String] = ["第一个选项", "第二个选项"]
	_ui.present_line("店员", "\n".join(paragraphs), load("res://src/resources/dialogue/demo_portrait.tres"), choices)
	_ui.reveal_all()
	await _frames()
	var panel: Control = _ui.get_node("Panel")
	var text: RichTextLabel = _ui.get_node("Panel/Margin/Content/Line/Text")
	var scrollbar := text.get_v_scroll_bar()
	_check(panel.size.x <= 560.0 and panel.size.y <= 140.0, "Panel stays compact with portrait, long text and two choices")
	_check(text.scroll_active and scrollbar.max_value > scrollbar.page, "Long dialogue overflows into an active scrollbar")
	_check(is_zero_approx(scrollbar.value), "Revealed text starts at the beginning for reading")
	text.scroll_to_line(20)
	await _frames()
	_check(scrollbar.value > 0.0, "Long dialogue can scroll within the fixed text area")
	_check(panel.size.y <= 140.0, "Scrolling does not enlarge the dialogue panel")
	_ui.present_line("店员", "新的短对白。", null, [])
	_ui.reveal_all()
	await _frames()
	_check(is_zero_approx(scrollbar.value), "A new line resets the previous scroll position")
	_ui.close_dialogue()


func _test_edge_cases() -> void:
	_check(_manager.load_dialogues("res://tests/fixtures/dialogue_edge_cases.json") == OK, "A host can load a different JSON catalogue")
	_check(_manager.load_dialogues("res://missing.json") == ERR_FILE_NOT_FOUND, "Failed reload reports an error without discarding the loaded catalogue")
	_check(_manager.start_dialogue("demo.greeting") == ERR_DOES_NOT_EXIST, "Unknown ID does not silently replace an explicitly loaded catalogue")
	_check(_manager.start_dialogue("test.immediate_choice") == OK and not _ui.is_revealing(), "Empty text immediately exposes choices")
	var order: Array[String] = []
	var on_choice := func(_id: String, _line: String, _choice: String) -> void:
		order.append("choice")
		_manager.select_choice(0)
	var on_end := func(_id: String, _cancelled: bool) -> void: order.append("end")
	_manager.choice_selected.connect(on_choice)
	_manager.dialogue_ended.connect(on_end)
	_manager.select_choice(0)
	_check(not _manager.is_active() and order == ["choice", "end"], "A terminal choice notifies selection before completion and prevents duplicate dispatch")
	_manager.choice_selected.disconnect(on_choice)
	_manager.dialogue_ended.disconnect(on_end)
	_check(_manager.load_dialogues() == OK, "Default catalogue can be explicitly reloaded")


func _test_choice_handoff() -> void:
	_check(_manager.start_dialogue("demo.first_shift") == OK, "Choice handoff fixture starts")
	for index in range(3):
		_ui.reveal_all()
		_manager.advance()
	_ui.reveal_all()
	_check(_manager.get_current_line_id() == "question", "Choice handoff fixture reaches its choice")
	var lines: Array[String] = []
	var on_line := func(id: String) -> void: lines.append(id)
	var on_choice := func(_dialogue: String, _line: String, _choice: String) -> void:
		_manager.end_dialogue()
		_manager.start_dialogue.call_deferred("demo.greeting")
	_manager.line_changed.connect(on_line)
	_manager.choice_selected.connect(on_choice)
	_manager.select_choice(0)
	await _frames(3)
	_check(_manager.is_active() and _manager.get_current_line_id() == "hello", "A replacement dialogue keeps its own opening line")
	_check(not "learn_result" in lines and not "ready_result" in lines, "The replaced dialogue never receives the old choice's next line")
	_manager.choice_selected.disconnect(on_choice)
	_manager.line_changed.disconnect(on_line)
	_manager.end_dialogue()


## A dialogue whose UI cannot open must end immediately: the host lock and the
## visible screen stay in the same state.
func _test_ui_unavailable() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var manager_ui := UIManager.new()
	root.add_child(manager_ui)
	manager_ui.configure({"popup": layer})
	var view: DialogueUI = load("res://src/UI/dialogue/dialogue_ui.tscn").instantiate()
	root.add_child(view)
	_check(manager_ui.register_screen(&"dialogue", view, &"popup", true) == OK, "Dialogue screen registers with a real manager")
	var manager := DialogueManager.new()
	root.add_child(manager)
	manager.configure(view)
	var ends: Array[bool] = []
	manager.dialogue_ended.connect(func(_id: String, cancelled: bool) -> void: ends.append(cancelled))
	paused = true
	var error := manager.start_dialogue("demo.greeting")
	paused = false
	_check(error == ERR_BUSY and not manager.is_active(), "A dialogue blocked by a paused popup never stays active")
	_check(ends == [true] and not manager.last_error.is_empty(), "The failed line ends the session so its input lock is released")
	_check(not view.visible, "The dialogue view stays closed when it could not open")
	view.queue_free()
	manager.queue_free()
	manager_ui.queue_free()
	await _frames()


func _test_portrait_facing() -> void:
	var portrait: TextureRect = _ui.get_node("Portrait")
	_check(_ui.right_facing_portraits.size() == 7, "All seven audited right-facing NPC illustrations are configured")
	for texture: Texture2D in _ui.right_facing_portraits:
		_check(_ui.present_line("NPC", "朝向", texture, []) == OK and portrait.flip_h, "Right-facing NPC looks inward from the right: " + texture.resource_path)
		_ui.reveal_all()
		_ui.set_portrait(texture)
		_check(portrait.flip_h, "Runtime portrait replacement preserves the facing rule")
		_check(_ui.present_line("主角", "朝向", texture, [], true) == OK and not portrait.flip_h, "Moving the same portrait to the left clears the mirror")
	for path: String in [
		"res://assets/characters/apron_man/player_neutral_portrait.png",
		"res://assets/characters/apron_man/player_talking_portrait.png",
		"res://assets/characters/apron_man/player_bad_laugh.png",
	]:
		_check(_ui.present_line("主角", "主角保持朝右", load(path), [], true) == OK and not portrait.flip_h, "Player expression stays unchanged on the left")
	for path: String in [
		"res://assets/characters/npc/prayer_woman/portrait.png",
		"res://assets/characters/npc/goblin_boy/portrait.png",
		"res://assets/characters/dialogue/common_goblin_portrait.png",
		"res://assets/characters/fat_goblin/fat_goblin_smiling_portrait.png",
	]:
		_ui.set_portrait(_ui.right_facing_portraits[0])
		_check(_ui.present_line("NPC", "保留原朝向", load(path), []) == OK and not portrait.flip_h, "Left-facing and frontal artwork clears the previous mirror")
	_ui.set_portrait(null)
	_check(not portrait.visible and not portrait.flip_h, "Hiding a portrait clears mirroring")
	_ui.close_dialogue()


func _test_speaker_portraits() -> void:
	for path: String in [
		"res://assets/characters/apron_man/player_neutral_portrait.png",
		"res://assets/characters/apron_man/player_talking_portrait.png",
		"res://assets/characters/fat_goblin/fat_goblin_smiling_portrait.png",
		"res://assets/characters/fat_goblin/fat_goblin_laughing_portrait.png",
	]:
		var image := (load(path) as Texture2D).get_image()
		_check(image.detect_alpha() != Image.ALPHA_NONE and not image.is_invisible(), "Portrait contains both transparency and a visible character: " + path)
		if "/apron_man/" in path:
			_check(image.get_pixel(276, 28).a == 0.0 and image.get_pixel(196, 32).a == 0.0 and image.get_pixel(107, 92).a == 0.0, "Hair tips and gaps have no gray-white matte residue: " + path)
			_check(image.get_pixel(132, 435).a == 0.0 and image.get_pixel(222, 735).a == 0.0, "The arm and leg gaps are transparent: " + path)
			_check(image.get_pixel(89, 840).a == 0.0, "No white ground remains outside the boot silhouette: " + path)
			var boot_rim_clear := true
			for point: Vector2i in [Vector2i(127, 827), Vector2i(203, 814), Vector2i(240, 849), Vector2i(371, 828), Vector2i(239, 856)]:
				boot_rim_clear = boot_rim_clear and image.get_pixelv(point).a == 0.0
			_check(boot_rim_clear, "Both toes, instep, heel and sole have no leftover paper rim: " + path)
		_check(image.get_pixel(0, 0).a == 0.0 and image.get_pixel(image.get_width() - 1, image.get_height() - 1).a == 0.0, "Portrait background corners are transparent: " + path)
	# The fat goblin illustration is exclusive to that character; every other
	# goblin speaker must use their own artwork or omit the illustration.
	for speaker: String in ["哥布林", "赌徒哥布林", "说教的哥布林", "爱收集的哥布林", "胆小的哥布林", "围观的哥布林", "凑热闹的哥布林", "另一名哥布林", "酒馆老板", "赌场老板"]:
		_check(_manager.speaker_portraits.get(speaker) != _manager.speaker_portraits["胖哥布林"], "The fat goblin portrait stays exclusive to 胖哥布林: " + speaker)
	_check(_manager.start_dialogue("demo.speaker_portraits") == OK, "Portrait demo starts through the real manager")
	var portrait: TextureRect = _ui.get_node("Portrait")
	var expected := {
		"player": "res://assets/characters/apron_man/player_talking_portrait.png",
		"goblin": "res://assets/characters/fat_goblin/fat_goblin_smiling_portrait.png",
		"common": "",
		"narrator": "",
		"inner": "res://assets/characters/apron_man/player_neutral_portrait.png",
		"override": "res://assets/characters/fat_goblin/fat_goblin_laughing_portrait.png",
		"hidden": "",
	}
	for line_id: String in expected:
		_check(_manager.get_current_line_id() == line_id, "Portrait sequence reaches " + line_id)
		var path: String = expected[line_id]
		if path.is_empty():
			_check(not portrait.visible and portrait.texture == null, "Missing or suppressed portrait clears the previous speaker: " + line_id)
		else:
			_check(portrait.visible and portrait.texture.resource_path == path, "Speaker default or explicit override is shown: " + line_id)
		_ui.reveal_all()
		await _frames()
		var panel: Control = _ui.get_node("Panel")
		var portrait_rect: Rect2 = portrait.get_global_rect()
		var panel_rect: Rect2 = panel.get_global_rect()
		var visible_ratio := (panel_rect.position.y - portrait_rect.position.y) / portrait_rect.size.y
		_check(visible_ratio >= 0.65, "The panel leaves the upper body of the portrait readable")
		_check(portrait_rect.end.y - panel_rect.position.y <= portrait_rect.size.y * 0.35, "The panel hides only the portrait's lower strip")
		_check(panel.z_index > portrait.z_index and portrait_rect.end.y <= panel_rect.end.y, "Portrait is behind the panel with no feet protruding below")
		var on_left := line_id in ["player", "inner", "hidden"]
		_check((portrait.get_global_rect().get_center().x < root.get_visible_rect().size.x / 2.0) == on_left, "Player is on the left and NPC is on the right: " + line_id)
		_check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(portrait.get_global_rect()), "Portrait fits the viewport")
		if "--capture-portraits" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://dialogue-portrait-%s.png" % line_id)
		_manager.advance()
	_check(not _manager.is_active() and not portrait.visible and portrait.texture == null, "Ending dialogue clears the portrait")
	_manager.start_dialogue("demo.speaker_portraits")
	_manager.end_dialogue(true)
	_check(not portrait.visible and portrait.texture == null, "Cancelling dialogue clears the portrait")
	_check(_manager.load_dialogues("res://src/resources/dialogue/day1_demo_dialogues.json") == OK, "Existing Day 1 dialogue loads without adding portrait fields")
	_manager.start_dialogue("day1.opening")
	_check(portrait.visible and portrait.texture == _manager.speaker_portraits["主角·内心"], "Existing opening resolves the protagonist portrait automatically")
	_manager.end_dialogue()
	_check(_manager.load_dialogues("res://src/resources/dialogue/day1_stages_03_06.json") == OK, "Infiltration dialogue loads with the guard speaker binding")
	_check(_manager.start_dialogue("day1.s05.drunken_guard") == OK, "The actual guard interception starts")
	_check(portrait.visible and portrait.texture == _manager.speaker_portraits["醉酒守卫"] and not portrait.texture is AtlasTexture, "The guard interception shows the supplied guard illustration")
	_check(portrait.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR, "Guard illustration uses smooth filtering")
	var guard_portrait: TextureRect = _ui.get_node("Portrait")
	_check(guard_portrait.offset_top == DialogueUI.PORTRAIT_TOP and guard_portrait.get_global_rect().position.y >= 0.0, "Tall guard art fits the portrait slot without cutting the helmet")
	_manager.end_dialogue()
	_check(_manager.load_dialogues("res://src/resources/dialogue/day2_stages_01_05.json") == OK, "Load the actual Day 2 dialogue illustrations")
	for example: Array in [
		["day2.s03.tavern_commission", "酒馆老板", "tavern"],
		["day2.s04.casino_boss", "赌场老板", "casino"],
		["day2.s02.emissary_rumor", "哥布林顾客", "common_goblin"],
		["day2.s05.deliver_guard", "守卫", "guard"],
		["day2.s05.deliver_guard_after_delivery", "守卫", "guard"],
		["day2.s01.fat_goblin_wakes", "胖哥布林", "fat_goblin_sick"],
	]:
		_check(_manager.start_dialogue(example[0]) == OK, "Start actual illustration scene: " + example[0])
		var reached := false
		for index in range(16):
			if not _manager.is_active():
				break
			if _ui.get_node("Panel/Margin/Content/Speaker").text == example[1]:
				reached = true
				break
			_ui.reveal_all()
			await _frames()
			_manager.advance()
		_check(reached and portrait.visible and portrait.texture.resource_path == "res://assets/characters/dialogue/%s_portrait.png" % example[2], "The correct character illustration is shown: " + example[1])
		_check(portrait.texture != null and portrait.texture.get_height() > 500 and not portrait.texture is AtlasTexture, "Dialogue uses a full illustration, separate from a pixel avatar")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			_ui.reveal_all()
			await _frames()
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://.godot/portrait_feedback/captures")
			root.get_texture().get_image().save_png("res://.godot/portrait_feedback/captures/" + example[2] + ".png")
		_manager.end_dialogue()
	_check(_manager.load_dialogues() == OK, "Restore default dialogue catalogue after portrait checks")


func _test_runtime_portraits() -> void:
	var neutral: Texture2D = load("res://assets/characters/apron_man/player_neutral_portrait.png")
	var talking: Texture2D = load("res://assets/characters/apron_man/player_talking_portrait.png")
	var portrait: TextureRect = _ui.get_node("Portrait")
	var text: RichTextLabel = _ui.get_node("Panel/Margin/Content/Line/Text")
	var changed: Array[String] = []
	var on_line := func(id: String) -> void: changed.append(id)
	_manager.line_changed.connect(on_line)
	_check(neutral.get_size() == talking.get_size() and neutral != talking, "Both imported expressions have distinct textures on the same canvas")
	_check(_manager.set_current_portrait(talking) == ERR_UNCONFIGURED and not _ui.visible, "Idle portrait changes cannot open the dialogue UI")
	_manager.start_dialogue("demo.player_expressions")
	await _frames()
	var characters := text.visible_characters
	var revealing := _ui.is_revealing()
	var placement := portrait.get_global_rect()
	_check(_manager.set_current_portrait(talking) == OK and portrait.texture == talking and portrait.visible, "Program switches expression immediately while a line is revealing")
	_check(text.visible_characters == characters and _ui.is_revealing() == revealing and changed == ["neutral"], "Switching preserves reveal progress and emits no extra line notification")
	_check(portrait.get_global_rect() == placement, "Switching keeps portrait size and placement")
	_manager.set_current_portrait(null)
	_check(not portrait.visible and portrait.texture == null and text.visible_characters == characters, "Program can hide the current portrait without changing text")
	_manager.set_speaker_portrait("主角", talking)
	_check(portrait.texture == talking and text.visible_characters == characters, "Updating the current speaker default refreshes only the portrait")
	_manager.set_speaker_portrait("主角", neutral)
	_ui.reveal_all()
	_manager.advance()
	_check(_manager.get_current_line_id() == "talking" and portrait.texture == talking, "A per-line JSON path selects the imported talking expression")
	_manager.set_speaker_portrait("主角", neutral)
	_check(portrait.texture == talking, "Updating speaker defaults respects an explicit per-line portrait")
	_manager.set_current_portrait(neutral)
	_check(portrait.texture == neutral and _ui.is_revealing(), "An explicit program override also works on a JSON portrait line")
	_ui.reveal_all()
	_manager.advance()
	_check(_manager.get_current_line_id() == "default" and portrait.texture == neutral, "Next line restores the configured default after a temporary override")
	_manager.set_speaker_portrait("主角", null)
	_check(not portrait.visible and not _manager.speaker_portraits.has("主角"), "Null speaker defaults remove the mapping and clear the current image")
	_manager.set_speaker_portrait("主角", neutral)
	_ui.reveal_all()
	_manager.advance()
	_check(not _manager.is_active() and not portrait.visible and portrait.texture == null, "Natural completion clears a program-selected expression")
	_manager.line_changed.disconnect(on_line)
	_manager.start_dialogue("demo.first_shift")
	for index in range(2):
		_ui.reveal_all()
		_manager.advance()
	_ui.reveal_all()
	await _frames()
	var buttons: Node = _ui.get_node("Panel/Margin/Content/ChoiceScroll/Choices")
	var first_button := buttons.get_child(0)
	var focus := root.gui_get_focus_owner()
	_manager.set_current_portrait(talking)
	_check(buttons.get_child_count() == 2 and buttons.get_child(0) == first_button and root.gui_get_focus_owner() == focus, "Expression changes preserve live choice buttons and focus")
	_manager.select_choice(1)
	_check(_manager.get_current_line_id() == "ready_result" and not portrait.visible, "The original choice still advances and clears the temporary expression")
	_manager.set_current_portrait(talking)
	_manager.end_dialogue(true)
	_check(not portrait.visible and portrait.texture == null and _manager.set_current_portrait(neutral) == ERR_UNCONFIGURED, "Cancellation clears runtime images and rejects idle changes")


func _test_lifecycle() -> void:
	_manager.start_dialogue("demo.greeting")
	_manager.free()
	_check(not _ui.visible and _ends.back()["cancelled"], "Removing an active manager closes its UI and cancels once")
	_ui.free()
	_manager = DialogueManager.new()
	root.add_child(_manager)
	_ui = load("res://src/UI/dialogue/dialogue_ui.tscn").instantiate()
	root.add_child(_ui)
	_manager.configure(_ui)
	_manager.start_dialogue("demo.greeting")
	_ui.queue_free()
	await _frames()
	_check(not _manager.is_active(), "Removing an active UI cancels the session")
	_check(_manager.start_dialogue("demo.greeting") == ERR_UNCONFIGURED, "Missing UI cannot start another session")
	_manager.free()


func _test_demo() -> void:
	var demo: Node = load("res://src/debug/dialogue/dialogue_demo.tscn").instantiate()
	root.add_child(demo)
	await _frames()
	var manager: DialogueManager = demo.get_node("Systems/DialogueManager")
	var player: PlayerController = demo.get_node("World/Player")
	_check(manager.is_active() and not player.movement_enabled, "Standalone scene starts without MainGame and locks its demo player")
	if "--capture" in OS.get_cmdline_user_args():
		var ui: DialogueUI = demo.get_node("PopupLayer/DialogueUI")
		ui.reveal_all()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://dialogue-demo-welcome.png")
		for index in range(2):
			manager.advance()
			ui.reveal_all()
		await _frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://dialogue-demo-choices.png")
	var demo_ui: DialogueUI = demo.get_node("PopupLayer/DialogueUI")
	var demo_portrait: TextureRect = demo_ui.get_node("Portrait")
	await _click(demo.get_node("DebugLayer/Screen/PortraitControls/Talking"))
	_check(demo_portrait.texture.resource_path.ends_with("player_talking_portrait.png"), "Standalone talking button uses the program switch API")
	await _click(demo.get_node("DebugLayer/Screen/PortraitControls/Hidden"))
	_check(not demo_portrait.visible, "Standalone hidden button clears the expression")
	await _click(demo.get_node("DebugLayer/Screen/PortraitControls/Neutral"))
	_check(demo_portrait.visible and demo_portrait.texture.resource_path.ends_with("player_neutral_portrait.png"), "Standalone neutral button restores the expression")
	await _tap(KEY_ESCAPE)
	_check(player.movement_enabled and demo.get_node("HudLayer/Screen/Menu").visible, "Standalone scene restores controls and offers replay")
	demo.get_node("HudLayer/Screen/Menu/Portraits").pressed.emit()
	_check(manager.get_current_line_id() == "player" and (demo.get_node("PopupLayer/DialogueUI/Portrait") as TextureRect).visible, "Standalone portrait menu starts the speaker portrait preview")
	manager.end_dialogue(true)
	demo.queue_free()
	await _frames()


func _test_main_input_lock() -> void:
	var game: MainGame = load("res://src/debug/story/legacy_shop.tscn").instantiate()
	root.add_child(game)
	await _frames()
	var player := game.get_player() as PlayerController
	var manager := game.get_dialogue_manager()
	var shop_ui: ShopUI = game.get_node("HudLayer/ShopUI")
	var interaction: ShopInteraction = game.get_node("Systems/ShopInteraction")
	var ui: DialogueUI = game.get_node("PopupLayer/DialogueUI")
	var point: InteractionPoint = (game.get_active_level() as MilkTeaShop).get_interaction_points()[0]
	player.global_position = point.global_position
	await _frames(3)
	_check(point.is_available(), "Integration test uses a real nearby interaction point")
	_check(manager.start_dialogue("demo.greeting") == OK and not player.movement_enabled and not interaction.is_input_enabled(), "MainGame locks both movement and shop interaction synchronously")
	_check(not shop_ui.get_node("Prompt").visible and ui.get_parent() == game.get_node("PopupLayer"), "Dialogue uses PopupLayer and hides the interaction prompt")
	var before := player.global_position
	Input.action_press("move_right")
	await _frames(8)
	Input.action_release("move_right")
	_check(player.global_position.is_equal_approx(before) and player.velocity == Vector2.ZERO, "Held movement input cannot move the player during dialogue")
	point.interact()
	_check(not shop_ui.is_open(), "Direct scene interaction is also blocked")
	await _tap(KEY_E)
	await _tap(KEY_E)
	_check(not manager.is_active() and player.movement_enabled and interaction.is_input_enabled(), "Natural completion restores gameplay input")
	_check(not shop_ui.is_open(), "Final E is consumed before it can reopen the shop popup")
	await _tap(KEY_E)
	_check(shop_ui.is_open() and manager.start_dialogue("demo.greeting") == ERR_BUSY, "Existing shop popup prevents a competing dialogue")
	_check(not ui.visible and not player.movement_enabled, "Rejected start preserves the existing shop movement lock")
	shop_ui.close()
	player.set_movement_enabled(false)
	interaction.set_input_enabled(false)
	manager.start_dialogue("demo.greeting")
	await _frames()
	await _tap(KEY_ESCAPE)
	_check(not player.movement_enabled and not interaction.is_input_enabled(), "Ending dialogue preserves pre-existing disabled input")
	player.set_movement_enabled(true)
	interaction.set_input_enabled(true)
	manager.start_dialogue("demo.first_shift")
	for index in range(2):
		ui.reveal_all()
		manager.advance()
	ui.reveal_all()
	await _frames()
	var panel: Control = ui.get_node("Panel")
	_check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(panel.get_global_rect()), "Dialogue panel fits the 640x360 viewport")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://dialogue-choices.png")
	manager.end_dialogue(true)
	var protected_ends: Array[bool] = []
	manager.dialogue_ended.connect(func(_id: String, cancelled: bool) -> void: protected_ends.append(cancelled))
	_check(manager.start_dialogue("demo.greeting", true) == OK and ui.is_cancel_protected(), "Real host starts a protected story dialogue")
	await _frames()
	await _tap(KEY_ESCAPE)
	_check(not manager.is_active() and protected_ends == [false] and player.movement_enabled, "Esc through the modal stack skips story dialogue and restores input")
	ui.queue_free()
	await _frames()
	_check(not manager.is_active() and player.movement_enabled and interaction.is_input_enabled(), "UI removal releases the real gameplay lock")
	game.queue_free()
	await _frames()
