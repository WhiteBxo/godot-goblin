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
	var position := button.get_global_rect().get_center()
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
	await _test_compact_ui()
	_test_edge_cases()
	await _test_speaker_portraits()
	await _test_runtime_portraits()
	await _test_lifecycle()
	await _test_demo()
	_check(root.get_node("GameState").call("to_dict") == state_before, "Dialogue components never change GameState")
	await _test_main_input_lock()
	state_before.flags["shop.orders_viewed"] = true
	state_before.flags["task.shop.first_order.active"] = true
	state_before.flags["ui.handbook.tasks_unlocked"] = true
	_check(root.get_node("GameState").call("to_dict") == state_before, "Shop integration records the viewed order board and accepts only its revealed order")
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


func _test_speaker_portraits() -> void:
	for path: String in [
		"res://assets/characters/apron_man/player_neutral_portrait.png",
		"res://assets/characters/apron_man/player_talking_portrait.png",
		"res://assets/characters/goblin/goblin_smiling_portrait.png",
		"res://assets/characters/goblin/goblin_laughing_portrait.png",
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
	_check(_manager.start_dialogue("demo.speaker_portraits") == OK, "Portrait demo starts through the real manager")
	var portrait: TextureRect = _ui.get_node("Portrait")
	var expected := {
		"player": "res://assets/characters/apron_man/player_neutral_portrait.png",
		"goblin": "res://assets/characters/goblin/goblin_smiling_portrait.png",
		"narrator": "",
		"inner": "res://assets/characters/apron_man/player_neutral_portrait.png",
		"override": "res://assets/characters/goblin/goblin_laughing_portrait.png",
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
		_check(is_equal_approx(portrait.get_global_rect().get_center().y, panel.get_global_rect().position.y), "Dialogue panel covers the lower half of the centered portrait")
		_check(panel.z_index > portrait.z_index and portrait.get_global_rect().end.y <= panel.get_global_rect().end.y, "Portrait is behind the panel with no feet protruding below")
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
	_check(portrait.visible and portrait.texture == _manager.speaker_portraits["主角"], "Existing opening resolves the protagonist portrait automatically")
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
		root.get_texture().get_image().save_png("/private/tmp/dialogue-demo-welcome.png")
		for index in range(2):
			manager.advance()
			ui.reveal_all()
		await _frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/dialogue-demo-choices.png")
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
		root.get_texture().get_image().save_png("/private/tmp/dialogue-choices.png")
	ui.queue_free()
	await _frames()
	_check(not manager.is_active() and player.movement_enabled and interaction.is_input_enabled(), "UI removal releases the real gameplay lock")
	game.queue_free()
	await _frames()
