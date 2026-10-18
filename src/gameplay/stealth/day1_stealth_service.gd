class_name Day1StealthService
extends Node
## Day 1 gameplay only. Story and the host consume results and own player control.

signal changed
signal attempt_failed(guard_id: StringName)
signal guard_intercepted(event_id: String)
signal escaped
signal throw_resolved(kind: StringName, affected: bool)
signal retry_travel_requested

enum Status { IDLE, PENDING, RUNNING, FAILED, INTERCEPTED, ESCAPED }

var status: Status = Status.IDLE
## Forwarded from the player's held slot; this scene never keeps its own copy.
var selected_kind: StringName:
	get:
		return _player.held_item if is_instance_valid(_player) else &""
var selected_drink_id: String:
	get:
		return _player.held_variant_id if is_instance_valid(_player) and _player.held_item == &"drink" else ""
var message := ""
var _state: Node
var _inventory: WarehouseInventory
var _player: PlayerController
var _effects: Node2D
var _setup: Day1StealthSetup
var _actor_lookup: Callable
var _can_operate: Callable
var _pending_throw: Dictionary = {}
var _target_override: Variant
var _projectiles: Array[Day1ThrowProjectile] = []
var _areas: Array[DrinkEffectArea] = []
var _generation := 0
var _releasing := false
var _confusion_created := false
var _auto_start := true

func configure(state: Node, inventory: WarehouseInventory, player: PlayerController, effects: Node2D, setup: Day1StealthSetup, actor_lookup: Callable, can_operate: Callable) -> void:
	_state = state
	_inventory = inventory
	_player = player
	_effects = effects
	_setup = setup
	_actor_lookup = actor_lookup
	_can_operate = can_operate
	_player.action_started.connect(_on_action_started)
	_player.action_triggered.connect(_on_action_triggered)
	_player.action_finished.connect(_on_action_finished)
	_state.state_reset.connect(_on_session_replaced)
	_state.state_restored.connect(_on_session_replaced)
	if is_instance_valid(_setup):
		for guard: Variant in _setup.guards:
			if is_instance_valid(guard) and is_instance_valid(guard.actor):
				guard.capture_checkpoint()
	_refresh_pending()

func get_configuration_issues() -> PackedStringArray:
	return _setup.get_issues(_inventory, _actor_lookup) if is_instance_valid(_setup) else PackedStringArray(["缺少潜入关卡配置（P09）"])

func get_inventory() -> WarehouseInventory:
	return _inventory

func get_setup() -> Day1StealthSetup:
	return _setup

func get_objective_progress() -> String:
	var lines := PackedStringArray()
	for flag: String in _setup.objective_names:
		lines.append("%s %s" % ["✓" if _state.get_flag(flag) else "○", _setup.objective_names[flag]])
	return " · ".join(lines)

func has_mission_items() -> bool:
	if not _setup.required_flags.all(func(flag: StringName) -> bool: return _state.get_flag(String(flag))):
		return false
	return _inventory.has_uses(_setup.required_items) if _setup.wallet_coins else _inventory.has_materials(_setup.required_items)

func is_blocking() -> bool:
	return status in [Status.FAILED, Status.INTERCEPTED]

func is_mission_stage() -> bool:
	return is_instance_valid(_state) and _state.get_business_profile() == "day1" and Day1Access.can_enter_elder(_state)

func can_accept_input() -> bool:
	return status == Status.RUNNING and _external_control_available() and _player.movement_enabled and not _player.is_performance_controlled()

func select_throwable(kind: StringName) -> Error:
	if kind not in [&"coin", &"torch"]:
		return ERR_INVALID_PARAMETER
	if _setup.wallet_coins and kind != &"coin":
		return ERR_UNAVAILABLE
	if not can_accept_input() or not _pending_throw.is_empty() or _releasing:
		return ERR_BUSY
	if not _player.set_held(kind):
		return ERR_INVALID_PARAMETER
	changed.emit()
	return OK

func select_drink(id: String) -> Error:
	if _inventory.get_drink_stock(id) <= 0 or _inventory.get_drink_record(id).is_empty():
		return ERR_DOES_NOT_EXIST
	if not can_accept_input() or not _pending_throw.is_empty() or _releasing:
		return ERR_BUSY
	if not _player.set_held(&"drink", id):
		return ERR_INVALID_PARAMETER
	changed.emit()
	return OK

func get_active_areas() -> Array[DrinkEffectArea]:
	return _areas.duplicate()

