class_name ShopInteraction
extends Node
## The sole selector/dispatcher. Feedback observes signals and never triggers gameplay.

signal target_changed(point: InteractionPoint)
signal interaction_succeeded(point: InteractionPoint)
signal interaction_failed(point: InteractionPoint)

## Scores use world pixels. A challenger must beat the incumbent by this margin.
@export_range(0.0, 64.0) var switch_margin := 12.0
@export_range(0.0, 64.0) var facing_weight := 24.0

var _player: PlayerController
var _ui: ShopUI
var _points: Array[InteractionPoint] = []
var _target: InteractionPoint
var _input_enabled := true
var _event_handler: Callable
var _dispatching := false
var _last_dispatch_frame := -1
var _armed := true
var _priority_resolver: Callable

func set_priority_resolver(resolver: Callable) -> void:
	_priority_resolver = resolver
	refresh_target()

func is_input_enabled() -> bool:
	return _input_enabled

func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if not enabled:
		_armed = false
		_set_target(null)
	else:
		refresh_target()

func configure(player: PlayerController, ui: ShopUI, points: Array[InteractionPoint], event_handler: Callable = Callable()) -> void:
	_set_target(null)
	if is_instance_valid(_ui):
		_ui.closed.disconnect(_on_closed)
		target_changed.disconnect(_ui.show_prompt)
	for point in _points:
		if is_instance_valid(point):
			point.availability_changed.disconnect(_on_availability_changed)
			point.interacted.disconnect(_on_interacted)
	_event_handler = event_handler
	_player = player
	_ui = ui
	_points = points.duplicate()
	_ui.closed.connect(_on_closed)
	target_changed.connect(_ui.show_prompt)
	for point in _points:
		point.availability_changed.connect(_on_availability_changed)
		point.interacted.connect(_on_interacted)
	refresh_target()

func get_target() -> InteractionPoint:
	return _target if is_instance_valid(_target) else null

func _process(_delta: float) -> void:
	if not Input.is_action_pressed("interact"):
		_armed = true
	refresh_target()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		_armed = false
		_set_target(null)

func _can_interact() -> bool:
	return (is_inside_tree() and can_process() and not get_tree().paused
		and _input_enabled and not _dispatching
		and is_instance_valid(_player) and _player.is_inside_tree() and not _player.is_queued_for_deletion()
		and _player.movement_enabled and not _player.is_performance_controlled()
		and is_instance_valid(_ui) and _ui.is_inside_tree() and not _ui.is_open())

func refresh_target() -> void:
	if not _can_interact():
		_set_target(null)
		return
	var best: InteractionPoint
	var best_score := INF
	for point in _points:
		if not is_instance_valid(point) or not point.is_available():
			continue
		var score := _score(point)
		if score < best_score:
			best = point
			best_score = score
	# First select the nearby equipment/group by distance and facing. Only then
	# resolve competing actions within that group; delivery cannot steal a station.
	if best != null and best.selection_group != &"":
		for point: InteractionPoint in _points:
			if not is_instance_valid(point) or not point.is_available() or point.selection_group != best.selection_group:
				continue
			if _priority(point) > _priority(best) or (_priority(point) == _priority(best) and _score(point) < _score(best)):
				best = point
		best_score = _score(best)
	if is_instance_valid(_target) and _target.is_available() and best != _target:
		var priority_changed := best != null and best.selection_group != &"" and best.selection_group == _target.selection_group and _priority(best) > _priority(_target)
		if not priority_changed and best_score + switch_margin >= _score(_target):
			best = _target
	_set_target(best)

func _score(point: InteractionPoint) -> float:
	var offset := point.global_position - _player.global_position
	return offset.length() - _player.get_facing_vector().dot(offset.normalized()) * facing_weight

func _priority(point: InteractionPoint) -> int:
	return int(_priority_resolver.call(point.interaction_id)) if _priority_resolver.is_valid() else 0

func _set_target(point: InteractionPoint) -> void:
	if is_instance_valid(_target) and _target == point:
		return
	if _target == null and point == null:
		return
	# The world prompt listens to this signal: exactly one capsule on screen,
	# attached to the object it describes.
	_target = point
	target_changed.emit(point)

func _input(event: InputEvent) -> void:
	if event.is_action_released("interact"):
		_armed = true

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or event.is_echo():
		return
	# Refresh at the input boundary too: a lock, deletion or exit can precede this frame's process.
	refresh_target()
	var was_armed := _armed
	_armed = false
	if not was_armed or not is_instance_valid(_target):
		return
	_target.interact()
	get_viewport().set_input_as_handled()

func _on_availability_changed(_point: InteractionPoint, _available: bool) -> void:
	refresh_target()

func _on_interacted(point: InteractionPoint) -> void:
	if not _can_interact() or _last_dispatch_frame == Engine.get_process_frames() or not is_instance_valid(point) or not point.is_available():
		return
	_last_dispatch_frame = Engine.get_process_frames()
	_dispatching = true
	# Legacy bool handlers consume on true. Error handlers distinguish success from rejection.
	var result: Variant = _event_handler.call(point.interaction_id) if _event_handler.is_valid() else false
	var consumed: bool = result if result is bool else result != ERR_DOES_NOT_EXIST
	var succeeded: bool = result if result is bool else result == OK
	if not consumed and is_instance_valid(_player) and is_instance_valid(_ui) and is_instance_valid(point):
		_ui.open(point)
		succeeded = _ui.is_open()
	_dispatching = false
	refresh_target()
	if succeeded and is_instance_valid(point) and not point.is_queued_for_deletion():
		interaction_succeeded.emit(point)
	elif not succeeded and is_instance_valid(point) and not point.is_queued_for_deletion():
		interaction_failed.emit(point)

func _on_closed() -> void:
	_armed = false
	refresh_target()
