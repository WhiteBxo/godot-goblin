class_name DeveloperTools
extends Node

const SPEED_MULTIPLIERS := [1, 2, 4, 8]
const LOG_CAPACITY := 200
const TOGGLE_ACTION := &"debug_toggle_console"
const SCREEN_ID := &"developer_console"

var _set_multiplier: Callable
var _get_multiplier: Callable
var _panel: DeveloperPanel
var _context: Dictionary = {}
var _story: StoryDirector
var _ui: UIManager
var _logs: Array[String] = []
var _configured := false
var _refresh_elapsed := 0.0

func _ready() -> void:
	if DebugRuntime.is_enabled() and not InputMap.has_action(TOGGLE_ACTION):
		InputMap.add_action(TOGGLE_ACTION)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_F3
		InputMap.action_add_event(TOGGLE_ACTION, key)

## Optional context: public status/respawn/restart/guard Callables and scene services.
## Missing capabilities disable only their own controls; observation remains available.
func configure(set_multiplier: Callable, get_multiplier: Callable, panel: DeveloperPanel, context: Dictionary = {}) -> Error:
	close_panel()
	if is_instance_valid(_ui):
		_ui.unregister_screen(SCREEN_ID)
	if is_instance_valid(_panel):
		_disconnect_panel()
	_set_multiplier = set_multiplier
	_get_multiplier = get_multiplier
	_panel = panel
	_context = context.duplicate()
	_ui = context.get("ui_manager") as UIManager
	bind_story_director(context.get("story") as StoryDirector)
	_configured = DebugRuntime.is_enabled() and is_instance_valid(_panel)
	if not _configured:
		if is_instance_valid(_panel):
			_panel.hide()
		return ERR_UNCONFIGURED
	_panel.configure_choices(PackedInt32Array(SPEED_MULTIPLIERS))
	_panel.speed_multiplier_selected.connect(set_player_speed_multiplier)
	_panel.close_requested.connect(close_panel)
	_panel.respawn_requested.connect(return_to_spawn)
	_panel.restart_requested.connect(restart_scene)
	_panel.clear_log_requested.connect(clear_log)
	_panel.hide()
	if is_instance_valid(_ui):
		_ui.register_screen(SCREEN_ID, _panel, &"debug", true)
	refresh()
	return OK if _set_multiplier.is_valid() and _get_multiplier.is_valid() else ERR_UNCONFIGURED

func _disconnect_panel() -> void:
	for pair: Array in [[_panel.speed_multiplier_selected, set_player_speed_multiplier],
		[_panel.close_requested, close_panel], [_panel.respawn_requested, return_to_spawn],
		[_panel.restart_requested, restart_scene], [_panel.clear_log_requested, clear_log]]:
		var source: Signal = pair[0]
		if source.is_connected(pair[1]):
			source.disconnect(pair[1])

func get_panel() -> DeveloperPanel:
	return _panel

func is_open() -> bool:
	return is_instance_valid(_panel) and _panel.visible

func toggle_panel() -> void:
	if is_open():
		close_panel()
	elif _configured and DebugRuntime.is_enabled():
		refresh()
		if is_instance_valid(_ui):
			_ui.open_screen(SCREEN_ID)
		else:
			_panel.show()
		_panel.get_default_focus().grab_focus()

func close_panel() -> void:
	if is_instance_valid(_ui):
		_ui.close_screen(SCREEN_ID)
	if is_instance_valid(_panel):
		_panel.cancel_restart()
		_panel.hide()

func _input(event: InputEvent) -> void:
	if not _configured or not DebugRuntime.is_enabled():
		return
	if event.is_action(TOGGLE_ACTION):
		get_viewport().set_input_as_handled()
		if event.is_pressed() and not event.is_echo():
			toggle_panel()
		return
	if not is_open():
		return
	# Keep pause ownership unchanged, including when inspecting an already paused game.
	if event.is_action("pause_game") or event.is_action("ui_cancel"):
		get_viewport().set_input_as_handled()
		if event.is_action_pressed("ui_cancel") and not event.is_echo():
			close_panel()
		return
	# GUI navigation/text selection stays native; gameplay input cannot reach scene tools.
	for action: StringName in [&"interact", &"debug_cycle_walls", &"debug_toggle_overview", &"debug_settlement_routes"]:
		if event.is_action(action):
			get_viewport().set_input_as_handled()
			return

