extends SceneTree

const StateData = preload("res://src/core/game_state.gd")
var _checks := 0
var _failures: Array[String] = []
var _game: MainGame
var _capture := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)
		push_error(message)

func frames(count: int = 4) -> void:
	for index in range(count):
		await process_frame

func capture(label: String) -> void:
	if not _capture or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/order_" + label + ".png")

func _run() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	root.size = Vector2i(640, 360)
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	var state: StateData = root.get_node("GameState")
	state.start_new_game()
	state.select_business_profile("day1")
	for id: String in ["day1.opening", "day1.first_goblin", "day1.group_arrival"]:
		state.complete_event(id)
	state.set_flag("day1.group_open")
	_game = load("res://src/core/main.tscn").instantiate()
	root.add_child(_game)
	current_scene = _game
	await frames(10)
	var ui := _game.get_shop_ui()
	var board: InteractionPoint
	var station: InteractionPoint
	for point: InteractionPoint in _game.get_active_level().get_interaction_points():
		if point.interaction_id == &"orders":
			board = point
		elif point.interaction_id == &"tea_station":
			station = point
	ui.open(board)
	await frames()
	var page := ui.get_popup().get_page().get_order_board_page()
	check(ui.is_open() and not _game.get_task_delivery().is_order_accepted("day1_group_a"), "Opening a real board never accepts an order")
	ui.close()
	ui.open(board)
	await frames()
	check(not _game.get_task_delivery().is_order_accepted("day1_group_a"), "Reopening never accepts either")
	check(page.select_order("day1_group_c"), "Select the last order independently of queue position")
	check(page.get_ticket().get_primary_button().text == "接取订单", "Available order has one clear acceptance action")
	await capture("available_640")
	page.get_ticket().get_primary_button().pressed.emit()
	await frames()
	check(_game.get_task_delivery().is_order_accepted("day1_group_c"), "Acceptance button commits the selected order")
	check(not _game.get_task_delivery().is_order_accepted("day1_group_a"), "Acceptance never touches another order")
	check(state.get_variable(OrderBoardModel.TRACKED_KEY) == "day1_group_c", "Acceptance tracks that order")
	check(page.get_ticket().get_primary_button().disabled, "Tracked action cannot be repeated")
	for id: String in ["day1_group_a", "day1_group_b"]:
		page.select_order(id)
		page.get_ticket().get_primary_button().pressed.emit()
	page.select_order("day1_group_c")
	page.get_ticket().get_primary_button().pressed.emit()
	await frames()
	check(page.get_selected_id() == "day1_group_c", "Stock refresh preserves selection")
	await capture("active_640")
	check(ui.get_popup().get_panel_rect().end.y <= ui.get_viewport_rect().size.y, "Order panel stays inside viewport")
	var primary := page.get_ticket().get_primary_button()
	check(primary.get_global_rect().end.y <= ui.get_popup().get_panel_rect().end.y, "Primary action stays visible at base resolution")
	ui.close()
	ui.open(station)
	await frames()
	var crafting := ui.get_popup().get_page().get_order_crafting_page()
	check(crafting.visible and crafting.get_ticket().get_primary_button().text == "制作 1 杯并入库", "Station defaults to order crafting with automatic recipe")
	check("椰果茉莉奶茶" in crafting.get_ticket().get_title_text(), "Station follows the selected order")
	await capture("crafting_640")
	var inventory := _game.get_warehouse_inventory()
	var before := inventory.get_stock("coconut_milk_tea")
	check(crafting.submit().get("ok", false), "One confirmation crafts the tracked recipe")
	check(inventory.get_stock("coconut_milk_tea") == before + 1, "Order crafting produces exactly one carried cup")
	check(not state.get_flag("day1.group_c_settled"), "Crafting never settles the order")
	var snapshot := state.to_dict()
	check(not crafting.submit().get("ok", false) and state.to_dict() == snapshot, "Repeated confirmation after stock is ready is harmless")
	await capture("ready_640")
	ui.get_popup().get_page().select_crafting_mode(true)
	check(ui.get_popup().get_crafting_panel().visible and not crafting.visible, "Free mixing remains available as a secondary mode")
	ui.close()
	ui.open(board)
	page.select_order("day1_group_c")
	await frames()
	check("可交付" == _game.get_order_board().get_entry("day1_group_c").status_text, "Board reflects actual crafted inventory")
	root.size = Vector2i(1280, 720)
	await frames(8)
	await capture("active_1280")
	check(page.get_ticket().get_global_rect().end.x <= ui.get_viewport_rect().size.x, "Ticket fits larger viewport")
	ui.close()
	await frames()
	check(_game.get_player().movement_enabled, "Closing restores gameplay movement")
	_game.free()
	await frames()
	state.start_new_game()
	print("ORDER_UI: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
