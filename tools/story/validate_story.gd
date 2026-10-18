extends SceneTree
## Offline authoring checks only. All execution stays in the existing StoryDirector.

const REQUEST_ERRORS := {"OK": OK, "ERR_UNAUTHORIZED": ERR_UNAUTHORIZED, "ERR_ALREADY_EXISTS": ERR_ALREADY_EXISTS, "ERR_DOES_NOT_EXIST": ERR_DOES_NOT_EXIST, "ERR_BUSY": ERR_BUSY}

var _errors: Array[String] = []
var _story := StoryLibrary.new()
var _dialogue := DialogueLibrary.new()
var _manifest: Dictionary
var _current_dialogue := ""

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, context: String) -> bool:
	if not ok:
		_errors.append(context)
		push_error("AUTHORING: " + context)
	return ok

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not _check(args.size() == 1, "Usage: -- <authoring manifest.json>"):
		quit(1)
		return
	var json := JSON.new()
	if not _check(FileAccess.file_exists(args[0]), "Manifest missing: " + args[0]):
		quit(1)
		return
	if not _check(json.parse(FileAccess.get_file_as_string(args[0])) == OK and json.data is Dictionary, "Manifest JSON: " + json.get_error_message()):
		quit(1)
		return
	_manifest = json.data
	if not _validate_manifest():
		quit(1)
		return
	if not _check(_story.load_file(_manifest.story) == OK, _story.last_error) or not _check(_dialogue.load_file(_manifest.dialogue) == OK, _dialogue.last_error):
		quit(1)
		return
	_validate_mapping()
	var covered: Array[String] = []
	for case: Dictionary in _manifest.cases:
		var event: String = case.get("expected_event", case.get("event", ""))
		_check(not _story.get_event(event).is_empty(), "Case references unknown event: " + event)
		if case.get("request_error", "OK") == "OK":
			covered.append(event)
	for event: String in _story.get_event_ids():
		_check(event in covered, "Event has no execution case: " + event)
	if _errors.is_empty():
		for case: Dictionary in _manifest.cases:
			await _run_case(case)
	print("STORY_AUTHORING: %d cases, %d failures" % [_manifest.cases.size(), _errors.size()])
	quit(0 if _errors.is_empty() else 1)

func _validate_manifest() -> bool:
	_check(_manifest.get("version") == 1, "Expected authoring manifest version 1")
	for field: String in ["source", "scene", "story", "dialogue"]:
		var path: Variant = _manifest.get(field)
		_check(path is String and path.begins_with("res://") and FileAccess.file_exists(path), "Missing project path: " + field)
	_check(_manifest.get("source_sha256") is String, "Expected source_sha256")
	_check(_manifest.get("beats") is Array and not _manifest.get("beats", []).is_empty(), "Expected non-empty beats")
	_check(_manifest.get("cases") is Array and not _manifest.get("cases", []).is_empty(), "Expected non-empty cases")
	if not _errors.is_empty():
		return false
	_check(_manifest.source.ends_with(".md") and _manifest.source.begins_with("res://docs/design/"), "Source must be docs/design/*.md")
	_check(FileAccess.get_sha256(_manifest.source) == _manifest.source_sha256, "Source changed; regenerate affected data/mapping before validation")
	for beat: Variant in _manifest.beats:
		if not _check(beat is Dictionary and beat.has_all(["id", "event", "start", "count", "dialogues"]), "Malformed Beat mapping"):
			continue
		_check(beat.id is String and beat.event is String and beat.dialogues is Array, "Invalid Beat field types")
		_check(typeof(beat.start) in [TYPE_INT, TYPE_FLOAT] and beat.start >= 0 and floor(beat.start) == beat.start, "Beat start must be a nonnegative integer")
		_check(typeof(beat.count) in [TYPE_INT, TYPE_FLOAT] and beat.count > 0 and floor(beat.count) == beat.count, "Beat count must be a positive integer")
	for case: Variant in _manifest.cases:
		if not _check(case is Dictionary, "Case must be an object"):
			continue
		_check(case.has("event") != case.has("trigger"), "Case requires exactly one event or trigger")
		_check(case.get("expected_event", case.get("event", null)) is String, "Trigger case requires expected_event")
		for field: String in ["choices", "state", "expect_flags"]:
			_check(case.get(field, {}) is Dictionary, "Case " + field + " must be an object")
		_check(case.get("expected_skips", []) is Array, "expected_skips must be an array")
		_check(case.get("request_error", "OK") in REQUEST_ERRORS, "Unknown expected request_error")
		if case.get("expected_skips", []) is Array:
			for index: Variant in case.get("expected_skips", []):
				_check(typeof(index) in [TYPE_INT, TYPE_FLOAT] and index >= 0 and floor(index) == index, "expected_skips requires nonnegative integers")
		for field: String in ["timeout", "reading_seconds"]:
			var value: Variant = case.get(field, 1.0)
			_check(typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(value) and value > 0, field + " must be positive and finite")
	return _errors.is_empty()

