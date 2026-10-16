class_name ActorDirector
extends Node
## Scene-local presentation only. No story flags, conditions or sequence dispatch.
## One exclusive action per actor; another director cannot claim the same body.

signal action_finished(action: ActorAction)
signal actor_control_changed(actor_id: StringName, controlled: bool)

const ARRIVAL_DISTANCE := 0.5

@export_range(0.1, 10.0, 0.1) var blocked_timeout := 1.0

var last_error := ""
var _actors: Dictionary = {}
var _positions: Dictionary = {}
var _active: Dictionary = {}
var _pending: Array[Dictionary] = []
var _entity_root: Node2D
var _next_id := 0
var _closing := false
var _changing := false

func configure(entity_root: Node2D) -> void:
	_entity_root = entity_root

func actor_register(actor_id: StringName, actor: PlayerController) -> Error:
	if _closing or _changing or not is_inside_tree():
		return _registration_error(ERR_UNCONFIGURED, "ActorDirector is unavailable")
	if actor_id.is_empty() or not _valid_actor(actor):
		return _registration_error(ERR_INVALID_PARAMETER, "actor_register requires a non-empty ID and a ready PlayerController")
	if _actors.has(actor_id):
		return _registration_error(ERR_ALREADY_EXISTS, "Actor ID already registered: %s" % actor_id)
	for entry: Dictionary in _actors.values():
		if entry.actor == actor:
			return _registration_error(ERR_ALREADY_EXISTS, "Actor body already has an ID")
	var on_exit := _on_actor_exiting.bind(actor_id)
	actor.tree_exiting.connect(on_exit)
	_actors[actor_id] = {"actor": actor, "on_exit": on_exit, "spawned": false}
	last_error = ""
	return OK

func actor_unregister(actor_id: StringName) -> Error:
	if _changing:
		return _registration_error(ERR_BUSY, "Actor registry is changing")
	if not _actors.has(actor_id):
		return _registration_error(ERR_DOES_NOT_EXIST, "Unknown actor: %s" % actor_id)
	if _active.has(actor_id):
		_finish(actor_id, ERR_SKIP, "Actor unregistered: %s" % actor_id)
	var entry: Dictionary = _actors[actor_id]
	var actor: PlayerController = entry.actor
	if is_instance_valid(actor) and actor.tree_exiting.is_connected(entry.on_exit):
		actor.tree_exiting.disconnect(entry.on_exit)
	_actors.erase(actor_id)
	return OK

func get_actor(actor_id: StringName) -> PlayerController:
	var actor: PlayerController = _actors.get(actor_id, {}).get("actor")
	return actor if _valid_actor(actor) else null

func is_actor_controlled(actor_id: StringName) -> bool:
	return _active.has(actor_id) and _active[actor_id].get("claimed", false)

func register_position(position_id: StringName, marker: Marker2D) -> Error:
	if position_id.is_empty() or not is_instance_valid(marker) or not marker.is_inside_tree():
		return _registration_error(ERR_INVALID_PARAMETER, "Position requires a non-empty ID and a Marker2D in the scene")
	if _positions.has(position_id):
		return _registration_error(ERR_ALREADY_EXISTS, "Position ID already registered: %s" % position_id)
	_positions[position_id] = weakref(marker)
	return OK

func get_position(position_id: StringName) -> Marker2D:
	var reference: WeakRef = _positions.get(position_id)
	var marker := reference.get_ref() as Marker2D if reference != null else null
	return marker if is_instance_valid(marker) and marker.is_inside_tree() and not marker.is_queued_for_deletion() else null

func unregister_position(position_id: StringName) -> void:
	_positions.erase(position_id)

## Targets: global Vector2, Marker2D, or a registered String/StringName. No NodePaths.
func actor_spawn(actor_id: StringName, scene: PackedScene, target: Variant) -> ActorAction:
	var action := _request(actor_id, &"spawn", false)
	if action.completed:
		return action
	if _actors.has(actor_id) or scene == null or not scene.can_instantiate() or not is_instance_valid(_entity_root) or not _entity_root.is_inside_tree():
		_finish(actor_id, ERR_INVALID_PARAMETER, "Spawn requires an unused Actor ID, scene and configured EntityRoot: %s" % actor_id)
		return action
	_prepare_target(actor_id, target)
	if not action.completed:
		_active[actor_id].scene = scene
	return action

func actor_move(actor_id: StringName, target: Variant, speed: float = 120.0, timeout: float = 15.0) -> ActorAction:
	var action := _request(actor_id, &"move")
	if action.completed:
		return action
	if not is_finite(speed) or speed <= 0.0 or not is_finite(timeout) or timeout <= 0.0:
		_finish(actor_id, ERR_INVALID_PARAMETER, "Move speed and timeout must be finite and positive: %s" % actor_id)
		return action
	_prepare_target(actor_id, target)
	if not action.completed:
		_active[actor_id].merge({"speed": speed, "timeout": timeout, "elapsed": 0.0, "stalled": 0.0})
	return action

