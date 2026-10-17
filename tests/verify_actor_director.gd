extends SceneTree

const ACTOR_SCENE = preload("res://src/debug/actors/demo_actor.tscn")

var _checks := 0
var _failures: Array[String] = []
var _watched: Array[ActorAction] = []
var _notifications: Dictionary = {}
var _host: Node2D
var _entities: Node2D
var _director: ActorDirector
var _actor: PlayerController

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)

func _frames(count: int = 2) -> void:
	for index in range(count):
		await physics_frame
	await process_frame

func _watch(action: ActorAction) -> ActorAction:
	_watched.append(action)
	_notifications[action] = 0
	action.finished.connect(func(result: ActorAction) -> void: _notifications[result] += 1)
	return action

func _wait(action: ActorAction) -> void:
	var ticks := 0
	while not action.completed and ticks < 1200:
		await _frames(1)
		ticks += 1
	_check(action.completed, "Action must settle within test deadline: %s/%s" % [action.actor_id, action.command])
	if not action.completed:
		_director.cancel_action(action, "Test deadline")
	await _frames()

func _new_host() -> void:
	_host = Node2D.new()
	root.add_child(_host)
	_entities = Node2D.new()
	_host.add_child(_entities)
	_director = ActorDirector.new()
	_director.blocked_timeout = 0.15
	_host.add_child(_director)
	_director.configure(_entities)
	_actor = ACTOR_SCENE.instantiate()
	_entities.add_child(_actor)
	_check(_director.actor_register(&"player", _actor) == OK, "Register existing actor by stable ID")

func _dispose() -> void:
	_host.queue_free()
	await _frames()

