extends SceneTree
## Recipe catalog, free crafting service and the two-column crafting panel.

var _failures: Array[String] = []

const BASIC_MENU := "res://src/resources/milk_tea/basic_menu.tres"
const DAY1_MENU := "res://src/resources/milk_tea/day1_menu.tres"
const SHOP := "res://src/debug/story/legacy_shop.tscn"
const PEARL: Array[String] = ["black_tea", "creamer", "pearl", "syrup"]
const COCONUT: Array[String] = ["green_tea", "creamer", "coconut", "syrup"]
const PLAIN: Array[String] = ["black_tea", "creamer", "syrup"]
const BLOOD: Array[String] = ["day1_griffin_blood", "black_tea", "creamer", "syrup"]
const BLOOD_FLAG := "day1.s05.blood_acquired"

## Stands in for GameState: recipe availability only reads session flags.
class FlagState:
	extends Node
	## TeaProduction subscribes to it, so the double must expose the signal too.
	signal state_changed
	var flags: Dictionary = {}
	var story_stage := "day1.s05"

	func get_flag(key: String, default_value: bool = false) -> bool:
		return bool(flags.get(key, default_value))

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_check_menus()
	_check_blood_unlock()
	_check_preview()
	_check_free_crafting()
	_check_atomic_failures()
	_check_reentrancy()
	_check_capacity()
	_check_order_entry()
	await _check_locked_panel()
	await _check_panel()
	print("TEA_RECIPES: ", "PASS" if _failures.is_empty() else "FAIL")
	quit(0 if _failures.is_empty() else 1)

func _check_menus() -> void:
	for path: String in [BASIC_MENU, DAY1_MENU]:
		var menu: TeaMenu = load(path)
		var errors := TeaProduction.validate_menu(menu)
		_check(errors.is_empty(), "%s recipes validate: %s" % [path, "；".join(errors)])
		var products: Dictionary = {}
		for recipe: TeaRecipe in menu.get_recipes():
			products[recipe.product_id] = true
		for order: Dictionary in menu.orders:
			_check(products.has(order.product_id), "%s order %s has a recipe" % [path, order.id])
	var book: TeaRecipeBook = load("res://src/resources/milk_tea/recipe_book.tres")
	_check(book.find_by_product("pearl_milk_tea") != null, "Recipe book resolves products")
	_check(book.find_by_materials(["syrup", "pearl", "creamer", "black_tea"]) != null, "Recipe lookup ignores selection order")
	var blood: TeaRecipe = book.find_by_product("day1_blood_milk_tea")
	_check(blood != null and blood.required_flag == BLOOD_FLAG, "Blood recipe is gated by the acquisition fact")
	_check(book.get_recipes_for(null).size() == 3, "Gated recipe stays hidden without a session state")
	_check(book.find_by_product("day1_blood_milk_tea") != null, "Product lookup still resolves a locked recipe")

func _check_blood_unlock() -> void:
	var menu: TeaMenu = load(DAY1_MENU)
	var state := FlagState.new()
	var inventory := WarehouseInventory.new(menu)
	var production := TeaProduction.new()
	production.configure(inventory, state)
	_check(production.get_recipe_errors().is_empty(), "Formal menu validates with the gated recipe")
	_check(inventory.add_ingredient("day1_griffin_blood", 3), "Acquired blood enters the shared inventory")
	var book: TeaRecipeBook = menu.recipe_book
	_check(book.get_recipes_for(state).size() == 3, "Locked recipe is filtered out in catalog order")
	var preview := production.preview_craft(BLOOD)
	_check(preview.code == "locked", "Locked recipe previews as locked")
	_check(preview.product_id.is_empty() and preview.materials == BLOOD, "Locked preview leaks no product and consumes nothing")
	var before := inventory.to_dict()
	var result := production.craft(BLOOD)
	_check(not result.ok and result.code == "locked", "Locked recipe refuses to craft")
	_check(inventory.to_dict() == before, "Locked recipe keeps every stock entry unchanged")
	_check(inventory.get_stock("day1_blood_milk_tea") == 0, "Locked recipe produces no cup")
	state.flags[BLOOD_FLAG] = true
	_check(production.preview_craft(BLOOD).code == "locked", "Blood acquisition alone does not unlock S06 crafting")
	state.flags["day1.s05.returned_shop"] = true
	_check(production.preview_craft(BLOOD).code == "locked", "S05 remains locked even with blood and a return receipt")
	state.story_stage = "day1.s06.wait_blood_drink"
	var unlocked := book.get_recipes_for(state)
	_check(unlocked.size() == 4, "Unlocked recipe joins the catalog")
	_check(unlocked.size() == 4 and unlocked[3].id == "day1_blood_recipe", "Unlocked recipe keeps its catalog position")
	preview = production.preview_craft(BLOOD)
	_check(preview.code == "ok" and preview.product_id == "day1_blood_milk_tea", "Unlocked recipe previews the blood drink")
	_check(not preview.advances_order, "Blood recipe never joins the fixed order queue")
	result = production.craft(BLOOD)
	_check(result.ok and result.code == "ok", "Unlocked recipe crafts")
	_check(inventory.get_stock("day1_blood_milk_tea") == 1, "Blood drink enters the shared inventory")
	_check(inventory.get_stock("day1_griffin_blood") == 2, "Blood is consumed once per cup")
	_check(inventory.get_stock("black_tea") == 11 and inventory.get_stock("creamer") == 11 and inventory.get_stock("syrup") == 9, "Each supporting material is consumed once")
	for _index in range(2):
		_check(production.craft(BLOOD).ok, "Unlocked recipe crafts repeatedly")
	_check(inventory.get_stock("day1_blood_milk_tea") == 3 and inventory.get_stock("day1_griffin_blood") == 0, "Repeated crafting keeps producing while blood lasts")
	result = production.craft(BLOOD)
	_check(result.code == "missing_materials" and int(result.missing.get("day1_griffin_blood", 0)) == 1, "Running out of blood reports the shortfall")
	_check(production.get_completed_count() == 0, "Blood crafting never advances the order queue")
	production.free()
	inventory.free()
	state.free()

