extends SceneTree

var _checks := 0
var _failures: Array[String] = []
const GAME := preload("res://src/core/main.tscn")

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames(count: int) -> void:
	for index in range(count):
		await physics_frame
	await process_frame
	await process_frame

func _initial_spawn(room_name: String, spawn: Vector2) -> void:
	var game: MainGame = GAME.instantiate()
	game.get_node("World/LevelRoot/MilkTeaShop/Spawn").position = spawn
	root.add_child(game)
	var room: RoomReveal = game.get_active_level().get_node("Rooms/" + room_name)
	_check(room.get_occlusion_alpha() == 0, room_name + " has no opaque startup flash")
	await _frames(5)
	_check(room.is_occupied() and room.get_occlusion_alpha() == 0, room_name + " resolves a player spawned indoors")
	game.queue_free()
	await _frames(3)

func _walk(player: ShopPlayer, level: MilkTeaShop, action: String, target: Vector2, axis: Vector2) -> void:
	var game_id := current_scene.get_instance_id()
	var camera := player.camera
	var zoom := camera.zoom
	var center := camera.get_screen_center_position()
	Input.action_press(action)
	for frame in range(150):
		await _frames(1)
		_check(camera.get_screen_center_position().distance_to(center) < 9, "Room crossing keeps the camera continuous")
		center = camera.get_screen_center_position()
		if (level.to_local(player.global_position) - target).dot(axis) >= 0:
			break
	Input.action_release(action)
	await _frames(6)
	_check((level.to_local(player.global_position) - target).dot(axis) >= -1, "Open doorway allows actual movement: " + action)
	_check(player.movement_enabled and player.camera == camera and camera.is_current() and camera.zoom == zoom, "Reveal preserves player control and current camera")
	_check(current_scene.get_instance_id() == game_id, "Crossing never changes the game scene")

func _room_behavior(game: MainGame, room_name: String, outside: Vector2, inside: Vector2, enter_action: String, exit_action: String, axis: Vector2) -> void:
	var level := game.get_active_level() as MilkTeaShop
	var player := game.get_player() as ShopPlayer
	var room: RoomReveal = level.get_node("Rooms/" + room_name)
	player.global_position = level.to_global(outside)
	player.velocity = Vector2.ZERO
	await _frames(30)
	_check(not room.is_occupied() and is_equal_approx(room.get_occlusion_alpha(), 1), room_name + " is covered when outside")
	await _walk(player, level, enter_action, inside, axis)
	await create_timer(0.3).timeout
	_check(room.is_occupied() and is_zero_approx(room.get_occlusion_alpha()), room_name + " reveals after walking in")
	_check(level.get_node("Background").modulate.a == 1, "Background remains fully opaque")
	await _walk(player, level, exit_action, outside, -axis)
	await create_timer(0.3).timeout
	_check(not room.is_occupied() and is_equal_approx(room.get_occlusion_alpha(), 1), room_name + " restores after walking out")
	# Teleports here are test setup for sub-frame boundary cases, not gameplay.
	player.global_position = level.to_global(inside)
	await _frames(3)
	await create_timer(0.09).timeout
	var midway := room.get_occlusion_alpha()
	_check(midway > 0 and midway < 1, room_name + " interpolates instead of instantly toggling")
	player.global_position = level.to_global(outside)
	await _frames(3)
	_check(absf(room.get_occlusion_alpha() - midway) < 0.6, room_name + " reversal continues from its current alpha")
	await create_timer(0.3).timeout
	_check(is_equal_approx(room.get_occlusion_alpha(), 1), room_name + " interrupted fade finishes in the correct state")
	var transition_started := [0]
	var record_start := func(occupied: bool) -> void:
		if occupied:
			transition_started[0] = Time.get_ticks_msec()
	room.occupancy_changed.connect(record_start)
	player.global_position = level.to_global(inside)
	await _frames(3)
	var deadline := Time.get_ticks_msec() + 600
	while room.get_occlusion_alpha() > 0.001 and Time.get_ticks_msec() < deadline:
		await process_frame
	var duration := Time.get_ticks_msec() - int(transition_started[0])
	_check(transition_started[0] > 0 and duration >= 200 and duration <= 290, room_name + " fade completes in 0.25 seconds with frame tolerance: " + str(duration))
	room.occupancy_changed.disconnect(record_start)
	player.global_position = level.to_global(outside)
	await _frames(3)
	await create_timer(0.3).timeout
	for index in range(6):
		player.global_position = level.to_global(inside if index % 2 == 0 else outside)
		await _frames(3)
	await create_timer(0.3).timeout
	_check(not room.is_occupied() and is_equal_approx(room.get_occlusion_alpha(), 1), room_name + " rapid crossings leave no stale tween")
	# Another physics body on the same layer does not reveal the roof.
	var stranger := CharacterBody2D.new()
	stranger.collision_layer = 2
	stranger.collision_mask = 0
	var collider := CollisionShape2D.new()
	collider.shape = CircleShape2D.new()
	stranger.add_child(collider)
	stranger.position = level.to_global(inside)
	root.add_child(stranger)
	await _frames(5)
	_check(not room.is_occupied(), room_name + " ignores non-player bodies")
	stranger.add_to_group("player")
	# Force a real enter signal after changing the body's role.
	stranger.position = level.to_global(outside)
	await _frames(3)
	stranger.position = level.to_global(inside)
	await _frames(4)
	player.global_position = level.to_global(inside)
	await _frames(4)
	player.global_position = level.to_global(outside)
	await create_timer(0.3).timeout
	_check(room.is_occupied() and is_zero_approx(room.get_occlusion_alpha()), room_name + " stays revealed until all players leave")
	stranger.queue_free()
	await _frames(4)
	await create_timer(0.3).timeout
	_check(not room.is_occupied() and is_equal_approx(room.get_occlusion_alpha(), 1), room_name + " restores when the last observer is freed")