func _run() -> void:
	var detached := ActorDirector.new()
	var rejected := _watch(detached.actor_move(&"missing", Vector2.ZERO))
	_check(rejected.completed and rejected.error == ERR_UNCONFIGURED, "Detached director returns explicit failure")
	_check(await rejected.wait() == rejected, "Waiting on an already finished failure never hangs")
	detached.free()
	_new_host()
	await _test_registry_and_spawn()
	await _test_control_and_motion()
	await _test_failures_and_collision()
	await _test_emote_pause_cancel()
	await _test_callbacks()
	await _dispose()
	await _test_lifecycle()
	await _test_main_locks()
	await _test_demo()
	await _frames()
	for action in _watched:
		_check(action.completed and _notifications[action] == 1, "Exactly one finished signal, including rejection/cancel/exit: %s/%s" % [action.actor_id, action.command])
	print("ACTOR_DIRECTOR: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_registry_and_spawn() -> void:
	_check(_director.actor_register(&"player", _actor) == ERR_ALREADY_EXISTS, "Duplicate stable ID rejected")
	_check(_director.actor_register(&"alias", _actor) == ERR_ALREADY_EXISTS, "Body cannot be registered twice")
	_check(_director.actor_register(&"", _actor) == ERR_INVALID_PARAMETER, "Empty actor ID rejected")
	_check(_director.actor_register(&"null", null) == ERR_INVALID_PARAMETER, "Missing body rejected")
	var marker := Marker2D.new()
	_host.add_child(marker)
	marker.position = Vector2(120, 65)
	_check(_director.register_position(&"door", marker) == OK, "Named Marker2D registration")
	_check(_director.register_position(&"door", marker) == ERR_ALREADY_EXISTS, "Duplicate position ID rejected")
	_entities.position = Vector2(35, 20)
	var spawn := _watch(_director.actor_spawn(&"customer_01", ACTOR_SCENE, &"door"))
	await _wait(spawn)
	var customer := _director.get_actor(&"customer_01")
	_check(spawn.succeeded and customer != null and customer.global_position.distance_to(marker.global_position) < 0.01, "Spawn uses global coordinates under transformed EntityRoot")
	_check(customer.get_parent() == _entities and not customer.accepts_player_input, "Spawn belongs to EntityRoot; NPC uses shared controller without input")
	var saved := customer.position
	Input.action_press("move_right")
	await _frames(10)
	Input.action_release("move_right")
	_check(customer.position == saved, "Idle NPC never reads player InputMap")
	for direction in [&"up", &"left", &"right", &"down"]:
		var face := _watch(_director.actor_face(&"customer_01", direction))
		await _wait(face)
		_check(face.succeeded and customer.animated_sprite.animation == StringName("idle_" + direction), "Face reuses existing animation: %s" % direction)
	await _wait(_watch(_director.actor_hide(&"customer_01")))
	_check(not customer.visible, "actor_hide hides body and child visuals")
	await _wait(_watch(_director.actor_show(&"customer_01")))
	_check(customer.visible, "actor_show restores visibility")
	await _wait(_watch(_director.actor_spawn(&"customer_01", ACTOR_SCENE, marker)))
	_check(_director.get_actor(&"customer_01") == customer, "Rejected duplicate spawn preserves existing actor")
	_director.unregister_position(&"door")
	await _wait(_watch(_director.actor_move(&"customer_01", &"door")))
	_check(_director.last_error.contains("target"), "Missing named location has explicit diagnostic")
	marker.queue_free()
	_entities.position = Vector2.ZERO
	_actor.position = Vector2.ZERO

func _test_control_and_motion() -> void:
	_actor.accepts_player_input = true
	_actor.set_movement_enabled(false)
	var original_speed := _actor.speed
	var move := _watch(_director.actor_move(&"player", Vector2(120, 0), 120.0))
	var busy := _watch(_director.actor_face(&"player", &"up"))
	_check(busy.error == ERR_BUSY and not move.completed, "Conflicting action fails without interrupting active move")
	var other := ActorDirector.new()
	_host.add_child(other)
	other.actor_register(&"same_body", _actor)
	var contested := _watch(other.actor_move(&"same_body", Vector2(-100, 0)))
	_check(contested.error == ERR_BUSY, "Controller prevents two directors claiming the same body")
	Input.action_press("move_left")
	await _frames(5)
	_check(_actor.position.x > 0 and is_equal_approx(_actor.velocity.x, 120), "Directed speed and direction override held player input and dialogue lock")
	_check(_actor.animated_sprite.animation == &"run_right", "Directed movement reuses run animation")
	await _wait(move)
	Input.action_release("move_left")
	_check(move.succeeded and _actor.position.distance_to(Vector2(120, 0)) <= 0.5, "Move completes at destination")
	_check(not _actor.movement_enabled and not _actor.is_performance_controlled(), "Move preserves pre-existing movement lock")
	_check(_actor.velocity.is_zero_approx() and _actor.animated_sprite.animation == &"idle_right", "Arrival stops velocity and selects facing idle")
	_check(_actor.speed == original_speed, "Directed speed never modifies ordinary movement tuning")
	_actor.set_movement_enabled(true)
	var interrupted := _watch(_director.actor_move(&"player", Vector2(1000, 0)))
	await _frames(3)
	_director.cancel_action(interrupted, "Interrupted by caller")
	var stopped := _actor.position
	await _frames(8)
	_check(interrupted.error == ERR_SKIP and interrupted.reason == "Interrupted by caller" and _actor.position == stopped, "Cancel immediately stops pending motion")
	var replacement := _watch(_director.actor_move(&"player", stopped + Vector2(0, 20), 60))
	_director.cancel_action(interrupted)
	_check(not replacement.completed, "Old action handle cannot cancel a newer request")
	await _wait(replacement)
	Input.action_press("move_right")
	await _frames(12)
	Input.action_release("move_right")
	_check(_actor.position.x > stopped.x, "Ordinary player input resumes after release")
	await _frames(10)
	_actor.accepts_player_input = false
	var parallel := _watch(_director.actor_move(&"player", _actor.global_position + Vector2(0, 20)))
	var second := _watch(_director.actor_emote(&"customer_01", "?", 0.1))
	await _wait(parallel)
	await _wait(second)
	_check(parallel.succeeded and second.succeeded, "Independent actors can perform in parallel")
	other.queue_free()

func _test_failures_and_collision() -> void:
	for action: ActorAction in [
		_director.actor_move(&"unknown", Vector2.ZERO),
		_director.actor_move(&"player", &"missing_marker"),
		_director.actor_move(&"player", NodePath("World/Counter")),
		_director.actor_move(&"player", Vector2(INF, 0)),
		_director.actor_move(&"player", Vector2.ZERO, 0),
		_director.actor_move(&"player", Vector2.ZERO, NAN),
		_director.actor_move(&"player", Vector2.ZERO, 10, INF),
		_director.actor_face(&"player", &"diagonal"),
		_director.actor_emote(&"player", "", 1),
		_director.actor_emote(&"player", "!", -1),
		_director.actor_spawn(&"null_scene", null, Vector2.ZERO),
		_director.actor_spawn(&"empty_scene", PackedScene.new(), Vector2.ZERO),
	]:
		_watch(action)
		_check(action.completed and not action.succeeded and not action.reason.is_empty(), "Invalid request returns a descriptive failure")
	var wrong_scene := PackedScene.new()
	var wrong_root := Node2D.new()
	wrong_scene.pack(wrong_root)
	wrong_root.free()
	var invalid_spawn := _watch(_director.actor_spawn(&"bad_scene", wrong_scene, Vector2.ZERO))
	await _wait(invalid_spawn)
	_check(invalid_spawn.error == ERR_INVALID_DATA and _director.get_actor(&"bad_scene") == null, "Spawn rejects incompatible controller and frees instance")
	var marker := Marker2D.new()
	_host.add_child(marker)
	marker.position = Vector2(800, 0)
	var removed_target := _watch(_director.actor_move(&"player", marker))
	await _frames(3)
	marker.queue_free()
	await _wait(removed_target)
	_check(not removed_target.succeeded and removed_target.reason.contains("exited"), "Removing a live target fails instead of waiting")
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10, 200)
	shape.shape = rectangle
	wall.add_child(shape)
	wall.position = Vector2(50, 0)
	_host.add_child(wall)
	_actor.position = Vector2.ZERO
	await _frames()
	var blocked := _watch(_director.actor_move(&"player", Vector2(100, 0), 2000.0, 2))
	await _wait(blocked)
	_check(blocked.error == ERR_TIMEOUT and _actor.position.x < 40 and _actor.position.x > 30, "Physics movement cannot tunnel through wall at high speed; stall returns failure")
	_check(not _actor.is_performance_controlled() and _actor.velocity.is_zero_approx(), "Blocked failure releases claim and stops motion")
	wall.queue_free()
	await _frames()
	var timed_out := _watch(_director.actor_move(&"player", Vector2(9000, 0), 1, 0.05))
	await _wait(timed_out)
	_check(timed_out.error == ERR_TIMEOUT, "Long route has a hard timeout even while making progress")
	var cave: CavePlayer = load("res://src/gameplay/player/player.tscn").instantiate()
	_entities.add_child(cave)
	cave.accepts_player_input = false
	cave.configure(func(point: Vector2, half_size: Vector2) -> bool: return point.x + half_size.x <= 40)
	_director.actor_register(&"cave", cave)
	var cave_move := _watch(_director.actor_move(&"cave", Vector2(100, 0), 2000))
	await _wait(cave_move)
	_check(cave_move.error == ERR_TIMEOUT and cave.position.x <= 33, "Directed cave movement retains subclass footprint/walkability checks")
	cave.queue_free()

