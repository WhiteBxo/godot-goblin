extends SceneTree
## Formal otherworld catalog: spreadsheet rows, warehouse view and teaching isolation.

var _checks: int = 0
var _failures: Array[String] = []

const DAY1_MENU := "res://src/resources/milk_tea/day1_menu.tres"
const BASIC_MENU := "res://src/resources/milk_tea/basic_menu.tres"
const BOOK := "res://src/resources/milk_tea/day1_recipe_book.tres"

## Mirrors docs/design/otherworld_data_mapping.md. Keep in sync with the spreadsheet.
## source_ids holds the spreadsheet row ids so the catalog stays traceable to the draft.
const EXPECTED: Array[Dictionary] = [
	{"sources": ["F01"], "id": "moss_green", "name": "苔痕青", "rarity": "普通", "form": "液体",
		"processing": ["免加工"], "price": 0},
	{"sources": ["F02"], "id": "sugar_yam", "name": "窟窟糖芋", "rarity": "普通", "form": "固体",
		"processing": ["切丁", "切块"], "price": 0},
	{"sources": ["F03"], "id": "insomnia_mushroom", "name": "醒神菇", "rarity": "稀有", "form": "固体",
		"processing": ["榨汁"], "price": 0},
	{"sources": ["F04"], "id": "firefly_cap", "name": "萤火伞", "rarity": "稀有", "form": "固体",
		"processing": ["切块", "榨汁"], "price": 0},
	{"sources": ["F05", "W02"], "id": "goblin_firebrew", "name": "纯正哥布林老火烧", "rarity": "优秀", "form": "液体",
		"processing": ["免加工"], "price": 4},
	{"sources": ["F06", "W04"], "id": "griffin_amber_wine", "name": "格里芬琥珀酒", "rarity": "史诗", "form": "液体",
		"processing": ["免加工"], "price": 100},
	{"sources": ["F07"], "id": "red_mottled_wood", "name": "红斑咬木", "rarity": "优秀", "form": "固体",
		"processing": ["切丁", "免加工"], "price": 0},
	{"sources": ["F08"], "id": "honey_amber_crystal", "name": "蜜珀晶", "rarity": "优秀", "form": "固体",
		"processing": ["切块"], "price": 0},
	{"sources": ["F09"], "id": "day1_griffin_blood", "name": "格里芬之血", "rarity": "传奇", "form": "液体",
		"processing": ["免加工"], "price": 0},
	{"sources": ["F10"], "id": "phantom_gold_mushroom", "name": "幻金菇", "rarity": "史诗", "form": "固体",
		"processing": ["切块"], "price": 0},
	{"sources": ["F11"], "id": "rainbow_cube", "name": "幻彩小方", "rarity": "史诗", "form": "胶体",
		"processing": ["切丁"], "price": 0},
	{"sources": ["F12"], "id": "scorch_tongue_pepper", "name": "炽舌椒", "rarity": "稀有", "form": "固体",
		"processing": ["切丁", "榨汁"], "price": 0},
	{"sources": ["W01"], "id": "sour_moss_ale", "name": "劣质酸苔麦酒", "rarity": "普通", "form": "液体",
		"processing": ["免加工"], "price": 1},
	{"sources": ["W03"], "id": "brute_lava_firebrew", "name": "暴徒熔岩老火烧", "rarity": "稀有", "form": "液体",
		"processing": ["免加工"], "price": 15},
	{"sources": ["W05"], "id": "griffin_sacred_wine", "name": "格里芬圣血祭酒", "rarity": "传奇", "form": "液体",
		"processing": ["免加工"], "price": 0},
	{"sources": ["C01"], "id": "creamer_milk_tea_base", "name": "植脂末奶茶底", "rarity": "", "form": "",
		"processing": [], "price": 0},
	{"sources": ["C02"], "id": "industrial_green_tea", "name": "工业绿茶清汤", "rarity": "", "form": "",
		"processing": [], "price": 0},
	{"sources": ["C03"], "id": "mint_syrup", "name": "荧绿薄荷糖浆", "rarity": "", "form": "",
		"processing": [], "price": 0},
	{"sources": ["C04"], "id": "instant_coffee_concentrate", "name": "浓缩速溶咖啡原浆", "rarity": "", "form": "",
		"processing": [], "price": 0},
	{"sources": ["C05"], "id": "brown_sugar_boba", "name": "黑糖波霸珍珠", "rarity": "", "form": "",
		"processing": [], "price": 0},
	{"sources": ["C06"], "id": "mint_choc_crisp", "name": "代可可脂薄荷巧脆碎", "rarity": "", "form": "",
		"processing": [], "price": 0},
	{"sources": ["C07"], "id": "ice", "name": "冰块", "rarity": "", "form": "",
		"processing": [], "price": 0},
	{"sources": ["C08"], "id": "cocoa_powder", "name": "可可粉", "rarity": "", "form": "",
		"processing": [], "price": 0},
	{"sources": ["C09"], "id": "apple_jam", "name": "苹果果酱", "rarity": "", "form": "",
		"processing": [], "price": 0},
	{"sources": ["C10"], "id": "strawberry_jam", "name": "草莓果酱", "rarity": "", "form": "",
		"processing": [], "price": 0},
	{"sources": ["H01"], "id": "classic_boba_milk_tea", "name": "经典珍珠奶茶（成品）", "rarity": "", "form": "",
		"processing": [], "price": 0},
	{"sources": ["H02"], "id": "mint_choc_milk_tea", "name": "薄荷巧脆奶茶（成品）", "rarity": "", "form": "",
		"processing": [], "price": 0},
	{"sources": ["H03"], "id": "coffee_cocoa_ice_milk", "name": "咖啡可可冰奶（成品）", "rarity": "", "form": "",
		"processing": [], "price": 0},
	{"sources": ["H04"], "id": "apple_milk_green_tea", "name": "苹果奶绿（成品）", "rarity": "", "form": "",
		"processing": [], "price": 0},
	{"sources": ["H05"], "id": "strawberry_milk_green_tea", "name": "草莓奶绿（成品）", "rarity": "", "form": "",
		"processing": [], "price": 0},
	{"sources": ["H06"], "id": "iced_mint_latte", "name": "冰吸薄荷拿铁（成品）", "rarity": "", "form": "",
		"processing": [], "price": 0},
]

