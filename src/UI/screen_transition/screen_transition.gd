class_name ScreenTransition
extends Control
## Visuals only. Host owns its CanvasLayer, gameplay locks and scene changes.

signal completed(action: TransitionAction)
signal cancelled(action: TransitionAction)

@onready var _black: ColorRect = $Black
@onready var _white: ColorRect = $White
@onready var _top: ColorRect = $TopBar
@onready var _bottom: ColorRect = $BottomBar

var _actions: Dictionary = {}
var _tweens: Dictionary = {}
var _next_id := 0
var _mutating := false
var _exiting := false
var _bar_ratio := 0.0

func _enter_tree() -> void:
	_exiting = false

func _exit_tree() -> void:
	_exiting = true
	# Exit may be triggered synchronously by a cancellation subscriber.
	_mutating = false
	cancel_all("ScreenTransition exited")

## Cover the image with black, retaining black after completion.
func fade_out(duration: float = 0.5) -> TransitionAction:
	return _start(&"black", &"fade_out", 1.0, duration)

## Reveal the image from the current black opacity; call fade_out(0) for an initial black.
func fade_in(duration: float = 0.5) -> TransitionAction:
	return _start(&"black", &"fade_in", 0.0, duration)

## Immediate white pulse followed by a fade to transparent. Does not clear black/bars.
func flash_white(duration: float = 0.25) -> TransitionAction:
	return _start(&"white", &"flash_white", 0.0, duration)

## Ratio is the height of EACH bar relative to viewport height, in [0, 0.5].
func letterbox(show_bars: bool, duration: float = 0.4, ratio: float = 0.12) -> TransitionAction:
	return _start(&"bars", &"letterbox", ratio if show_bars else 0.0, duration, ratio)

## 画面是否已经被黑色盖满（供宿主决定"淡回来"还是"直接切"）。
func is_black_covered() -> bool:
	return is_instance_valid(_black) and _black.color.a > 0.99

func is_busy() -> bool:
	return not _actions.is_empty()

## Only cancels this handle if it is still active. Clears its channel's visual.
func cancel(action: TransitionAction, reason: String = "Cancelled") -> void:
	if _mutating or action == null:
		return
	for channel: StringName in _actions.keys():
		if _actions[channel] == action:
			_mutating = true
			_set_value(channel, 0.0)
			_stop(channel, reason)
			_mutating = false
			return

## Also clears completed, retained black/bars. Never changes SceneTree.paused.
func cancel_all(reason: String = "Cancelled") -> void:
	if _mutating:
		return
	_mutating = true
	for channel: StringName in [&"black", &"white", &"bars"]:
		_set_value(channel, 0.0)
		_stop(channel, reason)
	_mutating = false

func _start(channel: StringName, effect: StringName, target: float, duration: float, ratio: float = 0.0) -> TransitionAction:
	_next_id += 1
	var action := TransitionAction.new()
	action.id = _next_id
	action.effect = effect
	if _exiting or not is_node_ready() or not is_inside_tree() or is_queued_for_deletion() or _mutating:
		action.resolve(TransitionAction.Result.FAILED, "Unavailable or cancelling; retry after the signal callback")
		return action
	if not is_finite(duration) or duration < 0.0 or not is_finite(ratio) or ratio < 0.0 or ratio > 0.5:
		action.resolve(TransitionAction.Result.FAILED, "Duration must be finite and nonnegative; bar ratio must be in [0, 0.5]")
		return action
	_mutating = true
	_stop(channel, "Replaced")
	_mutating = false
	# A cancellation subscriber may have queued this node for deletion.
	if _exiting or not is_inside_tree() or is_queued_for_deletion():
		action.resolve(TransitionAction.Result.CANCELLED, "ScreenTransition exited")
		cancelled.emit(action)
		return action
	_actions[channel] = action
	if channel == &"white":
		_set_value(channel, 1.0)
	if duration == 0.0:
		_set_value(channel, target)
		_complete.call_deferred(channel, action)
	else:
		var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
		_tweens[channel] = tween
		var start := _get_value(channel)
		var update := func(weight: float) -> void: _set_value(channel, lerpf(start, target, weight))
		tween.tween_method(update, 0.0, 1.0, duration)
		tween.finished.connect(_complete.bind(channel, action))
	return action

func _complete(channel: StringName, action: TransitionAction) -> void:
	if _actions.get(channel) != action:
		return
	_actions.erase(channel)
	_tweens.erase(channel)
	action.resolve(TransitionAction.Result.COMPLETED)
	completed.emit(action)

func _stop(channel: StringName, reason: String) -> void:
	if _tweens.has(channel):
		(_tweens[channel] as Tween).kill()
		_tweens.erase(channel)
	if _actions.has(channel):
		var action: TransitionAction = _actions[channel]
		_actions.erase(channel)
		action.resolve(TransitionAction.Result.CANCELLED, reason)
		cancelled.emit(action)

func _get_value(channel: StringName) -> float:
	match channel:
		&"black": return _black.color.a
		&"white": return _white.color.a
	return _bar_ratio

func _set_value(channel: StringName, value: float) -> void:
	# Children may already have left the tree during _exit_tree, but are still valid.
	match channel:
		&"black":
			if is_instance_valid(_black):
				_black.color.a = value
		&"white":
			if is_instance_valid(_white):
				_white.color.a = value
		&"bars":
			_bar_ratio = value
			if is_instance_valid(_top):
				_top.anchor_bottom = value
			if is_instance_valid(_bottom):
				_bottom.anchor_top = 1.0 - value