func _test_emote_pause_cancel() -> void:
	var emote := _watch(_director.actor_emote(&"player", "!", 0.8))
	await _frames(3)
	var label := _actor.get_node_or_null("ActorEmote") as Label
	_check(label != null and label.text == "!" and label.position.y < -10, "Emote attaches above actor with temporary text")
	paused = true
	var label_position := label.position
	await create_timer(0.15, true).timeout
	_check(not emote.completed and label.position == label_position, "Pause freezes emote Tween and completion")
	paused = false
	_director.cancel_action(emote)
	await _frames(55)
	_check(emote.error == ERR_SKIP and _actor.get_node_or_null("ActorEmote") == null, "Cancel kills emote Tween, removes label and never succeeds later")
	var move := _watch(_director.actor_move(&"player", _actor.position + Vector2(50, 0), 60, 0.3))
	await _frames(3)
	paused = true
	var position_before := _actor.position
	await create_timer(0.4, true).timeout
	_check(not move.completed and _actor.position == position_before, "Pause freezes movement and its hard timeout")
	paused = false
	_director.cancel_all()
	await _frames()
	var successful := _watch(_director.actor_emote(&"player", "?", 0.1))
	_check(await successful.wait() == successful and successful.succeeded, "Action-specific await resumes on emote completion")
	await _frames()
	_check(_actor.get_node_or_null("ActorEmote") == null, "Successful emote frees its temporary visual")
	var removed_visual := _watch(_director.actor_emote(&"player", "!", 2))
	await _frames()
	_actor.get_node("ActorEmote").queue_free()
	await _wait(removed_visual)
	_check(removed_visual.error == ERR_DOES_NOT_EXIST and not _actor.is_performance_controlled(), "Unexpected visual removal settles emote and releases claim")

