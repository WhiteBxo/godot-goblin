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
## Stall keepers the chapter data knows about. They keep their goods to
## themselves on the first day, when the protagonist is still a stranger.
var _vendor_ids: Dictionary = {}
## Authored once per level; the physics step must not walk the entrance list.
var _shop_door: SceneEntrance
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
	# An older save or an F6 spawn may already be beyond the newly gated market.
	# Recover to the authored shop entrance rather than trapping every movement axis.
	if _level.market_only and _level.first_visit_bounds.has_area() and not _level.first_visit_bounds.has_point(_level.to_local(_player.global_position)):
		if _shop_door != null:
			_player.teleport_to(_shop_door.global_position)
			_on_market_boundary()
	if not Day1Access.at_stage(_state, "day1.s03.explore"):
		return
	if _level.is_observing_market(_player.global_position) and not _state.get_flag("day1.s03.observed_yard"):
		_state.set_flag("day1.s03.observed_yard")
	if (_shop_door != null and _state.get_flag("day1.s03.exploration_completed")
		and _player.global_position.distance_to(_shop_door.global_position) <= 80.0
		and not _state.get_flag("day1.s03.returned_to_door")):
		_state.set_flag("day1.s03.returned_to_door")

func configure(state: Node, level: Node2D, actors: Array[SettlementCharacter], points: Dictionary) -> void:
	_state = state
	_level = level
	_actors = actors
	_points = points
	_shop_door = level.get_scene_entrance(&"shop_door")
	_state.state_changed.connect(_schedule_refresh)
	_refresh()

## `lookup(actor_id) -> Variant`: non-null when chapter staging owns that actor's
## visibility for the current stage; null keeps the default projection.
func set_staging_lookup(lookup: Callable) -> void:
	_staging = lookup
	_schedule_refresh()

## Market vendors listed by chapter data. Registered once; the day gate decides
## whether they are worth talking to.
func set_vendor_ids(ids: Array) -> void:
	_vendor_ids.clear()
	for id: Variant in ids:
		_vendor_ids[StringName(id)] = true
	_schedule_refresh()

func _schedule_refresh() -> void:
	if not _refresh_pending:
		_refresh_pending = true
		_refresh.call_deferred()

func _refresh() -> void:
	_refresh_pending = false
	if not is_inside_tree() or not is_instance_valid(_state):
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
		if actor is FatGoblin:
			actor.set_health(_fat_goblin_health())
			actor.set_mood(_fat_goblin_mood())
		if _points.has(actor.actor_id):
			var trading: bool = not _vendor_ids.has(actor.actor_id) or _state.current_day >= 2
			# Resting changes the patient's pose, not his ability to receive a cup.
			# The story route and TaskDelivery still validate the actual handoff.
			_points[actor.actor_id].interaction_enabled = actor.visible and trading
	if _level is SettlementMap:
		_level.set_elder_access(_state.get_business_profile() != "day1" or Day1Access.can_enter_elder(_state))
	if _level is RpgChapterMap:
		_level.market_only = Day1Access.is_market_only(_state)
		for id: StringName in _points:
			_points[id].interaction_enabled = _points[id].interaction_enabled and not _level.market_only
	if _state.get_business_profile() == "day1":
		var ready := Day1Access.can_make_blood_drink(_state)
		_state.set_flag("day1.s06.blood_drink_available", ready)

## 剧情事实投影：喝下格里芬之血倒地后是坐地反胃，第二天起改为坐地休养，
## 救治成功（signature.S06.rescued_in_time）后恢复常态。
func _fat_goblin_health() -> FatGoblin.Health:
	if _state.get_business_profile() != "day1" or _state.get_flag("signature.S06.rescued_in_time"):
		return FatGoblin.Health.NORMAL
	if _state.current_day >= 2:
		return FatGoblin.Health.RESTING
	return FatGoblin.Health.COLLAPSED if _state.get_flag("day1.s06.blood_collapsed") else FatGoblin.Health.NORMAL

## 剧情事实投影（第一天委托流程）：他上门求主角收下哥布林食材时合十拜托，
## 嘀咕"这食材怎么奇形怪状"时摸额头苦恼，吃完奶茶给出地图时摸着肚子满足。
## 身体状态非 NORMAL 时情绪不生效，由 FatGoblin 自己保证。
func _fat_goblin_mood() -> FatGoblin.Mood:
	if _state.get_business_profile() != "day1" or _state.current_day >= 2:
		return FatGoblin.Mood.NEUTRAL
	if Day1Access.at_stage(_state, "day1.s04.wait_map"):
		return FatGoblin.Mood.HAPPY
	if Day1Access.at_stage(_state, "day1.s04.wait_taste"):
		return FatGoblin.Mood.WORRIED
	if Day1Access.at_stage(_state, "day1.s04"):
		return FatGoblin.Mood.PLEADING
	return FatGoblin.Mood.NEUTRAL

func record_shop_arrival() -> void:
	if _state.get_business_profile() != "day1":
		return
	if Day1Access.at_stage(_state, "day1.s04"):
		_state.set_flag("day1.s03.returned_shop")
	# Travel may finish before the exterior's next physics tick checks its zone.
	# A real shop arrival can also finish the return, with the mission goods and
	# both guard payments intact. Optional documents never gate this fact.
	if (Day1Access.can_enter_elder(_state)
		and _state.get_flag("day1.s05.drunken_paid")
		and _state.get_flag("day1.s05.guard_payment_completed")
		and _state.get_flag("day1.s05.blood_acquired")
		and _state.get_warehouse_inventory().has_uses({"day1_griffin_blood": 3})):
		_state.set_flag("day1.s05.escape_completed")
	if (Day1Access.at_stage(_state, "day1.s05") or Day1Access.at_stage(_state, "day1.s06")) and _state.get_flag("day1.s05.escape_completed"):
		_state.set_flag("day1.s05.returned_shop")
