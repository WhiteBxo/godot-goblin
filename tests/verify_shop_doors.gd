extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames(count: int) -> void:
	for index in range(count):
		await physics_frame
	await process_frame
	await process_frame

func _run() -> void:
	var main: MainGame = load("res://src/core/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(4)
	var level := main.get_active_level() as MilkTeaShop
	var player := main.get_player() as ShopPlayer
	var doors := level.get_node("Doors").get_children()
	_check(doors.size() == 2, "Only counter and entrance retain automatic doors")
	for door: AutomaticDoor in doors:
		var axis := Vector2.DOWN if door.vertical else Vector2.RIGHT
		var normal := Vector2.RIGHT if door.vertical else Vector2.DOWN
		var midpoint := door.position + axis * door.door_width * (0.75 if door.vertical else 0.5)
		# The exterior mat is shallow; the entrance is approached from inside first.
		var distance := 25.0 if door.name == "EntranceDoor" else 85.0
		player.global_position = level.get_spawn_position()
		player.velocity = Vector2.ZERO
		await _frames(65)
		_check(not door.is_open and not door.get_node("Body/CollisionShape2D").disabled, str(door.name) + " closes and restores collision")
		var closed_start := level.to_global(midpoint + normal * 22)
		_check(player.test_move(Transform2D(0, closed_start), -normal * 55), str(door.name) + " blocks when closed")
		for direction in [-1.0, 1.0]:
			player.global_position = level.to_global(midpoint + normal * distance * direction)
			player.velocity = Vector2.ZERO
			await _frames(3)
			var action := ("move_right" if direction < 0 else "move_left") if door.vertical else ("move_down" if direction < 0 else "move_up")
			Input.action_press(action)
			await _frames(ceili((distance + 25) * 1.25 / player.speed * 60) + 7)
			Input.action_release(action)
			await _frames(6)
			var side := (level.to_local(player.global_position) - midpoint).dot(normal)
			_check(side * direction < -12, str(door.name) + " can be crossed from side " + str(direction) + " position=" + str(level.to_local(player.global_position)))
			_check(door.is_open and door.get_node("Body/CollisionShape2D").disabled, str(door.name) + " opens without E")
		player.global_position = level.to_global(midpoint)
		player.velocity = Vector2.ZERO
		await _frames(90)
		_check(door.is_open, str(door.name) + " stays open while occupied")
		player.global_position = level.get_spawn_position()
		await _frames(65)
		_check(not door.is_open, str(door.name) + " closes after leaving")
		# Re-enter during closing: animation must reverse and collision must reopen.
		player.global_position = level.to_global(midpoint)
		await _frames(20)
		player.global_position = level.get_spawn_position()
		await _frames(44)
		player.global_position = level.to_global(midpoint)
		await _frames(25)
		_check(door.is_open and door._openness > 0.99 and door.get_node("Body/CollisionShape2D").disabled, str(door.name) + " reverses closing safely")
		player.global_position = level.get_spawn_position()
		await _frames(65)
	if "--capture" in OS.get_cmdline_user_args():
		player.configure_camera(level.get_camera_bounds())
		await _frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/milk_tea_verification/new_shop.png")
	print("SHOP_DOORS: ", "PASS" if _failures.is_empty() else "FAIL", " (2 shop doors, both directions, collision, occupancy, delayed close, re-entry)")
	quit(0 if _failures.is_empty() else 1)
