class_name TaskJournal
extends Node
## A disposable, read-only projection. GameState remains the only progress source.

signal projection_changed
const StateData = preload("res://src/core/game_state.gd")

var _state: StateData
var _definitions: Array[Dictionary] = []
var _projection: Array[Dictionary] = []

func configure(catalog: TaskCatalog, state: StateData) -> Error:
	if catalog == null or not is_instance_valid(state):
		return ERR_INVALID_PARAMETER
	var error := state.bind_task_catalog(catalog)
	if error != OK:
		return error
	_disconnect_state()
	_definitions = catalog.get_tasks()
	_state = state
	if is_inside_tree():
		_connect_state()
	refresh()
	return OK

func _enter_tree() -> void:
	_connect_state()
	refresh()

func _exit_tree() -> void:
	_disconnect_state()

func _connect_state() -> void:
	if is_instance_valid(_state) and not _state.state_changed.is_connected(refresh):
		_state.state_changed.connect(refresh)

func _disconnect_state() -> void:
	if is_instance_valid(_state) and _state.state_changed.is_connected(refresh):
		_state.state_changed.disconnect(refresh)

func get_task(id: String) -> Dictionary:
	for task in _definitions:
		if task.id == id and is_instance_valid(_state):
			return _project(task)
	return {}

func get_active_tasks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for task in _projection:
		if task.status == "active":
			result.append(task.duplicate(true))
	return result

## History includes hidden active entries with the same masking as get_task.
func get_visible_tasks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for task: Dictionary in _projection:
		if task.status != "inactive":
			result.append(task.duplicate(true))
	return result

## Revealed active or completed history, including after restoring an older session.
func has_started_tasks() -> bool:
	for task: Dictionary in _projection:
		if task.revealed and task.status != "inactive":
			return true
	return false

func get_current_main_task() -> Dictionary:
	for task in _projection:
		if task.type == "main" and task.status == "active":
			return task.duplicate(true)
	return {}

func refresh() -> void:
	var next: Array[Dictionary] = []
	if is_instance_valid(_state):
		for task in _definitions:
			next.append(_project(task))
	if next != _projection:
		_projection = next
		projection_changed.emit()

func _matches(condition: Dictionary) -> bool:
	return TaskCatalog.matches_condition(condition, _state)

func _revealed(data: Dictionary) -> bool:
	return not data.has("reveal_when") or _matches(data.reveal_when)

func _project(task: Dictionary) -> Dictionary:
	var revealed := _revealed(task)
	var status := "inactive"
	if _matches(task.activate_when):
		status = "completed" if _matches(task.complete_when) else "active"
	var result := _state.get_task_result(task.id)
	if not result.is_empty():
		status = result.status
	# Ambiguous success/failure/deadline facts are pending, never guessed by UI.
	elif status == "completed" and _state.has_conflicting_task_result(task.id):
		status = "active"
	var objectives: Array[Dictionary] = []
	var current: Dictionary = {}
	for definition: Dictionary in task.objectives:
		var visible_info := revealed and _revealed(definition)
		var objective := {"id": definition.id, "text": definition.text if visible_info else "???",
			"completed": _matches(definition.complete_when), "required": definition.get("required", true),
			"revealed": visible_info, "location_id": definition.get("location_id", "") if visible_info else "",
			"progress": null, "target": null}
		var condition: Dictionary = definition.complete_when
		if visible_info and condition.type == "variable_at_least":
			var value: Variant = _state.get_variable(condition.key)
			objective.progress = clampf(float(value), 0.0, condition.value) if TaskCatalog.is_number(value) else 0.0
			objective.target = condition.value
		objectives.append(objective)
		if current.is_empty() and objective.required and not objective.completed:
			current = objective
	var rewards: Dictionary = {}
	if task.has("rewards"):
		var reward_revealed := revealed and _revealed(task.rewards)
		rewards = {"text": task.rewards.text if reward_revealed else "???", "revealed": reward_revealed}
	var delivery: Dictionary = {}
	if revealed and task.has("delivery"):
		delivery = {"target_object_id": task.delivery.target_object_id}
		if task.delivery.has("items"):
			delivery.items = task.delivery.items.duplicate(true)
		elif task.delivery.has("drink"):
			delivery.drink = task.delivery.drink.duplicate(true)
		else:
			delivery.product_id = task.delivery.product_id
	if status != "active":
		current = {}
	return {"id": task.id, "type": task.type, "status": status, "result": result if revealed else {}, "revealed": revealed,
		"title": task.title if revealed else "???", "description": task.description if revealed else "???",
		"location_id": task.get("location_id", "") if revealed else "",
		"difficulty": task.get("difficulty", "") if revealed else "???",
		"rewards": rewards, "delivery": delivery, "objectives": objectives, "current_objective": current}