func _validate_mapping() -> void:
	var source := FileAccess.get_file_as_string(_manifest.source)
	var headings: Array[String] = []
	for line: String in source.split("\n"):
		if line.begins_with("## Beat "):
			headings.append(line.trim_prefix("## Beat ").strip_edges())
	var ids: Array[String] = []
	var offsets: Dictionary = {}
	var owned_dialogues: Dictionary = {}
	for beat: Dictionary in _manifest.beats:
		_check(beat.id not in ids, "Duplicate Beat: " + beat.id)
		ids.append(beat.id)
		var event := _story.get_event(beat.event)
		if not _check(not event.is_empty(), "Unknown Beat event: " + beat.event):
			continue
		_check(int(beat.start) == int(offsets.get(beat.event, 0)), "Gap/overlap at Beat: " + beat.id)
		offsets[beat.event] = int(beat.start + beat.count)
		var used: Array[String] = []
		for index in range(int(beat.start), mini(int(beat.start + beat.count), event.steps.size())):
			var step: Dictionary = event.steps[index]
			if step.command == "dialogue" and step.id not in used:
				used.append(step.id)
		_check(used == Array(beat.dialogues), "Beat dialogue mapping differs: " + beat.id)
		for id: String in beat.dialogues:
			_check(_dialogue.has_dialogue(id), "Unknown mapped dialogue: " + id)
			owned_dialogues[id] = true
	_check(ids == headings, "Beat order/IDs differ from source headings")
	for event: String in _story.get_event_ids():
		_check(int(offsets.get(event, 0)) == _story.get_event(event).steps.size(), "Unmapped steps: " + event)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_manifest.dialogue))
	for id: String in data.dialogues:
		_check(owned_dialogues.has(id), "Unmapped dialogue: " + id)

func _references(game: MainGame) -> void:
	var actors := game.get_actor_director()
	var audio := game.get_audio_manager()
	for event_id: String in _story.get_event_ids():
		var event := _story.get_event(event_id)
		_check_items(game, event.get("conditions", {}).get("items", {}), event_id + "/conditions")
		# Include declared spawns for static existence; runtime checks their order/conditions.
		var spawned: Array[String] = []
		var steps: Array = event.steps
		for step: Dictionary in steps:
			if step.command == "actor_spawn":
				spawned.append(step.actor)
		for index in range(steps.size()):
			var step: Dictionary = steps[index]
			var context := "%s/steps[%d]" % [event_id, index]
			if step.has("actor"):
				_check(actors.get_actor(StringName(step.actor)) != null or step.actor in spawned, context + ": missing actor " + step.actor)
			if step.has("target") and step.target is String:
				_check(actors.get_position(StringName(step.target)) != null, context + ": missing Marker " + step.target)
			if step.command == "actor_spawn":
				var scene := load(step.scene) as PackedScene
				if _check(scene != null, context + ": missing PackedScene"):
					var instance := scene.instantiate()
					_check(instance is PlayerController, context + ": scene root must extend PlayerController")
					instance.free()
			if step.command == "dialogue":
				_check(_dialogue.has_dialogue(step.id), context + ": missing dialogue " + step.id)
			_check_items(game, step.get("when", {}).get("items", {}), context + "/when")
			if step.command == "pay_items":
				_check_items(game, step.items, context)
			if step.command == "actor_animate":
				var animated := actors.get_actor(StringName(step.actor))
				_check(animated == null or animated.animated_sprite.sprite_frames.has_animation(StringName(step.animation)), context + ": missing animation " + step.animation)
			if step.command == "title_card":
				_check(game.get_title_card() != null, context + ": host has no TitleCard")
			if step.command in ["play_sfx", "play_bgm"]:
				var stream: AudioStream = audio.sounds.get(step.id) if step.has("id") else load(step.path) as AudioStream
				_check(stream != null, context + ": missing audio " + str(step.get("id", step.get("path", ""))))
				if stream is AudioStreamWAV and step.get("wait", step.command != "play_sfx") and step.command == "play_sfx":
					_check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, context + ": blocking looping SFX")
			var choice: Dictionary = step.get("when", {}).get("choice", {})
			if not choice.is_empty():
				var line: Dictionary = _dialogue.get_dialogue(choice.dialogue).get("lines", {}).get(choice.line, {})
				_check(line.get("choices", []).any(func(item: Dictionary) -> bool: return item.id == choice.id), context + ": missing when.choice reference")
	if steps_need_camera() and game.get_camera_director() == null:
		_check(false, "Host has no CameraDirector")

func _check_items(game: MainGame, items: Dictionary, context: String) -> void:
	for item: String in items:
		_check(game.get_warehouse_inventory().get_definition(item) != null, context + ": unknown item " + item)

func steps_need_camera() -> bool:
	for id: String in _story.get_event_ids():
		for step: Dictionary in _story.get_event(id).steps:
			if step.command.begins_with("camera_"):
				return true
	return false

