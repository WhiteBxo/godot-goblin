extends SceneTree

var _checks: int = 0
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	_test_inventory()
	_test_production_transaction()
	await _test_discovery_ui()
	await _test_session("res://src/core/main.tscn")
	await _test_session("res://src/core/settlement.tscn")
	print("WAREHOUSE_INVENTORY: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	quit(0 if _failures.is_empty() else 1)

func _fixture_menu() -> TeaMenu:
	var menu: TeaMenu = WarehouseInventory.CATALOG.duplicate(true)
	var hidden := IngredientDefinition.new()
	hidden.id = "test_otherworld"
	hidden.display_name = "测试食材"
	hidden.origin = "otherworld"
	hidden.icon = menu.ingredients[0].icon
	hidden.flavor_tags = ["测试风味"]
	hidden.special_effects = ["测试隐藏效果"]
	hidden.combat_attributes = ["测试战斗属性"]
	hidden.acquisition_sources = ["测试隐藏来源"]
	menu.ingredients.append(hidden)
	return menu

func _test_inventory() -> void:
	var inventory := WarehouseInventory.new()
	var notifications: Array[Dictionary] = []
	inventory.changed.connect(func() -> void: notifications.append(inventory.to_dict()))
	_check(inventory.get_ingredients().size() == 6, "Teaching inventory contains exactly the six configured ingredients")
	for definition in WarehouseInventory.CATALOG.ingredients:
		_check(inventory.get_stock(definition.id) == WarehouseInventory.CATALOG.initial_stock[definition.id] and inventory.is_discovered(definition.id), "Initial quantity/discovery matches catalog: " + definition.id)
		_check(definition.icon != null, "Each configured ingredient has an icon")
	_check(inventory.add_ingredient("black_tea", 2) and inventory.get_stock("black_tea") == 14 and notifications.size() == 1, "Adding stock commits and notifies once")
	var before := inventory.to_dict()
	for bad: Variant in [0, -1, 1.5, 1.0, true, "1", null, [], {}, WarehouseInventory.MAX_QUANTITY + 1]:
		_check(not inventory.add_ingredient("black_tea", bad), "Reject invalid addition: " + str(bad))
		_check(not inventory.try_consume({"black_tea": bad}), "Reject invalid consumption: " + str(bad))
	for id: Variant in ["unknown", "", 1, null, true]:
		_check(not inventory.add_ingredient(id, 1) and not inventory.try_consume({id: 1}) and not inventory.discover(id), "Reject unknown/invalid ingredient ID")
		_check(inventory.get_definition(id) == null and inventory.get_ingredient_view(id).is_empty(), "Invalid query has no definition or UI view")
	for bad: Variant in [null, [], "black_tea", 3, {}, {"black_tea": 1, "unknown": 1}, {"black_tea": 1, "pearl": 9}]:
		_check(not inventory.has_materials(bad) and not inventory.try_consume(bad), "Malformed/insufficient group fails atomically")
	_check(inventory.to_dict() == before and notifications.size() == 1, "All failed operations leave every quantity and discovery unchanged, without signals")
	_check(inventory.try_consume({"black_tea": 2, "pearl": 8}), "Consume sufficient grouped materials")
	_check(inventory.get_stock("black_tea") == 12 and inventory.get_stock("pearl") == 0 and notifications.size() == 2, "A grouped commit emits exactly one complete snapshot")
	_check(inventory.get_ingredients().size() == 6 and inventory.is_discovered("pearl"), "Zero-stock discovered ingredients remain listed")
	var copy := inventory.get_definition("black_tea")
	copy.display_name = "changed"
	var view := inventory.get_ingredient_view("black_tea")
	view.flavor_tags.append("changed")
	var snapshot := inventory.to_dict()
	snapshot.ingredients.black_tea.quantity = 999
	_check(inventory.get_definition("black_tea").display_name == "红茶" and not "changed" in inventory.get_ingredient_view("black_tea").flavor_tags and inventory.get_stock("black_tea") == 12, "Returned definitions/views/snapshots cannot mutate live state")
	var valid := inventory.to_dict()
	var restored := WarehouseInventory.new()
	_check(restored.restore_state(JSON.parse_string(JSON.stringify(valid))) == OK and restored.to_dict() == valid, "Versioned snapshot survives a JSON round trip")
	var restores: Array[bool] = []
	restored.changed.connect(func() -> void: restores.append(true))
	_check(restored.restore_state(valid) == OK and restores.is_empty(), "Identical restore does not emit duplicate notifications")
	for bad: Variant in [null, [], {}, {"schema_version": 2, "ingredients": valid.ingredients}]:
		_check(restored.restore_state(bad) == ERR_INVALID_DATA, "Reject invalid snapshot structure/version")
	for bad: Variant in [-1, 0.5, true, "3", INF, NAN, WarehouseInventory.MAX_QUANTITY + 1]:
		var invalid := valid.duplicate(true)
		invalid.ingredients.pearl.quantity = bad
		_check(restored.restore_state(invalid) == ERR_INVALID_DATA and restored.to_dict() == valid, "Invalid restore cannot partially change stock")
	var invalid := valid.duplicate(true)
	invalid.ingredients["unknown"] = invalid.ingredients.pearl
	_check(restored.restore_state(invalid) == ERR_INVALID_DATA, "Reject unknown saved IDs")
	invalid = valid.duplicate(true)
	invalid.ingredients.erase("pearl")
	_check(restored.restore_state(invalid) == ERR_INVALID_DATA, "Reject incomplete saved inventory")
	invalid = valid.duplicate(true)
	invalid.ingredients.pearl.known_properties = ["special_effects", "special_effects"]
	_check(restored.restore_state(invalid) == ERR_INVALID_DATA, "Reject duplicate discovery properties")
	invalid = valid.duplicate(true)
	invalid.ingredients.black_tea.discovered = false
	_check(restored.restore_state(invalid) == ERR_INVALID_DATA, "Reject positive stock or known properties on an undiscovered ingredient")
	invalid = valid.duplicate(true)
	invalid.ingredients.pearl.known_properties = ["unknown"]
	_check(restored.restore_state(invalid) == ERR_INVALID_DATA, "Reject unknown discovery properties on restore")
	_check(restores.is_empty(), "Failed restores never notify")
	invalid = valid.duplicate(true)
	invalid.ingredients.black_tea.quantity = WarehouseInventory.MAX_QUANTITY
	_check(restored.restore_state(invalid) == OK and not restored.add_ingredient("black_tea", 1), "Reject addition overflow")
	_check(WarehouseInventory.CATALOG.initial_stock.black_tea == 12, "Runtime mutations never alter shared Resource defaults")
	var bad_menu: TeaMenu = WarehouseInventory.CATALOG.duplicate(true)
	bad_menu.initial_stock["unknown"] = 1
	var empty := WarehouseInventory.new(bad_menu)
	_check(empty.get_ingredients().is_empty(), "Invalid catalog is rejected as a whole")
	empty.free()
	restored.free()
	inventory.free()

func _test_production_transaction() -> void:
	var inventory := WarehouseInventory.new()
	var production := TeaProduction.new()
	production.configure(inventory)
	var recipe: Array[String] = ["black_tea", "creamer", "pearl", "syrup"]
	var before := inventory.to_dict()
	_check(not production.make_drink(["unknown"]).ok and inventory.to_dict() == before and production.get_completed_count() == 0, "Invalid recipe changes neither stock nor order")
	inventory.try_consume({"pearl": 8})
	before = inventory.to_dict()
	_check(not production.make_drink(recipe).ok and inventory.to_dict() == before and production.get_completed_count() == 0, "Insufficient production is atomic for inventory and orders")
	inventory.add_ingredient("pearl", 8)
	var observations: Array[bool] = []
	var reentrant: Array[bool] = []
	inventory.changed.connect(func() -> void:
		observations.append(production.get_completed_count() == 1 and inventory.get_stock("syrup") == 9)
		reentrant.append(production.make_drink(["green_tea", "creamer", "coconut", "syrup"]).ok))
	production.changed.connect(func() -> void:
		reentrant.append(production.make_drink(["green_tea", "creamer", "coconut", "syrup"]).ok))
	var order_id: String = production.get_order().id
	_check(production.make_drink(recipe, order_id).ok and production.get_completed_count() == 1, "Valid production commits one order")
	_check(observations == [true] and not true in reentrant, "Synchronous listeners see a full commit and cannot reenter delivery")
	before = inventory.to_dict()
	_check(not production.make_drink(recipe, order_id).ok and not production.make_drink(["green_tea", "creamer", "coconut", "syrup"], order_id).ok and inventory.to_dict() == before, "Replayed old order ID rejects even a recipe matching the next order")
	_check(production.get_stock("syrup") == inventory.get_stock("syrup"), "Production reads the injected inventory")
	production.free()
	inventory.free()

func _test_discovery_ui() -> void:
	var inventory := WarehouseInventory.new(_fixture_menu())
	var acquired := WarehouseInventory.new(_fixture_menu())
	_check(acquired.add_ingredient("test_otherworld", 1) and acquired.is_discovered("test_otherworld") and not acquired.is_property_known("test_otherworld", "special_effects"), "Acquiring a new material discovers its identity without revealing hidden effects")
	acquired.free()
	var panel := WarehousePanel.new()
	root.add_child(panel)
	panel.configure(inventory)
	_check(not inventory.is_discovered("test_otherworld") and inventory.get_ingredients("otherworld").is_empty(), "Undiscovered material is absent from the list")
	_check(inventory.discover("test_otherworld") and inventory.get_stock("test_otherworld") == 0, "Discovering does not grant stock")
	_check(not inventory.discover("test_otherworld"), "Repeated discovery is idempotent")
	panel._filter.select(2)
	panel._filter.item_selected.emit(2)
	_check(panel._list.item_count == 1 and "缺货" in panel._list.get_item_text(0), "Otherworld filter displays discovered zero-stock material")
	_check("???" in panel._details.text and not "测试隐藏" in panel._details.text and not "测试风味" in panel._details.text, "UI masks all unknown property groups")
	_check(not inventory.discover_property("test_otherworld", "unknown"), "Unknown property group is rejected")
	_check(inventory.discover_property("test_otherworld", "flavor_tags") and not inventory.discover_property("test_otherworld", "flavor_tags"), "Property discovery is explicit and idempotent")
	_check("测试风味" in panel._details.text and not "测试隐藏效果" in panel._details.text, "Discovery refresh reveals only the unlocked group")
	_check(inventory.add_ingredient("test_otherworld", 2) and "2" in panel._list.get_item_text(0), "Inventory change automatically refreshes an open list")
	var restored := WarehouseInventory.new(_fixture_menu())
	_check(restored.restore_state(JSON.parse_string(JSON.stringify(inventory.to_dict()))) == OK and restored.is_property_known("test_otherworld", "flavor_tags") and not restored.is_property_known("test_otherworld", "special_effects"), "Discovery state round-trips independently of static attributes")
	panel._filter.select(1)
	panel._filter.item_selected.emit(1)
	_check(panel._list.item_count == 6, "Human filter excludes otherworld materials")
	panel._filter.select(0)
	panel._filter.item_selected.emit(0)
	_check(panel._list.item_count == 7, "All filter combines discovered origins")
	panel.free()
	restored.free()
	inventory.free()
	await process_frame

func _test_session(scene_path: String) -> void:
	root.size = Vector2i(1280, 720)
	var main: MainGame = load(scene_path).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	var inventory := main.get_warehouse_inventory()
	var production := main.get_tea_production()
	_check(inventory != null and production.get_inventory() == inventory, "Both formal entries inject one shared inventory: " + scene_path)
	var ui := main.get_shop_ui()
	var points: Dictionary = {}
	for point: InteractionPoint in main.get_active_level().get_interaction_points():
		points[point.interaction_id] = point
	var popup: ShopPopup = main.get_node("PopupLayer/Modal")
	ui.open(points[&"storage"])
	await process_frame
	_check(popup._warehouse_panel.visible and not (main.get_player() as PlayerController).movement_enabled, "Warehouse uses the existing modal and movement lock")
	_check(inventory.try_consume({"black_tea": 12}) and "缺货" in popup._warehouse_panel._list.get_item_text(0), "Open warehouse reacts to external stock changes")
	for size: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		root.size = size
		await process_frame
		await process_frame
		_check(popup.get_node("Center/Panel").size.x <= size.x and popup.get_node("Center/Panel").size.y <= size.y, "Warehouse fits the configured gameplay viewport: " + str(size))
	inventory.add_ingredient("black_tea", 12)
	ui.close()
	_check((main.get_player() as PlayerController).movement_enabled, "Closing warehouse restores movement")
	ui.open(points[&"tea_station"])
	_check(popup._production_panel.visible and not popup._warehouse_panel.visible, "Station switches to production controls")
	inventory.try_consume({"pearl": 8})
	_check(popup._production_panel._selectors[2].is_item_disabled(1), "Open production selectors refresh from the same stock")
	inventory.add_ingredient("pearl", 8)
	_check(not popup._production_panel._selectors[2].is_item_disabled(1), "Restocking refreshes production without reopening")
	_check(production.make_drink(["black_tea", "creamer", "pearl", "syrup"], "order_001").ok, "Session production succeeds")
	ui.close()
	ui.open(points[&"orders"])
	_check("椰果茉莉奶茶" in popup.get_node("Center/Panel/Margin/Content/DescriptionScroll/Description").text, "Order board reads the same committed progress")
	ui.close()
	ui.open(points[&"storage"])
	_check("红茶  11" in popup._warehouse_panel._list.get_item_text(0), "Reopened warehouse retains consumed stock")
	ui.close()
	ui.open(points[&"tea_station"])
	_check(production.get_completed_count() == 1 and "椰果茉莉奶茶" in popup._production_panel._order.text, "Reopened station retains order progress")
	ui.close()
	ui.open(points[&"orders"])
	_check(production.make_drink(["green_tea", "creamer", "coconut", "syrup"], "order_002").ok and "原味奶茶" in popup.get_node("Center/Panel/Margin/Content/DescriptionScroll/Description").text, "An open order board refreshes committed progress automatically")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		ui.close()
		ui.open(points[&"storage"])
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/warehouse_" + scene_path.get_file().get_basename() + ".png")
	ui.close()
	main.queue_free()
	await process_frame
	await process_frame