func actor_face(actor_id: StringName, direction: StringName) -> ActorAction:
	var action := _request(actor_id, &"face")
	if not action.completed:
		var index := PlayerController.DIRECTION_NAMES.find(direction)
		if index < 0:
			_finish(actor_id, ERR_INVALID_PARAMETER, "Facing must be up/down/left/right: %s" % direction)
		else:
			_active[actor_id].direction = index
	return action

func actor_show(actor_id: StringName) -> ActorAction:
	return _request(actor_id, &"show")

func actor_hide(actor_id: StringName) -> ActorAction:
	return _request(actor_id, &"hide")

func actor_emote(actor_id: StringName, symbol: String = "!", duration: float = 0.8) -> ActorAction:
	var action := _request(actor_id, &"emote")
	if not action.completed:
		if symbol.strip_edges().is_empty() or not is_finite(duration) or duration <= 0.0:
			_finish(actor_id, ERR_INVALID_PARAMETER, "Emote requires text and a finite positive duration: %s" % actor_id)
		else:
			_active[actor_id].merge({"symbol": symbol, "duration": duration})
	return action

## Cancel by handle so an old callback cannot cancel a newer action on this actor.
func cancel_action(action: ActorAction, reason: String = "Action cancelled") -> void:
	if action != null and not action.completed and _active.has(action.actor_id) and _active[action.actor_id].action == action:
		_finish(action.actor_id, ERR_SKIP, reason)

func cancel_all(reason: String = "Performance cancelled") -> void:
	# Block reentrant requests while all claims are being released.
	var was_closing := _closing
	_closing = true
	for actor_id: StringName in _active.keys():
		_finish(actor_id, ERR_SKIP, reason)
	_closing = was_closing

func _registration_error(error: Error, message: String) -> Error:
	last_error = message
	return error

func _valid_actor(actor: PlayerController) -> bool:
	return is_instance_valid(actor) and actor.is_inside_tree() and actor.is_node_ready() and not actor.is_queued_for_deletion()

func _request(actor_id: StringName, command: StringName, claim: bool = true) -> ActorAction:
	var action := ActorAction.new()
	_next_id += 1
	action.id = _next_id
	action.actor_id = actor_id
	action.command = command
	action.finished.connect(_on_action_finished)
	if _closing or _changing or not is_inside_tree() or is_queued_for_deletion():
		_reject(action, ERR_UNCONFIGURED, "ActorDirector is unavailable")
		return action
	if actor_id.is_empty() or _active.has(actor_id):
		_reject(action, ERR_BUSY, "Empty or busy Actor ID: %s" % actor_id)
		return action
	var actor := get_actor(actor_id)
	if claim and actor == null:
		_reject(action, ERR_DOES_NOT_EXIST, "Unknown or unavailable actor: %s" % actor_id)
		return action
	if claim and not actor.claim_performance_control(self):
		_reject(action, ERR_BUSY, "Actor is controlled by another performance: %s" % actor_id)
		return action
	var data := {"action": action, "claimed": claim, "started": false}
	_active[actor_id] = data
	_pending.append(data)
	last_error = ""
	if claim:
		_changing = true
		actor_control_changed.emit(actor_id, true)
		_changing = false
	return action

func _prepare_target(actor_id: StringName, target: Variant) -> void:
	var data: Dictionary = _active[actor_id]
	if target is String or target is StringName:
		var reference: WeakRef = _positions.get(StringName(target))
		target = reference.get_ref() if reference != null else null
	if target is Marker2D and is_instance_valid(target) and target.is_inside_tree() and not target.is_queued_for_deletion() and target.global_position.is_finite():
		data.marker = weakref(target)
		data.target = target.global_position
	elif target is Vector2 and target.is_finite():
		data.target = target
	else:
		_finish(actor_id, ERR_DOES_NOT_EXIST, "Missing or invalid target for actor: %s" % actor_id)

func _physics_process(delta: float) -> void:
	var pending := _pending
	_pending = []
	for data in pending:
		var action: ActorAction = data.action
		if not action.completed:
			_start(action.actor_id, data)
	for actor_id: StringName in _active.keys():
		if not _active.has(actor_id):
			continue
		var data: Dictionary = _active[actor_id]
		if data.action.command == &"move" and data.started:
			_tick_move(actor_id, data, delta)

func _target_alive(data: Dictionary) -> bool:
	if not data.has("marker"):
		return true
	var marker: Marker2D = data.marker.get_ref()
	return is_instance_valid(marker) and marker.is_inside_tree() and not marker.is_queued_for_deletion()

