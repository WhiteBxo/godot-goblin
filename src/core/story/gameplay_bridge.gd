class_name GameplayBridge
extends Node
## Scene-local gameplay handoff only. StoryDirector still runs every cinematic step.

signal phase_started(id: String)
signal continuation_failed(event_id: String, error: Error)

const StateData = preload("res://src/core/game_state.gd")
var last_error := ""
var _state: StateData
var _director: StoryDirector
var _ui: UIManager
var _tea: TeaMaking
var _links: Array[Dictionary] = []
var _active: Dictionary = {}
var _session := 0
var _inflight := ""
var _enabled := false
var _requesting := false
var _waiting := false

func configure(director: StoryDirector, ui: UIManager, tea: TeaMaking) -> void:
	_director = director
	_ui = ui
	_tea = tea
	_state = get_node("/root/GameState") as StateData
	_tea.recipe_completed.connect(_on_recipe_completed)
	_state.state_reset.connect(stop)
	_state.state_restored.connect(stop)
	_director.event_finished.connect(_on_event_finished)
	_director.tree_exiting.connect(stop)
	_ui.tree_exiting.connect(stop)
	_tea.tree_exiting.connect(stop)

## Reload/resume is explicit: restore never replays story effects automatically.
func load_phases(path: String) -> Error:
	last_error = ""
	if _director.is_busy():
		return ERR_BUSY
	if not FileAccess.file_exists(path):
		last_error = "Phase file does not exist: " + path
		return ERR_FILE_NOT_FOUND
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		last_error = "Phase JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		return ERR_PARSE_ERROR
	var data: Variant = parser.data
	if not data is Dictionary or data.size() != 2 or typeof(data.get("version")) not in [TYPE_INT, TYPE_FLOAT] or data.version != 1 or not data.get("phases") is Array:
		return _invalid_phase(path)
	var links: Array[Dictionary] = []
	var used: Dictionary = {}
	for link: Variant in data.phases:
		if not link is Dictionary or link.size() != 6 or not link.has_all(["id", "after_event", "stage", "recipe", "completion_flag", "next_event"]):
			return _invalid_phase(path)
		for key: String in link:
			if not link[key] is String or link[key].is_empty():
				return _invalid_phase(path)
		for key: String in ["id", "after_event", "completion_flag", "next_event"]:
			if not StoryLibrary.is_namespaced(link[key]):
				return _invalid_phase(path)
		if not TeaMaking.RECIPES.has(link.recipe) or link.after_event == link.next_event:
			return _invalid_phase(path)
		for key: String in ["id", "stage", "completion_flag", "after_event", "next_event"]:
			var unique: String = key + ":" + link[key]
			if used.has(unique):
				return _invalid_phase(path)
			used[unique] = true
		links.append(link.duplicate(true))
	stop()
	_links = links
	_enabled = true
	last_error = ""
	return OK

func stop() -> void:
	_enabled = false
	_inflight = ""
	_active = {}
	_waiting = false
	if is_instance_valid(_tea) and not _tea.is_queued_for_deletion():
		_tea.cancel()

func allows_story_start() -> bool:
	# Reserve the gameplay phase even before this component's next process tick.
	if _requesting or not _inflight.is_empty() or not _enabled:
		return true
	if not _active.is_empty():
		return false
	for link: Dictionary in _links:
		if _eligible(link):
			return false
	return true

func _eligible(link: Dictionary) -> bool:
	return (_state.story_stage == link.stage and _state.is_event_completed(link.after_event)
		and not _state.is_event_completed(link.next_event))

func _process(_delta: float) -> void:
	if not _enabled:
		return
	if not is_instance_valid(_director) or not is_instance_valid(_ui) or not is_instance_valid(_tea):
		stop()
		return
	if not _active.is_empty() and not _eligible(_active):
		stop() # External stage changes invalidate pending sessions and continuations.
		return
	if not _inflight.is_empty() or _director.is_busy() or get_tree().paused:
		return
	if _active.is_empty():
		for link: Dictionary in _links:
			if _eligible(link):
				_active = link
				_waiting = _state.get_flag(link.completion_flag)
				if not _waiting:
					_session = _tea.begin(link.recipe)
				phase_started.emit(link.id)
				return # Never start a continuation in the activation callback stack.
	if _active.is_empty() or not _waiting or _ui.has_modal():
		return
	var next: String = _active.next_event
	_requesting = true
	_inflight = next # Reserve before synchronous event_started listeners can cancel.
	var error := _director.request_event(next)
	_requesting = false
	if not _enabled:
		return
	if error != OK:
		_inflight = ""
	if error == ERR_BUSY:
		return
	if error != OK:
		last_error = "Continuation %s rejected (%d): %s" % [next, error, _director.last_error]
		stop()
		continuation_failed.emit(next, error)
		return
	_active = {}
	_waiting = false
	_tea.cancel()

func _on_recipe_completed(recipe: String, session: int) -> void:
	if not _enabled or _active.is_empty() or _waiting or session != _session:
		return
	if recipe != _active.recipe or not _eligible(_active) or _director.is_busy() or get_tree().paused:
		return
	_waiting = true
	_state.set_flag(_active.completion_flag)

func _on_event_finished(id: String, succeeded: bool, _reason: String) -> void:
	if id != _inflight:
		return
	_inflight = ""
	if not succeeded:
		stop() # Cancellation/error needs an explicit host retry, never autoplay.

func _invalid_phase(path: String) -> Error:
	last_error = "Invalid phase data: " + path
	return ERR_INVALID_DATA

func _exit_tree() -> void:
	stop()
