extends Node2D
## Visibility of authored signs only; never changes travel or story facts.

@export var required_stages: Array[String] = []
@export var required_flags: Array[StringName] = []
var _state: Node

func _ready() -> void:
	_state = get_node("/root/GameState")
	_state.state_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	visible = required_flags.all(func(flag: StringName) -> bool: return _state.get_flag(String(flag)))
	if not required_stages.is_empty():
		visible = visible and required_stages.any(func(stage: String) -> bool: return Day1Access.at_stage(_state, stage))
