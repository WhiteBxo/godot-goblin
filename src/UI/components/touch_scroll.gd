class_name TouchScroll
extends Node
## Lets every ScrollContainer, and every scrollable RichTextLabel, under the
## injected roots be dragged by finger.
##
## Godot's ScrollContainer reacts to the wheel and to scrollbar drags, and
## RichTextLabel only reacts to the wheel, so on a phone a long list — or a long
## authored note, which is a RichTextLabel — has no way to scroll. Touch events
## keep reaching the control after a child button ignores them, which is where
## this hooks in.

const WATCHED := &"touch_scroll_watched"
## A finger that moves less than this is a tap, not a drag.
const DRAG_THRESHOLD := 8.0
## Desktop mice get the same drag on RichTextLabel only: lists keep their
## scrollbar behaviour so a click on the bar is not stolen by a "drag".
const MOUSE_POINTER := -1

var _roots: Array[Node] = []
var _target: Control
var _pointer := -1
var _origin := Vector2.ZERO
var _dragged := false


func configure(roots: Array[Node]) -> void:
	_roots = roots.duplicate()
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	for root: Node in _roots:
		_watch_tree(root)


func _in_roots(node: Node) -> bool:
	for scope: Node in _roots:
		if is_instance_valid(scope) and (scope == node or scope.is_ancestor_of(node)):
			return true
	return false


func _watch_tree(node: Node) -> void:
	_watch_node(node)
	for child: Node in node.get_children():
		_watch_tree(child)


func _on_node_added(node: Node) -> void:
	if _in_roots(node):
		_watch_deferred.call_deferred(weakref(node))


func _watch_deferred(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node
	if is_instance_valid(node):
		_watch_node(node)


func _watch_node(node: Node) -> void:
	if not _in_roots(node):
		return
	if node is ScrollContainer:
		var scroll := node as ScrollContainer
		if scroll.has_meta(WATCHED):
			return
		scroll.set_meta(WATCHED, true)
		scroll.gui_input.connect(_on_control_gui_input.bind(scroll))
		return
	if node is RichTextLabel:
		var label := node as RichTextLabel
		# Long authored prose is built at runtime with `scroll_active`; labels
		# that never scroll must not swallow drags from the world below.
		if not label.scroll_active or label.has_meta(WATCHED):
			return
		label.set_meta(WATCHED, true)
		label.gui_input.connect(_on_control_gui_input.bind(label))


func _on_control_gui_input(event: InputEvent, control: Control) -> void:
	if not is_instance_valid(control):
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin(control, event.index, event.position)
		elif event.index == _pointer:
			_end_drag()
		return
	if event is InputEventScreenDrag:
		if event.index != _pointer:
			return
		_drag_to(control, event.position, event.relative)
		return
	if not control is RichTextLabel:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin(control, MOUSE_POINTER, event.position)
		elif _pointer == MOUSE_POINTER:
			_end_drag()
		return
	if event is InputEventMouseMotion and _pointer == MOUSE_POINTER:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_end_drag()
			return
		_drag_to(control, event.position, event.relative)


func _begin(control: Control, pointer: int, position: Vector2) -> void:
	_target = control
	_pointer = pointer
	_origin = position
	_dragged = false


func _drag_to(control: Control, position: Vector2, relative: Vector2) -> void:
	if not is_instance_valid(_target) or _target != control:
		return
	if not _dragged and position.distance_to(_origin) < DRAG_THRESHOLD:
		return
	_dragged = true
	_scroll(control, relative)


func _scroll(control: Control, delta: Vector2) -> void:
	if control is ScrollContainer:
		var scroll := control as ScrollContainer
		scroll.scroll_vertical -= int(delta.y)
		scroll.scroll_horizontal -= int(delta.x)
	elif control is RichTextLabel:
		var bar := (control as RichTextLabel).get_v_scroll_bar()
		bar.value -= delta.y


func _end_drag() -> void:
	_target = null
	_pointer = -1
	_dragged = false


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