func _run() -> void:
	var bedroom_only := "--bedroom-only" in OS.get_cmdline_user_args()
	await _initial_spawn("Bedroom", Vector2(362, 385))
	if not bedroom_only:
		await _initial_spawn("Bathroom", Vector2(272, 634))
	var game: MainGame = GAME.instantiate()
	root.add_child(game)
	current_scene = game
	await _frames(6)
	var level := game.get_active_level() as MilkTeaShop
	var player := game.get_player() as ShopPlayer
	_check(not level.has_node("Doors/BedroomDoor"), "Bedroom has no door animation or blocking door body")
	_check(player.test_move(Transform2D(0, level.to_global(Vector2(250, 385))), Vector2(0, 90) * level.scale), "Bedroom south wall blocks passage beside the opening")
	_check(player.test_move(Transform2D(0, level.to_global(Vector2(370, 360))), Vector2(100, 0) * level.scale), "Middle cream wall remains solid")
	if not bedroom_only:
		_check(not level.has_node("Doors/BathroomDoor"), "Bathroom has no animated or blocking door")
		_check(player.test_move(Transform2D(0, level.to_global(Vector2(272, 590))), Vector2(100, 0) * level.scale), "Bathroom cream side wall blocks passage")
		_check(player.test_move(Transform2D(0, level.to_global(Vector2(272, 475))), Vector2(0, -100) * level.scale), "Bathroom north wall blocks passage")
		_check(not player.test_move(Transform2D(0, level.to_global(Vector2(272, 634))), Vector2(98, 0) * level.scale), "Bathroom lower doorway stays open")
		_check(player.test_move(Transform2D(0, level.to_global(Vector2(530, 400))), Vector2(150, 0) * level.scale), "Service divider blocks passage through the painted wall")
		_check(not player.test_move(Transform2D(0, level.to_global(Vector2(690, 536))), Vector2(-160, 0) * level.scale), "Hall connects to the shop through the visible gap")
	await _room_behavior(game, "Bedroom", Vector2(362, 510), Vector2(362, 385), "move_up", "move_down", Vector2.UP)
	if not bedroom_only:
		await _room_behavior(game, "Bathroom", Vector2(370, 634), Vector2(272, 634), "move_left", "move_right", Vector2.LEFT)
		game.get_player().global_position = level.to_global(Vector2(362, 385))
		await create_timer(0.35).timeout
		_check(level.get_node("Rooms/Bedroom").get_occlusion_alpha() == 0 and level.get_node("Rooms/Bathroom").get_occlusion_alpha() == 1, "Each room fades independently")
	# Destroy the scene during an active fade: no orphan tween may survive.
	game.get_player().global_position = game.get_active_level().get_spawn_position()
	await _frames(3)
	game.queue_free()
	await _frames(4)
	print("ROOM_REVEAL: %s (%d checks, bedroom_only=%s)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, bedroom_only])
	quit(0 if _failures.is_empty() else 1)
