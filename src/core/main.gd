class_name MainGame
extends Node

@onready var _active_level: CaveMap = $World/LevelRoot/CaveMap
@onready var _player: CavePlayer = $World/EntityRoot/Player
@onready var _debug_tools: CaveDemoController = $Systems/CaveDemoController
@onready var _debug_overlay: CaveDebugOverlay = $DebugLayer/DebugOverlay

func _ready() -> void:
	_debug_tools.configure(_active_level, _player, _debug_overlay)
	var error := _debug_tools.prepare_level()
	if error != OK:
		push_error("Could not initialize MainGame level (error %d)" % error)
		get_tree().quit(1)
		return
	_player.configure(_active_level.can_stand_at)
	_player.global_position = _active_level.get_spawn_position()
	_player.follow_player()
	_debug_tools.start()

func get_active_level() -> CaveMap:
	return _active_level

func get_player() -> CavePlayer:
	return _player

func get_debug_tools() -> CaveDemoController:
	return _debug_tools
