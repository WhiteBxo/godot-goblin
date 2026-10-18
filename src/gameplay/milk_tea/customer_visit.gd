class_name CustomerVisit
extends Node
## One group's visual adapter. Routes come from the host; no story or money rules.

signal movement_failed(group_id: String, reason: String)

var _scheduler: BusinessScheduler
var _director: ActorDirector
var _group_id := ""
var _members: Array[Dictionary] = []
var _actions: Array[ActorAction] = []
var _generation := 0
var _status := ""
var _live_status := ""
var _queued := false
var _route_pending := false

## member: {actor_id, scene?:PackedScene, entry, waiting, exit,
##          arrival_route?:Array, departure_route?:Array, speed?:float, timeout?:float}
## Positions are registered Marker IDs or Vector2; routes contain actual turns.
func configure(scheduler: BusinessScheduler, director: ActorDirector, group_id: String,
		members: Array[Dictionary]) -> Error:
	if is_instance_valid(_scheduler) or not is_instance_valid(scheduler) or not is_instance_valid(director):
		return ERR_INVALID_PARAMETER
	var group := scheduler.get_group(group_id)
	if group.is_empty() or members.size() != group.actor_ids.size():
		return ERR_INVALID_DATA
	var seen: Dictionary = {}
	for member: Dictionary in members:
		var id: Variant = member.get("actor_id")
		if not id is String or id not in group.actor_ids or seen.has(id):
			return ERR_INVALID_DATA
		seen[id] = true
		for key: String in ["entry", "waiting", "exit"]:
			if not _valid_position(member.get(key), director):
				return ERR_INVALID_DATA
		for key: String in ["arrival_route", "departure_route"]:
			var route: Variant = member.get(key, [])
			if not route is Array:
				return ERR_INVALID_DATA
			for target: Variant in route:
				if not _valid_position(target, director):
					return ERR_INVALID_DATA
		for key: String in ["speed", "timeout"]:
			var value: Variant = member.get(key, 120.0 if key == "speed" else 15.0)
			if not value is float and not value is int:
				return ERR_INVALID_DATA
			if not is_finite(value) or value <= 0.0:
				return ERR_INVALID_DATA
		if member.has("scene") and not member.scene is PackedScene:
			return ERR_INVALID_DATA
	_scheduler = scheduler
	_director = director
	_group_id = group_id
	_members = members.duplicate(true)
	_scheduler.changed.connect(_schedule_sync)
	_scheduler.customer_transition.connect(_on_transition)
	_scheduler.projection_reset.connect(_on_replaced)
	_schedule_sync()
	return OK

func _exit_tree() -> void:
	_cancel()
	if is_instance_valid(_scheduler):
		if _scheduler.changed.is_connected(_schedule_sync):
			_scheduler.changed.disconnect(_schedule_sync)
		if _scheduler.customer_transition.is_connected(_on_transition):
			_scheduler.customer_transition.disconnect(_on_transition)
		if _scheduler.projection_reset.is_connected(_on_replaced):
			_scheduler.projection_reset.disconnect(_on_replaced)

func _on_replaced() -> void:
	_cancel()
	_status = ""
	_live_status = ""
	_route_pending = false
	_schedule_sync()

func _on_transition(id: String, status: String) -> void:
	if id == _group_id:
		_live_status = status
		_schedule_sync()

func _schedule_sync() -> void:
	if not _queued:
		_queued = true
		_sync.call_deferred()

## A failed route stays pending. Retrying never creates a new visit or settlement.
func retry() -> void:
	if _route_pending:
		_live_status = _status
	_status = ""
	_schedule_sync()

func _sync() -> void:
	_queued = false
	if not is_inside_tree() or not is_instance_valid(_scheduler):
		return
	var group := _scheduler.get_group(_group_id)
	if group.is_empty():
		return
	var status: String = group.status
	if status == _status:
		return
	_cancel()
	_status = status
	var live := _live_status == status
	_route_pending = live and status in ["entering", "leaving"]
	_live_status = ""
	_run(status, live, _generation)

func _run(status: String, live: bool, token: int) -> void:
	for member: Dictionary in _members:
		var id := StringName(member.actor_id)
		var actor := _director.get_actor(id)
		if status in ["dormant", "departed"]:
			if actor != null and not await _perform(_director.actor_hide(id), token):
				return
			continue
		var start: Variant = member.entry if live and status == "entering" else member.waiting
		if status == "leaving" and not live:
			start = member.exit
		if not _valid_position(start, _director):
			movement_failed.emit(_group_id, "Customer position is no longer registered")
			return
		if actor == null:
			if not member.has("scene"):
				movement_failed.emit(_group_id, "Missing registered actor and scene: " + member.actor_id)
				return
			if not await _perform(_director.actor_spawn(id, member.scene, start), token):
				return
			actor = _director.get_actor(id)
		elif not live or status == "entering":
			if _director.is_actor_controlled(id):
				movement_failed.emit(_group_id, "Actor is already controlled: " + member.actor_id)
				return
			actor.teleport_to(_position(start))
		if not await _perform(_director.actor_show(id), token):
			return
		if live and status in ["entering", "leaving"]:
			var route: Array = member.get("arrival_route" if status == "entering" else "departure_route", []).duplicate()
			route.append(member.waiting if status == "entering" else member.exit)
			for target: Variant in route:
				if not await _perform(_director.actor_move(id, target, member.get("speed", 120.0), member.get("timeout", 15.0)), token):
					return
		if status == "leaving" and not await _perform(_director.actor_hide(id), token):
			return
	if token != _generation:
		return
	_route_pending = false
	var error := OK
	if status == "entering":
		error = _scheduler.confirm_arrival(_group_id)
	elif status == "leaving":
		error = _scheduler.confirm_departure(_group_id)
	if error != OK:
		movement_failed.emit(_group_id, "Visit acknowledgement failed: %d" % error)

func _perform(action: ActorAction, token: int) -> bool:
	_actions.append(action)
	await action.wait()
	_actions.erase(action)
	if token != _generation:
		return false
	if not action.succeeded:
		movement_failed.emit(_group_id, action.reason)
	return action.succeeded

func _cancel() -> void:
	_generation += 1
	if is_instance_valid(_director):
		for action: ActorAction in _actions.duplicate():
			_director.cancel_action(action, "Customer visit projection changed")
	_actions.clear()

func _valid_position(target: Variant, director: ActorDirector) -> bool:
	if target is Vector2:
		return target.is_finite()
	return (target is String or target is StringName) and director.get_position(StringName(target)) != null

func _position(target: Variant) -> Vector2:
	if target is Vector2:
		return target
	return _director.get_position(StringName(target)).global_position
