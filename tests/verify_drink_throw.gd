extends SceneTree
## Uses an isolated debug fixture, real bodies and real animation release.

var _checks := 0
var _failures: Array[String] = []
var _demo: Node2D
var _inventory: WarehouseInventory
var _service: Day1StealthService
var _guard: Day1GuardResponse
var _player: PlayerController
var _setup: Day1StealthSetup
var _world: PhysicsDirectSpaceState2D
var _results: Array[StringName] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames(count: int = 3) -> void:
	for i in range(count):
		await physics_frame
	await process_frame

func _until(predicate: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await _frames(1)
	_check(predicate.call(), message)

func _parameters(extras: Array, iced := false) -> Dictionary:
	return _inventory.calculate_formula(["goblin_firebrew"] + extras, true, iced).throw

func _area(extras: Array, at := Vector2(680, 400)) -> DrinkEffectArea:
	var area := DrinkEffectArea.new()
	area.configure(_parameters(extras))
	_demo.add_child(area)
	area.global_position = at
	return area

func _reset() -> void:
	for guard: Day1GuardResponse in _setup.guards:
		guard.reset_response()
	for target: Day1FlammableTarget in _setup.flammable_targets:
		target.reset_target()
	for target: Day1DestructibleTarget in _setup.destructible_targets:
		target.reset_target()
	_player.teleport_to(Vector2(480, 400))

func _run() -> void:
	_demo = load("res://src/debug/stealth/drink_throw_demo.tscn").instantiate()
	root.add_child(_demo)
	current_scene = _demo
	_inventory = _demo.inventory
	_service = _demo.service
	_setup = _demo.setup
	_guard = _setup.guards[0]
	_player = _demo.player
	_player.animation_speed = 4.0
	_player.accepts_player_input = false
	_service.set_physics_process(false)
	_service.throw_resolved.connect(func(kind: StringName, _affected: bool) -> void: _results.append(kind))
	_check(_service.begin_attempt() == OK, "Complete isolated fixture starts through service")
	await _frames()
	_world = _demo.get_world_2d().direct_space_state
	_check(_service.get_configuration_issues().is_empty(), "Confirmed optional destructible binding validates")
	var wood := _setup.destructible_targets[0]
	wood.design_reference = ""
	_check(not _service.get_configuration_issues().is_empty(), "Unconfirmed wooden scenery cannot become a meltable target")
	wood.design_reference = "debug fixture wooden crate"
	if "--capture-only" not in OS.get_cmdline_user_args():
		_test_inventory()
		_test_states()
		await _test_areas()
		await _test_service()
	if "--capture" in OS.get_cmdline_user_args():
		await _capture()
	current_scene = null
	_demo.queue_free()
	await _frames()
	print("DRINK_THROW: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	quit(0 if _failures.is_empty() else 1)

func _test_inventory() -> void:
	var id: String = _demo.sample_ids[0]
	var before := _inventory.get_drink_stock(id)
	var record := _inventory.get_drink_record(id)
	_check(not _inventory.try_consume_drink(4) and not _inventory.try_consume_drink("unknown") and not _inventory.try_consume_drink(id, 0), "Invalid finished cup requests fail atomically")
	_inventory.set_session_locked(true)
	_check(not _inventory.try_consume_drink(id) and _inventory.get_drink_stock(id) == before, "Session replacement lock also blocks cup throws")
	_inventory.set_session_locked(false)
	_check(not _inventory.try_consume_drink(id, before + 1), "Insufficient cups do not partially spend")
	var notifications: Array[int] = []
	var observe := func() -> void: notifications.append(_inventory.get_drink_stock(id))
	_inventory.changed.connect(observe, CONNECT_ONE_SHOT)
	_check(_inventory.try_consume_drink(id) and notifications == [before - 1], "One cup commits before its single notification")
	_check(_inventory.get_drink_record(id).ingredients == record.ingredients, "Throwing preserves encyclopedia discovery")
	_check(_parameters(["mint_syrup"], true) == _parameters(["mint_syrup"]), "Iced name option grants no mine or extra combat buff")

func _test_states() -> void:
	_reset()
	var area := _area(["mint_syrup", "mint_syrup"])
	var facing := _guard.actor.facing
	area.advance(0.0, _setup, _world)
	_check(_guard.state == Day1GuardResponse.State.STUNNED and is_equal_approx(_guard.remaining, 6.0), "Two paralysis portions double stun duration")
	_check(_guard.effective_sight_range() == 0.0, "Stun makes effective sight zero")
	_check(not _guard.distract(Vector2(600, 400)), "Coin cannot override stun")
	_guard.confuse(Vector2(600, 400), 1000, 20)
	_check(_guard.state == Day1GuardResponse.State.STUNNED and _guard.actor.facing == facing, "Confusion cannot turn a stunned guard")
	_player.teleport_to(_guard.actor.global_position + Vector2(50, 0))
	_check(not _guard.advance(5.9, _player, _world) and _guard.exposure == 0.0 and _guard.actor.facing == facing, "Stunned guard cannot discover or alarm at point blank range")
	_guard.advance(0.11, _player, _world)
	_check(_guard.state == Day1GuardResponse.State.WATCHING and _guard.effective_sight_range() == _guard.sight_range, "Stun expires without changing configured sight")
	area.free()
	_reset()
	area = _area(["strawberry_jam", "strawberry_jam"])
	area.advance(0.0, _setup, _world)
	_player.teleport_to(_guard.actor.global_position + Vector2(50, 0))
	_check(is_equal_approx(_guard.detection_multiplier, 6.0), "Two corrosion portions double the configured detection multiplier")
	for i in range(6):
		area.advance(0.25, _setup, _world)
		_guard.advance(0.25, _player, _world)
	_check(is_equal_approx(_guard.exposure, 0.25), "Corroded guard accumulates real sight exposure more slowly")
	_guard.advance(4.0, _player, _world)
	_check(_guard.detection_multiplier == 1.0, "Corrosion expires")
	area.free()
	_reset()
	area = _area(["rainbow_cube"])
	area.advance(0.0, _setup, _world)
	_check(_guard.state == Day1GuardResponse.State.CONFUSED, "Hallucination reuses existing confusion")
	var drunk := _setup.guards[3]
	drunk.confuse(drunk.actor.global_position, 100, 3)
	_check(drunk.state == Day1GuardResponse.State.WATCHING, "Existing drunken confusion immunity remains")
	_check(drunk.stun(3), "Paralysis supports a distinct drunken guard without granting clearance")
	_check(not get_node_state().get_flag("day1.s05.guard_payment_completed"), "Drink effects do not invent mission payment facts")
	area.free()
	_reset()

func get_node_state() -> Node:
	return root.get_node("GameState")

func _test_areas() -> void:
	var area := _area(["firefly_cap", "phantom_gold_mushroom"])
	area.advance(0.99, _setup, _world)
	_check(area.pulse_count == 0 and _guard.state == Day1GuardResponse.State.WATCHING, "Silent lure waits for its one-second pulse")
	area.advance(0.02, _setup, _world)
	_check(area.pulse_count == 1 and _guard.state == Day1GuardResponse.State.DISTRACTED, "Lure emits a real coin distraction each second")
	area.advance(1.99, _setup, _world)
	_check(area.pulse_count == 3 and area.finished, "Lure handles final tick and expires at duration")
	area.free()
	_reset()
	area = _area(["firefly_cap", "firefly_cap"])
	area.advance(1.0, _setup, _world)
	_check(area.pulse_count == 1 and is_equal_approx(_guard.remaining, _guard.distraction_seconds * 2), "Lure strength stacks without doubling pulse frequency")
	area.free()
	_reset()
	area = _area(["firefly_cap", "cocoa_powder"])
	_guard.actor.teleport_to(Vector2(680, 520))
	area.advance(1.0, _setup, _world)
	_check(area.pulse_count == 1 and _guard.state == Day1GuardResponse.State.DISTRACTED, "Expansion also widens the lure pulse area")
	area.free()
	_reset()
	area = _area(["scorch_tongue_pepper"], _setup.flammable_targets[0].global_position)
	_guard.actor.teleport_to(area.global_position)
	area.advance(0.0, _setup, _world)
	_check(_setup.flammable_targets[0].remaining > 0.0 and area.confusion_created and _guard.state == Day1GuardResponse.State.CONFUSED, "Burn ignites confirmed scenery and confuses nearby guards")
	area.free()
	_reset()
	area = _area(["cocoa_powder", "cocoa_powder"])
	_check(area.contains_point(Vector2(967, 400)) and not area.contains_point(Vector2(969, 400)), "Two expansion portions create a bounded 9 by 9 square")
	area.advance(0.0, _setup, _world)
	var pushed := _guard.actor.global_position
	_check(pushed.x > 680 and pushed.x < 820, "Stacked knockback stops at real wooden crate collision")
	area.advance(0.1, _setup, _world)
	_check(_guard.actor.global_position == pushed, "Knockback is applied once per guard per cup")
	area.free()
	_reset()
	area = _area(["honey_amber_crystal"], Vector2(660, 400))
	area.advance(0.0, _setup, _world)
	_check(_guard.actor.global_position.distance_to(Vector2(660, 400)) < 1.0, "Vortex pulls a guard toward impact")
	area.free()
	_reset()
	area = _area(["red_mottled_wood"])
	for i in range(20):
		area.advance(0.05, _setup, _world)
	_check(not area.contains_point(_guard.actor.global_position) and _guard.actor.global_position.x > 712, "Day 1 gas drives guard outside its region")
	area.free()
	_reset()
	area = _area(["brown_sugar_boba", "brown_sugar_boba"])
	_check(is_equal_approx(area.remaining, 23.0), "Sticky stacks duration additions")
	area.free()
	area = _area(["rainbow_cube", "apple_jam"])
	area.advance(0.0, _setup, _world)
	_check(area.attached_guard == _guard and area.remaining == 8.0, "Attachment binds an affected real guard and extends duration")
	_guard.actor.teleport_to(Vector2(600, 500))
	area.advance(0.1, _setup, _world)
	_check(area.global_position == _guard.actor.global_position and area.contains_point(Vector2(690, 500)), "Attached three-cell region follows moving guard")
	area.free()
	_reset()
	# Mine remains reachable for historical cups, never from the new ice checkbox.
	var mine := _parameters(["mint_syrup"])
	mine.modifiers["mine"] = {"arm_trigger_cells": 1.0, "arm_timeout": 3.0, "stacks": 1}
	area = DrinkEffectArea.new()
	area.configure(mine)
	_demo.add_child(area)
	area.global_position = Vector2(600, 400)
	area.advance(1.0, _setup, _world)
	_check(area.armed and area.remaining == 3.0 and _guard.state == Day1GuardResponse.State.WATCHING, "Mine waits without spending its active duration")
	_guard.actor.teleport_to(Vector2(600, 400))
	area.advance(0.1, _setup, _world)
	_check(not area.armed and _guard.state == Day1GuardResponse.State.STUNNED, "Guard entering trigger area activates a mine")
	area.free()
	_reset()
	area = DrinkEffectArea.new()
	area.configure(mine)
	_demo.add_child(area)
	area.global_position = Vector2(500, 600)
	area.advance(3.0, _setup, _world)
	_check(not area.armed and area.remaining == 3.0, "Mine timeout preserves its full active lifetime")
	area.free()
	# Real ray queries against a wall, and collision-safe pull across that wall.
	_reset()
	_guard.actor.teleport_to(Vector2(960, 440))
	area = _area(["mint_syrup", "cocoa_powder"], Vector2(880, 440))
	area.advance(0.1, _setup, _world)
	_check(_guard.state == Day1GuardResponse.State.WATCHING and _guard.actor.global_position.x == 960, "Wall blocks normal area effects and displacement")
	area.free()
	area = _area(["mint_syrup", "phantom_gold_mushroom"], Vector2(905, 440))
	_guard.actor.teleport_to(Vector2(935, 440))
	area.advance(0.1, _setup, _world)
	_check(_guard.state == Day1GuardResponse.State.STUNNED, "Phantom area reaches guard through a wall")
	area.free()
	_reset()
	var wood := _setup.destructible_targets[0]
	area = _area(["strawberry_jam", "strawberry_jam"], wood.global_position - Vector2(23, 0))
	area.advance(0.5, _setup, _world)
	_check(is_equal_approx(wood.damage, 1.0) and not wood.destroyed, "Corrosion applies stacked damage per second to explicit wood")
	area.advance(0.5, _setup, _world)
	_check(wood.destroyed and wood.blocker.collision_layer == 0 and not wood.visual.visible, "Melted crate removes real blocking and its bound visual")
	area.free()
	wood.reset_target()
	_check(not wood.destroyed and wood.damage == 0.0 and wood.blocker.collision_layer == 1 and wood.visual.visible, "Retry restores wooden crate durability, visual and collision")
	await _frames()
	_reset()

func _test_service() -> void:
	_service.set_physics_process(true)
	var id: String = _demo.sample_ids[0]
	var stock := _inventory.get_drink_stock(id)
	_check(_service.select_drink(id) == OK, "Held finished cup can be selected")
	_check(_service.select_drink("missing") == ERR_DOES_NOT_EXIST, "Unknown cup cannot be selected")
	_check(_service.request_throw(Vector2(680, 400)) == OK, "Cup follows player's real throw animation")
	_check(_service.select_drink(_demo.sample_ids[1]) == ERR_BUSY, "Selection cannot replace a cup after animation starts")
	_player.set_movement_enabled(false)
	await _frames(15)
	_check(_inventory.get_drink_stock(id) == stock and _service.get_active_areas().is_empty(), "Cancellation before release spends no cup and spawns no field")
	_player.set_movement_enabled(true)
	var reenter := func() -> void:
		_player.action_triggered.emit(&"throw", Vector2.RIGHT)
		_check(_service.retry_attempt() == ERR_BUSY, "Synchronous cup notification cannot reenter release")
	_inventory.changed.connect(reenter, CONNECT_ONE_SHOT)
	_service.request_throw(Vector2(680, 400))
	await _until(func() -> bool: return not _results.is_empty(), "Animated cup physically lands")
	_check(_inventory.get_drink_stock(id) == stock - 1 and _results == [&"drink"], "Exactly one finished cup consumed and resolved")
	_check(_guard.state == Day1GuardResponse.State.STUNNED and _service.get_active_areas().size() == 1, "Service connects generated payload to real stun field")
	_demo.external_lock = true
	var area := _service.get_active_areas()[0]
	var remaining := area.remaining
	var guard_remaining := _guard.remaining
	await _frames(15)
	_check(area.remaining == remaining and _guard.remaining == guard_remaining, "Host lock freezes field and guard timers together")
	_demo.external_lock = false
	paused = true
	await process_frame
	_check(area.remaining == remaining, "Tree pause freezes gameplay field")
	paused = false
	await _until(func() -> bool: return _player.get_active_action().is_empty(), "Cup animation finishes")
	var snapshot := _inventory.to_dict()
	_service.cancel_attempt()
	await _frames()
	_check(_service.get_active_areas().is_empty() and _guard.state == Day1GuardResponse.State.WATCHING and _guard.detection_multiplier == 1.0, "Cancel clears all cup areas and guard statuses")
	_check(_inventory.to_dict() == snapshot, "Cancelling never refunds cup or erases discovery")
	_check(_service.begin_attempt() == OK, "Restart isolated attempt")
	# Standard flight must stop at the crate; phantom must reach the chosen far point.
	await _throw(_demo.sample_ids[0], Vector2(880, 400))
	_check(_service.get_active_areas()[-1].global_position.x < 820, "Solid crate stops ordinary cup flight")
	_service.cancel_attempt()
	_service.begin_attempt()
	await _throw(_demo.sample_ids[7], Vector2(935, 400))
	area = _service.get_active_areas()[-1]
	_check(area.global_position.is_equal_approx(Vector2(935, 400)), "Phantom projectile crosses crate and wall to exact destination")
	_check(_guard.state == Day1GuardResponse.State.WATCHING, "Silent cup impact creates no ordinary sound distraction")
	_service.cancel_attempt()
	_service.begin_attempt()
	await _throw(_demo.sample_ids[3], Vector2(797, 400))
	var wood := _setup.destructible_targets[0]
	await _until(func() -> bool: return wood.destroyed, "Real thrown corrosion melts wooden collision")
	var after_corrosion := _inventory.get_drink_stock(_demo.sample_ids[3])
	_player.teleport_to(Vector2(1230, 350))
	await _until(func() -> bool: return _service.status == Day1StealthService.Status.FAILED, "An independent watching guard still discovers player during cup effects")
	_check(_service.get_active_areas().is_empty() and not wood.destroyed and _guard.remaining == 0.0, "Discovery clears fields, guard effects and melted scenery")
	_check(_service.retry_attempt() == OK and _inventory.get_drink_stock(_demo.sample_ids[3]) == after_corrosion, "Retry restores actor checkpoints without refunding a thrown cup")
	# Empty stock can be sold/spent during windup; release must recheck it.
	_service.cancel_attempt()
	_service.begin_attempt()
	_service.select_drink(id)
	_service.request_throw(Vector2(680, 400))
	_inventory.try_consume_drink(id, _inventory.get_drink_stock(id))
	var resolutions := _results.size()
	await _frames(25)
	_check(_results.size() == resolutions and _service.get_active_areas().is_empty(), "Cup spent by another business before release cannot be thrown")
	var cancel_id: String = _demo.sample_ids[1]
	var cancel_stock := _inventory.get_drink_stock(cancel_id)
	_inventory.changed.connect(func() -> void: _service.cancel_attempt(), CONNECT_ONE_SHOT)
	_service.select_drink(cancel_id)
	_service.request_throw(Vector2(680, 400))
	await _frames(25)
	_check(_inventory.get_drink_stock(cancel_id) == cancel_stock - 1 and _results.size() == resolutions and _service.get_active_areas().is_empty(), "Session cancellation inside release notification cannot spawn a stale cup")
	_service.begin_attempt()
	# Restore from shared GameState cancels transient state even in the isolated host.
	await _throw(_demo.sample_ids[2], Vector2(680, 400))
	var state := get_node_state()
	var saved: Dictionary = state.to_dict()
	state.set_flag("fixture.changed")
	_check(state.restore_state(saved) == OK, "Full session restore succeeds with active cup effects")
	await _frames()
	_check(_service.get_active_areas().is_empty() and _guard.state == Day1GuardResponse.State.WATCHING, "Restore removes attached fields and guard effects")
	_check(not _setup.destructible_targets[0].destroyed, "Restore recovers local destructibles")
	# The actual HUD exposes owned cups and submits the public select API.
	var choices: OptionButton = _demo.hud.get_node("Panel/Content/Drinks")
	_check(choices.item_count == _inventory.get_drinks().size() + 1, "HUD lists only currently held cup variants")
	if _service.status == Day1StealthService.Status.IDLE:
		_service.begin_attempt()
	choices.item_selected.emit(1)
	_check(_service.selected_kind == &"drink" and _service.selected_drink_id == choices.get_item_metadata(1), "HUD cup choice selects the actual finished inventory item")
	_demo.external_lock = true
	await _frames()
	_check(choices.disabled, "HUD respects host gameplay lock")
	_demo.external_lock = false
	# A melt observer may reset the attempt synchronously inside area.advance.
	_service.cancel_attempt()
	_service.begin_attempt()
	wood.melted.connect(func() -> void: _service.cancel_attempt(), CONNECT_ONE_SHOT)
	await _throw(_demo.sample_ids[3], Vector2(797, 400))
	await _until(func() -> bool: return _service.status == Day1StealthService.Status.IDLE, "Melt callback can synchronously cancel an attempt")
	_check(_service.get_active_areas().is_empty() and not wood.destroyed and _guard.remaining == 0.0, "Cancellation during effect execution cannot leave later effects or destroyed state")

func _throw(id: String, at: Vector2) -> void:
	await _until(func() -> bool: return _player.get_active_action().is_empty(), "Previous action finished")
	var count := _results.size()
	_check(_service.select_drink(id) == OK and _service.request_throw(at) == OK, "Select and throw finished cup")
	await _until(func() -> bool: return _results.size() > count, "Finished cup resolves")
	await _until(func() -> bool: return _player.get_active_action().is_empty(), "Thrown cup animation completed")

func _capture() -> void:
	_service.cancel_attempt()
	_service.begin_attempt()
	_service.set_physics_process(true)
	_inventory.try_make_formula(["goblin_firebrew", "mint_syrup", "mint_syrup"], 2)
	await _throw(_demo.sample_ids[0], Vector2(680, 400))
	await _frames(4)
	RenderingServer.force_draw()
	_check(_demo.hud.get_global_rect().encloses(_demo.hud.get_node("Panel").get_global_rect()), "Cup HUD fits the fixture viewport")
	var path := "res://.godot/drink_throw"
	DirAccess.make_dir_recursive_absolute(path)
	_check(root.get_texture().get_image().save_png(path + "/demo.png") == OK, "Graphical throw fixture capture saved")
