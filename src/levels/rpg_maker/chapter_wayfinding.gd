extends Node2D
## Visibility of authored signs only; never changes travel or story facts.

@export var required_stages: Array[String] = []
@export var required_flags: Array[StringName] = []
@export_range(1, 30) var minimum_day := 1
var _state: Node

func _ready() -> void:
	_state = get_node("/root/GameState")
	_state.state_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	visible = _state.current_day >= minimum_day and required_flags.all(func(flag: StringName) -> bool: return _state.get_flag(String(flag)))
	if not required_stages.is_empty():
		visible = visible and required_stages.any(func(stage: String) -> bool: return Day1Access.at_stage(_state, stage))
