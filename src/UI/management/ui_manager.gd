class_name UIManager
extends Node
## Scene-local UI lifecycle. Gameplay locks belong to the host.

signal modal_changed
signal pause_changed(paused: bool)
signal screen_closed(id: StringName)

var _layers: Dictionary = {}
var _screens: Dictionary = {}
var _aliases: Dictionary = {}
var _stack: Array[StringName] = []
var _owns_pause := false
var _exiting := false
var _consumed_actions: Array[StringName] = []

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func configure(layers: Dictionary) -> void:
	_layers = layers.duplicate()
	get_viewport().gui_focus_changed.connect(_on_focus_changed)

func register_screen(id: StringName, view: Control, layer: StringName, modal: bool) -> Error:
	if _screens.has(id) or _aliases.has(id):
		return ERR_ALREADY_EXISTS
	if id == &"" or not is_instance_valid(view) or not _layers.has(layer):
		return ERR_INVALID_PARAMETER
	for entry: Dictionary in _screens.values():
		if entry.view == view:
			return ERR_ALREADY_EXISTS
	if view.get_parent() != _layers[layer]:
		if view.get_parent() == null:
			_layers[layer].add_child(view)
		else:
			view.reparent(_layers[layer])
	_screens[id] = {"view": view, "layer": layer, "modal": modal, "open": false,
		"focus": null, "mode": view.process_mode, "blocked": []}
	view.hide()
	view.tree_exiting.connect(_unregister.bind(id), CONNECT_ONE_SHOT)
	if view.has_method("bind_ui"):
		view.bind_ui(self, id)
	return OK

func register_screen_alias(id: StringName, target: StringName, prepare: Callable) -> Error:
	if _screens.has(id) or _aliases.has(id):
		return ERR_ALREADY_EXISTS
	if id == &"" or not _screens.has(target) or not prepare.is_valid():
		return ERR_INVALID_PARAMETER
	_aliases[id] = {"target": target, "prepare": prepare}
	return OK

func open_screen(id: StringName) -> Error:
	var prepare := Callable()
	if _aliases.has(id):
		prepare = _aliases[id].prepare
		id = _aliases[id].target
	if _exiting or not _screens.has(id):
		return ERR_DOES_NOT_EXIST
	var entry: Dictionary = _screens[id]
	if not is_instance_valid(entry.view) or not entry.view.is_inside_tree() or entry.view.is_queued_for_deletion():
		return ERR_UNCONFIGURED
	if entry.open:
		if prepare.is_valid():
			if get_tree().paused or _stack.is_empty() or _stack.back() != id:
				return ERR_BUSY
			return prepare.call()
		return OK
	if id == &"pause" and not _owns_pause:
		if get_tree().paused:
			return ERR_BUSY
		set_paused(true)
		return OK
	# One popup flow at a time; pause may cover it without ending the flow.
	if entry.layer == &"popup":
		if get_tree().paused:
			return ERR_BUSY
		for other: Dictionary in _screens.values():
			if other.open and other.modal and other.layer == &"popup":
				return ERR_BUSY
	if prepare.is_valid():
		var error: Error = prepare.call()
		if error != OK:
			return error
	var focus := get_viewport().gui_get_focus_owner()
	entry.focus = weakref(focus) if focus != null else null
	entry.open = true
	entry.view.show()
	if entry.modal:
		_stack.append(id)
	_refresh_stack()
	modal_changed.emit()
	return OK

func close_screen(id: StringName) -> void:
	id = _aliases[id].target if _aliases.has(id) else id
	if not is_open(id):
		return
	if id == &"pause" and _owns_pause:
		set_paused(false)
		return
	_close(id)

func _close(id: StringName) -> void:
	var entry: Dictionary = _screens[id]
	var was_top: bool = not _stack.is_empty() and _stack.back() == id
	entry.open = false
	_stack.erase(id)
	_restore_controls(entry)
	entry.view.hide()
	entry.view.process_mode = entry.mode
	_refresh_stack()
	if was_top:
		var previous: Control = entry.focus.get_ref() if entry.focus != null else null
		if is_instance_valid(previous) and previous.is_visible_in_tree() and previous.focus_mode != Control.FOCUS_NONE and _focus_allowed(previous):
			previous.grab_focus()
	entry.focus = null
	# Dialogue cancellation is dispatched through its manager, never just hidden.
	if entry.view.has_method("on_ui_closed"):
		entry.view.on_ui_closed()
	screen_closed.emit(id)
	modal_changed.emit()

func is_open(id: StringName) -> bool:
	id = _aliases[id].target if _aliases.has(id) else id
	return _screens.has(id) and _screens[id].open

func has_modal() -> bool:
	return not _stack.is_empty()

func request_back() -> void:
	if _owns_pause:
		set_paused(false)
	elif not _stack.is_empty():
		close_screen(_stack.back())
	elif not get_tree().paused:
		set_paused(true)

func set_paused(value: bool) -> void:
	if value:
		if _owns_pause or get_tree().paused or not _screens.has(&"pause"):
			return
		var view: Control = _screens[&"pause"].view
		if not is_instance_valid(view) or not view.is_inside_tree() or view.is_queued_for_deletion():
			return
		_owns_pause = true
		get_tree().paused = true
		_layers[&"pause"].show()
		open_screen(&"pause")
	else:
		if not _owns_pause:
			return
		_owns_pause = false
		get_tree().paused = false
		if is_open(&"pause"):
			_close(&"pause")
		_layers[&"pause"].hide()
	pause_changed.emit(value)

