extends SceneTree
## Exercise actual door input, scene ownership, physics and session preservation.

const SHOP := "res://src/core/main.tscn"
const STREET := "res://src/core/settlement.tscn"
const RECIPE: Array[String] = ["black_tea", "creamer", "pearl", "syrup"]
var _checks := 0
var _failures: Array[String] = []
var _state: Node
var _capture := false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames() -> void:
	for index in range(4):
		await physics_frame
	await process_frame

## One-time control hints are stored as story flags but they are presentation
## bookkeeping: the first frame a hint is allowed to show writes one, and that
## can land inside a travel. Stock, cups, queue, wallet, tasks and story are
## what these checks are about, so hint flags stay out of the comparison.
func _comparable(data: Dictionary) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	var flags: Dictionary = copy.get("flags", {})
	for key in flags.keys():
		if String(key).begins_with("ui.hint."):
			flags.erase(key)
	copy["flags"] = flags
	return copy

## Snapshot comparison that names the drifted keys instead of only reporting
## that "the session changed" — the whole point of these checks is which part.
func _check_state(expected: Dictionary, message: String) -> void:
	var now: Dictionary = _comparable(_state.to_dict())
	var want: Dictionary = _comparable(expected)
	if now == want:
		_checks += 1
		return
	var parts: Array[String] = []
	for key: String in now:
		if now[key] != want.get(key):
			parts.append("%s expected %s got %s" % [key, str(want.get(key)), str(now[key])])
	_check(false, message + " [" + "; ".join(parts) + "]")

func _key(pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func _wait_for_arrival(path: String) -> MainGame:
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		var game := current_scene as MainGame
		if game != null and game.scene_file_path == path and not game.get_scene_travel().is_busy():
			await _frames()
			return game
		await process_frame
	_check(false, "Arrived and revealed " + path)
	return null

func _check_landing(game: MainGame, entrance_id: StringName) -> void:
	var player := game.get_player() as ShopPlayer
	var entrance: SceneEntrance = game.get_active_level().get_scene_entrance(entrance_id)
	_check(player.global_position.is_equal_approx(entrance.global_position), "Use named entrance foot position")
	_check(player.facing == entrance.facing, "Use entrance facing and idle animation")
	_check(player.animated_sprite.animation == StringName("idle_" + String(PlayerController.DIRECTION_NAMES[entrance.facing])), "Arrival facing is visible on the sprite")
	_check(player.velocity == Vector2.ZERO and player.movement_enabled, "Arrival stops motion and restores controls")
	_check(root.get_camera_2d() == player.camera and player.camera.mode == BoundedFollowCamera.Mode.FOLLOW, "New player owns the follow camera")
	_check(player.camera.global_position.distance_to(player.camera.get_follow_position()) < 0.1, "Camera is already at the destination follow position")
	_check(not game.get_ui_manager().has_modal() and not game.get_shop_ui().is_open(), "Arrival has no leftover modal")
	_check(not game.get_node("TransitionLayer").visible, "Arrival removes retained black")
	var shape := player.get_node("CollisionShape2D") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape.shape
	query.transform = shape.global_transform
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	_check(player.get_world_2d().direct_space_state.intersect_shape(query).is_empty(), "Landing clears walls and furniture with the real foot shape")
	var start := player.global_position
	_check(not player.test_move(player.global_transform, _door(game).global_position - start), "Landing has a clear physical route back to the door")
	var action := &"move_up" if player.facing == PlayerController.Facing.UP else &"move_down"
	Input.action_press(action)
	for index in range(20):
		await physics_frame
	Input.action_release(action)
	var travelled: float = player.global_position.distance_to(start)
	_check(travelled > 15.0, "Player can walk away from the landing (moved %.1f px in 20 physics frames, speed %.0f)" % [travelled, player.get_movement_speed()])
	player.teleport_to(start)

func _door(game: MainGame) -> SceneExit:
	return game.get_active_level().get_scene_exits()[0]

func _cross(game: MainGame, destination: String) -> MainGame:
	var exit := _door(game)
	var old_game: WeakRef = weakref(game)
	game.get_player().teleport_to(exit.global_position)
	await _frames()
	_check(exit.is_available(), "Door detects nearby player")
	_check(game.get_shop_ui().get_prompt_text() == exit.display_name, "Door owns the actual interaction prompt")
	await _key(true)
	_check(game.get_scene_travel().is_busy() and not game.get_player().movement_enabled, "E starts one transition and locks movement")
	_check(game.get_scene_travel().request_exit(exit) == ERR_BUSY, "Duplicate request rejects while travelling")
	var arrived := await _wait_for_arrival(destination)
	_check(old_game.get_ref() == null, "Outgoing MainGame is disposed")
	if arrived != null:
		# Keep E held through arrival: echoes must not immediately return through the door.
		await _key(true, true)
		await _frames()
		_check(current_scene == arrived and not arrived.get_scene_travel().is_busy(), "Holding E never bounces between scenes")
	await _key(false)
	return arrived

func _snapshot(game: MainGame, name: String) -> void:
	if not _capture:
		return
	game.get_player().camera.reset_smoothing()
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("/tmp/goblin_scene_travel_" + name + ".png") == OK, "Capture " + name)