func _check_preview() -> void:
	var inventory := WarehouseInventory.new()
	var production := TeaProduction.new()
	production.configure(inventory)
	_check(production.get_recipe_errors().is_empty(), "Configured production has no recipe errors")
	var preview := production.preview_craft([])
	_check(preview.code == "empty", "Empty selection previews as empty")
	preview = production.preview_craft(["unknown"])
	_check(preview.code == "unknown_material", "Unknown id previews as unknown material")
	preview = production.preview_craft(["black_tea", "creamer"])
	_check(preview.code == "unknown_recipe", "Partial recipe previews as unknown recipe")
	preview = production.preview_craft(["syrup", "pearl", "creamer", "black_tea"])
	_check(preview.code == "ok" and preview.product_id == "pearl_milk_tea", "Any order previews the matching drink")
	_check(preview.advances_order and preview.order_id == "order_001", "Matching the current order marks the preview as advancing it")
	inventory.try_consume({"pearl": 8})
	preview = production.preview_craft(PEARL)
	_check(preview.code == "missing_materials" and int(preview.missing.get("pearl", 0)) == 1, "Missing material is reported per item")
	_check(production.get_completed_count() == 0, "Preview never advances the queue")
	production.free()
	inventory.free()

func _check_free_crafting() -> void:
	var inventory := WarehouseInventory.new()
	var production := TeaProduction.new()
	production.configure(inventory)
	var result := production.craft(PLAIN)
	_check(result.ok and result.code == "ok", "Known recipe crafts without an order match")
	_check(production.get_completed_count() == 0, "Off-order cup does not advance the queue")
	_check(inventory.get_stock("plain_milk_tea") == 1 and inventory.get_stock("syrup") == 9, "Off-order cup enters inventory and consumes materials")
	result = production.craft(["pearl", "black_tea", "creamer", "syrup"])
	_check(result.ok and production.get_completed_count() == 1, "Matching the current order advances it in any order")
	_check(inventory.get_stock("pearl_milk_tea") == 1, "Order cup is carried in inventory")
	production.free()
	inventory.free()

func _check_atomic_failures() -> void:
	var inventory := WarehouseInventory.new()
	var production := TeaProduction.new()
	production.configure(inventory)
	var before := inventory.to_dict()
	var result := production.craft(["black_tea", "creamer", "pearl", "pearl", "syrup"])
	_check(result.code == "unknown_recipe" and inventory.to_dict() == before, "Unknown combination consumes nothing")
	_check(production.get_completed_count() == 0, "Unknown combination keeps the queue")
	inventory.try_consume({"pearl": 8})
	before = inventory.to_dict()
	result = production.craft(PEARL)
	_check(result.code == "missing_materials" and inventory.to_dict() == before, "Missing materials consume nothing")
	_check(production.get_completed_count() == 0, "Missing materials keep the queue")
	production.free()
	inventory.free()

func _check_reentrancy() -> void:
	var inventory := WarehouseInventory.new()
	var production := TeaProduction.new()
	production.configure(inventory)
	var nested: Array[bool] = []
	var observer := func() -> void:
		if nested.is_empty():
			nested.append(production.craft(PLAIN).ok)
	production.changed.connect(observer)
	_check(production.craft(PLAIN).ok, "Outer craft succeeds")
	production.changed.disconnect(observer)
	_check(nested == [false], "Crafting inside the changed notification is rejected")
	production.free()
	inventory.free()

func _check_capacity() -> void:
	var inventory := WarehouseInventory.new()
	var production := TeaProduction.new()
	production.configure(inventory)
	_check(inventory.add_ingredient("pearl_milk_tea", WarehouseInventory.MAX_QUANTITY), "Product stock can reach capacity")
	var before := inventory.to_dict()
	var result := production.craft(PEARL)
	_check(result.code == "capacity", "Full product stock rejects the craft")
	_check(inventory.to_dict() == before and production.get_completed_count() == 0, "Capacity failure rolls back progress and materials")
	production.free()
	inventory.free()

