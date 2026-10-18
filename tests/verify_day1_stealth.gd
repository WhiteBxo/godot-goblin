extends SceneTree
## Component fixtures are isolated from the real host: fixture_torch is NOT a Day 1 item.

var _failures: Array[String] = []
var _checks := 0
var _state: Node
var _world: Node2D
var _player: PlayerController
var _inventory: WarehouseInventory
var _setup: Day1StealthSetup
var _service: Day1StealthService
var _actors := {}
var _external_lock := false
var _results: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames(count: int = 3) -> void:
	for index in range(count):
		await physics_frame
	await process_frame

func _until(predicate: Callable, description: String) -> void:
	var deadline := Time.get_ticks_msec() + 2500
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await _frames(1)
	_check(predicate.call(), description)

func _shape(parent: CollisionObject2D, size: Vector2) -> void:
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	parent.add_child(shape)

func _fixture() -> void:
	_world = Node2D.new()
	root.add_child(_world)
	_player = load("res://src/gameplay/player/shop_player.tscn").instantiate()
	_player.animation_speed = 4.0
	_world.add_child(_player)
	# Only this test constructs an extra catalog. Production receives GameState's inventory.
	var menu := WarehouseInventory.CATALOG.duplicate(true) as TeaMenu
	var torch := IngredientDefinition.new()
	torch.id = "fixture_torch"
	torch.display_name = "测试火把（非正式资源）"
	menu.ingredients.append(torch)
	_inventory = WarehouseInventory.new(menu)
	_world.add_child(_inventory)
	_inventory.add_ingredient("strange_coin", 12)
	_inventory.add_ingredient("fixture_torch", 12)
	_setup = Day1StealthSetup.new()
	_world.add_child(_setup)
	_setup.torch_item_id = "fixture_torch"
	_setup.escape_rules_reference = "test fixture only; does not settle P08"
	_setup.checkpoint = Marker2D.new()
	_world.add_child(_setup.checkpoint)
	_setup.checkpoint.position = Vector2(-220, 0)
	_setup.escape_zone = Area2D.new()
	_setup.escape_zone.collision_layer = 0
	_shape(_setup.escape_zone, Vector2(80, 80))
	_world.add_child(_setup.escape_zone)
	_setup.escape_zone.position = Vector2(-350, 0)
	for role: int in Day1GuardResponse.Role.values():
		var actor: SettlementCharacter = load("res://src/gameplay/characters/guard.tscn").instantiate()
		actor.actor_id = StringName("fixture_guard_%d" % role)
		actor.initial_facing = PlayerController.Facing.RIGHT
		actor.position = Vector2([0, 2000, 2080, 4000][role], 0)
		_world.add_child(actor)
		_actors[actor.actor_id] = actor
		var guard := Day1GuardResponse.new()
		guard.role = role
		guard.actor = actor
		guard.sight_range = 160.0
		guard.discovery_seconds = 0.2
		guard.distraction_seconds = 0.35
		guard.hearing_range = 300.0
		if role in [Day1GuardResponse.Role.MANSION_GATE, Day1GuardResponse.Role.DRUNKEN]:
			guard.clearance_flag = StringName("fixture.guard_%d.cleared" % role)
		if role == Day1GuardResponse.Role.DRUNKEN:
			guard.encounter_event_id = "fixture.drunken_guard"
		_world.add_child(guard)
		_setup.guards.append(guard)
	var target := Day1FlammableTarget.new()
	target.target_id = &"fixture_target"
	target.design_reference = "test fixture only; NOT confirmed scenery"
	target.confusion_seconds = 0.4
	target.confusion_radius = 180.0
	_shape(target, Vector2(40, 40))
	_world.add_child(target)
	target.position = Vector2(0, 100)
	_setup.flammable_targets.append(target)
	_service = Day1StealthService.new()
	_world.add_child(_service)
	_service.configure(_state, _inventory, _player, _world, _setup,
		func(id: StringName) -> PlayerController: return _actors.get(id),
		func() -> bool: return not _external_lock)
	_service.throw_resolved.connect(func(kind: StringName, affected: bool) -> void:
		_results.append({"kind": kind, "affected": affected}))