func _run() -> void:
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/scene_travel_%d" % OS.get_process_id())
	_capture = "--capture" in OS.get_cmdline_user_args()
	ProjectSettings.set_setting("debug/developer_tools/enabled", "--with-tools" in OS.get_cmdline_user_args())
	root.size = Vector2i(1280, 720)
	_state = root.get_node("GameState")
	_check(_state.start_new_game() == OK, "Initialize real session")
	_check(change_scene_to_file("res://src/debug/story/legacy_shop.tscn") == OK, "Enter tutorial fixture with shared shop doors")
	await scene_changed
	await _frames()
	var game := current_scene as MainGame
	_check(game.get_player().global_position == game.get_active_level().get_spawn_position(), "Direct F6 entry retains its default spawn")
	var inventory := game.get_warehouse_inventory()
	var production := game.get_tea_production()
	_check(game.get_task_delivery().accept_order("order_001") == OK, "Accept actual order")
	_check(production.make_drink(RECIPE, "order_001").ok, "Carry a real produced cup")
	_check(game.get_transactions().add_money(37, "travel.seed").ok, "Seed wallet through real transaction")
	_state.set_current_day(2)
	_state.set_story_stage("travel.test")
	_state.set_flag("travel.keep")
	_state.set_variable("travel.payload", {"notes": ["kept", 2]})
	_state.complete_event("travel.once")
	var snapshot: Dictionary = _state.to_dict()
	var subscriptions: int = _state.state_changed.get_connections().size()
	var exit := _door(game)
	# Rejections must not touch scene ownership, pause, state or the input lock.
	exit.destination_scene = "res://missing_door_destination.tscn"
	_check(game.get_scene_travel().request_exit(exit) == ERR_FILE_NOT_FOUND, "Missing scene rejected before input lock")
	exit.destination_scene = STREET
	exit.destination_entrance = &"missing_entrance"
	var errors: Array[int] = []
	game.get_scene_travel().travel_failed.connect(func(_point: SceneExit, error: Error) -> void: errors.append(error))
	_check(game.get_scene_travel().request_exit(exit) == OK, "Preflight begins without destroying source")
	await _frames()
	_check(errors == [ERR_DOES_NOT_EXIST] and current_scene == game and not game.get_scene_travel().is_busy(), "Invalid entrance keeps source and releases travel lock")
	_check(game.get_shop_ui().is_open(), "Failed travel offers a visible retry message")
	game.get_shop_ui().close()
	exit.destination_entrance = &"shop_door"
	exit.destination_scene = GameEntry.TITLE_SCENE
	_check(game.get_scene_travel().request_exit(exit) == OK, "Preflight a scene without an arrival interface")
	await _frames()
	_check(errors.back() == ERR_UNCONFIGURED and current_scene == game, "Unsupported destination never replaces the source")
	game.get_shop_ui().close()
	exit.destination_scene = STREET
	game.get_ui_manager().set_paused(true)
	_check(game.get_scene_travel().request_exit(exit) == ERR_BUSY and paused, "Paused travel refuses without unpausing")
	game.get_ui_manager().set_paused(false)
	game.get_shop_ui().open(game.get_active_level().get_interaction_points()[1])
	_check(game.get_scene_travel().request_exit(exit) == ERR_BUSY, "Modal refuses travel")
	game.get_shop_ui().close()
	game.get_player().set_movement_enabled(false)
	_check(game.get_scene_travel().request_exit(exit) == ERR_BUSY, "Existing movement lock refuses travel")
	game.get_player().set_movement_enabled(true)
	_check(game.get_player().claim_performance_control(self), "Actor control can reserve the player")
	_check(game.get_scene_travel().request_exit(exit) == ERR_BUSY, "Performance-controlled player refuses travel")
	game.get_player().release_performance_control(self)
	_check_state(snapshot, "All rejected requests preserve the entire session")
	# Pause during fade cancels safely and leaves pause owned by the source UI.
	_check(game.get_scene_travel().request_exit(exit) == OK, "Begin travel before pause interruption")
	game.get_ui_manager().set_paused(true)
	await create_timer(0.4).timeout
	_check(current_scene == game and paused and not game.get_scene_travel().is_busy(), "Pause during fade retains source and does not release pause")
	game.get_ui_manager().set_paused(false)
	_check(game.get_player().movement_enabled and not game.get_node("TransitionLayer").visible, "Cancelled travel restores movement and visuals after resume")
	# A concurrent entry-navigation reservation must not leave retained black or a stale target.
	GameEntry._changing_scene = true
	_check(game.get_scene_travel().request_exit(exit) == OK, "Queue travel before shared navigation slot check")
	await create_timer(0.4).timeout
	_check(current_scene == game and errors.back() == ERR_BUSY and not game.get_scene_travel().is_busy(), "Busy navigation slot releases target and travel lock")
	GameEntry._changing_scene = false
	game.get_shop_ui().close()
	# Dispose the outgoing host with a detached destination waiting behind its fade.
	game.get_scene_travel().fade_seconds = 1.0
	_check(game.get_scene_travel().request_exit(exit) == OK, "Begin travel before source reload")
	await process_frame
	_check(game.get_scene_travel().is_busy(), "Source still owns pending fade")
	_check(reload_current_scene() == OK, "Reload source during travel")
	await scene_changed
	await _frames()
	game = current_scene as MainGame
	_check(not game.get_scene_travel().is_busy() and game.get_player().movement_enabled, "Source disposal leaves no navigation or input lock")
	_check_state(snapshot, "Interrupted navigation never changes the session")
	for index in range(3):
		game = await _cross(game, STREET)
		if game == null:
			quit(1)
			return
		await _check_landing(game, &"shop_door")
		_check(game.get_warehouse_inventory() == inventory and game.get_tea_production() == production, "Street reuses the same session services")
		_check_state(snapshot, "Leaving preserves stock, cups, queue, wallet, tasks and story")
		if index == 0:
			await _snapshot(game, "street")
		game = await _cross(game, SHOP)
		if game == null:
			quit(1)
			return
		await _check_landing(game, &"street_door")
		_check_state(snapshot, "Returning preserves the entire session")
		_check(_state.state_changed.get_connections().size() == subscriptions, "Round trip does not accumulate state subscriptions")
		if index == 0:
			await _snapshot(game, "shop")
	_check(game.get_task_delivery().deliver_to("fat_goblin").ok, "Carried cup remains deliverable after repeated round trips")
	snapshot = _state.to_dict()
	game = await _cross(game, STREET)
	game = await _cross(game, SHOP)
	_check(not game.get_task_delivery().deliver_to("fat_goblin").ok and _state.to_dict() == snapshot, "Delivery receipt and reward remain once-only after travel")
	_check(reload_current_scene() == OK, "Reload after arrival")
	await scene_changed
	await _frames()
	game = current_scene as MainGame
	_check(game.get_player().global_position == game.get_active_level().get_spawn_position(), "Arrival request is local to one instance and never leaks into reload")
	_check_state(snapshot, "Reload still preserves session")
	_check(GameEntry.return_to_title(self) == OK, "Title navigation remains available after travel and interruptions")
	await scene_changed
	_check(current_scene is TitleMenu and not paused and _state.to_dict() == snapshot, "Returning to title preserves session and releases pause")
	_check(GameEntry.start_new_game(self) == OK, "Explicit new game remains available")
	await scene_changed
	await _frames()
	game = current_scene as MainGame
	_check(game.get_player().global_position == game.get_active_level().get_spawn_position() and not _state.has_flag("travel.keep"), "New game clears old session and uses default spawn without a stale arrival")
	print("SCENE_TRAVEL: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
