class_name TouchScroll
extends Node
## Lets every ScrollContainer under the injected roots be dragged by finger.
##
## Godot's ScrollContainer reacts to the wheel and to scrollbar drags, so on a
## phone a long list has no way to scroll. Touch events keep reaching the
## container after a child button ignores them, which is where this hooks in.

const WATCHED := &"touch_scroll_watched"
## A finger that moves less than this is a tap, not a drag.
const DRAG_THRESHOLD := 8.0

var _roots: Array[Node] = []
var _container: ScrollContainer
var _touch_index := -1
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
	if not node is ScrollContainer or not _in_roots(node):
		return
	var scroll := node as ScrollContainer
	if scroll.has_meta(WATCHED):
		return
	scroll.set_meta(WATCHED, true)
	scroll.gui_input.connect(_on_scroll_gui_input.bind(scroll))


func _on_scroll_gui_input(event: InputEvent, scroll: ScrollContainer) -> void:
	if not is_instance_valid(scroll):
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_container = scroll
			_touch_index = event.index
			_origin = event.position
			_dragged = false
		elif event.index == _touch_index:
			_end_drag()
		return
	if not event is InputEventScreenDrag or event.index != _touch_index:
		return
	if not is_instance_valid(_container) or _container != scroll:
		return
	if not _dragged and event.position.distance_to(_origin) < DRAG_THRESHOLD:
		return
	_dragged = true
	scroll.scroll_vertical -= int(event.relative.y)
	scroll.scroll_horizontal -= int(event.relative.x)


func _end_drag() -> void:
	_container = null
	_touch_index = -1
	_dragged = false


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
