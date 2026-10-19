class_name BusinessScheduler
extends Node
## Disposable coordination. GameState owns durable snapshots; TaskDelivery settles.

signal changed
signal projection_reset
signal stage_published(stage_id: String)
signal customer_transition(group_id: String, status: String)
signal group_served(group_id: String)

signal business_completed(session_id: String)
signal operation_failed(error: Error)

const StateData = preload("res://src/core/game_state.gd")
const SESSION_RULES = preload("res://src/gameplay/milk_tea/business_session_rules.gd")

var _session_id := ""
var _stages: Dictionary = {}
var _groups: Dictionary = {}
var _order_groups: Dictionary = {}
var _state: StateData
var _delivery: TaskDelivery
var _load: Callable
var _commit: Callable
var _close: Callable
var _changing := false
var _active := false
var _pending_served: Dictionary = {}
var _recover_departures: Dictionary = {}
var _departure_guard: Callable

## A scene may hold a served customer while an accepted extra commission remains.
func set_departure_guard(guard: Callable) -> void:
	_departure_guard = guard

## plan: {session_id, stages:[{id, ordinary_customers:[], story_customers:[]}]}
## customer: {id, actor_ids:[String], order_ids:[String]}. No recipes or prices here.
## load(session_id)->Dictionary; commit(session_id, expected, next)->Error.
## Production adapter. Missing authored close rules keep closing unavailable.
func configure_session(plan: Dictionary, state: StateData, delivery: TaskDelivery, close_rule: Dictionary = {}) -> Error:
	if _changing or not _session_id.is_empty():
		return ERR_BUSY
	if not is_instance_valid(state) or not is_instance_valid(delivery):
		return ERR_INVALID_PARAMETER
	if _parse_plan(plan, delivery).is_empty():
		return ERR_INVALID_DATA
	var error := state.bind_business_session(plan, close_rule)
	if error != OK:
		return error
	return configure(plan, state, delivery, state.load_business_session, state.commit_business_session,
		state.close_business_session if not close_rule.is_empty() else Callable())

## close has the same arguments and atomically persists closed with its close facts.
func configure(plan: Dictionary, state: StateData, delivery: TaskDelivery,
		load_snapshot: Callable = Callable(), commit_snapshot: Callable = Callable(),
		close_session: Callable = Callable()) -> Error:
	if _changing or not _session_id.is_empty():
		return ERR_BUSY
	if not is_instance_valid(state) or not is_instance_valid(delivery):
		return ERR_INVALID_PARAMETER
	var parsed := _parse_plan(plan, delivery)
	if parsed.is_empty():
		return ERR_INVALID_DATA
	_session_id = plan.session_id
	_stages = parsed.stages
	_groups = parsed.groups
	_order_groups = parsed.orders
	_state = state
	_delivery = delivery
	_load = load_snapshot
	_commit = commit_snapshot
	_close = close_session
	var ids: Array[String] = []
	ids.assign(_order_groups.keys())
	var error := delivery.set_order_availability(ids, is_order_available)
	if error != OK:
		_session_id = ""
		return error
	_connect_sources()
	_find_recovery_departures()
	refresh()
	return OK

func _enter_tree() -> void:
	_active = true
	_connect_sources()
	refresh()

func _exit_tree() -> void:
	_active = false
	_disconnect_sources()
	_pending_served.clear()
	if is_instance_valid(_delivery):
		_delivery.refresh_availability()

func _connect_sources() -> void:
	if is_instance_valid(_state):
		if not _state.state_changed.is_connected(refresh):
			_state.state_changed.connect(refresh)
		for event: Signal in [_state.state_restored, _state.state_reset]:
			if not event.is_connected(_on_replaced):
				event.connect(_on_replaced)
	if is_instance_valid(_delivery) and not _delivery.delivered.is_connected(_on_delivered):
		_delivery.delivered.connect(_on_delivered)