func _test_callbacks() -> void:
	var cancel_on_claim := func(_id: StringName, controlled: bool) -> void:
		if controlled:
			_director.cancel_all("Synchronous listener cancellation")
	_director.actor_control_changed.connect(cancel_on_claim)
	var cancelled := _watch(_director.actor_move(&"player", Vector2.ZERO))
	_director.actor_control_changed.disconnect(cancel_on_claim)
	await _frames()
	_check(cancelled.error == ERR_SKIP and not _actor.is_performance_controlled(), "Claim listener may cancel synchronously without starting stale movement")
	var next: Array[ActorAction] = []
	var first := _watch(_director.actor_face(&"player", &"left"))
	first.finished.connect(func(_result: ActorAction) -> void: next.append(_watch(_director.actor_face(&"player", &"right"))))
	await _wait(first)
	_check(next.size() == 1, "Finish callback can safely request the next action")
	await _wait(next[0])
	_check(next[0].succeeded and _actor.facing == PlayerController.Facing.RIGHT, "Stale completion cannot finish or cancel callback's new action")

func _test_lifecycle() -> void:
	for removed in ["actor", "director", "scene", "unregister", "pending"]:
		_new_host()
		var move := _watch(_director.actor_move(&"player", Vector2(500, 0)))
		if removed != "pending":
			await _frames(3)
		match removed:
			"actor": _actor.queue_free()
			"director", "pending": _director.queue_free()
			"scene": _host.queue_free()
			"unregister": _director.actor_unregister(&"player")
		await _frames(5)
		_check(move.completed and not move.succeeded, "Removing %s settles unfinished action" % removed)
		if is_instance_valid(_actor):
			_check(not _actor.is_performance_controlled() and _actor.velocity.is_zero_approx(), "Removing %s releases controller" % removed)
		if is_instance_valid(_host):
			await _dispose()
	_new_host()
	var spawn := _watch(_director.actor_spawn(&"owned", ACTOR_SCENE, Vector2(100, 0)))
	await _wait(spawn)
	var owned := _director.get_actor(&"owned")
	var effect := _watch(_director.actor_emote(&"player", "!", 2))
	await _frames()
	_director.queue_free()
	await _frames(6)
	_check(effect.completed and not effect.succeeded and _actor.get_node_or_null("ActorEmote") == null, "Director exit cleans emote and settles its handle")
	_check(not is_instance_valid(owned) and is_instance_valid(_actor), "Director frees owned spawns while preserving registered actors")
	await _dispose()

