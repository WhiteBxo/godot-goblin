class_name CameraDirector
extends Node
## Scene-local scheduling over one existing BoundedFollowCamera. No input ownership.

signal action_finished(action: CameraAction)
signal camera_recovered(reason: String)

@export var shake_enabled := true:
	set(value):
		shake_enabled = value
		if not value:
			cancel_shake("Screen shake disabled")
@export_range(0.0, 8.0, 0.5) var maximum_shake_pixels := 6.0

var _camera: BoundedFollowCamera
var _actions: Dictionary = {}
var _tweens: Dictionary = {}
var _next_id := 0
var _target: WeakRef
var _stopping := false
var _exiting := false
var _rng := RandomNumberGenerator.new()

func configure(camera: BoundedFollowCamera) -> void:
	cancel_all("CameraDirector reconfigured")
	if is_instance_valid(_camera):
		_camera.tree_exiting.disconnect(_on_camera_exiting)
		_camera.focus_target_lost.disconnect(_on_target_lost)
	_camera = camera
	if is_instance_valid(_camera):
		_camera.tree_exiting.connect(_on_camera_exiting)
		_camera.focus_target_lost.connect(_on_target_lost)

func get_camera() -> BoundedFollowCamera:
	return _camera

func camera_follow(duration: float = 0.6, transition: Tween.TransitionType = Tween.TRANS_SINE, ease: Tween.EaseType = Tween.EASE_IN_OUT) -> CameraAction:
	return _move(&"camera_follow", null, duration, transition, ease, true)

## Node2D (live target) or Vector2 (world position). NodePath resolution belongs to host.
func camera_focus(target: Variant, duration: float = 0.8, transition: Tween.TransitionType = Tween.TRANS_SINE, ease: Tween.EaseType = Tween.EASE_IN_OUT) -> CameraAction:
	return _move(&"camera_focus", target, duration, transition, ease)

func camera_move(world_position: Vector2, duration: float = 0.8, transition: Tween.TransitionType = Tween.TRANS_SINE, ease: Tween.EaseType = Tween.EASE_IN_OUT) -> CameraAction:
	return _move(&"camera_move", world_position, duration, transition, ease)

func camera_zoom(value: float, duration: float = 0.5, transition: Tween.TransitionType = Tween.TRANS_SINE, ease: Tween.EaseType = Tween.EASE_IN_OUT) -> CameraAction:
	var action := _new_action(&"camera_zoom")
	if not _validate(action, duration, transition, ease):
		return action
	if not is_finite(value) or value <= 0.0:
		return _failed(action, "Zoom must be finite and positive")
	_replace(&"zoom", action)
	var start := _camera.get_directed_zoom()
	var update := func(weight: float) -> void: _camera.set_directed_zoom(lerpf(start, value, weight))
	_animate(&"zoom", action, duration, transition, ease, update)
	return action

## Intensity in 640x360 viewport pixels, not window pixels. Replaces previous shake.
func camera_shake(intensity: float = 2.0, duration: float = 0.3, decay: float = 1.5) -> CameraAction:
	var action := _new_action(&"camera_shake")
	if not _validate(action, duration):
		return action
	if not is_finite(intensity) or intensity < 0.0 or not is_finite(decay) or decay < 0.0:
		return _failed(action, "Shake intensity and decay must be finite and nonnegative")
	_replace(&"shake", action)
	var strength := minf(intensity, maximum_shake_pixels) if shake_enabled else 0.0
	var update := func(weight: float) -> void:
		var amplitude := strength * pow(maxf(0.0, 1.0 - weight), decay)
		_camera.set_shake_pixels(Vector2(_rng.randf_range(-amplitude, amplitude), _rng.randf_range(-amplitude, amplitude)))
	_animate(&"shake", action, duration if strength > 0.0 else 0.0, Tween.TRANS_LINEAR, Tween.EASE_IN, update)
	return action

func camera_reset() -> CameraAction:
	var action := _new_action(&"camera_reset")
	if not _validate(action, 0.0):
		return action
	cancel_all("Camera reset")
	action.resolve(CameraAction.Result.COMPLETED)
	return action

func cancel_shake(reason: String = "Shake cancelled") -> void:
	_stop_channel(&"shake", CameraAction.Result.CANCELLED, reason)
	if _camera_available():
		_camera.set_shake_pixels(Vector2.ZERO)

func cancel_all(reason: String = "Camera sequence cancelled") -> void:
	_terminate_all(CameraAction.Result.CANCELLED, reason)

func _process(_delta: float) -> void:
	if _target == null:
		return
	var target := _target.get_ref() as Node2D
	if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion():
		_on_target_lost()

