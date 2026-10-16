class_name StoryDirector
extends Node
## Scene-local sequence runner. The host owns input locks, never this module.

signal event_started(event_id: String)
signal event_finished(event_id: String, succeeded: bool, reason: String)
signal event_completed(event_id: String)
signal step_started(event_id: String, index: int, command: String)
signal step_skipped(event_id: String, index: int, reason: String)
signal choice_received(event_id: String, dialogue_id: String, line_id: String, choice_id: String)

const StateData = preload("res://src/core/game_state.gd")

@export_file("*.json") var event_file: String = ""

var last_error: String = ""
var _library := StoryLibrary.new()
var _state: StateData
var _loaded: bool = false
var _manager: DialogueManager
var _can_start: Callable
var _event_id: String = ""
var _event: Dictionary = {}
var _index: int = 0
var _generation: int = 0
var _pending: bool = false
var _finishing: bool = false
var _starting_dialogue: bool = false
var _waiting_dialogue: String = ""
var _choices: Dictionary = {}
var _timer: Timer
var _audio: StoryAudioAdapter
var _actors: ActorDirector
var _cameras: CameraDirector
var _actions: Dictionary = {}
var _used_camera := false


func _ready() -> void:
	_state = get_node("/root/GameState") as StateData
	_timer = Timer.new()
	_timer.one_shot = true
	add_child(_timer)
	_timer.timeout.connect(_schedule_next)
	_state.state_reset.connect(cancel_event.bind("GameState reset"))
	_state.state_restored.connect(cancel_event.bind("GameState restored"))
	set_process(false)


func configure(manager: DialogueManager, can_start: Callable = Callable()) -> void:
	cancel_event("Director reconfigured")
	if is_instance_valid(_manager):
		_manager.dialogue_ended.disconnect(_on_dialogue_ended)
		_manager.choice_selected.disconnect(_on_choice_selected)
		_manager.tree_exiting.disconnect(_on_manager_exiting)
	_manager = manager
	_can_start = can_start
	if is_instance_valid(_manager):
		_manager.dialogue_ended.connect(_on_dialogue_ended)
		_manager.choice_selected.connect(_on_choice_selected)
		_manager.tree_exiting.connect(_on_manager_exiting)


func set_audio_adapter(adapter: StoryAudioAdapter) -> void:
	cancel_event("Audio adapter replaced")
	_audio = adapter


func configure_cinematic(actors: ActorDirector, cameras: CameraDirector = null) -> void:
	cancel_event("Cinematic services replaced")
	for service: Node in [_actors, _cameras]:
		if is_instance_valid(service) and service.tree_exiting.is_connected(_on_service_exiting):
			service.tree_exiting.disconnect(_on_service_exiting)
	if is_instance_valid(_cameras) and _cameras.camera_recovered.is_connected(_on_camera_recovered):
		_cameras.camera_recovered.disconnect(_on_camera_recovered)
	_actors = actors
	_cameras = cameras
	for service: Node in [_actors, _cameras]:
		if is_instance_valid(service):
			service.tree_exiting.connect(_on_service_exiting)
	if is_instance_valid(_cameras):
		_cameras.camera_recovered.connect(_on_camera_recovered)


func _on_service_exiting() -> void:
	cancel_event("Cinematic service exited")


func _on_camera_recovered(reason: String) -> void:
	if _used_camera:
		cancel_event(reason)


func load_events(path: String = "") -> Error:
	if is_busy() or _finishing:
		return ERR_BUSY
	var error := _library.load_file(event_file if path.is_empty() else path)
	last_error = _library.last_error
	if error == OK:
		_loaded = true
	return error


func is_busy() -> bool:
	return not _event_id.is_empty()


## Allows the host's dialogue guard to reserve the manager for this sequence.
func is_starting_dialogue() -> bool:
	return _starting_dialogue


func get_choice(dialogue_id: String, line_id: String) -> String:
	return _choices.get(dialogue_id, {}).get(line_id, "")


