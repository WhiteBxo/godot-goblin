class_name UIButtonMotion
extends Node
## Gives every button under the injected roots a small hover lift and press squash.
## Presentational only: scaling never changes layout, focus or button signals.

const WATCHED := &"ui_motion_watched"
const TWEEN := &"ui_motion_tween"
const OPT_OUT := &"ui_motion"
const HOVER_LARGE := 1.02
const HOVER_SMALL := 1.05
const FOCUS_LARGE := 1.01
const FOCUS_SMALL := 1.02
const PRESS := 0.96
const HOVER_SECONDS := 0.09
const PRESS_SECONDS := 0.05
const RELEASE_SECONDS := 0.16

var _roots: Array[Node] = []

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func configure(roots: Array[Node]) -> void:
	_roots = roots.duplicate()
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	for root in _roots:
		_watch_tree(root)

func _in_roots(node: Node) -> bool:
	for scope in _roots:
		if is_instance_valid(scope) and (scope == node or scope.is_ancestor_of(node)):
			return true
	return false

func _watch_tree(node: Node) -> void:
	_watch_node(node)
	for child in node.get_children():
		_watch_tree(child)

func _on_node_added(node: Node) -> void:
	if _in_roots(node):
		_watch_weak_node.call_deferred(weakref(node))

func _watch_weak_node(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node
	if is_instance_valid(node):
		_watch_node(node)

func _watch_node(node: Node) -> void:
	if not node is BaseButton or not _in_roots(node):
		return
	var button := node as BaseButton
	if button.has_meta(WATCHED):
		return
	button.set_meta(WATCHED, true)
	if button.has_meta(OPT_OUT) and not bool(button.get_meta(OPT_OUT)):
		return
	_connect(button.mouse_entered, _lift.bind(button))
	_connect(button.mouse_exited, _settle.bind(button))
	_connect(button.button_down, _squash.bind(button))
	_connect(button.button_up, _release.bind(button))
	_connect(button.focus_entered, _focus.bind(button))
	_connect(button.focus_exited, _settle.bind(button))
	_connect(button.visibility_changed, _reset.bind(button))

func _connect(source: Signal, callback: Callable) -> void:
	if not source.is_connected(callback):
		source.connect(callback)

func _eligible(button: BaseButton) -> bool:
	return (is_instance_valid(button) and button.is_inside_tree() and button.is_visible_in_tree()
		and not button.disabled and not button.is_queued_for_deletion())

func _hover_scale(button: BaseButton) -> float:
	return HOVER_SMALL if maxf(button.size.x, button.size.y) < 120.0 else HOVER_LARGE

func _focus_scale(button: BaseButton) -> float:
	return FOCUS_SMALL if maxf(button.size.x, button.size.y) < 120.0 else FOCUS_LARGE

func _lift(button: BaseButton) -> void:
	if _eligible(button):
		_animate(button, _hover_scale(button), HOVER_SECONDS)

func _focus(button: BaseButton) -> void:
	if _eligible(button):
		_animate(button, _focus_scale(button), HOVER_SECONDS)

func _squash(button: BaseButton) -> void:
	if _eligible(button):
		_animate(button, PRESS, PRESS_SECONDS, Tween.TRANS_QUAD, Tween.EASE_OUT)

func _release(button: BaseButton) -> void:
	if _eligible(button):
		_animate(button, 1.0, RELEASE_SECONDS, Tween.TRANS_BACK, Tween.EASE_OUT)

func _settle(button: BaseButton) -> void:
	if _eligible(button):
		_animate(button, 1.0, RELEASE_SECONDS)

func _reset(button: BaseButton) -> void:
	if is_instance_valid(button) and (not button.visible or button.disabled):
		_stop(button)
		button.scale = Vector2.ONE

func _stop(button: BaseButton) -> void:
	var previous: Tween = null
	if button.has_meta(TWEEN):
		previous = button.get_meta(TWEEN) as Tween
	if previous != null and previous.is_valid():
		previous.kill()

func _animate(button: BaseButton, target: float, seconds: float,
		trans: Tween.TransitionType = Tween.TRANS_QUAD, ease_type: Tween.EaseType = Tween.EASE_OUT) -> void:
	_stop(button)
	button.pivot_offset = button.size * 0.5
	var tween := button.create_tween()
	tween.set_trans(trans).set_ease(ease_type)
	tween.tween_property(button, "scale", Vector2.ONE * target, seconds)
	button.set_meta(TWEEN, tween)

func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