## The six human drink recipes; product ids double as recipe ids.
const EXPECTED_RECIPES: Array[Dictionary] = [
	{"product_id": "classic_boba_milk_tea",
		"materials": ["creamer_milk_tea_base", "brown_sugar_boba", "ice"]},
	{"product_id": "mint_choc_milk_tea",
		"materials": ["creamer_milk_tea_base", "mint_syrup", "mint_choc_crisp", "ice"]},
	{"product_id": "coffee_cocoa_ice_milk",
		"materials": ["creamer_milk_tea_base", "instant_coffee_concentrate", "cocoa_powder", "ice"]},
	{"product_id": "apple_milk_green_tea",
		"materials": ["industrial_green_tea", "apple_jam", "creamer_milk_tea_base", "ice"]},
	{"product_id": "strawberry_milk_green_tea",
		"materials": ["industrial_green_tea", "strawberry_jam", "creamer_milk_tea_base", "ice"]},
	{"product_id": "iced_mint_latte",
		"materials": ["instant_coffee_concentrate", "creamer_milk_tea_base", "mint_syrup", "ice"]},
]

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	_check_catalog()
	_check_items()
	_check_spreadsheet_coverage()
	_check_teaching_session()
	await _check_warehouse_view()
	print("OTHERWORLD_CATALOG: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	quit(0 if _failures.is_empty() else 1)

func _definitions(menu: TeaMenu) -> Dictionary:
	var result := {}
	for definition: IngredientDefinition in menu.ingredients:
		result[definition.id] = definition
	return result

## Adding materials must never invalidate the recipes and orders already in use.
func _check_catalog() -> void:
	for path: String in [DAY1_MENU, BASIC_MENU]:
		var menu: TeaMenu = load(path)
		var errors := TeaProduction.validate_menu(menu)
		_check(errors.is_empty(), "%s still validates: %s" % [path, "；".join(errors)])
	var menu: TeaMenu = load(DAY1_MENU)
	_check(menu.orders.size() >= 5, "Formal menu keeps its Day 1 orders")
	var products: Array[String] = []
	for recipe: TeaRecipe in menu.get_recipes():
		products.append(recipe.product_id)
	for product: String in ["classic_boba_milk_tea", "mint_choc_milk_tea", "coffee_cocoa_ice_milk",
			"apple_milk_green_tea", "strawberry_milk_green_tea", "iced_mint_latte"]:
		_check(product in products, "Formal menu crafts %s" % product)
	for retired: String in ["pearl_milk_tea", "coconut_milk_tea", "plain_milk_tea"]:
		_check(retired not in products, "Formal menu omits retired teaching recipe: " + retired)
	var book: TeaRecipeBook = load(BOOK)
	for row: Dictionary in EXPECTED_RECIPES:
		var recipe := book.find_by_product(str(row.product_id))
		_check(recipe != null, "Recipe book resolves %s" % row.product_id)
		if recipe == null:
			continue
		var expected: Array[String] = []
		for item: Variant in row.materials:
			expected.append(item)
		expected.sort()
		var actual: Array[String] = recipe.materials.duplicate()
		actual.sort()
		_check(actual == expected, "%s uses the spreadsheet materials" % row.product_id)

## Catalog fields must match the spreadsheet rows they were imported from.
func _check_items() -> void:
	var definitions := _definitions(load(DAY1_MENU))
	for row: Dictionary in EXPECTED:
		var definition: IngredientDefinition = definitions.get(row.id)
		if definition == null:
			_check(false, "Catalog is missing %s (%s)" % [row.id, row.name])
			continue
		_check(definition.display_name == row.name, "%s is named %s" % [row.id, row.name])
		var formal: bool = str(row.sources[0]).begins_with("F") or str(row.sources[0]).begins_with("W")
		_check(definition.origin == ("otherworld" if formal else "human"),
			"%s keeps the origin recorded in the spreadsheet" % row.id)
		_check(definition.form == row.form, "%s form matches the spreadsheet" % row.id)
		_check(Array(definition.processing_methods) == row.processing, "%s processing matches the spreadsheet" % row.id)
		_check(definition.price == int(row.price), "%s price is %d" % [row.id, int(row.price)])
		_check(Array(definition.source_ids) == row.sources, "%s keeps its spreadsheet rows" % row.id)
		_check(not definition.description.is_empty(), "%s carries its compendium text" % row.id)
		_check(not definition.flavor_tags.is_empty(), "%s carries its flavour tags" % row.id)
	_check(definitions.has("day1_blood_milk_tea"), "Gated blood recipe keeps its product in the catalog")

## Every spreadsheet row that has a runtime item must be reachable from the catalog.
func _check_spreadsheet_coverage() -> void:
	var covered: Array[String] = []
	for definition: IngredientDefinition in (load(DAY1_MENU) as TeaMenu).ingredients:
		for source: String in definition.source_ids:
			covered.append(source)
	covered.sort()
	var expected_rows: Array[String] = []
	for index in range(1, 13):
		expected_rows.append("F%02d" % index)
	for index in range(1, 6):
		expected_rows.append("W%02d" % index)
	for index in range(1, 11):
		expected_rows.append("C%02d" % index)
	for index in range(1, 7):
		expected_rows.append("H%02d" % index)
	expected_rows.sort()
	_check(covered == expected_rows, "Every configured row maps to exactly one runtime item: %s" % str(covered))

## The tutorial keeps its observed materials; formal items stay dormant there.
func _check_teaching_session() -> void:
	var inventory := WarehouseInventory.new()
	# initial_stock has carried the same 16 teaching materials since before the resource
	# re-save; the old "six" number predates the expanded tutorial shelf. The invariant
	# worth guarding is that the tutorial never opens otherworld-only items.
	var total := inventory.get_ingredients().size()
	var human := inventory.get_ingredients("human").size()
	_check(human == total, "Tutorial exposes only human-side materials (%d of %d)" % [human, total])
	for id: String in ["moss_green", "goblin_firebrew", "classic_boba_milk_tea", "day1_griffin_blood"]:
		_check(not inventory.is_discovered(id) and inventory.get_stock(id) == 0, "Formal item %s is dormant in the tutorial" % id)
	inventory.free()

func _check_warehouse_view() -> void:
	var menu: TeaMenu = load(DAY1_MENU)
	var inventory := WarehouseInventory.new(menu)
	_check(not inventory.is_discovered("day1_griffin_blood") and inventory.get_stock("day1_griffin_blood") == 0, "New formal materials start undiscovered with no stock")
	_check(inventory.get_ingredients("otherworld").size() == 0, "Undiscovered formal materials stay out of the list")
	_check(inventory.add_ingredient("day1_griffin_blood", 1) and inventory.add_ingredient("goblin_firebrew", 2), "Gathering or trade can stock a formal material")
	var view := inventory.get_ingredient_view("goblin_firebrew")
	_check(view.form == "液体" and int(view.price) == 4 and not str(view.description).is_empty(), "Warehouse view exposes form, price and compendium text")
	var panel := WarehousePanel.new()
	root.add_child(panel)
	panel.configure(inventory)
	panel._filter.select(2)
	panel._filter.item_selected.emit(2)
	_check(panel._list.item_count == 2, "Otherworld filter lists the newly discovered materials")
	var index := -1
	for row_index in range(panel._list.item_count):
		if panel._list.get_item_metadata(row_index) == "goblin_firebrew":
			index = row_index
	_check(index >= 0, "Formal material appears in the warehouse list")
	if index >= 0:
		panel._select_item(index)
		var text: String = panel._details.text
		_check(text.contains("形态：液体") and text.contains("加工：免加工"), "Details show form and processing")
		_check(text.contains("标价：4G"), "Details show the spreadsheet price")
		_check(text.contains("用途：原料") and text.contains("稀有度：优秀"), "Details label the material category and rarity")
		_check(text.contains("获取方式：???"), "Unexplored property groups stay masked")
		inventory.discover_property("goblin_firebrew", "acquisition_sources")
		for row_index in range(panel._list.item_count):
			if panel._list.get_item_metadata(row_index) == "goblin_firebrew":
				index = row_index
		panel._select_item(index)
		_check(panel._details.text.contains("获取方式：在酒馆直接购买"), "Revealed acquisition source comes from the spreadsheet")
	var snapshot := inventory.to_dict()
	var restored := WarehouseInventory.new(menu)
	_check(restored.restore_state(JSON.parse_string(JSON.stringify(snapshot))) == OK and restored.get_stock("goblin_firebrew") == 2, "Formal stock survives a session snapshot")
	panel.free()
	restored.free()
	inventory.free()
	await process_frame
