class_name Day1WorldController
extends Node
## Projects session facts into world access. No dialogue or beat sequence.

var _state: Node
var _level: Node2D
var _actors: Array[SettlementCharacter] = []
var _points: Dictionary = {}
var _refresh_pending := false
var _staging: Callable

func configure(state: Node, level: Node2D, actors: Array[SettlementCharacter], points: Dictionary) -> void:
	_state = state
	_level = level
	_actors = actors
	_points = points
	_state.state_changed.connect(_schedule_refresh)
	_refresh()

## `lookup(actor_id) -> Variant`: non-null when chapter staging owns that actor's
## visibility for the current stage; null keeps the default projection.
func set_staging_lookup(lookup: Callable) -> void:
	_staging = lookup
	_schedule_refresh()

func _schedule_refresh() -> void:
	if not _refresh_pending:
		_refresh_pending = true
		_refresh.call_deferred()

func _refresh() -> void:
	_refresh_pending = false
	if not is_instance_valid(_state):
		return
	# Entering the accepted night mission is the formal day -> night boundary.
	if (_state.get_business_profile() == "day1" and Day1Access.at_stage(_state, "day1.s05")
		and _state.get_flag("day1.s04.commission_accepted") and not _state.get_flag("day1.s05.night_started")):
		if DayPhase.is_night(_state) or DayPhase.enter_night(_state):
			_state.set_flag("day1.s05.night_started")
	for actor: SettlementCharacter in _actors:
		# Actors named by the chapter's stage setup keep the visibility staging and
		# story events gave them; the default phase and S06 rules skip them.
		var staged := _staging.is_valid() and _staging.call(actor.actor_id) != null
		if not staged:
			actor.refresh_phase(_state)
			if _level is MilkTeaShop and actor.actor_id == &"fat_goblin" and Day1Access.is_later_stage(_state):
				actor.visible = Day1Access.at_stage(_state, "day1.s06")
		if _level is SettlementMap and _points.has(actor.actor_id):
			_points[actor.actor_id].interaction_enabled = actor.visible
	if _level is SettlementMap:
		_level.set_elder_access(_state.get_business_profile() != "day1" or Day1Access.can_enter_elder(_state))
	if _state.get_business_profile() == "day1":
		var ready := Day1Access.can_make_blood_drink(_state)
		_state.set_flag("day1.s06.blood_drink_available", ready)

func record_shop_arrival() -> void:
	if _state.get_business_profile() != "day1":
		return
	if (Day1Access.at_stage(_state, "day1.s05") or Day1Access.at_stage(_state, "day1.s06")) and _state.get_flag("day1.s05.escape_completed"):
		_state.set_flag("day1.s05.returned_shop")
