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

func press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await frames(2)

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
	page.get_ticket().get_primary_button().grab_focus()
	await press(&"ui_accept")
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
	check(page.get_selected_id() == "day1_group_c", "Deferred modal focus and resizing preserve the selected order")
	await capture("active_1280")
	check(page.get_ticket().get_global_rect().end.x <= ui.get_viewport_rect().size.x, "Ticket fits larger viewport")
	ui.close()
	await frames()
	check(_game.get_player().movement_enabled, "Closing restores gameplay movement")
	root.size = Vector2i(640, 360)
	var point := _game.get_delivery_point("goblin_c")
	_game.get_player().teleport_to(point.global_position + Vector2(0, -40))
	for index in range(5):
		await physics_frame
	await frames()
	check("交付" in ui.get_prompt_text() and "椰果" in ui.get_prompt_text(), "Ready customer prompt names the actual deliverable product")
	await capture("hud_640")
	var coins := inventory.get_stock("strange_coin")
	await press(&"interact")
	check(state.get_flag("day1.group_c_settled") and inventory.get_stock("strange_coin") == coins + 1, "Actual E interaction settles the selected customer once")
	check(not ui.is_open() and not _game.get_ui_manager().has_modal() and _game.get_player().movement_enabled, "Settlement feedback keeps gameplay available")
	check("交付成功" in ui.get_feedback_text() and "古怪硬币" in ui.get_feedback_text(), "Nonmodal feedback reports actual committed reward")
	check(_game.get_order_board().get_tracked_entry().order_id != "day1_group_c", "Completed tracking falls back to another active order")
	await capture("delivered_640")
	var settled := state.to_dict()
	await press(&"interact")
	check(state.to_dict() == settled, "Repeated physical E cannot pay twice")
	ui.open(board)
	await press(&"ui_cancel")
	check(not ui.is_open() and _game.get_player().movement_enabled, "Keyboard Esc closes the board and restores movement")
	await _test_long_content(_game.get_order_board().get_entries()[0])
	_game.free()
	await frames()
	state.start_new_game()
	print("ORDER_UI: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_long_content(sample: Dictionary) -> void:
	var list: OrderList = load("res://src/UI/milk_tea/order_list.tscn").instantiate()
	_game.get_node("HudLayer").add_child(list)
	list.position = Vector2(16, 16)
	list.size = Vector2(176, 150)
	var entries: Array[Dictionary] = []
	for index: int in range(20):
		var entry := sample.duplicate(true)
		entry.order_id = "long.%d" % index
		entries.append(entry)
	list.set_entries(entries, "long.18")
	list.focus_order("long.18")
	await frames()
	var focused := root.gui_get_focus_owner()
	var scroll := list.get_v_scroll_bar().value
	check(scroll > 0, "A long order list scrolls its focused row into view")
	entries[18].status_text = "缺料"
	list.set_entries(entries, "long.18")
	await frames()
	check(root.gui_get_focus_owner() == focused and is_equal_approx(list.get_v_scroll_bar().value, scroll), "Refreshing a long list preserves focus and scroll")
	await press(&"ui_up")
	check(root.gui_get_focus_owner() != focused and list.is_ancestor_of(root.gui_get_focus_owner()), "Keyboard arrows navigate long order lists")
	list.free()
	var ticket: OrderTicket = load("res://src/UI/components/order_ticket.tscn").instantiate()
	_game.get_node("HudLayer").add_child(ticket)
	ticket.position = Vector2(216, 116)
	ticket.size = Vector2(396, 216)
	var entry := sample.duplicate(true)
	entry.product_id = ""
	entry.items.clear()
	for index: int in range(20):
		entry.items.append({"name": "所需物资 %d" % index, "owned": 0, "needed": 1})
	ticket.present(entry, "追踪此单", true)
	await frames()
	# A real parent Container reapplies the available size after wrapped text settles.
	ticket.size = Vector2(396, 216)
	await frames()
	var hint := ticket.get_node("%NextStep") as Label
	check(hint.get_global_rect().end.y <= ticket.get_primary_button().global_position.y and ticket.get_primary_button().get_global_rect().end.y <= 332, "Long requirements scroll independently while next step and action stay visible")
	ticket.free()
	await frames()