## Also used by tests/tools; the same animation release and real inventory apply.
func request_throw(target: Vector2) -> Error:
	if not can_accept_input() or not _valid_target(target) or _releasing:
		return ERR_UNAVAILABLE
	_target_override = target
	var accepted := _player.request_action(&"throw")
	_target_override = null
	return OK if accepted else ERR_BUSY

func begin_attempt() -> Error:
	if status in [Status.RUNNING, Status.FAILED, Status.INTERCEPTED, Status.ESCAPED] or _releasing or not _external_control_available():
		return ERR_BUSY
	if not is_mission_stage():
		return ERR_UNAUTHORIZED
	var issues := get_configuration_issues()
	if not issues.is_empty():
		_set_status(Status.PENDING, "潜入尚未接通：" + "；".join(issues))
		return ERR_UNCONFIGURED
	if _state.get_flag("day1.s05.escape_completed"):
		_set_status(Status.ESCAPED, "已安全撤离")
		return ERR_ALREADY_EXISTS
	if _setup.wallet_coins:
		_state.begin_infiltration_attempt()
		_clear_local(false)
	else:
		_clear_local()
		_player.teleport_to(_setup.checkpoint.global_position)
	_set_status(Status.RUNNING, "鼠标指向落点，使用投掷操作")
	return OK

func retry_attempt() -> Error:
	if (not is_blocking() and not _setup.wallet_coins) or _releasing or not _external_control_available():
		return ERR_BUSY
	if not is_mission_stage() or not get_configuration_issues().is_empty():
		return ERR_UNCONFIGURED
	if _setup.wallet_coins:
		var error: Error = _state.retry_infiltration_attempt()
		if error != OK:
			return error
		if _setup.interior_only:
			retry_travel_requested.emit()
			return OK
	_clear_local()
	_player.teleport_to(_setup.checkpoint.global_position)
	_set_status(Status.RUNNING, "已恢复潜入开始前的完整状态" if _setup.wallet_coins else "已返回检查点；已使用的物品不会补回")
	return OK

func cancel_attempt() -> void:
	_clear_local()
	# Leaving the attempt must not leave the coin in the player's hands.
	if is_instance_valid(_player):
		_player.clear_held()
	_auto_start = false
	_set_status(Status.IDLE, "")

func _external_control_available() -> bool:
	return (is_inside_tree() and not get_tree().paused and is_instance_valid(_player)
		and is_instance_valid(_effects) and is_instance_valid(_setup)
		and _can_operate.is_valid() and _can_operate.call())

func _refresh_pending() -> void:
	var issues := get_configuration_issues()
	if not issues.is_empty():
		_set_status(Status.PENDING, "潜入尚未接通：" + "；".join(issues))

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_state):
		return
	if not is_mission_stage():
		if status not in [Status.IDLE, Status.PENDING]:
			cancel_attempt()
		_auto_start = true
		return
	if status == Status.IDLE and _auto_start:
		begin_attempt()
	if status in [Status.RUNNING, Status.INTERCEPTED] and not _bindings_available():
		cancel_attempt()
		_set_status(Status.PENDING, "潜入绑定已退出场景，请修复配置后重新开始")
		return
	if status == Status.INTERCEPTED and _external_control_available():
		for guard: Day1GuardResponse in _setup.guards:
			if guard.role == Day1GuardResponse.Role.DRUNKEN and _guard_cleared(guard) and _state.is_event_completed(guard.encounter_event_id):
				_set_status(Status.RUNNING, "守卫已放行")
	if not can_accept_input():
		return
	var space := _effects.get_world_2d().direct_space_state
	for target: Day1FlammableTarget in _setup.flammable_targets:
		target.advance(delta)
	for projectile: Day1ThrowProjectile in _projectiles.duplicate():
		var result := projectile.advance(delta, space)
		if not result.is_empty():
			_projectiles.erase(projectile)
			projectile.queue_free()
			_resolve_impact(result)
			if status != Status.RUNNING:
				return
	for area: DrinkEffectArea in _areas.duplicate():
		var generation := _generation
		area.advance(delta, _setup, space)
		if generation != _generation or status != Status.RUNNING:
			return
		_confusion_created = _confusion_created or area.confusion_created
		if area.finished:
			_areas.erase(area)
			area.queue_free()
	# Discovery wins over escape when both happen in the same tick.
	for guard: Day1GuardResponse in _setup.guards:
		guard.set_cleared(_guard_cleared(guard))
		if guard.advance(delta, _player, space):
			_clear_flights()
			_reset_responses(false)
			_player.cancel_action()
			if guard.role == Day1GuardResponse.Role.DRUNKEN:
				_set_status(Status.INTERCEPTED, "醉酒守卫拦住了你；完成交涉后继续，或返回检查点")
				guard_intercepted.emit(guard.encounter_event_id)
			else:
				_set_status(Status.FAILED, "%s发现了你。下次留意朝向，避开观察区域再通过。" % guard.actor.display_name)
				attempt_failed.emit(guard.actor.actor_id)
			return
	_try_escape()

