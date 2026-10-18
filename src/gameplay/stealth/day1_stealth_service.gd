class_name Day1StealthService
extends Node
## Day 1 gameplay only. Story and the host consume results and own player control.

signal changed
signal attempt_failed(guard_id: StringName)
signal guard_intercepted(event_id: String)
signal escaped
signal throw_resolved(kind: StringName, affected: bool)

enum Status { IDLE, PENDING, RUNNING, FAILED, INTERCEPTED, ESCAPED }

var status: Status = Status.IDLE
var selected_kind: StringName = &"coin"
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

func is_blocking() -> bool:
	return status in [Status.FAILED, Status.INTERCEPTED]

func is_mission_stage() -> bool:
	return is_instance_valid(_state) and _state.get_business_profile() == "day1" and Day1Access.can_enter_elder(_state)

func can_accept_input() -> bool:
	return status == Status.RUNNING and _external_control_available() and _player.movement_enabled and not _player.is_performance_controlled()

func select_throwable(kind: StringName) -> Error:
	if kind not in [&"coin", &"torch"]:
		return ERR_INVALID_PARAMETER
	if not can_accept_input() or not _pending_throw.is_empty() or _releasing:
		return ERR_BUSY
	selected_kind = kind
	changed.emit()
	return OK

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
	_clear_local()
	_player.teleport_to(_setup.checkpoint.global_position)
	_set_status(Status.RUNNING, "鼠标指向落点，使用投掷操作")
	return OK

func retry_attempt() -> Error:
	if not is_blocking() or _releasing or not _external_control_available():
		return ERR_BUSY
	if not is_mission_stage() or not get_configuration_issues().is_empty():
		return ERR_UNCONFIGURED
	_clear_local()
	_player.teleport_to(_setup.checkpoint.global_position)
	_set_status(Status.RUNNING, "已返回检查点；已使用的物品不会补回")
	return OK

func cancel_attempt() -> void:
	_clear_local()
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
	# Discovery wins over escape when both happen in the same tick.
	for guard: Day1GuardResponse in _setup.guards:
		guard.set_cleared(_guard_cleared(guard))
		if guard.advance(delta, _player, space):
			_clear_flights()
			_player.cancel_action()
			if guard.role == Day1GuardResponse.Role.DRUNKEN:
				_set_status(Status.INTERCEPTED, "醉酒守卫拦住了你；完成交涉后继续，或返回检查点")
				guard_intercepted.emit(guard.encounter_event_id)
			else:
				_set_status(Status.FAILED, "被守卫发现；可从检查点重试")
				attempt_failed.emit(guard.actor.actor_id)
			return
	_try_escape()

func _bindings_available() -> bool:
	if not is_instance_valid(_setup):
		return false
	for binding: Variant in _setup.guards + _setup.flammable_targets:
		if not is_instance_valid(binding) or not binding.is_inside_tree():
			return false
	for guard: Day1GuardResponse in _setup.guards:
		if not is_instance_valid(guard.actor) or not guard.actor.is_inside_tree():
			return false
	return true

func _guard_cleared(guard: Day1GuardResponse) -> bool:
	# A configured clearance fact cannot substitute for a successful payment.
	return (guard.clearance_flag != &"" and _state.get_flag(String(guard.clearance_flag))
		and _state.get_flag("day1.s05.guard_payment_completed"))

func _on_action_started(action: StringName, _direction: Vector2) -> void:
	if action != &"throw" or not can_accept_input() or _releasing:
		return
	var target: Vector2 = _target_override if _target_override is Vector2 else _effects.get_global_mouse_position()
	if not _valid_target(target):
		message = "落点超出投掷范围"
		changed.emit()
		return
	_pending_throw = {"kind": selected_kind, "target": target}

func _on_action_triggered(action: StringName, _direction: Vector2) -> void:
	if action != &"throw" or _pending_throw.is_empty() or not can_accept_input() or _releasing:
		return
	var pending := _pending_throw
	_pending_throw = {}
	var item: String = _setup.coin_item_id if pending.kind == &"coin" else _setup.torch_item_id
	var generation := _generation
	_releasing = true
	# The animation has one release; consume once under our reentry guard. Retry never consumes.
	var consumed := _inventory.try_consume({item: 1})
	_releasing = false
	if not consumed:
		message = "没有可用的投掷物品"
		changed.emit()
		return
	if generation != _generation or not can_accept_input():
		return
	var projectile := Day1ThrowProjectile.new()
	projectile.kind = pending.kind
	projectile.destination = pending.target
	_effects.add_child(projectile)
	projectile.global_position = _player.global_position
	_projectiles.append(projectile)
	message = "已投出%s" % ("金币" if pending.kind == &"coin" else "火把")
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
	else:
		var target := result.collider as Day1FlammableTarget
		if is_instance_valid(target) and target in _setup.flammable_targets and target.ignite():
			affected = true
			_confusion_created = true
			for guard: Day1GuardResponse in _setup.guards:
				guard.confuse(target.global_position, target.confusion_radius, target.confusion_seconds)
	message = ("守卫转移了注意力" if affected else "声响没有引开守卫") if result.kind == &"coin" else ("火把点燃了目标，附近守卫陷入混乱" if affected else "火把没有点燃目标")
	throw_resolved.emit(result.kind, affected)
	changed.emit()

func _try_escape() -> void:
	if not _setup.contains_escape_position(_player.global_position):
		return
	for flag: StringName in _setup.required_flags:
		if not _state.get_flag(String(flag)):
			return
	var active_confusion := false
	for target: Day1FlammableTarget in _setup.flammable_targets:
		active_confusion = active_confusion or target.remaining > 0.0
	if not _inventory.has_materials(_setup.required_items) or (_setup.confusion_required and (not _confusion_created or not active_confusion)):
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

func _clear_local(restore_actors: bool = true) -> void:
	_generation += 1
	_clear_flights()
	_confusion_created = false
	selected_kind = &"coin"
	if is_instance_valid(_player):
		_player.cancel_action()
	if is_instance_valid(_setup):
		for guard: Variant in _setup.guards:
			if is_instance_valid(guard):
				guard.reset_response(restore_actors)
		for target: Variant in _setup.flammable_targets:
			if is_instance_valid(target):
				target.reset_target()

func _set_status(next: Status, text: String) -> void:
	status = next
	message = text
	changed.emit()

func _on_session_replaced() -> void:
	cancel_attempt()
	_auto_start = true
	_refresh_pending()

func _exit_tree() -> void:
	_clear_local(false)
	if is_instance_valid(_player):
		_player.action_started.disconnect(_on_action_started)
		_player.action_triggered.disconnect(_on_action_triggered)
		_player.action_finished.disconnect(_on_action_finished)
	if is_instance_valid(_state):
		_state.state_reset.disconnect(_on_session_replaced)
		_state.state_restored.disconnect(_on_session_replaced)
