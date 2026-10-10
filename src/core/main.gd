class_name MainGame
extends Node

@onready var _active_level: CaveMap = $World/LevelRoot/CaveMap
@onready var _player: CavePlayer = $World/EntityRoot/Player

var _debug_tools: DeveloperTools
var _demo_tools: CaveDemoController
var _debug_panel: DeveloperPanel

func _ready() -> void:
	DebugRuntime.apply_release_policy(get_tree())
	var error := _active_level.load_error
	if DebugRuntime.is_enabled():
		_create_debug_components()
		error = _demo_tools.apply_layout_override()
	if error != OK:
		push_error("Could not initialize MainGame level (error %d)" % error)
		get_tree().quit(1)
		return
	_player.configure(_active_level.can_stand_at)
	_player.global_position = _active_level.get_spawn_position()
	_player.follow_player()
	if _debug_tools != null:
		_debug_tools.configure(_player.set_speed_multiplier, _player.get_speed_multiplier, _debug_panel)
		_demo_tools.start()

func get_active_level() -> CaveMap:
	return _active_level

func get_player() -> CavePlayer:
	return _player

func get_debug_tools() -> DeveloperTools:
	return _debug_tools

func get_demo_tools() -> CaveDemoController:
	return _demo_tools

func _create_debug_components() -> void:
	var panel: DeveloperPanel = load("res://src/debug/developer_tools/developer_panel.tscn").instantiate()
	_debug_panel = panel
	$DebugLayer.add_child(panel)
	_debug_tools = load("res://src/debug/developer_tools/developer_tools.tscn").instantiate()
	$Systems.add_child(_debug_tools)
	var overlay: CaveDebugOverlay = load("res://src/debug/cave_demo/debug_overlay.tscn").instantiate()
	$DebugLayer.add_child(overlay)
	_demo_tools = load("res://src/debug/cave_demo/cave_demo.tscn").instantiate()
	$Systems.add_child(_demo_tools)
	_demo_tools.configure(_active_level, _player, overlay)
	_demo_tools.capture_started.connect(panel.hide)
