extends SceneTree

const StateData = preload("res://src/core/game_state.gd")
const RULES: RecipeRules = preload("res://src/resources/milk_tea/recipe_rules.tres")
const BASE := "goblin_firebrew"
const FORMULA: Array[String] = [BASE, "mint_choc_crisp", "red_mottled_wood"]
const SWEET: Array[String] = [BASE, "mint_syrup", "mint_syrup"]
var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames(count := 4) -> void:
	for frame in range(count):
		await process_frame

func _run() -> void:
	_test_slot_roles()
	_test_formula()
	_test_ice()
	_test_crafting()
	_test_saves()
	_test_schema()
	_test_delivery()
	await _test_ui()
	print("FREE_RECIPES: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

## Free cups are only craftable and sellable once the ledger holds a permanent
## price. Tests confirm the price up front and read it back instead of guessing.
func _price(state: Node, materials: Array, request_id: String) -> int:
	var result: Dictionary = state.confirm_formula(materials, request_id)
	_check(result.get("ok", false), "Confirming a free-formula price succeeds: " + request_id)
	return int(result.get("record", {}).get("selling_price", -1))

func _stock(inventory: WarehouseInventory) -> void:
	for id: String in [BASE, "mint_choc_crisp", "red_mottled_wood", "mint_syrup", "scorch_tongue_pepper", "cocoa_powder", "brown_sugar_boba"]:
		inventory.add_ingredient(id, 5)

func _test_slot_roles() -> void:
	var coffee := "instant_coffee_concentrate"
	var creamer := "creamer_milk_tea_base"
	for path: String in ["res://src/resources/milk_tea/basic_menu.tres", "res://src/resources/milk_tea/day1_menu.tres"]:
		var inventory := WarehouseInventory.new(load(path))
		for id: String in [coffee, creamer, "industrial_green_tea", "mint_syrup", "day1_griffin_blood"]:
			inventory.add_ingredient(id, 1)
		var coffee_drink := inventory.calculate_formula([coffee, creamer])
		var milk_drink := inventory.calculate_formula([creamer, coffee])
		_check(coffee_drink.ok and coffee_drink.base_id == coffee and coffee_drink.name.ends_with("咖啡"), "Coffee base accepts creamer as an additive and retains the coffee suffix: " + path)
		_check(milk_drink.ok and milk_drink.base_id == creamer and milk_drink.name.ends_with("奶茶") and milk_drink.id != coffee_drink.id, "Swapping the base changes the name suffix and identity: " + path)
		var three_bases := inventory.calculate_formula([coffee, creamer, "industrial_green_tea"])
		_check(three_bases.ok and three_bases.base_id == coffee and three_bases.name.ends_with("咖啡"), "Three base-capable ingredients occupy exactly one base and two additive slots: " + path)
		var repeated := inventory.calculate_formula([coffee, coffee, coffee])
		_check(repeated.ok and repeated.counts[coffee] == 3 and repeated.base_id == coffee, "The same ingredient can fill the base and both additive slots: " + path)
		for id: String in [coffee, creamer]:
			_check(inventory.get_formula_choices(true).any(func(choice: Dictionary) -> bool: return choice.id == id) and inventory.get_formula_choices().any(func(choice: Dictionary) -> bool: return choice.id == id), "An ordinary base appears in both slot choice lists: " + id)
		_check(not inventory.calculate_formula(["mint_syrup", coffee]).ok, "An additive-only first slot cannot borrow base eligibility from a later ingredient")
		for invalid: Array in [[], ["day1_griffin_blood"], [coffee, "day1_griffin_blood"], [coffee, creamer, "industrial_green_tea", BASE]]:
			_check(not inventory.calculate_formula(invalid).ok, "Missing base, special ingredients and fourth slots reject: " + str(invalid))
		# Exercise all four flag combinations without changing catalog resources.
		for base_allowed: bool in [false, true]:
			for ordinary_allowed: bool in [false, true]:
				var candidate := inventory.get_definition(coffee)
				candidate.can_be_base = base_allowed
				candidate.free_recipe_allowed = ordinary_allowed
				var lookup := func(id: String) -> IngredientDefinition: return candidate if id == coffee else inventory.get_definition(id)
				_check(DrinkFormula.evaluate([coffee, BASE], lookup, RULES).ok == (base_allowed and ordinary_allowed), "First slot requires both independent permissions")
				_check(DrinkFormula.evaluate([BASE, coffee], lookup, RULES).ok == ordinary_allowed, "Additive eligibility depends on ordinary permission alone")
				_check(FormulaPricing.canonical([coffee, BASE], lookup).ok == (base_allowed and ordinary_allowed), "Pricing checks the same independent base permissions")
				_check(FormulaPricing.canonical([BASE, coffee], lookup).ok == ordinary_allowed, "Pricing never excludes an additive for base eligibility")
		inventory.free()

func _test_formula() -> void:
	var inventory := WarehouseInventory.new()
	var before := inventory.to_dict()
	var result := inventory.calculate_formula(FORMULA)
	_check(result.ok and result.taste == inventory.get_definition(BASE).get_taste(), "Additive tastes below three do not contribute")
	_check(result.price == 0 and is_equal_approx(result.cost, 8.0) and result.signature_id.is_empty(), "Evaluation stays unpriced and keeps the source example's 8G cost")
	_check(result.name == "纯正哥布林老火烧代可可脂薄荷巧脆碎红斑咬木特调", "Name follows source order and base suffix")
	_check(result.effects.count("强烈清凉感") == 1 and "辛辣" in result.flavors and "木香" in result.flavors, "Tag groups merge independently and deduplicate")
	_check(inventory.to_dict() == before, "Pure evaluation neither discovers nor consumes ingredients")
	var sweet := inventory.calculate_formula(SWEET)
	_check(sweet.taste.sweetness == 8 and "双重" in sweet.name, "Repeated sweetness-three additive contributes twice and is named twice")
	_check(sweet.throw.effects.paralyze.stacks == 2 and not sweet.throw.effects.has("burn"), "Only mapped ingredients contribute their own throw stacks")
	var reversed_formula: Array[String] = [BASE, FORMULA[2], FORMULA[1]]
	_check(DrinkFormula.key_for(FORMULA) == DrinkFormula.key_for(reversed_formula), "Additive order does not duplicate recipe identity")
	_check(DrinkFormula.key_for([FORMULA[1], BASE, FORMULA[2]]) != result.id and DrinkFormula.key_for([BASE, FORMULA[1]]) != result.id, "Changing the base or additive count changes identity")
	for invalid: Variant in [null, [], [BASE, null], ["black_tea"], ["mint_syrup", BASE], ["day1_griffin_blood"], [BASE, "day1_griffin_blood"], [BASE, "pearl_milk_tea"], [BASE, "strange_coin"], [BASE, "mint_syrup", "mint_syrup", "mint_syrup"]]:
		_check(not inventory.calculate_formula(invalid).ok, "Invalid or restricted formula rejects: " + str(invalid))
	var rules: RecipeRules = RULES.duplicate(true)
	rules.slot_count = 4
	var large: Array[String] = [BASE, "cocoa_powder", "cocoa_powder", "cocoa_powder"]
	var expanded := DrinkFormula.evaluate(large, inventory.get_definition, rules)
	_check(not expanded.ok and expanded.code == "slots", "A larger slot setting cannot bypass the three-slot limit")
	var historical := DrinkFormula.evaluate(large, inventory.get_definition, rules, false)
	_check(historical.ok and historical.throw.area_cells == rules.throw_tuning.max_area_cells and historical.throw.modifiers.burst.stacks == 3, "Historical longer recipes remain readable with capped throw area")
	var lingering := DrinkFormula.evaluate([BASE, "brown_sugar_boba", "brown_sugar_boba", "brown_sugar_boba"], inventory.get_definition, rules, false)
	_check(lingering.throw.duration == rules.throw_tuning.max_duration, "Stacked duration respects the tuning bound")
	rules.slot_count = 3
	rules.signatures = [{"id": "test_signature", "name": "测试专属名", "ingredients": reversed_formula}]
	var signature := DrinkFormula.evaluate(FORMULA, inventory.get_definition, rules)
	_check(signature.ok and signature.signature_id == "test_signature" and signature.name == "测试专属名", "Signature compares exact base and counts, independently of order")
	_check(signature.price == 0, "A signature names a discovery without pricing it")
	var priced_signature: RecipeRules = RULES.duplicate(true)
	priced_signature.signatures = [{"id": "test_signature", "name": "测试专属名", "ingredients": reversed_formula, "price": 57}]
	_check(not DrinkFormula.evaluate(FORMULA, inventory.get_definition, priced_signature).ok, "Signature entries carrying a price are rejected")
	_check(DrinkFormula.evaluate(SWEET, inventory.get_definition, rules).signature_id.is_empty(), "Nearby ingredients never partially match a signature")
	_check(RULES.signatures.is_empty(), "Production signature data remains empty")
	var unknown_cost := DrinkFormula.evaluate(FORMULA, func(id: String) -> IngredientDefinition:
		var definition := inventory.get_definition(id)
		if id == BASE:
			definition.market_price = -1
		return definition, RULES)
	_check(unknown_cost.ok and unknown_cost.cost == null and "单杯成本：未知" in DrinkFormula.describe(unknown_cost), "Unknown market cost remains unknown instead of becoming free")
	_check(inventory.get_definition(BASE).market_price >= 0, "Unknown-cost calculation does not mutate catalog definitions")
	rules.signatures.append(rules.signatures[0].duplicate(true))
	_check(not DrinkFormula.evaluate(FORMULA, inventory.get_definition, rules).ok, "Duplicate signature recipes reject before a product is created")
	var copy := signature.duplicate(true)
	copy.throw.effects.toxic.repel = false
	_check(RULES.throw_tuning.effects.toxic.repel, "Result dictionaries cannot mutate shared tuning")
	inventory.free()

func _test_ice() -> void:
	var state := StateData.new()
	var inventory := state.get_warehouse_inventory()
	_stock(inventory)
	var normal := inventory.calculate_formula(SWEET)
	var iced := inventory.calculate_formula(SWEET, true, true)
	_check(iced.ok and iced.name == normal.name.trim_suffix("特调") + "冰特调", "Ice is inserted immediately before the base suffix")
	for field: String in ["taste", "flavors", "textures", "effects", "counts", "ingredient_names", "cost", "price", "signature_id", "throw"]:
		_check(iced[field] == normal[field], "Naming-only ice leaves unchanged: " + field)
	for definition: IngredientDefinition in WarehouseInventory.CATALOG.ingredients:
		if not definition.can_be_base or not definition.free_recipe_allowed:
			continue
		var plain := inventory.calculate_formula([definition.id])
		var cold := inventory.calculate_formula([definition.id], true, true)
		_check(cold.ok and cold.name == plain.name.trim_suffix(definition.base_suffix) + "冰" + definition.base_suffix, "Ice naming supports base suffix: " + definition.base_suffix)
	_check(iced.id != normal.id and iced.id == DrinkFormula.key_for(SWEET, true), "Iced and non-iced stock retain independent names and stable IDs")
	_check(DrinkFormula.matches(iced, {"formula": SWEET}) and DrinkFormula.matches(normal, {"formula": SWEET}), "Ice does not change exact ingredient requirements")
	_check(not inventory.calculate_formula([BASE, "ice"]).ok, "Ice cannot be passed as a new ingredient slot through the service API")
	inventory.try_consume({"ice": inventory.get_stock("ice")})
	_check(inventory.get_uses("ice") == 0 and state.get_tea_production().preview_formula(SWEET, 1, true).ok, "Naming-only ice can be selected even with no ice inventory")
	inventory.add_ingredient("ice", 1)
	for choice: Dictionary in inventory.get_formula_choices():
		_check(choice.id != "ice", "Discovered ice never appears among the three ingredient choices")
	var ice_before := inventory.get_uses("ice")
	var mint_before := inventory.get_uses("mint_syrup")
	_price(state, SWEET, "ice.price")
	var production := state.get_tea_production()
	var cup := production.craft_formula(SWEET, 1, "ice.craft", true)
	var other := production.craft_formula(SWEET)
	_check(cup.ok and other.ok and inventory.get_drink_stock(cup.id) == 1 and inventory.get_drink_stock(other.id) == 1, "Serving variants coexist without renaming already crafted stock")
	_check(inventory.get_uses("ice") == ice_before and inventory.get_uses(BASE) == 23 and inventory.get_uses("mint_syrup") == mint_before - 4, "Ice is free while both full three-slot recipes spend their normal ingredient uses")
	var saved := state.to_dict()
	state.start_new_game()
	_check(state.restore_state(saved) == OK and inventory.get_drink_record(cup.id).iced and not inventory.get_drink_record(other.id).iced, "Both ice selections survive complete session restoration")
	for invalid: Variant in ["true", 1, null, false]:
		var broken := saved.duplicate(true)
		broken.business.inventory.encyclopedia[cup.id].iced = invalid
		broken.economy.inventory = broken.business.inventory.duplicate(true)
		_check(state.restore_state(broken) == ERR_INVALID_DATA and state.to_dict() == saved, "Invalid ice type or identity mismatch rejects atomically")
	var legacy := saved.duplicate(true)
	var historical: Array[String] = [BASE, "ice"]
	var historical_id := DrinkFormula.key_for(historical)
	legacy.business.inventory.drinks[historical_id] = 1
	# A pre-2026-10-19 cup: the ice slot is illegal now, so it stays read-only history.
	legacy.business.inventory.encyclopedia[historical_id] = {"ingredients": historical, "discovered_day": 1, "pricing": "legacy_unpriced"}
	legacy.economy.inventory = legacy.business.inventory.duplicate(true)
	_check(state.restore_state(legacy) == OK and inventory.get_drink_stock(historical_id) == 1, "Historical ice-as-ingredient records remain readable without allowing new crafts")
	var encyclopedia: DrinkEncyclopediaPanel = load("res://src/UI/milk_tea/drink_encyclopedia_panel.tscn").instantiate()
	root.add_child(encyclopedia)
	encyclopedia.configure(inventory)
	for index in range(encyclopedia.get_list().item_count):
		if encyclopedia.get_list().get_item_metadata(index) == historical_id:
			encyclopedia.get_list().item_selected.emit(index)
	_check(encyclopedia.get_remake_button().disabled, "Historical ice ingredient recipes explain unavailable remake instead of dropping an ingredient")
	encyclopedia.free()
	var rules: RecipeRules = RULES.duplicate(true)
	rules.signatures = [{"id": "ice_signature", "name": "专属特调", "ingredients": SWEET}]
	var signature := DrinkFormula.evaluate(SWEET, inventory.get_definition, rules, true, true)
	_check(signature.name == "专属冰特调" and signature.signature_id == "ice_signature" and signature.price == 0, "Ice preserves signature matching while applying the name suffix")
	state.free()

func _test_crafting() -> void:
	var state := StateData.new()
	var inventory := state.get_warehouse_inventory()
	_stock(inventory)
	var production := state.get_tea_production()
	_price(state, FORMULA, "craft.price")
	_price(state, SWEET, "craft.sweet.price")
	var observations: Array[bool] = []
	var attempts: Array[bool] = []
	var key := DrinkFormula.key_for(FORMULA)
	inventory.changed.connect(func() -> void:
		observations.append(inventory.get_drink_stock(key) == 2 and inventory.get_drinks(true).size() == 1 and inventory.get_uses(BASE) == 23)
		attempts.append(production.craft_formula(FORMULA).ok)
		attempts.append(state.start_new_game() == OK))
	var completed := production.get_completed_count()
	var first := production.craft_formula(FORMULA, 2, "craft.first")
	_check(first.ok and first.first_discovery and observations == [true] and attempts == [false, false], "Crafting publishes stock, discovery and use costs together and blocks reentry")
	_check(production.get_completed_count() == completed and state.get_transactions().get_balance() == 0 and state.get_variable("shop.orders_completed", 0) == 0, "Free crafting neither advances teaching orders nor earns money")
	var before := state.to_dict()
	_check(not production.craft_formula(FORMULA, 2, "craft.first").ok and state.to_dict() == before, "Replaying a request ID cannot produce or consume twice")
	# Retain the observer, but only its first notification is asserted above.
	var repeat := production.craft_formula([BASE, FORMULA[2], FORMULA[1]])
	_check(repeat.ok and not repeat.first_discovery and inventory.get_drink_stock(key) == 3 and inventory.get_drinks(true).size() == 1, "Reordered additive recipe adds stock without a second encyclopedia entry")
	_check(inventory.get_drink_record(key).ingredients == FORMULA and repeat.name == first.name, "Repeated recipes retain the first discovery's ordered name")
	before = state.to_dict()
	_check(not production.craft_formula(SWEET, 1000, "craft.retry").ok and state.to_dict() == before, "Insufficient uses leave stock, discoveries and request receipts unchanged")
	_check(production.craft_formula(SWEET, 1, "craft.retry").ok, "A failed request remains available for a corrected retry")
	var snapshot := state.to_dict()
	snapshot.business.inventory.drinks[key] = WarehouseInventory.MAX_QUANTITY
	snapshot.economy.inventory = snapshot.business.inventory.duplicate(true)
	_check(state.restore_state(snapshot) == OK, "Large formula inventory is a valid bounded snapshot")
	before = state.to_dict()
	_check(not production.craft_formula(FORMULA).ok and state.to_dict() == before, "Full formula stock never spends uses")
	var detached := inventory.get_drink_record(key)
	detached.ingredients.clear()
	detached.taste.sweetness = 999
	_check(inventory.get_drink_record(key).ingredients == FORMULA and inventory.get_drink_record(key).taste.sweetness == 2, "Drink records are independent copies")
	state.free()

func _test_saves() -> void:
	var state := StateData.new()
	var inventory := state.get_warehouse_inventory()
	_stock(inventory)
	_price(state, SWEET, "save.price")
	var result := state.get_tea_production().craft_formula(SWEET, 1, "save.receipt")
	var saved := state.to_dict()
	_check(saved.schema_version == StateData.SCHEMA_VERSION and saved.business.inventory.schema_version == 6, "Current session schema contains formula inventory v6")
	var file := FileAccess.open("user://verify_free_recipes.save", FileAccess.WRITE)
	file.store_var(saved)
	file.close()
	state.start_new_game()
	file = FileAccess.open("user://verify_free_recipes.save", FileAccess.READ)
	var loaded: Dictionary = file.get_var()
	file.close()
	_check(state.restore_state(loaded) == OK and state.to_dict() == saved, "Complete native file round trip preserves uses, formula stock, encyclopedia and receipts")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://verify_free_recipes.save"))
	_check(not state.get_tea_production().craft_formula(SWEET, 1, "save.receipt").ok, "A production receipt remains effective after restore")
	var baseline := state.to_dict()
	var missing_receipts := baseline.duplicate(true)
	missing_receipts.business.production.erase("formula_requests")
	_check(state.restore_state(missing_receipts) == ERR_INVALID_DATA and state.to_dict() == baseline, "Current session snapshots cannot silently lose production receipts")
	for receipts: Variant in [[], {"save.receipt": false}, {" ": true}]:
		var broken := baseline.duplicate(true)
		broken.business.production.formula_requests = receipts
		_check(state.restore_state(broken) == ERR_INVALID_DATA and state.to_dict() == baseline, "Malformed successful production receipts reject atomically")
	for field: String in ["drinks", "encyclopedia"]:
		var broken := baseline.duplicate(true)
		broken.business.inventory.erase(field)
		broken.economy.inventory = broken.business.inventory.duplicate(true)
		_check(state.restore_state(broken) == ERR_INVALID_DATA and state.to_dict() == baseline, "Missing current inventory data rejects atomically: " + field)
	for quantity: Variant in [-1, true, 1.5, INF, WarehouseInventory.MAX_QUANTITY + 1]:
		var broken := baseline.duplicate(true)
		broken.business.inventory.drinks[result.id] = quantity
		broken.economy.inventory = broken.business.inventory.duplicate(true)
		_check(state.restore_state(broken) == ERR_INVALID_DATA and state.to_dict() == baseline, "Invalid formula quantity rejects atomically")
	var wrong := baseline.duplicate(true)
	wrong.business.inventory.encyclopedia[result.id].ingredients = FORMULA
	wrong.economy.inventory = wrong.business.inventory.duplicate(true)
	_check(state.restore_state(wrong) == ERR_INVALID_DATA and state.to_dict() == baseline, "Recipe identities are checked against saved ingredient lists")
	var legacy := baseline.duplicate(true)
	legacy.schema_version = 3
	legacy.business.production.erase("formula_requests")
	# A real v3 session predates the pricing ledger, so the receipts leave with it.
	legacy.economy.schema_version = 1
	legacy.economy.erase("recipe_prices")
	legacy.economy.erase("signature_rewards")
	legacy.economy.erase("formula_crafts")
	for old: Dictionary in [legacy.business.inventory, legacy.economy.inventory]:
		old.schema_version = 2
		old.erase("drinks")
		old.erase("encyclopedia")
	var original := legacy.duplicate(true)
	var used: int = legacy.business.inventory.ingredients.mint_syrup.used
	_check(state.restore_state(legacy) == OK and inventory.get_drinks(true).is_empty() and inventory.to_dict().ingredients.mint_syrup.used == used and legacy == original, "v3 migration preserves open portions and invents no dynamic recipes")
	var restored: Array[bool] = []
	state.state_restored.connect(func() -> void: restored.append(true))
	_check(state.restore_state(legacy) == OK and restored.is_empty(), "Repeated legacy migration restores silently")
	_check(state.start_new_game() == OK and inventory.get_drinks(true).is_empty(), "Explicit new game clears formula stock and encyclopedia")
	state.free()
	# An older four-slot snapshot remains readable, but cannot create new cups.
	var wide_menu: TeaMenu = WarehouseInventory.CATALOG.duplicate(true)
	wide_menu.recipe_rules = RULES.duplicate(true)
	wide_menu.recipe_rules.slot_count = 4
	var wide := WarehouseInventory.new(wide_menu)
	_stock(wide)
	var long_recipe: Array[String] = [BASE, "mint_syrup", "mint_syrup", "mint_syrup"]
	var long_id := DrinkFormula.key_for(long_recipe)
	var historical := wide.to_dict()
	historical.drinks[long_id] = 1
	historical.encyclopedia[long_id] = {"ingredients": long_recipe, "discovered_day": 1, "pricing": "legacy_unpriced"}
	var narrow := WarehouseInventory.new()
	_check(narrow.restore_state(historical) == OK and narrow.get_drink_stock(long_id) == 1 and narrow.get_drink_record(long_id).ingredients == long_recipe, "The three-slot limit preserves historical stock and IDs")
	_check(not narrow.preview_formula(long_recipe).ok and not wide.try_make_formula(long_recipe).ok, "Neither default nor expanded configuration can craft a fourth ingredient")
	var production := TeaProduction.new()
	production.configure(wide)
	var panel: FreeCraftingPanel = load("res://src/UI/milk_tea/free_crafting_panel.tscn").instantiate()
	root.add_child(panel)
	panel.configure(production)
	_check(panel.get_slots().size() == 3 and not panel.select_formula(long_recipe), "Expanded configuration still shows only three UI slots and cannot refill a fourth")
	panel.free()
	production.free()
	wide.free()
	narrow.free()

func _task(requirement: Dictionary, money: int = -1) -> Dictionary:
	var task := {"id": "test.free_order", "type": "commission", "title": "测试饮品订单", "description": "按要求交付一杯饮品。",
		"activate_when": {"type": "flag", "key": "test.order.active"}, "complete_when": {"type": "flag", "key": "test.order.done"},
		"objectives": [{"id": "deliver", "text": "交付饮品", "complete_when": {"type": "flag", "key": "test.order.done"}}],
		"delivery": {"order_id": "free_order", "target_object_id": "fat_goblin", "drink": requirement}}
	if money >= 0:
		task["rewards"] = {"text": "测试固定货款", "money": money}
	return {"version": 1, "tasks": [task]}

func _test_schema() -> void:
	var catalog := TaskCatalog.new()
	var data := _task({"base_id": BASE, "flavors": ["薄荷"], "minimum_taste": {"sweetness": 8}})
	_check(catalog.load_json(JSON.stringify(data)) == OK, "Task schema accepts base, required tags and minimum tastes")
	var valid := catalog.get_tasks()
	for requirement: Variant in [{}, [], {"unknown": true}, {"base_id": "bad id"}, {"formula": []}, {"formula": [BASE, true]}, {"flavors": "薄荷"}, {"effects": []}, {"textures": ["丝滑", "丝滑"]}, {"minimum_taste": {"sweetness": true}}, {"minimum_taste": {"sweetness": -1}}, {"minimum_taste": {"unknown": 3}}]:
		var broken := data.duplicate(true)
		broken.tasks[0].delivery.drink = requirement
		_check(catalog.load_json(JSON.stringify(broken)) == ERR_INVALID_DATA and catalog.get_tasks() == valid, "Invalid formula requirement preserves the live task catalog")
	data.tasks[0].delivery["product_id"] = "pearl_milk_tea"
	_check(catalog.load_json(JSON.stringify(data)) == ERR_INVALID_DATA, "Static, material and dynamic requirements remain mutually exclusive")

func _test_delivery() -> void:
	for price: int in [-1, 0, 37]:
		var state := StateData.new()
		var inventory := state.get_warehouse_inventory()
		_stock(inventory)
		var production := state.get_tea_production()
		var unit := _price(state, SWEET, "delivery.price%d" % price)
		_price(state, FORMULA, "delivery.formula%d" % price)
		var cup := production.craft_formula(SWEET, 1, "", price == 0)
		var other := production.craft_formula(FORMULA)
		var requirement := {"formula": [BASE, "mint_syrup", "mint_syrup"], "base_id": BASE, "flavors": ["薄荷"], "minimum_taste": {"sweetness": 8}}
		var catalog := TaskCatalog.new()
		_check(catalog.load_json(JSON.stringify(_task(requirement, price))) == OK, "Formula delivery task loads")
		var journal := TaskJournal.new()
		journal.configure(catalog, state)
		var delivery := TaskDelivery.new()
		_check(delivery.configure(catalog, journal, state, inventory) == OK, "Formula deliveries use the canonical session inventory")
		var before := state.to_dict()
		_check(not delivery.try_submit("free_order", "fat_goblin").ok and state.to_dict() == before, "Unaccepted formula order consumes nothing")
		state.set_flag("test.order.active")
		var view := journal.get_task("test.free_order")
		view.delivery.drink.formula.clear()
		_check(journal.get_task("test.free_order").delivery.drink.formula == SWEET, "Journal formula requirements are independent snapshots")
		before = state.to_dict()
		_check(not delivery.try_submit("free_order", "wrong_npc", cup.id).ok and not delivery.try_submit("free_order", "fat_goblin", other.id).ok and state.to_dict() == before, "Wrong NPC or chosen recipe never consumes another matching cup")
		# An explicit task amount (including 0) overrides the ledger price.
		var expected := unit if price < 0 else price
		var observations: Array[bool] = []
		var reentrant: Array[bool] = []
		state.state_changed.connect(func() -> void:
			observations.append(state.get_flag("test.order.done") and inventory.get_drink_stock(cup.id) == 0 and state.get_transactions().get_balance() == expected)
			reentrant.append(delivery.try_submit("free_order", "fat_goblin").ok)
			reentrant.append(production.craft_formula(SWEET).ok))
		var sold := delivery.deliver_to("fat_goblin")
		_check(sold.ok and sold.money_delta == expected and observations == [true] and reentrant == [false, false], "Cup consumption, formula/default or explicit price, facts and receipts publish atomically")
		_check(inventory.get_drink_stock(other.id) == 1 and inventory.get_drinks(true).size() == 2, "Selling consumes the chosen cup while encyclopedia history and other recipes remain")
		before = state.to_dict()
		_check(not delivery.deliver_to("fat_goblin").ok and state.to_dict() == before, "Repeated order cannot collect another sale")
		delivery.free()
		journal.free()
		state.free()
	var state := StateData.new()
	var inventory := state.get_warehouse_inventory()
	_stock(inventory)
	_price(state, SWEET, "overflow.price")
	var cup := state.get_tea_production().craft_formula(SWEET)
	var catalog := TaskCatalog.new()
	catalog.load_json(JSON.stringify(_task({"base_id": BASE, "flavors": ["薄荷"]})))
	var journal := TaskJournal.new()
	journal.configure(catalog, state)
	var delivery := TaskDelivery.new()
	delivery.configure(catalog, journal, state, inventory)
	state.set_flag("test.order.active")
	state.get_transactions().add_money(WarehouseInventory.MAX_QUANTITY, "full.wallet")
	var before := state.to_dict()
	_check(not delivery.deliver_to("fat_goblin").ok and state.to_dict() == before and inventory.get_drink_stock(cup.id) == 1, "Wallet overflow leaves cup, flags and receipt untouched")
	delivery.free()
	journal.free()
	state.free()
	state = StateData.new()
	inventory = state.get_warehouse_inventory()
	_stock(inventory)
	var unit := _price(state, SWEET, "reward.price")
	cup = state.get_tea_production().craft_formula(SWEET)
	var reward_order := _task({"base_id": BASE})
	reward_order.tasks[0]["rewards"] = {"text": "糖浆", "items": {"syrup": 1}}
	catalog = TaskCatalog.new()
	catalog.load_json(JSON.stringify(reward_order))
	journal = TaskJournal.new()
	journal.configure(catalog, state)
	delivery = TaskDelivery.new()
	delivery.configure(catalog, journal, state, inventory)
	state.set_flag("test.order.active")
	inventory.add_ingredient("syrup", WarehouseInventory.MAX_QUANTITY - inventory.get_stock("syrup"))
	before = state.to_dict()
	_check(not delivery.deliver_to("fat_goblin").ok and state.to_dict() == before, "Full reward stock rejects cup consumption and formula income together")
	inventory.try_consume({"syrup": 1})
	_check(delivery.deliver_to("fat_goblin").ok and inventory.get_drink_stock(cup.id) == 0 and state.get_transactions().get_balance() == unit, "A capacity failure leaves the order available for a successful retry")
	var completed := state.to_dict()
	state.start_new_game()
	_check(state.restore_state(completed) == OK and not delivery.deliver_to("fat_goblin").ok and state.to_dict() == completed, "Restoring a sale preserves the delivery and wallet receipts")
	delivery.free()
	journal.free()
	state.free()

func _capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await _frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/free_recipes")
	root.get_texture().get_image().save_png("res://.godot/free_recipes/" + name + ".png")

func _test_ui() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	var state: StateData = root.get_node("GameState")
	state.start_new_game()
	var game: MainGame = load("res://src/debug/story/legacy_shop.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames()
	var inventory := state.get_warehouse_inventory()
	_stock(inventory)
	_price(state, SWEET, "ui.price")
	inventory.add_ingredient("ice", 2)
	var mint_before := inventory.get_uses("mint_syrup")
	var ice_before := inventory.get_uses("ice")
	var shop := game.get_shop_ui()
	var station: InteractionPoint
	for point: InteractionPoint in game.get_active_level().get_interaction_points():
		if point.interaction_id == &"tea_station":
			station = point
	shop.open(station)
	var panel := shop.get_popup().get_page().get_formula_panel()
	_check(panel.get_slots().size() == 3 and shop.select_formula(SWEET), "Real host populates the configured base and two additive slots")
	var base_image: TextureRect = panel.get_slots()[0].get_parent().get_node("IngredientImage")
	_check(base_image.texture == inventory.get_ingredient_view(BASE).icon, "Selected wine displays its catalog artwork in the real crafting page")
	_check(panel.select_formula([BASE]) and panel.get_slots()[1].get_parent().get_node("IngredientImage").texture == null, "Clearing an additive removes its old artwork")
	inventory.add_ingredient("instant_coffee_concentrate", 1)
	inventory.add_ingredient("creamer_milk_tea_base", 1)
	_check(panel.select_formula(["instant_coffee_concentrate", "creamer_milk_tea_base"]) and panel.get_materials() == ["instant_coffee_concentrate", "creamer_milk_tea_base"] and "咖啡\n" in panel.get_preview().text, "Real UI accepts creamer in an additive slot and previews a coffee name")
	_check(panel.select_formula(["creamer_milk_tea_base", "instant_coffee_concentrate"]) and "奶茶\n" in panel.get_preview().text, "Real UI can exchange the base and additive without excluding either ingredient")
	shop.select_formula(SWEET)
	_check(not panel.get_craft_button().disabled and not "甜度" in panel.get_preview().text, "Selection preview shows flavors and price without internal taste values")
	for option: OptionButton in panel.get_slots():
		for index in range(option.item_count):
			_check(option.get_item_metadata(index) != "day1_griffin_blood", "Story-only blood never enters the free-form selection UI")
			_check(option.get_item_metadata(index) != "ice", "Ice never occupies one of the three ingredient options")
	_check(not panel.is_iced() and panel.get_ice_option().get_item_text(0) == "不加冰" and panel.get_ice_option().get_item_text(1) == "加冰", "Ice is a separate binary option with no ice selected by default")
	panel.get_ice_option().select(1)
	panel.get_ice_option().item_selected.emit(1)
	_check(panel.is_iced() and panel.get_slots().size() == 3 and "冰特调" in panel.get_preview().text, "Selecting ice updates the real preview without consuming an ingredient slot")
	root.size = Vector2i(640, 360)
	await _capture("crafting_640")
	root.size = Vector2i(1280, 720)
	await _capture("crafting_1280")
	root.size = Vector2i(640, 360)
	panel.get_craft_button().pressed.emit()
	var key := DrinkFormula.key_for(SWEET, true)
	_check(inventory.get_drink_stock(key) == 1 and inventory.get_uses("mint_syrup") == mint_before - 2 and not game.get_player().movement_enabled, "UI craft signal follows the real host service and retains the modal movement lock")
	_check(inventory.get_uses("ice") == ice_before and inventory.get_drink_record(key).name.ends_with("冰特调"), "Real host preserves ice in the finished name without spending ice inventory")
	var book: HandbookPanel = game.get_node("PopupLayer/HandbookPanel")
	_check(not book.get_pages().is_tab_hidden(2) and game.get_node("HudLayer/HandbookHUD").visible, "First discovery immediately unlocks the handbook icon and drinks tab")
	shop.close()
	_check(game.get_player().movement_enabled and game.open_drinks() == OK, "Closing the crafting modal restores movement and the first drink unlocks the handbook page")
	var drinks := book.get_drinks_page()
	_check(book.get_pages().current_tab == 2 and drinks.get_list().item_count == 1 and "甜度 8" in drinks.get_details().text, "Encyclopedia displays the formula's six tastes through the shared handbook")
	_check(drinks.get_list().get_item_icon(0) != null and drinks.find_child("DrinkImage", true, false).texture != null, "Discovered free drink has both list and detail artwork")
	await _capture("encyclopedia_640")
	_check(shop.select_formula(SWEET) and not panel.is_iced(), "Selecting a formula without an ice option resets the separate option to no ice")
	var before := state.to_dict()
	drinks.get_remake_button().pressed.emit()
	_check(panel.get_materials() == SWEET and panel.is_iced() and state.to_dict() == before, "Remake restores both the ingredients and ice option without spending uses, selling or crafting remotely")
	root.size = Vector2i(1280, 720)
	await _capture("encyclopedia_1280")
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	root.push_input(cancel, true)
	await _frames()
	_check(not game.get_ui_manager().has_modal() and game.get_player().movement_enabled, "Esc closes the shared encyclopedia and restores movement")
	var saved := state.to_dict()
	game.free()
	await _frames()
	game = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames()
	_check(state.to_dict() == saved and game.open_drinks() == OK, "Scene rebuild preserves formula inventory and encyclopedia access")
	game.get_ui_manager().close_screen(ScreenIds.HANDBOOK)
	game.free()
	await _frames()
	state.start_new_game()
