extends SceneTree

var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames(count: int = 4) -> void:
	for index in range(count):
		await physics_frame
	await process_frame
	await process_frame

func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	Input.parse_input_event(event)
	await _frames(2)

func _capture(player: ShopPlayer, label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	player.camera.set_directed_zoom(0.8)
	await _frames(3)
	player.camera.reset_smoothing()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/milk_tea_verification/device_" + label + ".png")

func _run() -> void:
	var main: MainGame = load("res://src/debug/story/legacy_shop.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _frames()
	var level := main.get_active_level() as MilkTeaShop
	var player := main.get_player() as ShopPlayer
	var interaction: ShopInteraction = main.get_node("Systems/ShopInteraction")
	var feedback: InteractionFeedback = main.get_node("World/EffectRoot/InteractionFeedback")
	var ui: ShopUI = main.get_node("HudLayer/ShopUI")
	var counter: Node2D = level.get_node("EquipmentForeground/Counter")
	player.global_position = level.to_global(Vector2(1000, 430))
	await _frames()
	_check(counter.z_index > player.z_index, "Display shelf and counter occlude the player's feet from behind")
	await _capture(player, "counter_behind")
	player.global_position = level.to_global(Vector2(1000, 525))
	await _frames()
	_check(counter.z_index < player.z_index, "Player in front draws over the counter")
	await _capture(player, "counter_front")
	var customer := main.get_actor_director().get_actor(&"fat_goblin")
	customer.show()
	customer.global_position = level.to_global(Vector2(1000, 550))
	player.global_position = level.to_global(Vector2(1000, 430))
	await _frames()
	_check(player.z_index < counter.z_index and customer.z_index > counter.z_index, "Counter sorts player behind and customer in front simultaneously")
	await _capture(player, "customer_front_player_behind")
	customer.global_position = level.to_global(Vector2(1000, 430))
	player.global_position = level.to_global(Vector2(1000, 550))
	await _frames()
	_check(customer.z_index < counter.z_index and player.z_index > counter.z_index, "Customer moving behind the counter is occluded independently of player")
	for container: Node2D in [level.get_node("Doorframes"), level.get_node("EquipmentForeground")]:
		for foreground: DoorframeForeground in container.get_children():
			customer.global_position = foreground.get_baseline_position() + Vector2(0, 1)
			player.global_position = foreground.get_baseline_position() - Vector2(0, 1)
			await _frames()
			_check(player.z_index < foreground.z_index and customer.z_index > foreground.z_index, "Both actors respect furniture baseline: " + foreground.name)
			_check(customer.z_index < level.get_node("Rooms/Bedroom/Occlusion").z_index, "Room roofs remain above characters")
	_check(main.get_node("World/EntityRoot").y_sort_enabled, "Characters sharing a furniture band sort by their feet")
	customer.hide()
	for group in level.get_node("EquipmentForeground").get_children():
		for piece: Polygon2D in group.get_children():
			_check(piece.texture == level.get_node("Background").texture and piece.polygon == piece.uv, "Equipment uses original map texels at matching coordinates: " + piece.name)
	for config: Array in [["OrderBoard", Vector2(844, 525), "orders"], ["Storage", Vector2(514, 330), "storage"], ["TeaStation", Vector2(841, 330), "tea_station"]]:
		var point: InteractionPoint = level.get_node("InteractionPoints/" + config[0])
		player.global_position = level.to_global(config[1])
		player.velocity = Vector2.ZERO
		await _frames()
		_check(interaction.get_target() == point and point.is_available(), "Approach selects the actual device: " + config[0])
		_check(feedback._focus == point and feedback.z_index > counter.z_index, "Existing corner feedback stays above device art")
		_check(not point.get_node("Marker").visible and not point.get_node("Label").visible, "No floating marker or permanent label remains")
		_check(ui.get_node("Prompt").visible and point.display_name in ui.get_node("Prompt").text, "Existing E prompt names the selected equipment")
		await _capture(player, config[2])
		await _key(KEY_E)
		_check(ui.is_open(), "E opens existing equipment interaction: " + config[2])
		_check(interaction.get_target() == null and not ui.get_node("Prompt").visible, "Modal hides interaction feedback and prompt")
		await _key(KEY_ESCAPE)
		_check(not ui.is_open() and player.movement_enabled, "Closing restores free movement")
	player.global_position = level.get_spawn_position()
	await _frames()
	_check(interaction.get_target() == null and feedback._focus == null, "Leaving clears the only highlight")
	print("SHOP_EQUIPMENT: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	quit(0 if _failures.is_empty() else 1)
