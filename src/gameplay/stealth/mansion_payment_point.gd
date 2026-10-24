extends InteractionPoint
## The shared payment spot retires after clearance so it cannot steal the door's E prompt.

var _state: Node

func _ready() -> void:
	super._ready()
	_state = get_node("/root/GameState")
	_state.state_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	interaction_enabled = (Day1Access.at_stage(_state, "day1.s05")
		and not _state.get_flag("day1.s05.guard_payment_completed"))