func request_event(id: String) -> Error:
	last_error = ""
	if is_busy() or _finishing:
		return _reject(ERR_BUSY, "Another story sequence is running or finishing")
	if not _is_configured():
		return _reject(ERR_UNCONFIGURED, "StoryDirector requires a scene and DialogueManager")
	if _manager.is_active() or (_can_start.is_valid() and not _can_start.call()):
		return _reject(ERR_BUSY, "Dialogue or host popup is active")
	var load_error := _ensure_loaded()
	if load_error != OK:
		return load_error
	var event := _library.get_event(id)
	if event.is_empty():
		return _reject(ERR_DOES_NOT_EXIST, "Unknown story event: " + id)
	if event.get("once", true) and _state.is_event_completed(id):
		return _reject(ERR_ALREADY_EXISTS, "Story event already completed: " + id)
	if not _matches(event.get("conditions", {})):
		return _reject(ERR_UNAUTHORIZED, "Story conditions not met: " + id)
	_event_id = id
	_event = event
	_index = 0
	_generation += 1
	_choices.clear()
	_pending = true
	set_process(true)
	event_started.emit(id)
	return OK


## First eligible JSON event wins. No matching route means ShopUI may handle it.
func request_interaction(interaction_id: String) -> Error:
	last_error = ""
	if is_busy() or _finishing:
		return _reject(ERR_BUSY, "Story sequence is busy")
	if not _is_configured():
		return _reject(ERR_UNCONFIGURED, "StoryDirector requires a scene and DialogueManager")
	var load_error := _ensure_loaded()
	if load_error != OK:
		return load_error
	for id: String in _library.get_event_ids():
		var event := _library.get_event(id)
		if event.get("trigger", "") != interaction_id or interaction_id.is_empty():
			continue
		if event.get("once", true) and _state.is_event_completed(id):
			continue
		if _matches(event.get("conditions", {})):
			return request_event(id)
	return ERR_DOES_NOT_EXIST


func cancel_event(reason: String = "Cancelled") -> void:
	if is_busy() and not _finishing:
		_finish(false, reason)


func _is_configured() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and is_instance_valid(_state) and is_instance_valid(_manager) and _manager.is_inside_tree()


func _ensure_loaded() -> Error:
	if _loaded or event_file.is_empty():
		return OK
	return load_events()


func _reject(error: Error, message: String) -> Error:
	last_error = message
	return error


func _matches(conditions: Dictionary) -> bool:
	if conditions.has("day") and _state.current_day != int(conditions["day"]):
		return false
	if conditions.has("stage") and _state.story_stage != conditions["stage"]:
		return false
	for key: String in conditions.get("flags", {}):
		if _state.get_flag(key) != conditions["flags"][key]:
			return false
	for id: String in conditions.get("completed_events", []):
		if not _state.is_event_completed(id):
			return false
	for id: String in conditions.get("not_completed_events", []):
		if _state.is_event_completed(id):
			return false
	if conditions.has("choice"):
		var choice: Dictionary = conditions["choice"]
		if get_choice(choice["dialogue"], choice["line"]) != choice["id"]:
			return false
	return true