func _run_case(case: Dictionary) -> void:
	var state: Node = root.get_node("GameState")
	state.reset_state()
	var snapshot: Dictionary = state.to_dict()
	snapshot.merge(case.get("state", {}), true)
	if not _check(state.restore_state(snapshot) == OK, "Invalid case state snapshot"):
		return
	var scene := load(_manifest.scene) as PackedScene
	if not _check(scene != null, "Missing host scene"):
		return
	var host := scene.instantiate()
	if not _check(host.has_method("get_story_authoring_game") and host.get("autoplay") is bool, "Host needs get_story_authoring_game() and autoplay"):
		host.free()
		return
	host.set("autoplay", false)
	_check(host.get("story_file") == _manifest.story and host.get("dialogue_file") == _manifest.dialogue, "Host JSON configuration differs from manifest")
	root.add_child(host)
	var game: MainGame = host.get_story_authoring_game()
	if not _check(game != null and game.get_actor_director() != null and game.get_audio_manager() != null and game.get_story_director() != null and game.get_dialogue_manager() != null, "Host services missing"):
		host.queue_free()
		await process_frame
		return
	_references(game)
	var director := game.get_story_director()
	var manager := game.get_dialogue_manager()
	_check(manager.load_dialogues(_manifest.dialogue) == OK, manager.last_error)
	_check(director.load_events(_manifest.story) == OK, director.last_error)
	var results: Array[bool] = []
	var skips: Array[int] = []
	var consumed: Dictionary = {}
	var event_id: String = case.get("expected_event", case.get("event", ""))
	_current_dialogue = ""
	manager.dialogue_started.connect(func(id: String) -> void: _current_dialogue = id)
	director.event_started.connect(func(id: String) -> void: _check(id == event_id, "Wrong routed event: " + id))
	director.event_finished.connect(func(_id: String, ok: bool, reason: String) -> void:
		results.append(ok)
		_check(ok, "Execution: " + reason))
	director.step_skipped.connect(func(_id: String, index: int, _reason: String) -> void: skips.append(index))
	var error := director.request_interaction(case.trigger) if case.has("trigger") else director.request_event(event_id)
	var expected_error: int = REQUEST_ERRORS[case.get("request_error", "OK")]
	_check(error == expected_error, "Request rejected/unexpected result: " + director.last_error)
	if expected_error != OK:
		_check(not director.is_busy() and results.is_empty(), "Rejected request must not start an event")
		print("AUTHORING_CASE: %s, request %s" % [event_id, case.request_error])
		if director.is_busy():
			director.cancel_event("Unexpected accepted request")
		await _dispose(host)
		return
	var started := Time.get_ticks_msec()
	var deadline := started + int(case.get("timeout", 60.0) * 1000)
	var line_key := ""
	var line_started := started
	while director.is_busy() and Time.get_ticks_msec() < deadline and _errors.is_empty():
		if manager.is_active():
			var key := _current_dialogue + "/" + manager.get_current_line_id()
			if key != line_key:
				line_key = key
				line_started = Time.get_ticks_msec()
			if Time.get_ticks_msec() - line_started >= case.get("reading_seconds", 0.05) * 1000:
				# First advance reveals text. A later frame advances/selects the line.
				manager.advance()
				if manager.is_active() and manager.get_current_line_id() == key.get_slice("/", 1):
					var line: Dictionary = _dialogue.get_dialogue(_current_dialogue).lines[manager.get_current_line_id()]
					var choices: Array = line.get("choices", [])
					if not choices.is_empty():
						var selected: String = case.get("choices", {}).get(key, "")
						var choice_index := choices.find_custom(func(item: Dictionary) -> bool: return item.id == selected)
						if _check(choice_index >= 0, "Case must explicitly select valid choice: " + key):
							consumed[key] = true
							manager.select_choice(choice_index)
		else:
			line_key = ""
		await process_frame
	_check(not director.is_busy(), "Execution timeout/errors: " + event_id)
	if director.is_busy():
		director.cancel_event("Authoring validation stopped")
	_check(results == [true], "Expected one successful completion: " + event_id)
	var expected_skips: Array[int] = []
	for index: Variant in case.get("expected_skips", []):
		expected_skips.append(int(index))
	_check(skips == expected_skips, "Unexpected skipped steps: %s; expected %s" % [skips, expected_skips])
	for key: String in case.get("choices", {}):
		_check(consumed.has(key), "Unvisited case choice: " + key)
	for key: String in case.get("expect_flags", {}):
		_check(state.get_flag(key) == case.expect_flags[key], "Wrong final flag: " + key)
	if case.has("expect_stage"):
		_check(state.story_stage == case.expect_stage, "Wrong final stage")
	if _story.get_event(event_id).get("once", true):
		_check(state.is_event_completed(event_id), "Once event not recorded complete")
	print("AUTHORING_CASE: %s, %.2fs" % [event_id, (Time.get_ticks_msec() - started) / 1000.0])
	await _dispose(host)

func _dispose(host: Node) -> void:
	host.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
