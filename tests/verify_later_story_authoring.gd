extends SceneTree
## Content/release isolation only. Pending cases are never played with fabricated
## business results. Runtime route checks use the actual shop and settlement.

const PROJECTS := [
	"res://docs/story_authoring/day1_stages_03_06_project.json",
	"res://docs/story_authoring/day2_stages_01_05_project.json",
]

var _checks := 0
var _failures: Array[String] = []
var _state: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _json(path: String) -> Variant:
	var parser := JSON.new()
	var error := parser.parse(FileAccess.get_file_as_string(path))
	_check(error == OK, "JSON parses: " + path)
	return parser.data

func _frames(count := 5) -> void:
	for index in range(count):
		await physics_frame
	await process_frame

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	_state = root.get_node("GameState")
	for path: String in PROJECTS:
		_check_project(path)
	await _check_host("res://src/core/main.tscn")
	await _check_host("res://src/core/settlement.tscn")
	print("LATER_STORY_AUTHORING: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _check_project(path: String) -> void:
	var project := StoryProject.new()
	var error := project.open_project(path)
	_check(error == OK, "Original StoryProject accepts release envelope: " + project.last_error)
	if error != OK:
		return
	var document := project.snapshot()
	var pending: Dictionary = document.pending
	_check(not pending.beats.is_empty() and not pending.dialogues.is_empty(), "Pending work is present")
	_check(project.replace_document(document) == OK and project.snapshot().pending == pending, "Existing editor roundtrip preserves pending metadata")
	var compiled := project.compile()
	_check(compiled.story.events.is_empty() and compiled.dialogue.dialogues.is_empty() and compiled.phases.phases.is_empty(), "Pending contents cannot enter runtime products")
	for key: String in ["story", "dialogue", "phases"]:
		_check(_json(document.manifest[key]) == JSON.parse_string(JSON.stringify(compiled[key])), "Generated empty release product agrees: " + key)
	var manifest: Dictionary = _json(document.manifest.manifest_path)
	_check(manifest.authoring_project == path and manifest.authoring_sha256 == FileAccess.get_sha256(path), "Manifest identifies the saved engineering source")
	_check(manifest.beats.is_empty(), "No invented runtime step range")
	var dialogue_library := DialogueLibrary.new()
	_check(dialogue_library.load_json(JSON.stringify({"version": 1, "dialogues": pending.dialogues})) == OK, "Original DialogueLibrary validates all pending text: " + dialogue_library.last_error)
	var story_library := StoryLibrary.new()
	_check(story_library.load_json(JSON.stringify({"version": 1, "events": pending.event_drafts})) == OK, "Original StoryLibrary validates review fragments: " + story_library.last_error)
	var seen_beats: Array[String] = []
	var seen_steps: Array[String] = []
	var used_dialogues: Array[String] = []
	for beat: Dictionary in pending.beats:
		_check(beat.id not in seen_beats and beat.status == "pending" and not beat.blocked_by.is_empty(), "Stable Beat and explicit unresolved dependencies: " + beat.id)
		seen_beats.append(beat.id)
		_check(beat.source_markdown.begins_with("### Beat " + beat.id + "\n") and beat.source_end >= beat.source_start, "Source excerpt belongs to the Beat: " + beat.id)
		for line: Dictionary in beat.ordered_lines:
			_check(pending.dialogues.has(line.dialogue) and pending.dialogues[line.dialogue].lines.has(line.line), "Ordered source line resolves: " + beat.id)
		for step: Dictionary in beat.steps:
			_check(step.id not in seen_steps and step.data.command == "dialogue", "Review steps do not invent business actions: " + step.id)
			seen_steps.append(step.id)
			_check(pending.dialogues.has(step.data.id), "Review step references actual pending text")
			if step.data.id not in used_dialogues:
				used_dialogues.append(step.data.id)
		for record: Dictionary in beat.chronicles:
			var events := {"review.record": {"steps": record.steps}}
			_check(story_library.load_json(JSON.stringify({"version": 1, "events": events})) == OK, "Original StoryLibrary validates chronicle draft: " + story_library.last_error)
		if beat.has("choice"):
			var choices: Array = pending.dialogues[beat.choice.dialogue].lines[beat.choice.line].choices
			_check(choices.size() == 2 and choices[0].id == "accept" and choices[1].id == "refuse", "Stable accept/refuse choice has both paths")
	_check(used_dialogues.size() == pending.dialogues.size(), "Every pending dialogue has a Beat owner")
	_check(manifest.pending_beat_ids == seen_beats, "Manifest tracks all unresolved Beats in source order")
	var case_ids: Array[String] = []
	for item: Dictionary in pending.cases:
		_check(item.id not in case_ids and item.beat in seen_beats, "Unique case belongs to an authored Beat")
		case_ids.append(item.id)
		if item.id.ends_with(".route"):
			_check(item.status == "pending" and item.fixture == null, "Unresolved runtime case does not claim execution")
	for phase: Dictionary in pending.phases:
		_check(phase.beat in seen_beats and phase.status == "pending" and not phase.owner.is_empty() and not phase.missing.is_empty(), "Gameplay wait has a real owner and explicit gap")
		if phase.config != null:
			_check(phase.config.completion.flag != phase.config.completion_flag and phase.config.completion.allow_existing is bool, "Draft uses a separate Bridge output and explicit history policy")

func _check_host(scene: String) -> void:
	_check(_state.start_new_game() == OK and _state.select_business_profile("day1") == OK, "Clean session for route isolation")
	_state.set_story_stage("day1.investigate_coins")
	var game: MainGame = load(scene).instantiate()
	root.add_child(game)
	current_scene = game
	await _frames()
	var director := game.get_story_director()
	_check(game.get_chapter_controller().is_loaded(), "Actual host loads the preserved chapter: " + scene)
	for stage: String in ["day1.investigate_coins", "day1.s03", "day1.s04", "day1.s05", "day1.s06", "day2.placeholder"]:
		_state.set_story_stage(stage)
		await _frames()
		_check(director.get_event_ids().is_empty() and not director.is_busy(), "No pending event autoplays in " + stage)
		var before: Dictionary = _state.to_dict()
		for trigger: String in ["orders", "storage", "tea_station", "shop_exit", "fat_goblin", "guard", "drunken_guard", "day1_elder_document", "day1_blood_storage", "tavern", "casino", "unknown_later_story_route"]:
			_check(director.request_interaction(trigger) == ERR_DOES_NOT_EXIST, "Real route has no pending candidate: " + stage + "/" + trigger)
		_check(_state.to_dict() == before, "Routing unresolved content cannot manufacture completion facts")
	_check(not Day1Access.can_leave_shop(_state), "Day 2 remains the actual placeholder")
	if scene.ends_with("settlement.tscn"):
		for id: StringName in [&"00_shop_entrance", &"elder_document", &"elder_blood_storage", &"tavern_bartender", &"casino_boss", &"drunken_guard"]:
			_check(game.get_actor_director().get_position(id) != null, "Actual host registers existing Marker: " + String(id))
	current_scene = null
	game.queue_free()
	await _frames()
