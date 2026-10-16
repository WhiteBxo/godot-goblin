class_name ShopInteraction
extends Node

var _player: ShopPlayer
var _ui: ShopUI
var _nearby: Array[InteractionPoint] = []
var _target: InteractionPoint
var _input_enabled: bool = true
var _event_handler: Callable

func is_input_enabled() -> bool:
	return _input_enabled

func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if not enabled and _ui != null:
		_ui.show_prompt(null)

func configure(player: ShopPlayer, ui: ShopUI, points: Array[InteractionPoint], event_handler: Callable = Callable()) -> void:
	_event_handler = event_handler
	_player = player
	_ui = ui
	_ui.closed.connect(_on_closed)
	for point in points:
		point.availability_changed.connect(_on_availability_changed)
		point.interacted.connect(_on_interacted)

func _process(_delta: float) -> void:
	if _player == null or not _input_enabled:
		return
	_target = null
	for point in _nearby:
		if _target == null or _player.global_position.distance_squared_to(point.global_position) < _player.global_position.distance_squared_to(_target.global_position):
			_target = point
	_ui.show_prompt(_target)

func _unhandled_input(event: InputEvent) -> void:
	if _input_enabled and _ui != null and not _ui.is_open() and is_instance_valid(_target) and event.is_action_pressed("interact") and not event.is_echo():
		_target.interact()
		get_viewport().set_input_as_handled()

func _on_availability_changed(point: InteractionPoint, available: bool) -> void:
	if available and point not in _nearby:
		_nearby.append(point)
	elif not available:
		_nearby.erase(point)

func _on_interacted(point: InteractionPoint) -> void:
	if not _input_enabled or _ui.is_open():
		return
	if _event_handler.is_valid() and _event_handler.call(point.interaction_id):
		return
	_player.set_movement_enabled(false)
	_ui.open(point)

func _on_closed() -> void:
	_player.set_movement_enabled(true)