func _throw_at(kind: StringName, target: Vector2) -> void:
	var before := _results.size()
	_check(_service.select_throwable(kind) == OK, "Select " + String(kind))
	_check(_service.request_throw(target) == OK, "Start an animated throw")
	await _until(func() -> bool: return _results.size() > before, "Physical projectile resolves")
	await _until(func() -> bool: return _player.get_active_action().is_empty(), "Throw animation finishes")

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	_state = root.get_node("GameState")
	if "--host-only" in OS.get_cmdline_user_args():
		_state.start_new_game()
		_state.select_business_profile("day1")
		await _check_real_host()
		print("DAY1_STEALTH_HOST: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
		quit(0 if _failures.is_empty() else 1)
		return
	_state.start_new_game()
	_state.select_business_profile("day1")
	_state.set_story_stage("day1.s05.fixture")
	_state.set_flag("day1.s04.commission_accepted")
	DayPhase.enter_night(_state)
	_fixture()
	await _frames()
	_check(_service.status == Day1StealthService.Status.RUNNING, "Complete fixture activates through the real service")
	var original_actor := _setup.guards[2].actor
	_setup.guards[2].actor = _setup.guards[1].actor
	_check(not _service.get_configuration_issues().is_empty(), "One actor cannot stand in for the mansion's two guards")
	_setup.guards[2].actor = original_actor
	original_actor.actor_id = &"guard_captain"
	_check(not _service.get_configuration_issues().is_empty(), "Guard captain cannot become a mansion guard")
	original_actor.actor_id = &"fixture_guard_2"
	_check(_service.request_throw(Vector2(INF, 0)) == ERR_UNAVAILABLE and _service.request_throw(Vector2(5000, 0)) == ERR_UNAVAILABLE, "Invalid or out-of-range targets cannot start a throw")
	var entry := _setup.guards[0]
	var target := _setup.flammable_targets[0]
	var coins := _inventory.get_stock("strange_coin")
	_service.request_throw(Vector2(0, 80))
	_player.set_movement_enabled(false)
	await _frames(15)
	_check(_inventory.get_stock("strange_coin") == coins and _results.is_empty(), "Cancellation before animation release spends nothing")
	_player.set_movement_enabled(true)
	_inventory.changed.connect(func() -> void:
		_player.action_triggered.emit(&"throw", Vector2.RIGHT)
		_check(_service.retry_attempt() == ERR_BUSY, "Synchronous reentry cannot retry a release")
	, CONNECT_ONE_SHOT)
	await _throw_at(&"coin", Vector2(0, 80))
	_check(_inventory.get_stock("strange_coin") == coins - 1, "One real coin consumed once, including synchronous reentry")
	_check(_results[-1].affected and entry.state == Day1GuardResponse.State.DISTRACTED, "Coin impact actually distracts the entrance guard")
	_external_lock = true
	var remaining := entry.remaining
	await _frames(15)
	_check(is_equal_approx(entry.remaining, remaining), "Host modal/performance lock freezes gameplay timers")
	_external_lock = false
	await _until(func() -> bool: return entry.state == Day1GuardResponse.State.WATCHING, "Configured distraction expires")
	_check(not _setup.guards[2].distract(_setup.guards[2].actor.global_position), "A coin cannot distract the mansion's second guard")
	_check(_setup.guards[1].distract(_setup.guards[1].actor.global_position), "The mansion's other guard responds independently")
	_player.teleport_to(Vector2(80, 0))
	await _frames(4)
	_check(entry.state == Day1GuardResponse.State.ALERT, "Entering the sight cone raises alert before discovery")
	_player.teleport_to(Vector2(-80, 0))
	await _frames(10)
	_check(entry.state == Day1GuardResponse.State.WATCHING, "Leaving sight lets alert decay")
	var wall := StaticBody2D.new()
	_shape(wall, Vector2(12, 200))
	_world.add_child(wall)
	wall.position = Vector2(40, 0)
	_player.teleport_to(Vector2(80, 0))
	await _frames(18)
	_check(entry.state == Day1GuardResponse.State.WATCHING, "World collision occludes guard sight")
	wall.queue_free()
	await _until(func() -> bool: return _service.status == Day1StealthService.Status.FAILED, "Unoccluded discovery fails the attempt")
	coins = _inventory.get_stock("strange_coin")
	_external_lock = true
	_check(_service.retry_attempt() == ERR_BUSY, "Retry cannot bypass another control owner")
	_external_lock = false
	_check(_service.retry_attempt() == OK, "Failed attempt retries")
	_check(_player.global_position == _setup.checkpoint.global_position and entry.exposure == 0 and entry.remaining == 0, "Retry restores checkpoint, alert, facing and timers")
	_check(_inventory.get_stock("strange_coin") == coins, "Retry neither charges nor refunds coins")
	var torches := _inventory.get_stock("fixture_torch")
	_check(_service.select_throwable(&"torch") == OK and _service.request_throw(target.global_position) == OK, "Start a throw that will be interrupted in flight")
	await _until(func() -> bool: return _inventory.get_stock("fixture_torch") == torches - 1, "Animation releases and consumes the torch")
	_player.teleport_to(Vector2(2160, 0))
	await _until(func() -> bool: return _service.status == Day1StealthService.Status.FAILED, "Discovery interrupts an in-flight throw")
	_check(_world.get_children().filter(func(node: Node) -> bool: return node is Day1ThrowProjectile).is_empty(), "Failure removes the in-flight projectile before it can ignite scenery")
	_check(_service.retry_attempt() == OK and _inventory.get_stock("fixture_torch") == torches - 1 and target.remaining == 0, "Retry clears flight state without charging or refunding the released torch")
	var obstruction := StaticBody2D.new()
	_shape(obstruction, Vector2(12, 300))
	_world.add_child(obstruction)
	obstruction.position = Vector2(-100, 40)
	await _frames()
	await _throw_at(&"torch", target.global_position)
	_check(not _results[-1].affected and target.remaining == 0, "A wall stops the swept projectile before a legal target")
	obstruction.queue_free()
	await _frames()
	await _throw_at(&"torch", Vector2(0, -100))
	_check(not _results[-1].affected and target.remaining == 0.0, "A missed torch creates no confusion")
	target.design_reference = ""
	await _throw_at(&"torch", target.global_position)
	_check(not _results[-1].affected and target.remaining == 0.0, "A physically hit but unconfirmed target rejects fire")
	target.design_reference = "test fixture only"
	await _throw_at(&"torch", target.global_position)
	_check(_results[-1].affected and target.remaining > 0 and entry.state == Day1GuardResponse.State.CONFUSED, "Only a legal collision creates temporary confusion")
	_player.teleport_to(Vector2(2160, 0))
	await _until(func() -> bool: return _service.status == Day1StealthService.Status.FAILED, "Independent mansion guard can still discover the player")
	_check(_service.retry_attempt() == OK and target.remaining == 0 and entry.state == Day1GuardResponse.State.WATCHING, "Retry clears fire and every guard's local response")
	_player.teleport_to(Vector2(4080, 0))
	await _until(func() -> bool: return _service.status == Day1StealthService.Status.INTERCEPTED, "The distinct drunken guard intercepts instead of generic failure")
	_check(not _state.get_flag("day1.s05.guard_payment_completed"), "Interception does not pretend payment succeeded")
	_check(_service.retry_attempt() == OK, "Unresolved drunken event can retry without payment")
	# Fixture facts represent outputs of external businesses. No production price or order is invented.
	_player.teleport_to(_setup.escape_zone.global_position)
	await _frames()
	_check(not _state.get_flag("day1.s05.escape_completed"), "Reaching escape without the actual objective cannot succeed")
	_state.set_flag("day1.s05.blood_acquired")
	_inventory.add_ingredient("day1_griffin_blood", 1)
	await _frames()
	_check(not _state.get_flag("day1.s05.escape_completed"), "Blood alone cannot skip the dual guards and mandatory event")
	for guard: Day1GuardResponse in [_setup.guards[2], _setup.guards[3]]:
		_state.set_flag(String(guard.clearance_flag))
	_state.complete_event("fixture.drunken_guard")
	await _frames()
	_check(not _state.get_flag("day1.s05.escape_completed"), "Clearance flags and dialogue completion cannot substitute for payment")
	_state.set_flag("day1.s05.guard_payment_completed")
	_setup.confusion_required = true
	await _frames()
	_check(not _state.get_flag("day1.s05.escape_completed"), "Configured confusion requirement cannot use a previous attempt's fire")
	_player.teleport_to(_setup.checkpoint.global_position)
	target.confusion_seconds = 0.7
	await _throw_at(&"torch", target.global_position)
	await _until(func() -> bool: return target.remaining == 0, "Confusion and fire expire without a permanent fire state")
	_player.teleport_to(_setup.escape_zone.global_position)
	await _frames()
	_check(not _state.get_flag("day1.s05.escape_completed"), "Expired confusion cannot authorize a timed escape window")
	_player.teleport_to(_setup.checkpoint.global_position)
	await _throw_at(&"torch", target.global_position)
	_player.teleport_to(_setup.escape_zone.global_position)
	await _until(func() -> bool: return _service.status == Day1StealthService.Status.ESCAPED, "Actual objective, payment, event, confusion and escape volume complete the attempt")
	_check(_state.get_flag("day1.s05.escape_completed") and _inventory.get_stock("day1_griffin_blood") == 1, "Escape writes only its fact and keeps the acquired item")
	var stock := _inventory.to_dict()
	_check(_service.retry_attempt() == ERR_BUSY and _inventory.to_dict() == stock, "Successful escape cannot be retried for rewards")
	_state.set_flag("day1.s05.escape_completed", false)
	_service.cancel_attempt()
	await _frames()
	_check(_service.status == Day1StealthService.Status.IDLE, "Explicit cancellation stays cancelled")
	_check(_service.begin_attempt() == OK, "Explicit restart is available")
	_inventory.try_consume({"strange_coin": _inventory.get_stock("strange_coin")})
	_state.get_transactions().add_money(100, "fixture.normal_wallet")
	var balance: int = _state.get_transactions().get_balance()
	var resolutions := _results.size()
	_service.request_throw(Vector2(0, 80))
	await _frames(20)
	_check(_results.size() == resolutions and _state.get_transactions().get_balance() == balance, "Insufficient coins do not fall back to ordinary wallet money or spawn a projectile")
	_service.request_throw(Vector2(0, 80))
	var snapshot: Dictionary = _state.to_dict()
	_state.set_flag("fixture.snapshot_changed")
	_check(_state.restore_state(snapshot) == OK, "Session snapshot restores")
	await _frames()
	_check(_player.get_active_action().is_empty() and target.remaining == 0 and _world.get_children().filter(func(node: Node) -> bool: return node is Day1ThrowProjectile).is_empty(), "Restore clears pending release, projectiles and fire")
	target.queue_free()
	await _frames()
	_check(_service.status == Day1StealthService.Status.PENDING, "A disappearing binding cancels the attempt instead of leaving active local state")
	_setup.guards[0].queue_free()
	await _frames()
	_service.cancel_attempt()
	_check(not _service.get_configuration_issues().is_empty(), "Freed guard and target references remain safe during cancellation and validation")
	_world.queue_free()
	await _frames()
	await _check_real_host()
	print("DAY1_STEALTH: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	quit(0 if _failures.is_empty() else 1)

func _check_real_host() -> void:
	_state.start_new_game()
	_state.set_flag("day1.s04.commission_accepted")
	_state.set_story_stage("day1.s05")
	DayPhase.enter_night(_state)
	var host: MainGame = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(host)
	current_scene = host
	await _frames()
	var service := host.get_stealth_service()
	_check(service.get_inventory() == _state.get_warehouse_inventory(), "Formal host injects the sole shared inventory")
	_check(service.status == Day1StealthService.Status.PENDING and service.begin_attempt() == ERR_UNCONFIGURED, "Formal host rejects missing torch, roles and unconfirmed escape design")
	_check(host.get_actor_director().get_actor(&"guard") != null and host.get_actor_director().get_actor(&"drunken_guard") == null, "Formal guard actor and drunken marker are not conflated")
	var before: Dictionary = _state.to_dict()
	var event := InputEventAction.new()
	event.action = &"player_throw"
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(30)
	_check(_state.to_dict() == before and not _state.get_flag("day1.s05.escape_completed"), "Real InputMap throw in a pending host cannot consume or fake progress")
	event.pressed = false
	Input.parse_input_event(event)
	host.get_ui_manager().set_paused(true)
	_check(not (host.get_player() as PlayerController).movement_enabled, "Real host still coordinates pause lock")
	host.get_ui_manager().set_paused(false)
	_check((host.get_player() as PlayerController).movement_enabled, "Closing pause restores the host's previous movement permission")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		var hud := host.get_node("HudLayer/Day1StealthHUD") as Control
		_check(hud.get_global_rect().encloses(hud.get_node("Panel").get_global_rect()), "Stealth HUD fits the formal host viewport")
		_check(root.get_texture().get_image().save_png("/tmp/day1_stealth_pending.png") == OK, "Graphical formal-host capture saved")
	current_scene = null
	host.queue_free()
	await _frames()