func _move(command: StringName, target: Variant, duration: float, transition: Tween.TransitionType, ease: Tween.EaseType, follow: bool = false) -> CameraAction:
	var action := _new_action(command)
	if not _validate(action, duration, transition, ease):
		return action
	var node: Node2D
	if not follow:
		if typeof(target) == TYPE_VECTOR2:
			if not (target as Vector2).is_finite():
				return _failed(action, "Position must be finite")
		elif typeof(target) == TYPE_OBJECT and is_instance_valid(target) and target is Node2D and target.is_inside_tree() and not target.is_queued_for_deletion():
			node = target
		else:
			return _failed(action, "Focus requires a live Node2D or world Vector2")
	_replace(&"position", action)
	_camera.begin_cinematic()
	var start := _camera.global_position
	_target = weakref(node) if node != null else null
	var update := func(weight: float) -> void:
		var destination: Vector2
		if follow:
			destination = _camera.get_follow_position()
		elif _target != null:
			var live_target := _target.get_ref() as Node2D
			if not is_instance_valid(live_target) or not live_target.is_inside_tree() or live_target.is_queued_for_deletion():
				_on_target_lost()
				return
			destination = live_target.global_position
		else:
			destination = target
		_camera.set_cinematic_position(start.lerp(destination, weight))
	_animate(&"position", action, duration, transition, ease, update)
	return action

func _animate(channel: StringName, action: CameraAction, duration: float, transition: Tween.TransitionType, ease: Tween.EaseType, update: Callable) -> void:
	if duration == 0.0:
		update.call(1.0)
		_complete(channel, action)
		return
	var tween := create_tween().set_trans(transition).set_ease(ease)
	_tweens[channel] = tween
	tween.tween_method(update, 0.0, 1.0, duration)
	tween.finished.connect(_complete.bind(channel, action))

func _complete(channel: StringName, action: CameraAction) -> void:
	if _actions.get(channel) != action:
		return
	_tweens.erase(channel)
	_actions.erase(channel)
	if channel == &"position":
		if action.command == &"camera_follow":
			_camera.restore_follow()
		elif _target != null:
			var target := _target.get_ref() as Node2D
			if is_instance_valid(target) and target.is_inside_tree() and not target.is_queued_for_deletion():
				_camera.hold_focus(target)
			else:
				action.resolve(CameraAction.Result.FAILED, "Focus target exited")
				_on_target_lost()
				return
		_target = null
	elif channel == &"shake":
		_camera.set_shake_pixels(Vector2.ZERO)
	action.resolve(CameraAction.Result.COMPLETED)

func _replace(channel: StringName, action: CameraAction) -> void:
	_stop_channel(channel, CameraAction.Result.CANCELLED, "Replaced by another camera action")
	_actions[channel] = action

func _stop_channel(channel: StringName, result: CameraAction.Result, reason: String) -> void:
	if _tweens.has(channel):
		(_tweens[channel] as Tween).kill()
		_tweens.erase(channel)
	if channel == &"position":
		_target = null
	if _actions.has(channel):
		var action: CameraAction = _actions[channel]
		_actions.erase(channel)
		action.resolve(result, reason)

func _terminate_all(result: CameraAction.Result, reason: String) -> void:
	_stopping = true
	for channel: StringName in _actions.keys():
		_stop_channel(channel, result, reason)
	_target = null
	if _camera_available():
		_camera.reset_camera()
	_stopping = false

func _new_action(command: StringName) -> CameraAction:
	var action := CameraAction.new()
	_next_id += 1
	action.id = _next_id
	action.command = command
	action.finished.connect(func(done: CameraAction) -> void: action_finished.emit(done))
	return action

func _validate(action: CameraAction, duration: float, transition: int = Tween.TRANS_SINE, ease: int = Tween.EASE_IN_OUT) -> bool:
	if _exiting or _stopping or not is_inside_tree() or is_queued_for_deletion() or not _camera_available():
		_failed(action, "CameraDirector or camera unavailable")
		return false
	if not is_finite(duration) or duration < 0.0 or transition < Tween.TRANS_LINEAR or transition > Tween.TRANS_SPRING or ease < Tween.EASE_IN or ease > Tween.EASE_OUT_IN:
		_failed(action, "Invalid duration or easing")
		return false
	return true

func _failed(action: CameraAction, reason: String) -> CameraAction:
	action.resolve(CameraAction.Result.FAILED, reason)
	return action

func _camera_available() -> bool:
	return is_instance_valid(_camera) and _camera.is_inside_tree() and not _camera.is_queued_for_deletion()

func _on_target_lost() -> void:
	_terminate_all(CameraAction.Result.FAILED, "Focus target exited")
	camera_recovered.emit("Focus target exited")

func _on_camera_exiting() -> void:
	_terminate_all(CameraAction.Result.CANCELLED, "Camera exited")

func _exit_tree() -> void:
	_exiting = true
	cancel_all("CameraDirector exited")
