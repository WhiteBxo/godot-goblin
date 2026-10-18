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
var _flag_armed := false
var _invalidated := false
var _can_advance: Callable

func configure(director: StoryDirector, ui: UIManager, tea: TeaMaking = null, can_advance: Callable = Callable()) -> void:
	_can_advance = can_advance
	_director = director
	_ui = ui
	_tea = tea
	_state = get_node("/root/GameState") as StateData
	if is_instance_valid(_tea):
		_tea.recipe_completed.connect(_on_recipe_completed)
		_tea.tree_exiting.connect(stop)
	_state.state_changed.connect(_on_state_changed)
	_state.state_reset.connect(stop.bind(true))
	_state.state_restored.connect(stop.bind(true))
	_director.event_finished.connect(_on_event_finished)
	_director.tree_exiting.connect(stop)
	_ui.tree_exiting.connect(stop)

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
	if not data is Dictionary or data.size() != 2 or typeof(data.get("version")) not in [TYPE_INT, TYPE_FLOAT] or (data.version != 1 and data.version != 2) or not data.get("phases") is Array:
		return _invalid_phase(path)
	var links: Array[Dictionary] = []
	var used: Dictionary = {}
	for link: Variant in data.phases:
		var source_key := "recipe" if data.version == 1 else "completion"
		if not link is Dictionary or link.size() < 6 or link.size() > 7 or not link.has_all(["id", "after_event", "stage", source_key, "completion_flag", "next_event"]):
			return _invalid_phase(path)
		if link.has("allow_travel") and not link.allow_travel is bool:
			return _invalid_phase(path)
		for key: String in link:
			if key in ["completion", "allow_travel"]:
				continue
			if not link[key] is String or link[key].is_empty():
				return _invalid_phase(path)
		for key: String in ["id", "after_event", "completion_flag", "next_event"]:
			if not StoryLibrary.is_namespaced(link[key]):
				return _invalid_phase(path)
		if link.after_event == link.next_event:
			return _invalid_phase(path)
		if data.version == 1:
			if not is_instance_valid(_tea) or not _tea.has_recipe(link.recipe):
				return _invalid_phase(path)
		else:
			var condition: Variant = link.completion
			if not condition is Dictionary or condition.size() != 2 or not condition.has_all(["flag", "allow_existing"]):
				return _invalid_phase(path)
			if not StoryLibrary.is_namespaced(condition.flag) or not condition.allow_existing is bool or condition.flag == link.completion_flag:
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

func stop(preserve_wait: bool = false) -> void:
	var previous := _active
	_enabled = false
	_inflight = ""
	_active = {}
	_waiting = false
	_flag_armed = false
	_invalidated = false
	if not preserve_wait and previous.has("completion"):
		_state.set_variable(previous.id + ".bridge_wait", null)
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

## Only explicitly authored travel waits may cross hosts. Legacy waits stay local.
func allows_scene_travel() -> bool:
	if allows_story_start():
		return true
	return not _active.is_empty() and bool(_active.get("allow_travel", false))

## Independent read-only snapshot for tooling. Reads existing fields only: it
## never loads phases, dispatches continuations or mutates wait/reservation state.
func get_runtime_status() -> Dictionary:
	var link: Dictionary = _active
	return {"enabled": _enabled, "phase_count": _links.size(),
		"phase_id": str(link.get("id", "")), "stage": str(link.get("stage", "")),
		"next_event": str(link.get("next_event", "")), "waiting": _waiting,
		"inflight": _inflight, "allows_story_start": allows_story_start(),
		"last_error": last_error}

func _eligible(link: Dictionary) -> bool:
	return (_state.story_stage == link.stage and _state.is_event_completed(link.after_event)
		and not _state.is_event_completed(link.next_event))

func _process(_delta: float) -> void:
	if _can_advance.is_valid() and not _can_advance.call():
		return
	if not _enabled:
		return
	if not is_instance_valid(_director) or not is_instance_valid(_ui) or (_active.has("recipe") and not is_instance_valid(_tea)):
		stop()
		return
	if _invalidated or (not _active.is_empty() and not _eligible(_active)):
		stop() # External stage changes invalidate pending sessions and continuations.
		return
	if _active.has("completion"):
		_on_state_changed()
		if not _enabled:
			return
		_save_flag_wait()
		if not _enabled or _invalidated:
			return
	if not _inflight.is_empty() or _director.is_busy() or get_tree().paused:
		return
	if _active.is_empty():
		for link: Dictionary in _links:
			if _eligible(link):
				_active = link
				_waiting = _state.get_flag(link.completion_flag)
				if not _waiting and link.has("recipe"):
					_session = _tea.begin(link.recipe)
				elif not _waiting:
					var saved: Variant = _state.get_variable(link.id + ".bridge_wait")
					var resumed: bool = saved is Dictionary and saved.get("flag") == link.completion.flag and saved.get("armed") == true
					_flag_armed = resumed or link.completion.allow_existing or not _state.get_flag(link.completion.flag)
					_on_state_changed()
					if _enabled:
						_save_flag_wait()
				if not _enabled:
					return
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
		last_error = "Continuation %s rejected (%d): %s" % [next, error, _director.last_error]
		stop()
		continuation_failed.emit(next, error)
		return
	var previous := _active
	_active = {}
	_waiting = false
	if previous.has("completion"):
		_state.set_variable(previous.id + ".bridge_wait", null)
	if is_instance_valid(_tea):
		_tea.cancel()

func _on_state_changed() -> void:
	# Record only an active wait. Never activate/start story from synchronous signals.
	if not _enabled or _active.is_empty():
		return
	if not _eligible(_active):
		_invalidated = true
		return
	if _waiting or not _active.has("completion"):
		return
	var satisfied := _state.get_flag(_active.completion.flag)
	if not satisfied:
		_flag_armed = true
	elif _flag_armed:
		_waiting = true

func _save_flag_wait() -> void:
	# Mutate snapshots only from the process boundary, never inside restore_state's
	# state_changed notification (which precedes state_restored).
	_state.set_variable(_active.id + ".bridge_wait", {"flag": _active.completion.flag, "armed": _flag_armed})
	if _enabled and not _invalidated and not _active.is_empty() and _eligible(_active) and _waiting:
		_state.set_flag(_active.completion_flag)

func _on_recipe_completed(recipe: String, session: int) -> void:
	if not _enabled or _invalidated or _active.is_empty() or _waiting or session != _session:
		return
	if not _active.has("recipe") or recipe != _active.recipe or not _eligible(_active) or _director.is_busy() or get_tree().paused:
		return
	if not is_instance_valid(_tea) or not _tea.is_completed_session(recipe, session):
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
