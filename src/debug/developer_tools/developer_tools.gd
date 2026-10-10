class_name DeveloperTools
extends Node

const SPEED_MULTIPLIERS := [1, 2, 4, 8]

var _set_multiplier: Callable
var _get_multiplier: Callable
var _panel: DeveloperPanel
var _configured := false

func configure(set_multiplier: Callable, get_multiplier: Callable, panel: DeveloperPanel) -> Error:
	_configured = false
	if is_instance_valid(_panel) and _panel.speed_multiplier_selected.is_connected(set_player_speed_multiplier):
		_panel.speed_multiplier_selected.disconnect(set_player_speed_multiplier)
	_set_multiplier = set_multiplier
	_get_multiplier = get_multiplier
	_panel = panel
	if not is_instance_valid(_panel):
		return ERR_UNCONFIGURED
	if not DebugRuntime.is_enabled() or not _set_multiplier.is_valid() or not _get_multiplier.is_valid():
		_panel.hide()
		return ERR_UNCONFIGURED
	_panel.configure_choices(PackedInt32Array(SPEED_MULTIPLIERS))
	_panel.speed_multiplier_selected.connect(set_player_speed_multiplier)
	_panel.show()
	_configured = true
	set_player_speed_multiplier(1.0)
	return OK

func get_panel() -> DeveloperPanel:
	return _panel

func set_player_speed_multiplier(multiplier: float) -> void:
	if not _configured or not DebugRuntime.is_enabled() or not _set_multiplier.is_valid() or not _get_multiplier.is_valid():
		return
	if multiplier != int(multiplier) or int(multiplier) not in SPEED_MULTIPLIERS:
		return
	_set_multiplier.call(multiplier)
	if is_instance_valid(_panel):
		_panel.set_speed_multiplier(float(_get_multiplier.call()))