## One step per process tick: no recursive dispatch or suspended coroutines.
## Timer and this pump inherit Systems' pause mode.
func _process(_delta: float) -> void:
	if not _pending:
		return
	_pending = false
	var generation := _generation
	if _index == _event["steps"].size():
		# Drain visual actions launched without wait. Legacy SFX never delays the tail.
		for data: Dictionary in _actions.values():
			if data.kind != "audio":
				return
		_finish(true)
		return
	var step: Dictionary = _event["steps"][_index]
	if not _matches(step.get("when", {})):
		step_skipped.emit(_event_id, _index, "Step conditions not met")
		if _is_current(generation):
			_schedule_next()
		return
	step_started.emit(_event_id, _index, step["command"])
	if not _is_current(generation):
		return
	match step["command"]:
		"dialogue":
			_waiting_dialogue = step["id"]
			_starting_dialogue = true
			var error := _manager.start_dialogue(_waiting_dialogue)
			_starting_dialogue = false
			if _is_current(generation) and error != OK:
				_finish(false, "Dialogue '%s' failed (%d): %s" % [step["id"], error, _manager.last_error])
			return
		"wait":
			if step["seconds"] > 0:
				_timer.start(step["seconds"])
				return
		"set_flag":
			_state.set_flag(step["key"], step.get("value", true))
		"set_stage":
			_state.set_story_stage(step["value"])
		"play_sfx", "play_bgm", "stop_bgm", "fade_bgm":
			_dispatch_audio(step, generation)
			return
		"actor_spawn", "actor_move", "actor_face", "actor_emote", "actor_show", "actor_hide":
			_dispatch_actor(step, generation)
			return
		"camera_focus", "camera_move", "camera_shake", "camera_zoom", "camera_reset":
			_dispatch_camera(step, generation)
			return
	if _is_current(generation):
		_schedule_next()


func _is_current(generation: int) -> bool:
	return is_busy() and not _finishing and generation == _generation


func _schedule_next() -> void:
	if not is_busy() or _finishing:
		return
	_index += 1
	_pending = true


func _target(value: Variant) -> Variant:
	if value is Array:
		return Vector2(value[0], value[1])
	return StringName(value)


func _dispatch_actor(step: Dictionary, generation: int) -> void:
	if not is_instance_valid(_actors):
		_finish(false, "ActorDirector unavailable")
		return
	var action: ActorAction
	var actor := StringName(step.actor)
	match step.command:
		"actor_spawn":
			var scene: PackedScene
			if ResourceLoader.exists(step.scene, "PackedScene"):
				scene = load(step.scene) as PackedScene
			action = _actors.actor_spawn(actor, scene, _target(step.target))
		"actor_move": action = _actors.actor_move(actor, _target(step.target), step.get("speed", 120.0), step.get("timeout", 15.0))
		"actor_face": action = _actors.actor_face(actor, StringName(step.direction))
		"actor_emote": action = _actors.actor_emote(actor, step.get("symbol", "!"), step.get("duration", 0.8))
		"actor_show": action = _actors.actor_show(actor)
		"actor_hide": action = _actors.actor_hide(actor)
	if not _is_current(generation):
		if is_instance_valid(_actors):
			_actors.cancel_action(action)
		return
	_track(action, "actor", step.get("wait", true), generation)


func _camera_channel(command: String) -> String:
	return command if command in ["camera_zoom", "camera_shake"] else "position"


## Retire owned non-blocking requests before intentional channel replacement/reset.
## External cancellation still fails the sequence through its normal result.
func _retire_camera(command: String) -> void:
	for action: RefCounted in _actions.keys():
		var data: Dictionary = _actions[action]
		if data.kind == "camera" and (command == "camera_reset" or data.channel == _camera_channel(command)):
			_untrack(action)


func _dispatch_camera(step: Dictionary, generation: int) -> void:
	if not is_instance_valid(_cameras):
		_finish(false, "CameraDirector unavailable")
		return
	var target: Variant
	if step.has("actor"):
		target = _actors.get_actor(StringName(step.actor)) if is_instance_valid(_actors) else null
	elif step.has("target"):
		target = _target(step.target)
		if target is StringName:
			target = _actors.get_position(target) if is_instance_valid(_actors) else null
	if step.command in ["camera_focus", "camera_move"] and target == null:
		_finish(false, "Camera target unavailable")
		return
	_retire_camera(step.command)
	var action: CameraAction
	_used_camera = true
	match step.command:
		"camera_focus": action = _cameras.camera_focus(target, step.get("duration", 0.8))
		"camera_move": action = _cameras.camera_move(target.global_position if target is Node2D else target, step.get("duration", 0.8))
		"camera_shake": action = _cameras.camera_shake(step.get("intensity", 2.0), step.get("duration", 0.3), step.get("decay", 1.5))
		"camera_zoom": action = _cameras.camera_zoom(step.value, step.get("duration", 0.5))
		"camera_reset": action = _cameras.camera_reset()
	if _is_current(generation):
		_track(action, "camera", step.get("wait", true), generation, _camera_channel(step.command))