func _allowed(key: String) -> bool:
	var guard: Callable = _context.get(key, Callable())
	return not guard.is_valid() or bool(guard.call())

func _has_action(key: String) -> bool:
	var action: Callable = _context.get(key, Callable())
	return action.is_valid()

func set_player_speed_multiplier(multiplier: float) -> void:
	if not _configured or not DebugRuntime.is_enabled() or not _allowed("can_control") or not _set_multiplier.is_valid() or not _get_multiplier.is_valid():
		return
	if multiplier != int(multiplier) or int(multiplier) not in SPEED_MULTIPLIERS:
		return
	_set_multiplier.call(multiplier)
	refresh()

func return_to_spawn() -> void:
	if _configured and DebugRuntime.is_enabled() and _allowed("can_control") and _has_action("respawn"):
		_context.respawn.call()
		refresh()

## Called only after the panel's inline confirmation; never clears GameState.
func restart_scene() -> void:
	if _configured and DebugRuntime.is_enabled() and _allowed("can_restart") and _has_action("restart"):
		close_panel()
		_context.restart.call()

func _process(delta: float) -> void:
	if not DebugRuntime.is_enabled():
		close_panel()
		return
	if not is_open():
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.2:
		_refresh_elapsed = 0.0
		refresh()

func refresh() -> void:
	if not _configured or not DebugRuntime.is_enabled():
		return
	var status: Callable = _context.get("status", Callable())
	var data: Dictionary = status.call() if status.is_valid() else {}
	var state: Node = _context.get("state")
	var snapshot: Dictionary = state.to_dict() if is_instance_valid(state) else {}
	data["fps"] = Engine.get_frames_per_second()
	_panel.set_status(data, snapshot)
	_panel.set_story(snapshot, _story.get_runtime_status() if is_instance_valid(_story) else {})
	_panel.set_capabilities(_set_multiplier.is_valid() and _get_multiplier.is_valid() and _allowed("can_control"),
		_has_action("respawn") and _allowed("can_control"), _has_action("restart") and _allowed("can_restart"))
	if _get_multiplier.is_valid():
		_panel.set_speed_multiplier(float(_get_multiplier.call()))
	_panel.set_log(_logs)

func bind_story_director(story: StoryDirector) -> void:
	if is_instance_valid(_story):
		for pair: Array in _story_connections():
			var source: Signal = pair[0]
			if source.is_connected(pair[1]):
				source.disconnect(pair[1])
	_story = story
	if is_instance_valid(_story) and DebugRuntime.is_enabled():
		for pair: Array in _story_connections():
			var source: Signal = pair[0]
			source.connect(pair[1])

func _story_connections() -> Array:
	return [[_story.event_started, _on_event_started], [_story.step_started, _on_step_started],
		[_story.step_skipped, _on_step_skipped], [_story.event_completed, _on_event_completed],
		[_story.event_finished, _on_event_finished]]

func get_log() -> Array[String]:
	return _logs.duplicate()

func clear_log() -> void:
	_logs.clear()
	if is_instance_valid(_panel):
		_panel.set_log(_logs)

func _append_log(message: String) -> void:
	if not DebugRuntime.is_enabled():
		return
	_logs.append("[%s] %s" % [Time.get_time_string_from_system(), message])
	if _logs.size() > LOG_CAPACITY:
		_logs.pop_front()
	if is_open():
		_panel.set_log(_logs)

func _on_event_started(id: String) -> void:
	_append_log("事件开始 %s" % id)

func _on_step_started(id: String, index: int, command: String) -> void:
	_append_log("步骤开始 %s / %d · %s" % [id, index, command])

func _on_step_skipped(id: String, index: int, reason: String) -> void:
	_append_log("步骤跳过 %s / %d · %s" % [id, index, reason])

func _on_event_completed(id: String) -> void:
	_append_log("事件完成 %s" % id)

func _on_event_finished(id: String, succeeded: bool, reason: String) -> void:
	_append_log("事件结束 %s · 成功" % id if succeeded else "事件失败 %s · %s" % [id, reason])

func _exit_tree() -> void:
	close_panel()
	if is_instance_valid(_ui):
		_ui.unregister_screen(SCREEN_ID)
	bind_story_director(null)