func _start(actor_id: StringName, data: Dictionary) -> void:
	data.started = true
	if not _target_alive(data):
		_finish(actor_id, ERR_DOES_NOT_EXIST, "Target Marker2D exited: %s" % actor_id)
		return
	if data.action.command == &"spawn":
		if not is_instance_valid(_entity_root) or not _entity_root.is_inside_tree() or _entity_root.is_queued_for_deletion():
			_finish(actor_id, ERR_UNCONFIGURED, "Spawn EntityRoot exited")
			return
		var instance: Node = data.scene.instantiate()
		if not instance is PlayerController:
			instance.free()
			_finish(actor_id, ERR_INVALID_DATA, "Actor scene root must extend PlayerController: %s" % actor_id)
			return
		# Set position before _ready, including transformed EntityRoot containers.
		instance.position = _entity_root.to_local(data.target)
		_entity_root.add_child(instance)
		if data.action.completed:
			if is_instance_valid(instance):
				instance.queue_free()
			return
		var error := actor_register(actor_id, instance)
		if error != OK:
			instance.queue_free()
			_finish(actor_id, error, last_error)
			return
		_actors[actor_id].spawned = true
		_finish(actor_id, OK)
		return
	var actor := get_actor(actor_id)
	if actor == null:
		_finish(actor_id, ERR_DOES_NOT_EXIST, "Actor exited: %s" % actor_id)
		return
	match data.action.command:
		&"move":
			return
		&"face":
			actor.set_performance_facing(self, data.direction)
		&"show":
			actor.show()
		&"hide":
			actor.hide()
		&"emote":
			var label := Label.new()
			label.name = "ActorEmote"
			label.text = data.symbol
			label.position = actor.get_emote_offset() + Vector2(-24, -4)
			label.size = Vector2(48, 24)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.z_index = 1
			label.add_theme_color_override("font_color", Color(1, 0.9, 0.35))
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 4)
			actor.add_child(label)
			data.label = label
			label.tree_exiting.connect(_on_emote_exiting.bind(data.action))
			var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
			data.tween = tween
			tween.tween_property(label, "position:y", label.position.y - 8, data.duration * 0.3)
			tween.tween_interval(data.duration * 0.5)
			tween.tween_property(label, "modulate:a", 0.0, data.duration * 0.2)
			tween.finished.connect(_on_emote_finished.bind(data.action))
			return
	_finish(actor_id, OK)

func _tick_move(actor_id: StringName, data: Dictionary, delta: float) -> void:
	var actor := get_actor(actor_id)
	if actor == null or not _target_alive(data):
		_finish(actor_id, ERR_DOES_NOT_EXIST, "Actor or target exited during move: %s" % actor_id)
		return
	# Respect explicit actor disable/pause modes, but still bound the wait by timeout.
	data.elapsed += delta
	if actor.can_process():
		var distance := actor.global_position.distance_to(data.target)
		if distance <= ARRIVAL_DISTANCE:
			_finish(actor_id, OK)
			return
		actor.move_performance(self, data.target, data.speed, delta)
		var remaining := actor.global_position.distance_to(data.target)
		data.stalled = data.stalled + delta if distance - remaining < minf(0.01, data.speed * delta * 0.1) else 0.0
		if remaining <= ARRIVAL_DISTANCE:
			_finish(actor_id, OK)
			return
	if data.elapsed >= data.timeout or data.stalled >= blocked_timeout:
		_finish(actor_id, ERR_TIMEOUT, "Move blocked or timed out for '%s' toward %s" % [actor_id, data.target])

func _reject(action: ActorAction, error: Error, reason: String) -> void:
	last_error = reason
	action.settle(error, reason)

func _finish(actor_id: StringName, error: Error, reason: String = "") -> void:
	if not _active.has(actor_id):
		return
	var data: Dictionary = _active[actor_id]
	_active.erase(actor_id)
	if data.has("tween"):
		data.tween.kill()
	if data.has("label") and is_instance_valid(data.label):
		data.label.queue_free()
	if data.claimed:
		var actor: PlayerController = _actors.get(actor_id, {}).get("actor")
		if is_instance_valid(actor):
			actor.release_performance_control(self)
		_changing = true
		actor_control_changed.emit(actor_id, false)
		_changing = false
	_reject(data.action, error, reason)

func _on_action_finished(action: ActorAction) -> void:
	action_finished.emit(action)

func _on_emote_finished(action: ActorAction) -> void:
	if _active.has(action.actor_id) and _active[action.actor_id].action == action:
		_finish(action.actor_id, OK)

func _on_emote_exiting(action: ActorAction) -> void:
	if _active.has(action.actor_id) and _active[action.actor_id].action == action:
		_finish(action.actor_id, ERR_DOES_NOT_EXIST, "Emote visual exited: %s" % action.actor_id)

func _on_actor_exiting(actor_id: StringName) -> void:
	if _changing:
		_on_actor_exiting.call_deferred(actor_id)
	else:
		actor_unregister(actor_id)

func _exit_tree() -> void:
	_closing = true
	cancel_all("ActorDirector exited")
	_pending.clear()
	for actor_id: StringName in _actors.keys():
		var entry: Dictionary = _actors[actor_id]
		if entry.spawned and is_instance_valid(entry.actor):
			entry.actor.queue_free()
		actor_unregister(actor_id)
	_positions.clear()
