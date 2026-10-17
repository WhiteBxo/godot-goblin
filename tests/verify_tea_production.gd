extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	# Headless windows have no native size; use the gameplay window dimensions.
	root.size = Vector2i(1280, 720)
	var main: MainGame = load("res://src/core/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	var state_before: Dictionary = root.get_node("GameState").to_dict()
	var production := main.get_tea_production()
	var ui: ShopUI = main.get_node("HudLayer/ShopUI")
	var station: InteractionPoint
	var storage: InteractionPoint
	for point: InteractionPoint in (main.get_active_level() as MilkTeaShop).get_interaction_points():
		if point.interaction_id == &"tea_station":
			station = point
		if point.interaction_id == &"storage":
			storage = point
	var modal: Control = main.get_node("PopupLayer/Modal")
	var content: VBoxContainer = modal.get_node("Center/Panel/Margin/Content")
	var panel: TeaProductionPanel = content.get_node("ProductionPanel")
	ui.open(station)
	await process_frame
	await process_frame
	_check(panel.visible and ui.is_open(), "Station must open the production controls")
	_check(modal.get_node("Center/Panel").size.y <= root.size.y, "Production panel must fit viewport height")
	_check(modal.get_node("Center/Panel").size.x <= root.size.x, "Production panel must fit viewport width")
	var selectors: Array[OptionButton] = []
	for column in panel.get_child(1).get_children():
		selectors.append(column.get_child(1))
	panel.get_child(2).pressed.emit()
	_check(production.get_completed_count() == 0 and production.get_stock("syrup") == 10, "Incomplete selection must not consume stock")
	selectors[0].select(2)
	selectors[1].select(1)
	selectors[2].select(1)
	panel.get_child(2).pressed.emit()
	_check(production.get_completed_count() == 0 and production.get_stock("green_tea") == 12, "Wrong tea must not complete or consume")
	selectors[0].select(1)
	panel.get_child(2).pressed.emit()
	_check(production.get_completed_count() == 1 and production.get_stock("black_tea") == 11 and production.get_stock("pearl") == 7 and production.get_stock("creamer") == 11 and production.get_stock("syrup") == 9, "Button must complete order and consume each ingredient exactly once")
	ui.close()
	ui.open(storage)
	_check(not panel.visible and "红茶  11" in content.get_node("DescriptionScroll/Description").text, "Storage must show shared updated stock")
	ui.close()
	ui.open(station)
	_check(production.get_completed_count() == 1 and "椰果茉莉奶茶" in panel.get_child(0).text, "Reopening must retain progress and show next order")
	selectors[0].select(2)
	selectors[1].select(1)
	selectors[2].select(2)
	panel.get_child(2).pressed.emit()
	selectors[0].select(1)
	selectors[1].select(1)
	selectors[2].select(0)
	panel.get_child(2).pressed.emit()
	_check(production.get_completed_count() == 3 and panel.get_child(2).disabled, "No-topping order must succeed and final order must disable crafting")
	var after := production.get_stock("syrup")
	_check(not production.make_drink(["black_tea", "creamer", "syrup"]).ok and production.get_stock("syrup") == after, "Completed orders cannot be submitted twice")
	var state := root.get_node("GameState")
	_check(state.get_variable("shop.orders_completed") == 3 and state.get_flag("shop.order_001_delivered") and state.get_flag("shop.order_003_delivered"), "Successful business progress projects delivery facts to GameState")
	var after_delivery: Dictionary = state.to_dict()
	production.changed.emit()
	_check(state.to_dict() == after_delivery, "Duplicate changed signal never recounts a delivery")
	_check(state.story_stage == state_before.story_stage and state.get_completed_events() == state_before.completed_events and not state.get_flag("bridge.tea_done"), "Real orders never complete demonstration recipe or advance story directly")
	# Exercise stock exhaustion and atomic failure independently of the demo queue.
	var scarce := TeaProduction.new()
	scarce._stock["pearl"] = 0
	_check(not scarce.make_drink(["black_tea", "creamer", "pearl", "syrup"]).ok and scarce.get_stock("black_tea") == 12 and scarce.get_stock("creamer") == 12, "Insufficient stock must not partially consume the recipe")
	_check(not scarce.make_drink(["black_tea", "creamer", "pearl", "syrup", "otherworld"]).ok, "Unknown or locked ingredients must be rejected")
	scarce.free()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/tea_production_complete.png")
		ui.close()
		var fresh := TeaProduction.new()
		main.get_node("Systems").add_child(fresh)
		panel.configure(fresh)
		ui.open(station)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/tea_production.png")
	print("TEA_PRODUCTION: ", "PASS" if _failures.is_empty() else "FAIL")
	quit(0 if _failures.is_empty() else 1)