func _disconnect_sources() -> void:
	if is_instance_valid(_state):
		if _state.state_changed.is_connected(refresh):
			_state.state_changed.disconnect(refresh)
		for event: Signal in [_state.state_restored, _state.state_reset]:
			if event.is_connected(_on_replaced):
				event.disconnect(_on_replaced)
	if is_instance_valid(_delivery) and _delivery.delivered.is_connected(_on_delivered):
		_delivery.delivered.disconnect(_on_delivered)

## Pure projection, including restore/reset. Never republishes arrival or completion.
func refresh() -> void:
	if _changing:
		return
	if is_instance_valid(_delivery):
		_delivery.refresh_availability()
	changed.emit()

func _on_replaced() -> void:
	_pending_served.clear()
	_find_recovery_departures()
	projection_reset.emit()
	refresh()

func _find_recovery_departures() -> void:
	_recover_departures.clear()
	var snapshot := _snapshot()
	if snapshot.is_empty():
		return
	for id: String in _groups:
		if _groups[id].kind == "ordinary" and snapshot.groups.get(id) == "waiting" and is_group_served(id):
			_recover_departures[id] = true

func get_group(group_id: String) -> Dictionary:
	if not _groups.has(group_id):
		return {}
	var snapshot := _snapshot()
	if snapshot.is_empty():
		return {}
	var group: Dictionary = _groups[group_id].duplicate(true)
	group.status = snapshot.groups.get(group_id, "dormant")
	# A receipt may precede the deferred departure commit, or survive a scene exit.
	if _recover_departures.has(group_id) and group.status == "waiting":
		group.status = "leaving"
	group.served = is_group_served(group_id)
	return group

func is_group_served(group_id: String) -> bool:
	if not _groups.has(group_id) or not is_instance_valid(_state):
		return false
	for id: String in _groups[group_id].order_ids:
		if not _state.get_flag("delivery." + id + ".completed"):
			return false
	return not _departure_guard.is_valid() or bool(_departure_guard.call(group_id))

func is_order_available(order_id: String) -> bool:
	if not _order_groups.has(order_id):
		return true
	if not _active or is_queued_for_deletion():
		return false
	var snapshot := _snapshot()
	if snapshot.is_empty() or snapshot.closed or not _commit.is_valid():
		return false
	var group_id: String = _order_groups[order_id]
	return _groups[group_id].stage_id in snapshot.published_stages and snapshot.groups.get(group_id) == "waiting"

func get_progress() -> Dictionary:
	var snapshot := _snapshot()
	var completed := 0
	var served := 0
	var departed := 0
	for id: String in _order_groups:
		if is_instance_valid(_state) and _state.get_flag("delivery." + id + ".completed"):
			completed += 1
	for id: String in _groups:
		served += int(is_group_served(id))
		departed += int(not snapshot.is_empty() and snapshot.groups.get(id) == "departed")
	return {"session_id": _session_id, "orders_completed": completed, "orders_total": _order_groups.size(),
		"groups_served": served, "groups_total": _groups.size(), "groups_departed": departed,
		"published_stages": snapshot.get("published_stages", []).duplicate(), "stages_total": _stages.size(),
		"closed": snapshot.get("closed", false), "persistence_ready": _load.is_valid() and _commit.is_valid() and not snapshot.is_empty(),
		"close_ready": _close.is_valid()}

func publish_stage(stage_id: String) -> Error:
	if not _stages.has(stage_id):
		return ERR_DOES_NOT_EXIST
	var before := _snapshot()
	if before.is_empty():
		return ERR_UNAVAILABLE
	if stage_id in before.published_stages:
		return OK
	var next := before.duplicate(true)
	next.published_stages.append(stage_id)
	var transitions: Dictionary = {}
	for id: String in _stages[stage_id]:
		if _groups[id].kind == "ordinary":
			next.groups[id] = "entering"
			transitions[id] = "entering"
	return _write(before, next, transitions, stage_id)

