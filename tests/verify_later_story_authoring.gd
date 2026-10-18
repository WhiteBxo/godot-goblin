extends SceneTree
## Published engineering sources, archived review text and real host bindings.

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
	_check(parser.parse(FileAccess.get_file_as_string(path)) == OK, "JSON parses: " + path)
	return parser.data

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	_state = root.get_node("GameState")
	for path: String in PROJECTS:
		_check_project(path)
	for scene: String in ["main", "settlement", "tavern", "casino", "elder_house"]:
		await _check_host("res://src/core/" + scene + ".tscn")
	print("LATER_STORY_AUTHORING: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _check_project(path: String) -> void:
	var project := StoryProject.new()
	_check(project.open_project(path) == OK, "StoryProject opens published source: " + project.last_error)
	var document := project.snapshot()
	_check(not document.beats.is_empty() and not document.events.is_empty(), "Published scope has actual Beats and events")
	_check(project.replace_document(document) == OK and project.snapshot() == document, "Editor roundtrip preserves published and archival content")
	var compiled := project.compile()
	for key: String in ["story", "dialogue", "phases"]:
		_check(_json(document.manifest[key]) == JSON.parse_string(JSON.stringify(compiled[key])), "Runtime product equals engineering compilation: " + key)
	var manifest: Dictionary = _json(document.manifest.manifest_path)
	_check(manifest.authoring_project == path and manifest.authoring_sha256 == FileAccess.get_sha256(path), "Manifest identifies exact saved engineering source")
	_check(manifest.beats == JSON.parse_string(JSON.stringify(compiled.manifest.beats)), "Manifest ranges equal compiled stable Beats")
	var beat_ids: Array[String] = []
	for beat: Dictionary in document.beats:
		_check(beat.id not in beat_ids, "Stable unique Beat: " + beat.id)
		beat_ids.append(beat.id)
		if beat.has("phase"):
			_check(beat.phase.completion.flag != beat.phase.completion_flag, "Player phase consumes a separate gameplay fact")
		else:
			_check(compiled.story.events.has(beat.event) and not beat.steps.is_empty(), "Published Beat owns actual event steps")
	var pending: Dictionary = document.pending
	_check(pending.beats.is_empty() and pending.dialogues.is_empty(), "Resolved two-day scope is no longer reported as pending")
	# Unpublished metadata must stay isolated, even when an editor adds review text.
	document.pending.dialogues["review.unpublished"] = {"start": "line", "lines": {"line": {"text": "审阅内容", "next": ""}}}
	_check(project.replace_document(document) == OK, "Unpublished review text remains editable")
	_check(project.compile() == compiled, "Pending text never leaks into runtime products")

func _check_host(scene: String) -> void:
	_check(_state.start_new_game() == OK and _state.select_business_profile("day1") == OK, "Clean session for real host")
	_state.set_story_stage("day1.s03.explore")
	var game: MainGame = load(scene).instantiate()
	root.add_child(game)
	current_scene = game
	for frame in range(10):
		await process_frame
	var director := game.get_story_director()
	_check(game.get_chapter_controller().is_loaded() and not director.get_event_ids().is_empty(), "Real host loads published chapter: " + scene)
	var before: Dictionary = _state.to_dict()
	_check(director.request_interaction("unknown_later_story_route") == ERR_DOES_NOT_EXIST, "Unknown route has no fabricated candidate")
	_check(_state.to_dict() == before and not director.is_busy(), "Rejected route leaves all gameplay state unchanged")
	_check(game.get_chapter_gameplay() != null, "Host injects one scene-local business adapter")
	if scene.ends_with("settlement.tscn"):
		_check(game.get_actor_director().get_actor(&"entrance_guard") != null, "Cave registers the actual entrance guard")
		_check(game.get_actor_director().get_position(&"drunken_guard") != null, "Cave preserves guard handoff position")
	elif scene.ends_with("elder_house.tscn"):
		_check(game.get_actor_director().get_position(&"elder_document") != null, "Elder interior owns the document position")
	current_scene = null
	game.queue_free()
	await process_frame