func _test_main_locks() -> void:
	var game: MainGame = load("res://src/debug/story/legacy_shop.tscn").instantiate()
	root.add_child(game)
	await _frames()
	var director := game.get_actor_director()
	var player := game.get_player() as PlayerController
	var interaction := game.get_node("Systems/ShopInteraction") as ShopInteraction
	var story := game.get_story_director()
	story.load_events("res://tests/fixtures/story_events.json")
	_check(director.get_parent() == game.get_node("Systems") and director.get_actor(&"player") == player, "MainGame exposes scene-local ActorDirector and registered player")
	var target := player.global_position + Vector2(-20, 0)
	var move := _watch(director.actor_move(&"player", target, 60))
	_check(not player.movement_enabled and not interaction.is_input_enabled(), "Player takeover locks existing movement and interaction input")
	story.request_event("test.wait")
	director.cancel_action(move)
	_check(not player.movement_enabled and not interaction.is_input_enabled(), "Releasing actor claim does not unlock active story")
	story.cancel_event("Test")
	_check(player.movement_enabled and interaction.is_input_enabled(), "Final lock release restores prior input state")
	story.request_event("test.wait")
	var during_story := _watch(director.actor_move(&"player", target, 60))
	story.cancel_event("Test reverse lock order")
	_check(not player.movement_enabled and not interaction.is_input_enabled(), "Story release cannot unlock active actor claim")
	await _wait(during_story)
	_check(during_story.succeeded and player.movement_enabled and interaction.is_input_enabled(), "Movement works under host lock, then restores both controls")
	player.set_movement_enabled(false)
	interaction.set_input_enabled(false)
	await _wait(_watch(director.actor_face(&"player", &"up")))
	_check(not player.movement_enabled and not interaction.is_input_enabled(), "Takeover preserves pre-existing disabled inputs")
	player.set_movement_enabled(true)
	interaction.set_input_enabled(true)
	var exit_move := _watch(director.actor_move(&"player", target + Vector2(300, 0)))
	director.queue_free()
	await _frames(5)
	_check(exit_move.completed and player.movement_enabled and interaction.is_input_enabled(), "Director removal releases MainGame host lock")
	game.queue_free()
	await _frames()

func _test_demo() -> void:
	var demo: Node = load("res://src/debug/actors/actor_demo.tscn").instantiate()
	root.add_child(demo)
	var commands: Array[StringName] = []
	demo.director.action_finished.connect(func(action: ActorAction) -> void: commands.append(action.command))
	var ticks := 0
	var captured := false
	while not demo.completed and ticks < 800:
		await _frames(1)
		ticks += 1
		if not captured and "--capture" in OS.get_cmdline_user_args():
			var live_customer: PlayerController = demo.director.get_actor(&"customer_01")
			if live_customer != null and live_customer.get_node_or_null("ActorEmote") != null:
				await RenderingServer.frame_post_draw
				var path := OS.get_environment("TEMP").path_join("godot-goblin-actor-demo.png")
				_check(root.get_texture().get_image().save_png(path) == OK, "Demo screenshot saved")
				print("ACTOR_DEMO_CAPTURE: ", path)
				captured = true
	_check(demo.completed, "Standalone demo completes all five beats")
	_check(commands == [&"face", &"spawn", &"move", &"face", &"emote", &"face", &"move", &"hide"], "Demo waits for each actor action in exact order")
	var customer: PlayerController = demo.director.get_actor(&"customer_01")
	_check(customer != null and not customer.visible and customer.position.distance_to(Vector2(120, 295)) <= 0.5, "Demo customer returns to door and disappears")
	_check(demo.director.get_actor(&"player").facing == PlayerController.Facing.LEFT, "Demo player turns to customer")
	demo.play()
	await _frames(10)
	demo.cancel()
	await _frames(10)
	_check(not demo.running and not demo.completed and not demo.director.get_actor(&"customer_01").is_performance_controlled(), "Demo can replay and cancel without retaining control")
	demo.queue_free()
	await _frames()
	var exiting_demo: Node = load("res://src/debug/actors/actor_demo.tscn").instantiate()
	root.add_child(exiting_demo)
	await _frames(10)
	exiting_demo.queue_free()
	await _frames(10)
