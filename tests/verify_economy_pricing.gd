extends SceneTree
## 2026-10-19 economy contract: tiers, scopes, permanent prices and atomic crafts.
## Fixtures use the IDs actually present in the 10-19 catalog so a rename breaks
## this test instead of silently pricing nothing.

const StateData = preload("res://src/core/game_state.gd")
const DAY1_MENU := "res://src/resources/milk_tea/day1_menu.tres"
const BASIC_MENU := "res://src/resources/milk_tea/basic_menu.tres"
## C01 human base: 0G cost + the fixed 1G human markup.
const BASE := "creamer_milk_tea_base"
## F02 T1 goblin additive: 2G cost + fixed 1G.
const T1 := "sugar_yam"
## F05 T2 goblin base: 4G cost + 2-4G.
const T2 := "goblin_firebrew"
## F06 T4 goblin base: 20G cost + 10-15G.
const T4 := "griffin_amber_wine"
var _checks := 0
var _failures: Array[String] = []
var _state: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)


func _run() -> void:
	_test_catalog()
	_test_pure_quotes()
	_test_confirm_and_craft()
	_test_supply()
	_test_unsafe_pricing()
	_test_snapshot()
	_test_atomic_rewards_and_uses()
	_test_branch_migrations()
	print("ECONOMY_PRICING: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	quit(0 if _failures.is_empty() else 1)


func _menu(path: String = DAY1_MENU) -> TeaMenu:
	return load(path) as TeaMenu


func _test_catalog() -> void:
	for path: String in [BASIC_MENU, DAY1_MENU]:
		var menu := _menu(path)
		var traded: Array[IngredientDefinition] = []
		var by_source := {}
		for ingredient: IngredientDefinition in menu.ingredients:
			if ingredient.economy_scope == "none" or ingredient.source_ids.is_empty():
				continue
			traded.append(ingredient)
			for source: String in ingredient.source_ids:
				by_source[source] = ingredient
		_check(traded.size() == 22, "Twenty-two traded rows are imported: " + path)
		# Every traded row keeps the sheet's five uses, so per-use spending works.
		var uses_ok := true
		for ingredient: IngredientDefinition in traded:
			if ingredient.uses_per_portion != 5:
				uses_ok = false
		_check(uses_ok, "Every traded row keeps five uses: " + path)
		# Standard market prices follow the tier table; humans are free, F09 has none.
		_check(by_source["C01"].market_price == 0 and by_source["C10"].market_price == 0, "Human rows cost 0G: " + path)
		_check(by_source["F01"].market_price == 10 and by_source["F01"].economy_tier == 1, "T1 rows price at 10G: " + path)
		_check(by_source["F05"].market_price == 20 and by_source["F05"].economy_tier == 2, "T2 rows price at 20G: " + path)
		_check(by_source["F03"].economy_tier == 3 and by_source["F04"].economy_tier == 3 and by_source["F12"].economy_tier == 3, "T3 rows follow the 10-19 sheet: " + path)
		_check(by_source["F03"].market_price == 50 and by_source["F12"].market_price == 50, "T3 rows price at 50G: " + path)
		_check(by_source["F06"].economy_tier == 4 and by_source["F10"].economy_tier == 4 and by_source["F11"].economy_tier == 4, "T4 rows follow the 10-19 sheet: " + path)
		_check(by_source["F06"].market_price == 100 and by_source["F11"].market_price == 100, "T4 rows price at 100G: " + path)
		_check(by_source["F09"].economy_tier == 5 and by_source["F09"].economy_scope == "quest", "F09 is T5 and quest-only: " + path)
		_check(by_source["F09"].market_price == -1, "F09 never carries a market price: " + path)
		_check(by_source["F05"].economy_scope == "trade" and by_source["C05"].economy_scope == "trade", "Human and goblin rows are tradable: " + path)
		var rules: EconomyRules = menu.economy_rules
		_check(rules != null and rules.validate(), "Economy table validates: " + path)
		_check(rules.slot_cost(1) == 2 and rules.slot_cost(2) == 4 and rules.slot_cost(3) == 10 and rules.slot_cost(4) == 20 and rules.slot_cost(5) == 40, "Per-use tier costs match the design: " + path)
		_check(rules.markup_range(1) == Vector2i(1, 1) and rules.markup_range(2) == Vector2i(2, 4) and rules.markup_range(5) == Vector2i(20, 30), "Markup ranges are inclusive: " + path)
		_check(rules.human_cup_price == 3 and rules.signature_first_reward == 150, "Flat 3G cups and the 150G first reward: " + path)
		var recipe := _recipe(menu, "classic_boba_milk_tea")
		_check(recipe != null and recipe.sell_price == 3, "H01 sells at the flat 3G price: " + path)
		_check(_recipe(menu, "day1_blood_recipe").sell_price < 0, "Blood special keeps a task-only price: " + path)


func _recipe(menu: TeaMenu, id: String) -> TeaRecipe:
	for recipe: TeaRecipe in menu.recipe_book.recipes:
		if recipe.id == id:
			return recipe
	return null


func _test_pure_quotes() -> void:
	var menu := _menu()
	var inventory := WarehouseInventory.new(menu)
	var rules: EconomyRules = menu.economy_rules
	var lookup := Callable(inventory, "get_definition")
	# A pure human formula is not a goblin free recipe.
	var human := FormulaPricing.range_for([BASE, "brown_sugar_boba"], lookup, rules)
	_check(not human.ok and human.code == "human_only", "Pure human formulas are rejected")
	# F09 is a legal base yet story-only, so it never enters an ordinary quote.
	var blood := FormulaPricing.range_for(["day1_griffin_blood", T1], lookup, rules)
	_check(not blood.ok and blood.code == "restricted", "Quest-only blood cannot be priced")
	var blood_additive := FormulaPricing.range_for([BASE, "day1_griffin_blood"], lookup, rules)
	_check(not blood_additive.ok and blood_additive.code == "restricted", "Base eligibility never lets story-only blood enter an additive slot")
	for materials: Array in [[], [T1, T2], [BASE, T1, T2, T4]]:
		_check(not FormulaPricing.canonical(materials, lookup, 4).ok, "Pricing rejects a missing base, an additive-only first slot and more than three slots")
	var dual_role := FormulaPricing.quote(["instant_coffee_concentrate", BASE, T1], lookup, rules, func(pick_low: int, _pick_high: int) -> int: return pick_low)
	_check(dual_role.ok and FormulaPricing.validate_record(dual_role.record, lookup, rules), "An ordinary base used as an additive produces a valid persistent quote")
	# The documented F05 + C06 + F07 example: 13-17G with two independent T2 markups.
	var example: Array = [T2, "mint_choc_crisp", "red_mottled_wood"]
	var example_range := FormulaPricing.range_for(example, lookup, rules)
	_check(example_range.ok and example_range.minimum == 13 and example_range.maximum == 17, "The design's mixed example spans 13-17G")
	_check(example_range.cost == 8, "The mixed example keeps its 8G standard cost")
	# Duplicate slots keep one slot each, and reordering / ice keeps the price identity.
	var duplicate: Array = [BASE, T1, T1]
	var low := FormulaPricing.quote(duplicate, lookup, rules, func(pick_low: int, _pick_high: int) -> int: return pick_low)
	var high := FormulaPricing.quote(duplicate, lookup, rules, func(_pick_low: int, pick_high: int) -> int: return pick_high)
	_check(low.ok and high.ok, "Both duplicate-slot quotes generate")
	_check(low.record.slot_markups.size() == 3 and low.record.slot_markups[1] == 1, "T1 slots take the fixed 1G markup")
	_check(low.record.selling_price == 1 + 3 + 3 and high.record.selling_price == low.record.selling_price, "Fixed tiers ignore the endpoint picker")
	_check(low.record.slots[1].occurrence == 0 and low.record.slots[2].occurrence == 1, "Duplicate slots get independent occurrences")
	_check(low.record.slot_costs[0] == 0 and low.record.slot_markups[0] == 1, "Human slots cost 0G and add a fixed 1G")
	var ordered_ab := FormulaPricing.quote([BASE, T1, T2], lookup, rules, func(pick_low: int, _pick_high: int) -> int: return pick_low)
	var ordered_ba := FormulaPricing.quote([BASE, T2, T1], lookup, rules, func(pick_low: int, _pick_high: int) -> int: return pick_low)
	_check(ordered_ab.record.recipe_id == ordered_ba.record.recipe_id, "Reordering additives does not change the price identity")
	_check(ordered_ab.record.selling_price == ordered_ba.record.selling_price, "Reordering additives keeps the same total")
	_check(DrinkFormula.key_for(duplicate, true) != DrinkFormula.key_for(duplicate, false), "Iced cups keep a serving variant ID")
	# T2 endpoints are inclusive and stored per slot.
	var t2_low := FormulaPricing.quote([BASE, T2], lookup, rules, func(pick_low: int, _pick_high: int) -> int: return pick_low)
	var t2_high := FormulaPricing.quote([BASE, T2], lookup, rules, func(_pick_low: int, pick_high: int) -> int: return pick_high)
	_check(t2_low.record.selling_price == 7 and t2_high.record.selling_price == 9, "T2 quotes cover both 7G and 9G endpoints")
	# Out-of-range picks are rejected instead of clamping.
	var crafted := FormulaPricing.quote([BASE, T2], lookup, rules, func(_pick_low: int, _pick_high: int) -> int: return 99)
	_check(not crafted.ok and crafted.code == "invalid_markup", "A picker outside the tier range is rejected")
	inventory.free()


func _test_confirm_and_craft() -> void:
	_state = StateData.new(_menu())
	_state.select_business_profile("day1")
	var inventory: WarehouseInventory = _state.get_warehouse_inventory()
	var wallet: WalletTransactions = _state.get_transactions()
	inventory.add_ingredient(BASE, 2)
	inventory.add_ingredient(BASE, 2)
	inventory.add_ingredient(T1, 2)
	inventory.add_ingredient(T2, 2)
	var materials: Array = [BASE, T1, T2]
	# Preview never registers a price and does not consume RNG.
	var before: Dictionary = wallet.to_dict()
	var before_state: Dictionary = _state.to_dict()
	var preview: Dictionary = wallet.preview_formula_price(materials)
	_check(preview.ok and not preview.priced and preview.minimum == 10 and preview.maximum == 12, "Preview shows only the 10-12G range")
	_check(wallet.to_dict() == before, "Preview leaves the ledger untouched")
	var craft_before_price: Dictionary = _state.commit_formula_craft(materials, 1, "craft-before-price")
	_check(not craft_before_price.ok and craft_before_price.code == "unpriced", "Crafting an unpriced formula is rejected")
	_check(_state.to_dict() == before_state, "Rejected craft changes nothing")
	# A fixed RNG makes the first confirmation reproducible.
	_state.set_pricing_rng(_seeded_rng(20261019))
	var confirmed: Dictionary = _state.confirm_formula(materials, "price-1")
	_check(confirmed.ok and not confirmed.replayed, "First confirmation writes a new record")
	var confirmed_price := int(confirmed.record.selling_price)
	_check(confirmed_price >= 10 and confirmed_price <= 12, "The registered price stays inside the tier range")
	var again: Dictionary = _state.confirm_formula(materials, "price-2")
	_check(again.ok and again.replayed and int(again.record.selling_price) == confirmed_price, "A second confirmation returns the saved price")
	_check(wallet.get_balance() == 0, "Confirming a price pays nothing")
	# Iced and reordered variants share the record.
	var reordered_preview: Dictionary = wallet.preview_formula_price([BASE, T2, T1])
	_check(reordered_preview.priced and int(reordered_preview.selling_price) == confirmed_price, "Reordered servings read the same record")
	var stock_before := inventory.get_uses(T2)
	var craft: Dictionary = _state.commit_formula_craft(materials, 1, "craft-1", true)
	_check(craft.ok and craft.selling_price == confirmed_price, "Crafting succeeds with the registered price")
	_check(inventory.get_uses(T2) == stock_before - 1, "Craft spends one use, not a whole portion")
	_check(inventory.get_drink_stock(craft.id) == 1 and craft.priced, "The priced cup enters the shared inventory")
	var repeat: Dictionary = _state.commit_formula_craft(materials, 1, "craft-1")
	_check(not repeat.ok and repeat.code == "duplicate_transaction", "A repeated craft request is rejected")
	inventory.add_ingredient(T2, 1)
	inventory.try_spend_uses({T2: inventory.get_uses(T2)})
	var no_stock: Dictionary = _state.commit_formula_craft(materials, 1, "craft-2")
	_check(not no_stock.ok and no_stock.code == "missing_uses", "Missing uses reject the whole craft")
	_check(wallet.get_formula_price(materials).selling_price == confirmed_price, "A failed craft keeps the saved price")
	var snapshot: Dictionary = _state.to_dict()
	_check(snapshot.schema_version == 8, "Whole-session schema advances to v8")
	_check(snapshot.economy.schema_version == 3, "Economy snapshot advances to v3")
	_check(snapshot.business.inventory.schema_version == 6, "Inventory snapshot advances to v6")
	_check(snapshot.economy.recipe_prices.size() == 1 and snapshot.economy.formula_crafts.size() == 1, "Ledger and craft receipts persist")
	_state.free()
	# The same seed reproduces the same first price; another seed stays in range.
	var other := StateData.new(_menu())
	other.select_business_profile("day1")
	other.get_warehouse_inventory().add_ingredient(T2, 1)
	other.get_warehouse_inventory().add_ingredient(T1, 1)
	other.get_warehouse_inventory().add_ingredient(T4, 1)
	other.set_pricing_rng(_seeded_rng(20261019))
	var repeated: Dictionary = other.confirm_formula(materials, "price-1")
	_check(repeated.ok and int(repeated.record.selling_price) == confirmed_price, "A fixed RNG reproduces the quoted price")
	other.set_pricing_rng(_seeded_rng(1))
	var fresh: Dictionary = other.confirm_formula([BASE, T4], "price-3")
	_check(fresh.ok and int(fresh.record.selling_price) >= 30 and int(fresh.record.selling_price) <= 35, "T4 quotes stay inside 30-35G")
	other.free()


func _test_snapshot() -> void:
	var state := StateData.new(_menu())
	state.select_business_profile("day1")
	var old := state.to_dict()
	old.schema_version = 5
	old.business.inventory.schema_version = 3
	old.economy.schema_version = 1
	for entry: Dictionary in old.economy.inventory.encyclopedia.values():
		entry.erase("pricing")
	old.business.inventory = old.economy.inventory.duplicate(true)
	old.economy.inventory.ingredients["strange_coin"] = {"quantity": 3, "used": 0, "discovered": true, "known_properties": []}
	old.business.inventory.ingredients["strange_coin"] = old.economy.inventory.ingredients["strange_coin"].duplicate(true)
	_check(state.restore_state(old) == OK, "A v5 snapshot with physical coins still restores")
	_check(state.get_transactions().get_balance() == 30, "Coins fold into the wallet at face value once")
	_check(state.get_warehouse_inventory().get_stock("strange_coin") == 0, "Folded coins leave the inventory")
	var migrated: Dictionary = state.to_dict()
	_check(migrated.schema_version == 8 and migrated.economy.schema_version == 3 and migrated.business.inventory.schema_version == 6, "Every schema migrates forward")
	_check(migrated.economy.recipe_prices.is_empty() and migrated.economy.signature_rewards.is_empty(), "Migration invents no price or reward")
	_check(state.restore_state(old) == OK and state.get_transactions().get_balance() == 30, "Repeating the migration cannot credit coins twice")
	for quantity: Variant in [1.5, -1, WalletTransactions.LIMIT]:
		var broken := old.duplicate(true)
		broken.economy.inventory.ingredients.strange_coin.quantity = quantity
		broken.business.inventory = broken.economy.inventory.duplicate(true)
		_check(state.restore_state(broken) != OK and state.to_dict() == migrated, "Invalid or overflowing old coin quantities reject the whole restore")
	for field: String in ["ingredients", "merchant_stock"]:
		var broken := old.duplicate(true)
		if field == "ingredients":
			broken.economy.inventory.ingredients = []
			broken.business.inventory = broken.economy.inventory.duplicate(true)
		else:
			broken.economy.merchant_stock = []
		_check(state.restore_state(broken) != OK and state.to_dict() == migrated, "Malformed old containers reject atomically: " + field)
	state.free()



func _test_supply() -> void:
	var state := StateData.new(_menu())
	state.select_business_profile("day1")
	var inventory: WarehouseInventory = state.get_warehouse_inventory()
	# Human ingredients start at five portions each (five uses per portion).
	for id: String in ["creamer_milk_tea_base", "industrial_green_tea", "mint_syrup", "instant_coffee_concentrate", "brown_sugar_boba", "mint_choc_crisp", "ice", "cocoa_powder", "apple_jam", "strawberry_jam"]:
		_check(inventory.get_stock(id) == 5 and inventory.get_uses(id) == 25, "Human ingredients start at five portions: " + id)
	var wallet: WalletTransactions = state.get_transactions()
	_check(wallet.get_product_quotes().filter(func(q: Dictionary) -> bool: return q.unit_price == 0).size() == 10, "The warehouse offers ten 0G resupply entries")
	var purchase: Dictionary = wallet.purchase("supply_creamer_milk_tea_base", 1, "supply.test")
	_check(purchase.ok and wallet.get_balance() == 0, "A 0G resupply pays nothing")
	_check(inventory.get_uses("creamer_milk_tea_base") == 30, "A whole portion adds five uses")
	_check(not wallet.purchase("supply_creamer_milk_tea_base", 1, "supply.test").ok, "Duplicate supply request is rejected")
	var after_first: Dictionary = state.to_dict()
	var denied: Dictionary = wallet.purchase("day1_griffin_blood", 1, "supply.blood")
	_check(not denied.ok and denied.code == "unknown_product", "F09 has no ordinary purchase entry")
	_check(state.to_dict() == after_first, "A rejected purchase changes nothing")
	state.free()


func _test_unsafe_pricing() -> void:
	var state := StateData.new(_menu())
	state.select_business_profile("day1")
	state.get_warehouse_inventory().add_ingredient(T1, 1)
	var materials: Array = [BASE, T1]
	state.set_story_stage("day1.s05.infiltration")
	DayPhase.enter_night(state)
	var denied: Dictionary = state.confirm_formula(materials, "price-night")
	_check(not denied.ok and denied.code == "unsafe_phase", "Pricing is disabled during infiltration")
	var preview: Dictionary = state.get_transactions().preview_formula_price(materials)
	_check(preview.ok and not preview.priced, "Previews stay available while pricing is blocked")
	_check(DayPhase.enter_day(state) and state.set_story_stage("day2.s01"), "Leaving the unsafe phase succeeds")
	state.complete_event("day1.opening")
	var allowed: Dictionary = state.confirm_formula(materials, "price-day")
	_check(allowed.ok and int(allowed.record.selling_price) == 4, "Pricing resumes after the unsafe phase ends")
	state.free()

func _seeded_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func _test_atomic_rewards_and_uses() -> void:
	var menu := _menu().duplicate(true) as TeaMenu
	menu.recipe_rules.signatures = [{"id": "test_signature", "name": "测试爆品", "ingredients": [BASE, T1], "first_reward": 150}]
	var state := StateData.new(menu)
	var inventory: WarehouseInventory = state.get_warehouse_inventory()
	_check(state.commit_story_transaction("test.partial", {}, {T1: 3}, 50) == OK, "Partial uses and grant commit together")
	_check(inventory.get_uses(T1) == 3 and state.get_transactions().get_balance() == 50, "Three uses are not three portions")
	_check(state.commit_story_transaction("test.partial", {}, {T1: 3}, 50) == ERR_ALREADY_EXISTS, "A replay grants neither uses nor money")
	var before: Dictionary = state.to_dict()
	_check(state.commit_story_transaction("test.failed", {T1: 4}, {}, -10) != OK and state.to_dict() == before, "Failed partial-use payment leaves the entire state unchanged")
	inventory.add_ingredient(BASE, 5)
	_check(state.confirm_formula([BASE, T1], "reward-price").ok, "Fixture price confirms")
	_check(inventory.to_dict().drinks.is_empty() and state.get_transactions().get_balance() == 50, "Confirmation discovers no cup and awards nothing")
	var result: Dictionary = state.commit_formula_craft([BASE, T1], 2, "reward-batch")
	_check(result.ok and result.first_signature and state.get_transactions().get_balance() == 200, "Two-cup batch awards exactly 150G once")
	_check(state.validate_snapshot(state.to_dict()) == OK, "Reward receipt cross-validates with its craft")
	var saved: Dictionary = state.to_dict()
	_check(state.restore_state(saved) == OK and state.commit_formula_craft([BASE, T1], 1, "reward-next", true).ok, "Iced remake works after restore")
	_check(state.get_transactions().get_balance() == 200, "Iced remake cannot claim the reward twice")
	var broken: Dictionary = state.to_dict()
	broken.economy.signature_rewards.test_signature.reward = 151
	_check(state.restore_state(broken) != OK, "A forged reward is rejected")
	broken = state.to_dict()
	var price: Dictionary = broken.economy.recipe_prices.values()[0]
	price.slots[0].cost = 1
	price.slot_costs[0] = 1
	price.slots[0].price += 1
	price.slot_prices[0] += 1
	price.selling_price += 1
	_check(state.restore_state(broken) != OK, "Consistent but forged slot cost is rejected")
	state.free()

func _test_branch_migrations() -> void:
	var menu := _menu().duplicate(true) as TeaMenu
	menu.recipe_rules.signatures = [{"id": "test_signature", "name": "测试爆品", "ingredients": [BASE, T2], "first_reward": 150}]
	var state := StateData.new(menu)
	state.select_business_profile("day1")
	state.get_warehouse_inventory().add_ingredient(T2, 1)
	state.set_pricing_rng(_seeded_rng(19))
	_check(state.confirm_formula([BASE, T2], "migration-price").ok, "Create one permanent random quote for migration")
	var crafted: Dictionary = state.commit_formula_craft([BASE, T2], 1, "migration-craft")
	_check(crafted.ok and crafted.first_signature, "Create a real paid signature discovery")
	var original: Dictionary = state.to_dict()
	var recipe: String = DrinkFormula.key_for([BASE, T2], false)
	var main_branch := original.duplicate(true)
	main_branch.schema_version = 6
	main_branch.economy.schema_version = 2
	main_branch.economy.inventory.schema_version = 4
	main_branch.business.inventory = main_branch.economy.inventory.duplicate(true)
	_check(state.restore_state(main_branch) == OK, "Main branch v6/v2/v4 save migrates")
	_check(state.to_dict().economy.recipe_prices == original.economy.recipe_prices and state.to_dict().economy.signature_rewards == original.economy.signature_rewards, "Main branch retains exact quote and reward receipt")
	for version in [1, 2]:
		var economy_branch := original.duplicate(true)
		economy_branch.schema_version = 7
		economy_branch.economy.schema_version = version
		economy_branch.economy.erase("formula_crafts")
		economy_branch.economy.erase("recipe_prices")
		economy_branch.economy.claimed["signature:test_signature"] = true
		if version == 1:
			economy_branch.economy.erase("signature_rewards")
		else:
			economy_branch.economy.signature_rewards = {"test_signature": {"amount": 150, "request_id": "craft:migration-craft", "recipe_id": recipe}}
		var inventory: Dictionary = economy_branch.economy.inventory
		inventory.schema_version = 5
		inventory["recipe_prices"] = {}
		for id: String in original.economy.recipe_prices:
			var price: Dictionary = original.economy.recipe_prices[id].duplicate(true)
			price["ingredients"] = []
			for slot: Dictionary in price.slots:
				price.ingredients.append(slot.ingredient_id)
			price.erase("slots")
			inventory.recipe_prices[id] = price
		for entry: Dictionary in inventory.encyclopedia.values():
			entry.erase("pricing")
		economy_branch.business.inventory = inventory.duplicate(true)
		_check(state.restore_state(economy_branch) == OK, "Economy branch v%d wallet migrates" % version)
		_check(state.to_dict().economy.recipe_prices == original.economy.recipe_prices, "Migration preserves every original slot price without RNG")
		_check(state.get_transactions().get_balance() == 150 and state.get_warehouse_inventory().get_drink_stock(crafted.id) == 1, "Migration preserves balance and actual crafted cup")
		var restored: Dictionary = state.to_dict()
		_check(state.restore_state(restored) == OK, "Migrated signature receipt survives a second restore")
		_check(state.commit_formula_craft([BASE, T2], 1, "after-migration-%d" % version, true).ok and state.get_transactions().get_balance() == 150, "Migrated reward cannot be paid again by an iced remake")
		var forged := economy_branch.duplicate(true)
		forged.economy.inventory.encyclopedia.clear()
		forged.economy.inventory.drinks.clear()
		forged.business.inventory = forged.economy.inventory.duplicate(true)
		_check(state.restore_state(forged) != OK, "An old claimed flag without discovery evidence is rejected")
		if version == 2:
			forged = economy_branch.duplicate(true)
			forged.economy.signature_rewards.test_signature.recipe_id = "forged"
			_check(state.restore_state(forged) != OK, "An old reward for the wrong priced recipe is rejected")
	state.free()
