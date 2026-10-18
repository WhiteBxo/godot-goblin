class_name UIAudioFeedback
extends Node
## Binds UI signals inside injected roots, including controls created after setup.

@export var hover_sound := "ui.hover"
@export var press_sound := "ui.confirm"
@export var open_sounds: Dictionary[StringName, String] = {
	ScreenIds.HANDBOOK: "story.page_turn", ScreenIds.MAP: "story.page_turn", ScreenIds.PAUSE: "ui.confirm",
}
@export var close_sounds: Dictionary[StringName, String] = {
	ScreenIds.SHOP: "ui.cancel", ScreenIds.HANDBOOK: "ui.cancel", ScreenIds.MAP: "ui.cancel", ScreenIds.PAUSE: "ui.cancel",
}

var _sound_player: Callable
var _roots: Array[Node] = []
var _manager: UIManager
var _open: Dictionary[StringName, bool] = {}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(sound_player: Callable, roots: Array[Node], manager: UIManager = null) -> void:
	if is_instance_valid(_manager) and _manager.modal_changed.is_connected(_on_modal_changed):
		_manager.modal_changed.disconnect(_on_modal_changed)
		_manager.button_activating.disconnect(_on_press)
	_sound_player = sound_player
	_roots = roots.duplicate()
	_manager = manager
	_open.clear()
	if is_instance_valid(_manager):
		for id: StringName in _screen_ids():
			_open[id] = _manager.is_open(id)
		_manager.modal_changed.connect(_on_modal_changed)
		_manager.button_activating.connect(_on_press)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	for node in _roots:
		_watch_tree(node)


func _screen_ids() -> Array:
	var ids := open_sounds.keys()
	for id in close_sounds:
		if id not in ids:
			ids.append(id)
	return ids


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
	if not is_instance_valid(node) or not _in_roots(node):
		return
	if node is BaseButton:
		_connect(node.mouse_entered, _on_hover.bind(node))
		_connect(node.focus_entered, _on_focus.bind(node))
		# Play before a valid business handler hides or disables the pressed button.
		_connect(node.button_down, _on_press.bind(node))
	if node is ItemList or node is OptionButton:
		_connect(node.item_selected, _on_selection.bind(node))
	if node is TabBar:
		_connect(node.tab_changed, _on_selection.bind(node))


func _connect(source: Signal, callback: Callable) -> void:
	if not source.is_connected(callback):
		source.connect(callback)


func _eligible(control: Control) -> bool:
	return (is_instance_valid(control) and control.is_inside_tree() and _in_roots(control)
		and control.is_visible_in_tree() and control.can_process() and not control.is_queued_for_deletion()
		and control.mouse_filter != Control.MOUSE_FILTER_IGNORE
		and (not control is BaseButton or not control.disabled))


func _on_hover(button: BaseButton) -> void:
	if _eligible(button):
		_play(hover_sound)


func _on_focus(button: BaseButton) -> void:
	# Opening/rebuilding a screen restores focus programmatically; that is silent.
	for action: StringName in [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev"]:
		if Input.is_action_pressed(action):
			_on_hover(button)
			return


func _on_press(button: BaseButton) -> void:
	if _eligible(button):
		_play(str(button.get_meta("ui_press_sound", press_sound)))


func _on_selection(_index: int, control: Control) -> void:
	if _eligible(control):
		_play(press_sound)


func _on_modal_changed() -> void:
	for id: StringName in _screen_ids():
		var opened := _manager.is_open(id)
		if opened != _open.get(id, false):
			_open[id] = opened
			_play(open_sounds.get(id, "") if opened else close_sounds.get(id, ""))


func _play(id: String) -> void:
	if not id.is_empty() and _sound_player.is_valid():
		_sound_player.call(id, "UI")


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
