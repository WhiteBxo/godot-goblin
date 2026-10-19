class_name Day1WorldController
extends Node
## Projects session facts into world access. No dialogue or beat sequence.

var _state: Node
var _level: Node2D
var _actors: Array[SettlementCharacter] = []
var _points: Dictionary = {}
var _refresh_pending := false
var _staging: Callable
var _player: Node2D
var _boundary_cooldown := 0.0
signal boundary_reached(message: String)

func set_player(player: Node2D) -> void:
	_player = player
	if _level is RpgChapterMap:
		_level.market_boundary_reached.connect(_on_market_boundary)

func _on_market_boundary() -> void:
	if _boundary_cooldown <= 0.0:
		_boundary_cooldown = 3.0
		boundary_reached.emit(_level.first_visit_blocked_message)

func _physics_process(delta: float) -> void:
	_boundary_cooldown = maxf(0.0, _boundary_cooldown - delta)
	if not is_instance_valid(_player) or not _level is RpgChapterMap:
		return
	if not Day1Access.at_stage(_state, "day1.s03.explore"):
		return
	if _level.is_observing_market(_player.global_position) and not _state.get_flag("day1.s03.observed_yard"):
		_state.set_flag("day1.s03.observed_yard")
	var door: SceneEntrance = _level.get_scene_entrance(&"shop_door")
	if (door != null and _state.get_flag("day1.s03.exploration_completed")
		and _player.global_position.distance_to(door.global_position) <= 80.0
		and not _state.get_flag("day1.s03.returned_to_door")):
		_state.set_flag("day1.s03.returned_to_door")

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
		if _points.has(actor.actor_id):
			_points[actor.actor_id].interaction_enabled = actor.visible
	if _level is SettlementMap:
		_level.set_elder_access(_state.get_business_profile() != "day1" or Day1Access.can_enter_elder(_state))
	if _level is RpgChapterMap:
		_level.market_only = Day1Access.is_market_only(_state)
		for id: StringName in _points:
			_points[id].interaction_enabled = _points[id].interaction_enabled and not _level.market_only
	if _state.get_business_profile() == "day1":
		var ready := Day1Access.can_make_blood_drink(_state)
		_state.set_flag("day1.s06.blood_drink_available", ready)

func record_shop_arrival() -> void:
	if _state.get_business_profile() != "day1":
		return
	if Day1Access.at_stage(_state, "day1.s04"):
		_state.set_flag("day1.s03.returned_shop")
	if (Day1Access.at_stage(_state, "day1.s05") or Day1Access.at_stage(_state, "day1.s06")) and _state.get_flag("day1.s05.escape_completed"):
		_state.set_flag("day1.s05.returned_shop")