func _dispatch_audio(step: Dictionary, generation: int) -> void:
	if _audio == null:
		step_skipped.emit(_event_id, _index, "Optional audio adapter unavailable")
		if _is_current(generation):
			_schedule_next()
		return
	var action := _audio.request(step)
	if not _audio.last_error.is_empty():
		step_skipped.emit(_event_id, _index, _audio.last_error)
	if _is_current(generation):
		# A newer BGM transition intentionally replaces its predecessor.
		if step.command != "play_sfx":
			for old: RefCounted in _actions.keys():
				if _actions[old].channel == "music":
					_untrack(old)
		_track(action, "audio", step.get("wait", step.command != "play_sfx"), generation, "sfx" if step.command == "play_sfx" else "music")


func _track(action: RefCounted, kind: String, blocking: bool, generation: int, channel: String = "") -> void:
	var callback := _on_action_finished.bind(generation)
	_actions[action] = {"kind": kind, "wait": blocking, "index": _index, "callback": callback, "channel": channel}
	action.finished.connect(callback)
	if not blocking:
		_schedule_next()


func _untrack(action: RefCounted) -> void:
	var callback: Callable = _actions[action].callback
	_actions.erase(action)
	if action.finished.is_connected(callback):
		action.finished.disconnect(callback)


func _on_action_finished(action: RefCounted, generation: int) -> void:
	if not _is_current(generation) or not _actions.has(action):
		return
	var data: Dictionary = _actions[action]
	_untrack(action) # Consume before signals or scheduling: duplicate notices are harmless.
	var succeeded: bool = action.result == CameraAction.Result.COMPLETED if action is CameraAction else action.succeeded
	if not succeeded:
		_finish(false, "Action from steps[%d] failed: %s" % [data.index, action.reason])
	elif data.wait and data.index == _index:
		_schedule_next()
	elif _index == _event["steps"].size():
		_pending = true


func _cancel_actions() -> void:
	for action: RefCounted in _actions.keys():
		_untrack(action)
		if action is ActorAction and is_instance_valid(_actors):
			_actors.cancel_action(action, "Story finished")
	if _used_camera and is_instance_valid(_cameras):
		_cameras.cancel_all("Story finished")
	_used_camera = false


func _on_dialogue_ended(id: String, cancelled: bool) -> void:
	if not is_busy() or _finishing or _waiting_dialogue != id:
		return
	_waiting_dialogue = ""
	if cancelled:
		_finish(false, "Dialogue cancelled: " + id)
	else:
		_schedule_next()


func _on_choice_selected(id: String, line: String, choice: String) -> void:
	if not is_busy() or _finishing or _waiting_dialogue != id:
		return
	if not _choices.has(id):
		_choices[id] = {}
	_choices[id][line] = choice
	choice_received.emit(_event_id, id, line, choice)


func _on_manager_exiting() -> void:
	cancel_event("DialogueManager exited")


func _finish(succeeded: bool, reason: String = "") -> void:
	if not is_busy() or _finishing:
		return
	_finishing = true
	var id := _event_id
	_generation += 1
	_pending = false
	set_process(false)
	_timer.stop()
	_cancel_actions()
	if not _waiting_dialogue.is_empty() and is_instance_valid(_manager):
		_manager.end_dialogue(true)
	_waiting_dialogue = ""
	if _audio != null:
		_audio.stop_owned()
	if succeeded and _event.get("once", true):
		_state.complete_event(id)
	_event_id = ""
	_event = {}
	var finish_error := "" if succeeded else "%s/steps[%d]: %s" % [id, _index, reason]
	last_error = finish_error
	if succeeded:
		event_completed.emit(id)
	event_finished.emit(id, succeeded, finish_error)
	_finishing = false


func _exit_tree() -> void:
	cancel_event("StoryDirector exited")