func request_arrival(group_id: String) -> Error:
	if not _groups.has(group_id):
		return ERR_DOES_NOT_EXIST
	var before := _snapshot()
	if before.is_empty() or _groups[group_id].stage_id not in before.published_stages:
		return ERR_UNAVAILABLE
	if before.groups.has(group_id):
		return ERR_ALREADY_EXISTS
	return _transition(before, group_id, "entering")

func confirm_arrival(group_id: String) -> Error:
	var before := _snapshot()
	if before.is_empty() or before.groups.get(group_id) != "entering":
		return ERR_UNAVAILABLE
	return _transition(before, group_id, "waiting")

## Fixed story customers stay until the story coordinator explicitly releases them.
func request_departure(group_id: String) -> Error:
	var before := _snapshot()
	if before.is_empty() or before.groups.get(group_id) != "waiting" or not is_group_served(group_id):
		return ERR_UNAVAILABLE
	return _transition(before, group_id, "leaving")

func confirm_departure(group_id: String) -> Error:
	var before := _snapshot()
	if before.is_empty():
		return ERR_UNAVAILABLE
	var status: String = before.groups.get(group_id, "")
	if status != "leaving" and not (status == "waiting" and _groups[group_id].kind == "ordinary" and is_group_served(group_id)):
		return ERR_UNAVAILABLE
	return _transition(before, group_id, "departed")

## Default is pending. Authored rules decide the target phase and close facts.
func request_close() -> Error:
	var before := _snapshot()
	if before.is_empty():
		return ERR_UNAVAILABLE
	if before.closed:
		return OK
	var next := before.duplicate(true)
	next.closed = true
	return _write(before, next, {}, "", true)

func _transition(before: Dictionary, id: String, status: String) -> Error:
	var next := before.duplicate(true)
	next.groups[id] = status
	return _write(before, next, {id: status})

func _write(before: Dictionary, next: Dictionary, transitions: Dictionary = {}, stage: String = "", closing: bool = false) -> Error:
	if _changing:
		return ERR_BUSY
	if not _active or is_queued_for_deletion():
		return ERR_UNAVAILABLE
	var writer := _close if closing else _commit
	if not _load.is_valid() or not writer.is_valid() or (before.closed and not closing):
		return ERR_UNAVAILABLE
	_changing = true
	var result: Variant = writer.call(_session_id, before.duplicate(true), next.duplicate(true))
	var error: Error = result if result is int else ERR_INVALID_DATA
	if error == OK and _snapshot() != next:
		error = ERR_INVALID_DATA
	if error == OK:
		_delivery.refresh_availability()
		changed.emit()
		if not stage.is_empty():
			stage_published.emit(stage)
		for id: String in transitions:
			customer_transition.emit(id, transitions[id])
		if closing:
			business_completed.emit(_session_id)
	_changing = false
	return error

func _on_delivered(order_id: String) -> void:
	if not _order_groups.has(order_id):
		return
	var id: String = _order_groups[order_id]
	if is_group_served(id):
		_pending_served[id] = true
		_flush_served.call_deferred()

func _flush_served() -> void:
	var pending := _pending_served.keys()
	_pending_served.clear()
	for id: String in pending:
		if not is_group_served(id):
			continue
		if _groups[id].kind == "ordinary":
			var error := request_departure(id)
			if error != OK:
				operation_failed.emit(error)
		group_served.emit(id)

func _snapshot() -> Dictionary:
	if not _load.is_valid():
		return {}
	var value: Variant = _load.call(_session_id)
	if not value is Dictionary:
		return {}
	if value.is_empty():
		return SESSION_RULES.empty_snapshot()
	var definition := {"stages": _stages, "groups": _groups, "orders": _order_groups}
	return value.duplicate(true) if SESSION_RULES.valid_snapshot(value, definition) else {}

func _parse_plan(plan: Dictionary, delivery: TaskDelivery) -> Dictionary:
	return SESSION_RULES.parse_plan(plan, delivery.get_orders())