func _bindings_available() -> bool:
	if not is_instance_valid(_setup):
		return false
	if _setup.interior_only:
		return true
	if not is_instance_valid(_setup.checkpoint) or not _setup.checkpoint.is_inside_tree() or not _setup.checkpoint.global_position.is_finite() or not _setup.has_escape_shape():
		return false
	for binding: Variant in _setup.guards + _setup.flammable_targets + _setup.destructible_targets:
		if not is_instance_valid(binding) or not binding.is_inside_tree():
			return false
	for guard: Day1GuardResponse in _setup.guards:
		if not is_instance_valid(guard.actor) or not guard.actor.is_inside_tree():
			return false
	for target: Day1DestructibleTarget in _setup.destructible_targets:
		if not is_instance_valid(target.blocker) or not target.blocker.is_inside_tree():
			return false
	return true

func _guard_cleared(guard: Day1GuardResponse) -> bool:
	if _setup.wallet_coins:
		return guard.clearance_flag != &"" and _state.get_flag(String(guard.clearance_flag))
	# A configured clearance fact cannot substitute for a successful payment.
	return (guard.clearance_flag != &"" and _state.get_flag(String(guard.clearance_flag))
		and _state.get_flag("day1.s05.guard_payment_completed")
		and (guard.role != Day1GuardResponse.Role.DRUNKEN or _state.is_event_completed(guard.encounter_event_id)))

func _on_action_started(action: StringName, _direction: Vector2) -> void:
	if action != &"throw" or not can_accept_input() or _releasing:
		return
	if not _player.has_held():
		message = "没有手持物品"
		changed.emit()
		return
	var target: Vector2 = _target_override if _target_override is Vector2 else _effects.get_global_mouse_position()
	if not _valid_target(target):
		message = "落点超出投掷范围"
		changed.emit()
		return
	_pending_throw = {"kind": selected_kind, "target": target}
	if selected_kind == &"drink":
		var record := _inventory.get_drink_record(selected_drink_id)
		if record.is_empty():
			_pending_throw.clear()
			return
		_pending_throw["drink_id"] = selected_drink_id
		_pending_throw["payload"] = record.throw.duplicate(true)

func _on_action_triggered(action: StringName, _direction: Vector2) -> void:
	if action != &"throw" or _pending_throw.is_empty() or not can_accept_input() or _releasing:
		return
	var pending := _pending_throw
	_pending_throw = {}
	var item: String = _setup.coin_item_id if pending.kind == &"coin" else _setup.torch_item_id
	var generation := _generation
	_releasing = true
	# The animation has one release; consume once under our reentry guard. Retry never consumes.
	var consumed: bool
	if _setup.wallet_coins and pending.kind == &"coin":
		consumed = _state.commit_story_transaction("day1.throw_%d" % Time.get_ticks_usec(), {}, {}, -WalletTransactions.COIN_FACE_VALUE) == OK
	else:
		consumed = _inventory.try_consume_drink(pending.drink_id) if pending.kind == &"drink" else _inventory.try_consume({item: 1})
	_releasing = false
	if not consumed:
		message = "没有可用的投掷物品"
		changed.emit()
		return
	if generation != _generation or not can_accept_input():
		return
	var projectile := Day1ThrowProjectile.new()
	projectile.speed *= _setup.effect_scale
	projectile.scale = Vector2.ONE * _setup.effect_scale
	projectile.kind = pending.kind
	projectile.destination = pending.target
	projectile.payload = pending.get("payload", {})
	_effects.add_child(projectile)
	projectile.global_position = _player.global_position
	_projectiles.append(projectile)
	message = "已投出%s" % ({&"coin": "古怪金币", &"torch": "火把", &"drink": "饮品"}[pending.kind])
	changed.emit()

func _on_action_finished(action: StringName, _cancelled: bool) -> void:
	if action == &"throw":
		_pending_throw.clear()

func _valid_target(target: Vector2) -> bool:
	var distance := _player.global_position.distance_to(target)
	return target.is_finite() and distance > 1.0 and distance <= _setup.throw_range