func _check_order_entry() -> void:
	var inventory := WarehouseInventory.new()
	var production := TeaProduction.new()
	production.configure(inventory)
	_check(not production.make_drink(COCONUT).ok, "Wrong recipe is rejected for the current order")
	_check(production.make_drink(PEARL, "order_001").ok, "Order entry crafts the accepted order")
	_check(not production.make_drink(PEARL, "order_001").ok, "Replayed order id is rejected")
	_check(production.make_drink(COCONUT, "order_002").ok, "Next order crafts through the same commit path")
	_check(production.make_drink(PLAIN, "order_003").ok, "Final order crafts")
	_check(not production.make_drink(PLAIN).ok, "Finished queue rejects order entry")
	_check(production.craft(PLAIN).ok, "Free crafting still works after the queue")
	production.free()
	inventory.free()

func _check_locked_panel() -> void:
	var menu: TeaMenu = load(DAY1_MENU)
	var state := FlagState.new()
	var inventory := WarehouseInventory.new(menu)
	var production := TeaProduction.new()
	production.configure(inventory, state)
	inventory.add_ingredient("day1_griffin_blood", 2)
	var panel: CraftingPanel = load("res://src/UI/milk_tea/crafting_panel.tscn").instantiate()
	root.add_child(panel)
	panel.configure(production)
	_check(not _panel_has_row(panel, "day1_griffin_blood"), "Locked material never reaches the selectable list")
	_check(not _panel_has_row(panel, "day1_blood_milk_tea"), "Locked product never reaches the owned list")
	state.flags[BLOOD_FLAG] = true
	_check(production.preview_craft(BLOOD).code == "locked", "Blood acquisition alone does not unlock S06 crafting")
	state.flags["day1.s05.returned_shop"] = true
	_check(production.preview_craft(BLOOD).code == "locked", "S05 remains locked even with blood and a return receipt")
	state.story_stage = "day1.s06.wait_blood_drink"
	production.changed.emit()
	_check(_panel_has_row(panel, "day1_griffin_blood"), "Unlocked material joins the selectable list")
	_check(production.craft(BLOOD).ok, "Unlocked recipe crafts through the session service")
	_check(_panel_has_row(panel, "day1_blood_milk_tea"), "Freshly crafted blood drink appears as an owned product")
	panel.free()
	production.free()
	inventory.free()
	state.free()
	await process_frame

func _panel_has_row(panel: CraftingPanel, id: String) -> bool:
	var list: ItemList = panel.get_node("Body/Left/MaterialList")
	for index in range(list.item_count):
		var metadata: Variant = list.get_item_metadata(index)
		if metadata is Dictionary and str(metadata.get("id", "")) == id:
			return true
	return false

func _check_panel() -> void:
	var main: MainGame = load(SHOP).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	var ui: ShopUI = main.get_node("HudLayer/ShopUI")
	var modal: Control = main.get_node("PopupLayer/Modal")
	var station: InteractionPoint
	for point: InteractionPoint in (main.get_active_level() as MilkTeaShop).get_interaction_points():
		if point.interaction_id == &"tea_station":
			station = point
	ui.open(station)
	await process_frame
	var panel: CraftingPanel = main.get_node("PopupLayer/Modal/Center/Panel/Margin/Content/ProductionPanel")
	_check(panel.visible, "Crafting panel opens at the tea station")
	_check(root.gui_get_focus_owner() == panel.get_node("Body/Left/MaterialList"), "Focus starts on the material list")
	_check(not panel.is_craft_enabled(), "Empty selection cannot be submitted")
	panel.add_material("black_tea")
	panel.add_material("black_tea")
	_check(panel.selection_count() == 2, "Repeated clicks stack the same material")
	panel.remove_material("black_tea")
	_check(panel.selection_count() == 1, "Removing a chip drops one portion")
	panel.clear_selection()
	for id: String in PEARL:
		_check(panel.add_material(id), "Material is selectable: " + id)
	_check("珍珠奶茶" in panel.preview_text(), "Preview names the matched drink")
	_check(panel.is_craft_enabled(), "Complete selection enables crafting")
	var result := panel.submit()
	_check(result.ok and "制作完成" in panel.result_text(), "Submitting through the panel crafts the cup")
	_check(panel.selection_count() == 0, "Successful craft clears the tray")
	_check(panel.select_product("pearl_milk_tea"), "Owned cup can be selected")
	_check(panel.redo_selected_product(), "Owned cup refills the tray")
	_check(panel.selected_materials() == PEARL, "Redo restores the full recipe")
	for size: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		root.size = size
		await process_frame
		await process_frame
		_check(modal.get_node("Center/Panel").size.x <= size.x and modal.get_node("Center/Panel").size.y <= size.y, "Crafting panel fits the viewport: " + str(size))
	ui.close()
	main.queue_free()
	await process_frame
