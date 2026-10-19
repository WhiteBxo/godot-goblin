extends SceneTree
## Actual menu, register receipts, old-save recovery, navigation, hearing and focus loss.

var checks := 0
var failures: Array[String] = []
var state: Node
var game: MainGame

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func frames(count := 8) -> void:
	for i in range(count):
		await process_frame

func picture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/feedback_navigation/captures")
	root.get_texture().get_image().save_png("res://.godot/feedback_navigation/captures/" + name + ".png")

func mouse_at(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await frames(2)
	for i in range(4):
		await physics_frame

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/feedback_%d" % OS.get_process_id())
	state = root.get_node("GameState")
	await _orders_and_menu()
	await _market_and_recovery()
	await _guards_on_real_maps()
	await _hearing()
	print("FEEDBACK_ITERATION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _orders_and_menu() -> void:
	state.start_new_game()
	state.select_business_profile("day1")
	for id: String in ["day1.opening", "day1.first_goblin", "day1.group_arrival"]:
		state.complete_event(id)
	state.set_flag("day1.group_open")
	# This register fixture deliberately opens five slips together.
	for id: String in ["b", "c", "d", "e"]:
		state.set_flag("day1.group_" + id + "_open")
	game = load("res://src/core/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(20)
	# Keep this transaction test at its real wait boundary; the complete story is
	# separately driven by verify_two_day_flow.gd.
	game.get_gameplay_bridge().stop(true)
	var ui := game.get_shop_ui()
	var book := game.get_node("PopupLayer/HandbookPanel") as HandbookPanel
	check(game.open_game_menu() == OK, "Game menu opens at the real business boundary")
	var menu := game.get_game_menu()
	check(menu.get_navigation_button(ScreenIds.TASKS).text == "任务日志 [J]", "Task log replaces the commission menu")
	check(menu.get_navigation_button(ScreenIds.ORDER_HISTORY).text == "奶茶订单", "Separate milk order record is present")
	check(menu.get_navigation_button(ScreenIds.HIRING).disabled, "Hiring remains explicitly unavailable")
	check(menu.get_navigation_button(ScreenIds.DRINKS).text == "哥布林饮品图鉴", "Encyclopedia uses the requested name")
	await picture("menu")
	game.get_ui_manager().close_screen(ScreenIds.CHAPTER_ACTIONS)
	var register: InteractionPoint
	for point: InteractionPoint in game.get_active_level().get_interaction_points():
		if point.interaction_id == &"orders":
			register = point
	ui.open(register)
	var board := ui.get_popup().get_page().get_order_board_page()
	var accept := board.get_node("%AcceptAll") as Button
	accept.pressed.emit()
	await frames()
	var accepted := 0
	for entry: Dictionary in game.get_order_board().get_entries():
		accepted += 1 if entry.accepted else 0
	check(accepted == 5 and accept.disabled, "One acceptance click accepts all five current orders")
	check(board.get_tabs().tab_count == 2, "Production board has no completed-order tab")
	await picture("one_click_orders")
	ui.close()
	var product_ids := ["strawberry_milk_green_tea", "coffee_cocoa_ice_milk", "mint_choc_milk_tea", "iced_mint_latte"]
	for id: String in product_ids:
		var recipe := game.get_tea_production().get_recipe_by_product(id)
		check(game.get_tea_production().craft(recipe.materials, 2 if id == "strawberry_milk_green_tea" else 1).ok, "Prepare actual cups: " + id)
	var balance: int = state.get_transactions().get_balance()
	game.get_player().teleport_to(register.global_position + Vector2(0, -35))
	for i in range(8):
		await physics_frame
	await frames()
	await mouse_at(register.get_global_transform_with_canvas().origin)
	check(game.get_task_delivery().get_completed_count() == 5, "A real mouse click on the register delivers all ready cups")
	check(state.get_transactions().get_balance() == balance + 15, "Register settles each cup's real price exactly once")
	check(not ui.is_open(), "Successful register delivery requires no extra milk popup")
	var receipt: Dictionary = state.to_dict()
	await mouse_at(register.get_global_transform_with_canvas().origin)
	check(state.get_transactions().get_balance() == balance + 15 and game.get_task_delivery().get_completed_count() == 5, "Repeated register clicks cannot pay for completed receipts")
	check(board.get_tabs().get_tab_title(0) == "进行中 0" and not board.select_order("day1_group_a"), "Ended orders are absent from milk production")
	ui.close()
	check(game.get_ui_manager().open_screen(ScreenIds.ORDER_HISTORY) == OK, "Archived orders have their own menu page")
	var history := book.get_order_history_page()
	check(history.get_entries().item_count == 5, "All five ended orders remain recorded")
	for i in range(history.get_entries().item_count):
		check(history.get_entries().get_item_text(i).begins_with("[已完成]"), "Archive retains an explicit ended status")
	await picture("order_history")
	game.get_ui_manager().close_screen(ScreenIds.ORDER_HISTORY)
	check(state.restore_state(receipt) == OK, "Actual delivered snapshot restores")
	await frames()
	check(game.get_order_board().get_entry("day1_group_a").status == "completed", "Restore retains completed order history")
	check(game.open_tasks() == OK and book.get_tasks_page().get_entries().item_count == 0, "Milk order history is separate from the protagonist's tasks")
	game.get_ui_manager().close_screen(ScreenIds.TASKS)
	game.free()
	await frames()

func _market_and_recovery() -> void:
	state.start_new_game()
	state.select_business_profile("day1")
	state.set_flag("day1.stages_01_02_completed")
	state.set_flag("day1.s03.exited_shop")
	for id: String in ["day1.ending", "day1.s03.coin_inspect", "day1.s03.street_gone"]:
		state.complete_event(id)
	state.set_story_stage("day1.s03.explore")
	game = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var map := game.get_active_level() as RpgChapterMap
	var player := game.get_player() as PlayerController
	player.teleport_to(Vector2(600, 2136)) # A position reachable in an older, ungated save.
	await frames(25)
	for i in range(6):
		await physics_frame
	check(player.global_position.distance_to(map.get_scene_entrance(&"shop_door").global_position) < 1, "Old outside-market position recovers to the authored shop entrance")
	var initial := player.global_position
	Input.action_press(&"move_left")
	for i in range(8):
		await physics_frame
	check(player.global_position.distance_to(initial) > 1, "Recovered player can move normally")
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var stopped := player.global_position
	for i in range(8):
		await physics_frame
	check(not Input.is_action_pressed(&"move_left") and player.velocity.is_zero_approx() and player.global_position.distance_to(stopped) < 0.1, "Focus loss clears swallowed key releases and residual drift")
	player.teleport_to(Vector2(600, 2424))
	for i in range(20):
		await physics_frame
	check(state.get_flag("day1.s03.exploration_completed"), "Western market walking completes observation without interacting")
	check(game.get_task_journal().get_current_main_task().current_objective.text == "回奶茶店", "Exterior objective says only return to milk tea shop")
	var hud := game.get_navigation_hud()
	check(hud.is_visible_in_tree() and hud.get_target().get("text") == "回奶茶店", "Upper-right minimap and live objective update after observation")
	var path := map.get_navigation_path(player.global_position, map.get_scene_entrance(&"shop_door").global_position)
	check(not path.is_empty(), "Guidance has an actual walkable return path")
	for point: Vector2 in path:
		check(map.first_visit_bounds.has_point(map.to_local(point)), "First-visit guidance stays inside the market")
	await picture("market_minimap")
	state.set_flag("day1.s04.map_available")
	for location: String in RpgWorldMapData.location_ids():
		state.set_flag("ui.map.known." + location)
	check(game.open_map() == OK, "Unlocked full map opens")
	await picture("illustrated_map")
	game.get_ui_manager().close_screen(ScreenIds.MAP)
	var book := game.get_node("PopupLayer/HandbookPanel") as HandbookPanel
	check(game.open_tasks() == OK and book.get_tasks_page().get_entries().item_count == 1, "Exploration is recorded in task log")
	await picture("task_log")
	game.get_ui_manager().close_screen(ScreenIds.TASKS)
	game.free()
	await frames()

func _hearing() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var actor: SettlementCharacter = load("res://src/gameplay/characters/rpg_guard.tscn").instantiate()
	world.add_child(actor)
	actor.face_direction(PlayerController.Facing.RIGHT)
	var player: PlayerController = load("res://src/gameplay/player/rpg_player.tscn").instantiate()
	player.accepts_player_input = false
	world.add_child(player)
	player.teleport_to(Vector2(-80, 0))
	var guard := Day1GuardResponse.new()
	guard.actor = actor
	guard.hear_footsteps = true
	guard.hearing_range = 200
	guard.sight_range = 40
	world.add_child(guard)
	guard.capture_checkpoint()
	for i in range(3):
		await physics_frame
	var space := world.get_world_2d().direct_space_state
	check(guard.hear_noise(player.global_position, 1.0, space), "A loud sound behind the guard is heard")
	check(actor.facing == PlayerController.Facing.LEFT and guard.state == Day1GuardResponse.State.SEARCHING, "Hearing turns the guard and visibly starts investigation")
	check(not guard.advance(0.1, player, space), "Hearing alone is not instant discovery")
	check(actor.global_position.is_zero_approx(), "A stationary post does not turn into a patrol after hearing")
	guard.advance(3.0, player, space)
	check(guard.state == Day1GuardResponse.State.WATCHING and actor.facing == PlayerController.Facing.RIGHT, "Investigation expiry restores the original watch direction")
	guard.reset_response()
	guard.role = Day1GuardResponse.Role.MANSION_GATE
	check(guard.distract(player.global_position) and guard.state == Day1GuardResponse.State.SEARCHING, "A special sentry acknowledges coin noise without clearing its gate")
	check(actor.global_position.is_zero_approx(), "Coin noise does not move the stationary sentry")
	guard.reset_response()
	check(not guard.hear_noise(player.global_position, 0.1, space), "Sneaking has a smaller audible radius than running")
	var wall := StaticBody2D.new()
	wall.position = Vector2(-40, 0)
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 100)
	collider.shape = shape
	wall.add_child(collider)
	world.add_child(wall)
	for i in range(3):
		await physics_frame
	check(not guard.hear_noise(player.global_position, 1.0, space), "A wall attenuates hearing instead of broadcasting across rooms")
	world.free()
	await frames()

func _guards_on_real_maps() -> void:
	state.start_new_game()
	state.select_business_profile("day1")
	state.set_flag("day1.s04.commission_accepted")
	state.set_story_stage("day1.s05.ready")
	DayPhase.enter_night(state)
	game = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(15)
	game.get_player().teleport_to(Vector2(1752, 504))
	var setup := game.get_stealth_service().get_setup()
	check(setup.guards.size() == 6, "Exterior includes additional district guards")
	var posts: Array[Vector2] = [setup.guards[1].actor.global_position, setup.guards[2].actor.global_position]
	for i in range(20):
		await physics_frame
	check(setup.guards[1].actor.global_position == posts[0] and setup.guards[2].actor.global_position == posts[1], "Mansion-front guards remain at their posts during real physics ticks")
	await picture("mansion_sentries")
	game.free()
	await frames()
	state.set_flag("day1.s05.drunken_paid")
	state.set_flag("day1.s05.guard_payment_completed")
	game = load("res://src/core/elder_house.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(20)
	var map := game.get_active_level() as RpgChapterMap
	game.get_player().teleport_to(map.get_spawn_position())
	check(map.get_stealth_setup() == null and game.get_stealth_service() == null, "Elder house does not create an indoor stealth service")
	check(map.get_chapter_characters().is_empty(), "Indoor patrol guards are absent")
	var document: Vector2 = map.get_objective_position("day1.s05.infiltration", "document")
	check(not map.get_navigation_path(game.get_player().global_position, document).is_empty(), "Indoor navigation retains a floor route to the document")
	await picture("indoor_investigation")
	game.free()
	await frames()