func _resolve_impact(result: Dictionary) -> void:
	var affected := false
	if result.kind == &"coin":
		for guard: Variant in _setup.guards:
			affected = guard.distract(result.position) or affected
	elif result.kind == &"drink":
		var area := DrinkEffectArea.new()
		area.configure(result.payload, _setup.effect_scale)
		_effects.add_child(area)
		area.global_position = result.position
		_areas.append(area)
		if not area.is_silent():
			for guard: Day1GuardResponse in _setup.guards:
				affected = guard.distract(result.position) or affected
		area.advance(0.0, _setup, _effects.get_world_2d().direct_space_state)
		affected = area.affected or affected
		_confusion_created = _confusion_created or area.confusion_created
	else:
		var target := result.collider as Day1FlammableTarget
		if is_instance_valid(target) and target in _setup.flammable_targets and target.ignite():
			affected = true
			_confusion_created = true
			for guard: Day1GuardResponse in _setup.guards:
				guard.confuse(target.global_position, target.confusion_radius * _setup.effect_scale, target.confusion_seconds)
	message = ("守卫转移了注意力" if affected else "声响没有引开守卫") if result.kind == &"coin" else ("火把点燃了目标，附近守卫陷入混乱" if affected else "火把没有点燃目标")
	if result.kind == &"drink":
		message = "饮品已落地，效果区域正在生效"
	throw_resolved.emit(result.kind, affected)
	changed.emit()

func _try_escape() -> void:
	if _setup.interior_only:
		return
	if not _setup.contains_escape_position(_player.global_position):
		return
	for flag: StringName in _setup.required_flags:
		if not _state.get_flag(String(flag)):
			return
	var active_confusion := false
	for target: Day1FlammableTarget in _setup.flammable_targets:
		active_confusion = active_confusion or target.remaining > 0.0
	for guard: Day1GuardResponse in _setup.guards:
		active_confusion = active_confusion or (guard.state == Day1GuardResponse.State.CONFUSED and guard.remaining > 0.0)
	var has_items := _inventory.has_uses(_setup.required_items) if _setup.wallet_coins else _inventory.has_materials(_setup.required_items)
	if not has_items or (_setup.confusion_required and (not _confusion_created or not active_confusion)):
		return
	for guard: Day1GuardResponse in _setup.guards:
		if guard.role in [Day1GuardResponse.Role.MANSION_GATE, Day1GuardResponse.Role.DRUNKEN] and not _guard_cleared(guard):
			return
		if guard.role == Day1GuardResponse.Role.DRUNKEN and not _state.is_event_completed(guard.encounter_event_id):
			return
	var generation := _generation
	if not _state.set_flag("day1.s05.escape_completed"):
		return
	if generation != _generation or not is_mission_stage() or not _state.get_flag("day1.s05.escape_completed"):
		return
	_clear_local(false)
	_set_status(Status.ESCAPED, "已安全撤离")
	escaped.emit()

func _clear_flights() -> void:
	_pending_throw.clear()
	_target_override = null
	for projectile: Day1ThrowProjectile in _projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	_projectiles.clear()
	for area: DrinkEffectArea in _areas:
		if is_instance_valid(area):
			area.finished = true
			area.queue_free()
	_areas.clear()

func _clear_local(restore_actors: bool = true) -> void:
	_generation += 1
	_clear_flights()
	_confusion_created = false
	if is_instance_valid(_player):
		# A restarted or retried attempt always starts holding the coin again.
		_player.set_held(&"coin")
		_player.cancel_action()
	_reset_responses(restore_actors)

func _reset_responses(restore_actors: bool) -> void:
	if is_instance_valid(_setup):
		for guard: Variant in _setup.guards:
			if is_instance_valid(guard):
				guard.reset_response(restore_actors)
		for target: Variant in _setup.flammable_targets:
			if is_instance_valid(target):
				target.reset_target()
		for target: Variant in _setup.destructible_targets:
			if is_instance_valid(target):
				target.reset_target()

func _set_status(next: Status, text: String) -> void:
	status = next
	message = text
	if is_instance_valid(_setup):
		for guard: Day1GuardResponse in _setup.guards:
			if is_instance_valid(guard):
				guard.set_feedback_enabled(next == Status.RUNNING)
	changed.emit()

func _on_session_replaced() -> void:
	cancel_attempt()
	_auto_start = true
	_refresh_pending()

func _exit_tree() -> void:
	_clear_local(false)
	if is_instance_valid(_player):
		_player.clear_held()
		_player.action_started.disconnect(_on_action_started)
		_player.action_triggered.disconnect(_on_action_triggered)
		_player.action_finished.disconnect(_on_action_finished)
	if is_instance_valid(_state):
		_state.state_reset.disconnect(_on_session_replaced)
		_state.state_restored.disconnect(_on_session_replaced)
