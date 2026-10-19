extends SceneTree
## Real negotiation, gated travel, document lifecycle and corrected interior passages.

var state: Node
var game: MainGame
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count := 6) -> void:
	for frame in range(count):
		await process_frame

func picture(id: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/elder_feedback/" + id + ".png")

func negotiate(choice: int, success: bool) -> void:
	var director := game.get_story_director()
	var result: Array = []
	var callback := func(_id: String, ok: bool, _reason: String) -> void: result.append(ok)
	director.event_finished.connect(callback, CONNECT_ONE_SHOT)
	check(director.request_interaction("mansion_payment") == OK, "Guard negotiation can be requested again until payment")
	var deadline := Time.get_ticks_msec() + 5000
	while not game.get_dialogue_manager().is_active() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not game.get_dialogue_manager().is_active():
		check(false, "Negotiation reaches a real dialogue choice")
		director.event_finished.disconnect(callback)
		director.cancel_event()
		return
	check(not state.get_flag("day1.s05.guard_payment_completed"), "Opening negotiation does not grant clearance")
	game.get_dialogue_manager().advance()
	await picture("bribe_choice")
	game.get_dialogue_manager().select_choice(choice)
	while director.is_busy() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not director.is_busy() and result == [success], "Negotiation finishes with its actual transaction outcome")
	await frames()

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/elder_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute("res://.godot/elder_feedback")
	state = root.get_node("GameState")
	state.start_new_game()
	state.select_business_profile("day1")
	state.set_story_stage("day1.s05.ready")
	state.set_flag("day1.s04.commission_accepted")
	DayPhase.enter_night(state)
	state.set_flag("day1.s05.night_started")
	check(state.commit_story_transaction("test.elder.funding", {}, {}, 50) == OK, "Prepare a real funded wallet")
	game = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(20)
	var door: SceneExit = game.get_active_level().get_node("Exits/ElderDoor")
	check(game.get_scene_travel().request_exit(door) == ERR_UNAVAILABLE, "Commission alone cannot enter the mansion")
	game.get_shop_ui().close()
	state.set_flag("day1.s05.drunken_paid")
	check(game.get_scene_travel().request_exit(door) == ERR_UNAVAILABLE, "Paying the drunken guard alone cannot enter")
	game.get_shop_ui().close()
	var balance: int = state.get_transactions().get_balance()
	await negotiate(1, true)
	check(state.get_transactions().get_balance() == balance and not door.are_conditions_met(state), "Leaving the negotiation spends nothing and leaves the door locked")
	check(not state.is_event_completed("day1.s05.mansion_payment"), "Declining does not consume the repeatable negotiation")
	check(state.commit_story_transaction("test.elder.low_funds", {}, {}, 9 - balance) == OK, "Prepare insufficient funds")
	await negotiate(0, false)
	check(state.get_transactions().get_balance() == 9 and not door.are_conditions_met(state), "Failed payment grants neither a debit nor entry")
	check(state.commit_story_transaction("test.elder.top_up", {}, {}, 41) == OK, "Fund a later retry")
	await negotiate(0, true)
	check(state.get_transactions().get_balance() == 40 and door.are_conditions_met(state), "Only confirmed payment deducts exactly 10G and unlocks entry")
	check(game.get_story_director().request_interaction("mansion_payment") != OK and state.get_transactions().get_balance() == 40, "Paid guards cannot charge again")
	state.set_flag("day1.s04.commission_accepted", false)
	check(not door.are_conditions_met(state), "Clearance cannot bypass the accepted commission requirement")
	state.set_flag("day1.s04.commission_accepted")
	for id: String in RpgWorldMapData.location_ids():
		state.set_flag("ui.map.known." + id)
	check(game.unlock_map() in [OK, ERR_ALREADY_EXISTS] and game.open_map() == OK, "Open the real overview with known region labels")
	await frames()
	var panel: SettlementMapPanel = game.get_node("PopupLayer/SettlementMapPanel")
	var canvas := panel.get_map_canvas()
	check(canvas.OVERVIEW.get_size() == Vector2(1200, 1320), "Overview uses the exact supplied exterior image")
	var art: Rect2 = canvas._art_rect()
	check(canvas._art_point(Vector2(1200, 1320)).is_equal_approx(art.get_center()), "Map center projects directly to the supplied image center")
	check(canvas.map_data.regions.size() == 11, "All eleven known exterior regions remain labeled")
	await picture("world_map")
	game.get_ui_manager().close_screen(ScreenIds.MAP)
	check(game.get_scene_travel().request_exit(door) == OK, "Paid player can travel through the actual mansion door")
	await scene_changed
	game = current_scene as MainGame
	await frames(35)
	await verify_interior()
	game.queue_free()
	await frames()
	await verify_bathroom()
	print("ELDER_FEEDBACK: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func verify_interior() -> void:
	var map := game.get_active_level() as RpgChapterMap
	check(map.chapter_host == &"elder_house", "Actual travel reaches the mansion host")
	var document: StoryInteractionPoint = map.get_node("Interactions/day1_elder_document")
	var blood: StoryInteractionPoint = map.get_node("Interactions/day1_blood_storage")
	for point: StoryInteractionPoint in [document, blood]:
		check(not map.get_navigation_path(map.get_spawn_position(), point.global_position).is_empty(), "Corrected walls preserve the route to " + String(point.entry_id))
	for cell: Vector2i in [Vector2i(8, 9), Vector2i(12, 9), Vector2i(13, 10), Vector2i(6, 8), Vector2i(15, 3), Vector2i(2, 5)]:
		check(not map.can_stand_at(map.cell_to_world(cell), Vector2(8.5, 5)), "Wall or furniture blocks player feet at " + str(cell))
	for guard: Day1GuardResponse in map.get_stealth_setup().guards:
		for offset: Vector2 in guard.patrol_offsets:
			check(map.can_stand_at(guard.actor.global_position + offset, Vector2(5, 5)), "Guard spawn and patrol stay on corrected floor")
	var player := game.get_player() as PlayerController
	check(player.test_move(Transform2D(0, map.cell_to_world(Vector2i(9, 9))), Vector2(-48, 0)), "Actual physics body is stopped by the decorative wooden wall")
	game.get_player().teleport_to(document.global_position)
	for tick in range(4):
		await physics_frame
	check(game._route_story_interaction(document.interaction_id) == OK, "Real document interaction opens its modal")
	await frames()
	var illustration: TextureRect = game.get_shop_ui().get_popup().find_child("DocumentImage", true, false)
	check(illustration != null and illustration.is_visible_in_tree() and illustration.texture == document.document_texture, "Document modal displays the supplied scroll")
	check(illustration != null and illustration.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "Document preserves its original aspect ratio")
	check(not state.get_flag("day1.s05.document_read") and not player.movement_enabled, "Viewing image locks movement without prematurely granting the document")
	await picture("ancient_document")
	game.get_shop_ui().close()

	await frames()
	check(state.get_flag("day1.s05.document_read") and player.movement_enabled, "Closing the image commits reading and restores movement")
	var stock: int = state.get_warehouse_inventory().get_stock("day1_elder_document")
	check(game._route_story_interaction(document.interaction_id) == OK, "Document image can be reopened")
	game.get_shop_ui().close()
	check(state.get_warehouse_inventory().get_stock("day1_elder_document") == stock, "Rereading does not duplicate the item")
	game.get_shop_ui().open(blood)
	check(not illustration.is_visible_in_tree(), "Switching to another interaction hides the old scroll")
	game.get_shop_ui().close()

func verify_bathroom() -> void:
	var map: MilkTeaShop = load("res://src/levels/milkTea/milk_tea_shop.tscn").instantiate()
	var player: ShopPlayer = load("res://src/gameplay/player/shop_player.tscn").instantiate()
	player.get_node("Camera2D").enabled = false
	root.add_child(map)
	root.add_child(player)
	player.set_physics_process(false)
	for tick in range(3):
		await physics_frame
	check(player.test_move(Transform2D(0, map.to_global(Vector2(222, 588))), map.to_global(Vector2(222, 492)) - map.to_global(Vector2(222, 588))), "Bathroom wall face blocks walking behind the sink")
	check(player.test_move(Transform2D(0, map.to_global(Vector2(220, 563))), Vector2(-50, 0) * map.scale), "Bathroom shower tray blocks sideways entry")
	check(not player.test_move(Transform2D(0, map.to_global(Vector2(370, 634))), Vector2(-98, 0) * map.scale), "Bathroom lower doorway remains physically open")
	player.camera.enabled = true
	player.configure_camera(map.get_camera_bounds())
	player.teleport_to(map.to_global(Vector2(222, 588)))
	player.set_physics_process(true)
	player.set_movement_enabled(true)
	Input.action_press("move_up")
	for tick in range(60):
		await physics_frame
	Input.action_release("move_up")
	await frames()
	var feet := map.to_local(player.global_position)
	check(feet.y >= 544 and feet.y < 588, "Actual upward movement stops at the bathroom wall foot")
	await picture("bathroom_collision")
	player.queue_free()
	map.queue_free()
	await frames()