## Explicit removal supports scene tools rebinding a view before the old one exits.
func unregister_screen(id: StringName) -> void:
	if _aliases.has(id):
		_aliases.erase(id)
		return
	if not _screens.has(id):
		return
	var view: Control = _screens[id].view
	var callback := _unregister.bind(id)
	if is_instance_valid(view) and view.tree_exiting.is_connected(callback):
		view.tree_exiting.disconnect(callback)
	_unregister(id)

func _unregister(id: StringName) -> void:
	if not _screens.has(id):
		return
	if is_open(id):
		close_screen(id)
	_screens.erase(id)
	for alias: StringName in _aliases.keys():
		if _aliases[alias].target == id:
			_aliases.erase(alias)

func _restore_controls(entry: Dictionary) -> void:
	for saved: Dictionary in entry.blocked:
		if is_instance_valid(saved.control):
			saved.control.mouse_filter = saved.mouse
			saved.control.focus_mode = saved.focus
	entry.blocked.clear()

func _block_controls(node: Node, saved: Array) -> void:
	if node is Control:
		saved.append({"control": node, "mouse": node.mouse_filter, "focus": node.focus_mode})
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_block_controls(child, saved)

func _refresh_stack() -> void:
	for id: StringName in _screens:
		var entry: Dictionary = _screens[id]
		_restore_controls(entry)
		if entry.open:
			var covered: bool = has_modal() and id != _stack.back()
			entry.view.process_mode = Node.PROCESS_MODE_DISABLED if covered else entry.mode
			if covered:
				_block_controls(entry.view, entry.blocked)
	var focus := get_viewport().gui_get_focus_owner()
	if has_modal() and (focus == null or not _focus_allowed(focus)):
		_focus_top()
	elif not has_modal() and focus != null and not focus.is_visible_in_tree():
		focus.release_focus()

func _focus_allowed(control: Control) -> bool:
	if not has_modal():
		return true
	var view: Control = _screens[_stack.back()].view
	return control == view or view.is_ancestor_of(control)

func _focus_top() -> void:
	if not has_modal():
		return
	var view: Control = _screens[_stack.back()].view
	var target: Control = view.get_default_focus() if view.has_method("get_default_focus") else null
	if is_instance_valid(target) and target.is_visible_in_tree():
		target.grab_focus()
	else:
		var owner := get_viewport().gui_get_focus_owner()
		if owner != null:
			owner.release_focus()

func _on_focus_changed(control: Control) -> void:
	if is_instance_valid(control) and has_modal() and not _focus_allowed(control):
		_focus_top.call_deferred()

func _collect_focus(node: Node, controls: Array[Control]) -> void:
	if node is Control and node.is_visible_in_tree() and node.focus_mode == Control.FOCUS_ALL:
		if not node is BaseButton or not node.disabled:
			controls.append(node)
	for child in node.get_children():
		_collect_focus(child, controls)

func _navigate(backwards: bool) -> void:
	var controls: Array[Control] = []
	_collect_focus(_screens[_stack.back()].view, controls)
	if controls.is_empty():
		return
	var index := controls.find(get_viewport().gui_get_focus_owner())
	controls[wrapi(index + (-1 if backwards else 1), 0, controls.size())].grab_focus()

func _input(event: InputEvent) -> void:
	# Consume the matching release even if the press closed the last modal.
	for action in _consumed_actions.duplicate():
		if event.is_action_released(action):
			_consumed_actions.erase(action)
			get_viewport().set_input_as_handled()
			return
	var pause := event.is_action("pause_game")
	var back := event.is_action("ui_cancel")
	if pause or back:
		get_viewport().set_input_as_handled()
		if event.is_pressed() and not event.is_echo():
			_consumed_actions.append(&"pause_game" if pause else &"ui_cancel")
			if pause:
				set_paused(not _owns_pause)
			else:
				request_back()
		return
	if not has_modal():
		return
	var top_view: Control = _screens[_stack.back()].view
	# Some screens use native Control navigation (OptionButton popups, TextEdit scrolling).
	if top_view.has_method("uses_native_gui_input") and top_view.uses_native_gui_input():
		return
	var actions: Array[StringName] = [&"interact", &"ui_accept", &"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev"]
	for action in actions:
		if not event.is_action(action):
			continue
		get_viewport().set_input_as_handled()
		if not event.is_pressed() or event.is_echo():
			return
		_consumed_actions.append(action)
		var view: Control = _screens[_stack.back()].view
		if view.has_method("handle_ui_input") and action != &"ui_focus_next" and action != &"ui_focus_prev":
			view.handle_ui_input(event)
		elif action == &"interact" or action == &"ui_accept":
			var focused := get_viewport().gui_get_focus_owner() as BaseButton
			if focused != null and not focused.disabled and _focus_allowed(focused):
				focused.pressed.emit()
		else:
			_navigate(action in [&"ui_up", &"ui_left", &"ui_focus_prev"] or (action == &"ui_focus_next" and event is InputEventKey and event.shift_pressed))
		return

func _exit_tree() -> void:
	_exiting = true
	if _owns_pause:
		get_tree().paused = false
		_owns_pause = false
	var entries := _screens.duplicate()
	_stack.clear()
	_screens.clear()
	_aliases.clear()
	for id: StringName in entries:
		var entry: Dictionary = entries[id]
		_restore_controls(entry)
		if is_instance_valid(entry.view):
			entry.view.process_mode = entry.mode
			entry.view.hide()
			if entry.open and entry.view.has_method("on_ui_closed"):
				entry.view.on_ui_closed()
		if entry.open:
			screen_closed.emit(id)
	modal_changed.emit()
	_consumed_actions.clear()
	if get_viewport().gui_focus_changed.is_connected(_on_focus_changed):
		get_viewport().gui_focus_changed.disconnect(_on_focus_changed)
