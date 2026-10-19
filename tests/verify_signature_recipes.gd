extends SceneTree
## Source-backed signatures: exact servings, fixed sale, clue/experiment rewards,
## zero-stock discovery, cutoff, restore, atomic failure and real map bindings.

const StateData = preload("res://src/core/game_state.gd")
const MENU: TeaMenu = preload("res://src/resources/milk_tea/day1_menu.tres")
const PRICES := [12, 8, 25, 15, 10, 32, 40, 52, 85, 95]
var checks := 0
var failures := 0
var state: Node

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func fresh() -> void:
	if is_instance_valid(state):
		state.free()
	state = StateData.new(MENU)
	root.add_child(state)

func supply(materials: Array) -> void:
	for id: String in materials:
		state.get_warehouse_inventory().add_ingredient(id, 3)

func run() -> void:
	fresh()
	var inventory: WarehouseInventory = state.get_warehouse_inventory()
	var rules := inventory.get_recipe_rules()
	check(rules.signatures.size() == 10, "Ten signatures are available through the shared menu")
	for index in range(10):
		var signature: Dictionary = rules.signatures[index]
		check(signature.id == "S%02d" % (index + 1) and signature.price == PRICES[index] and signature.first_reward == 150, "Source identity, price and bounty: " + signature.id)
		var formula := inventory.calculate_signature_formula(signature.ingredients, signature.iced)
		check(formula.ok and formula.signature_id == signature.id and formula.name == signature.name and formula.price == signature.price, "Exact recipe preserves exclusive name and price: " + signature.id)
		check(formula.appearance == signature.appearance and formula.tasting_note == signature.tasting_note and formula.discovery_note == signature.discovery_note, "All original encyclopedia prose: " + signature.id)
		check(formula.flavors == signature.flavors and formula.textures == signature.textures and formula.effects == signature.effects, "Source tag sets override calculated labels: " + signature.id)
		var wrong_ice := inventory.calculate_signature_formula(signature.ingredients, not signature.iced)
		check(wrong_ice.ok and wrong_ice.signature_id.is_empty() and wrong_ice.price == 0, "Opposite ice serving stays ordinary: " + signature.id)
		var swapped: Array = [signature.ingredients[0], signature.ingredients[2], signature.ingredients[1]]
		check(inventory.calculate_signature_formula(swapped, signature.iced).signature_id == signature.id, "Additive order does not break signature: " + signature.id)
		check(signature.ingredients.size() == 3 and "ice" not in signature.ingredients, "Ice never occupies a slot: " + signature.id)
	# Five empty discovery flows use the explicitly documented trial path.
	for id: String in ["S01", "S02", "S03", "S05", "S09"]:
		fresh()
		var signature: Dictionary = state.get_warehouse_inventory().get_recipe_rules().get_signature(id)
		supply(signature.ingredients)
		var before: int = state.get_transactions().get_balance()
		check(state.confirm_formula(signature.ingredients, "confirm-" + id).ok, "Confirm underlying quote: " + id)
		var crafted: Dictionary = state.commit_formula_craft(signature.ingredients, 2, "craft-" + id, signature.iced)
		check(crafted.ok and crafted.price == signature.price and crafted.selling_price == signature.price, "Craft result uses source price: " + id)
		check(state.get_transactions().get_balance() == before + 150 and crafted.first_signature, "Batch receives only one bounty: " + id)
		var record: Dictionary = state.get_warehouse_inventory().get_drink_record(crafted.id)
		check(record.price == signature.price and record.quantity == 2, "Encyclopedia price and stock agree: " + id)
		check(state.get_transactions().get_drink_sale_price(record) == signature.price, "Sale selects the exclusive price: " + id)
		var preview: Dictionary = state.get_tea_production().preview_formula(signature.ingredients, 1, signature.iced)
		check(preview.price == signature.price and preview.priced, "Preview reads the exclusive price: " + id)
		var repeat: Dictionary = state.commit_formula_craft(signature.ingredients, 1, "repeat-" + id, signature.iced)
		check(repeat.ok and not repeat.first_signature and repeat.money_delta == 0, "Remaking never pays again: " + id)
		var saved: Dictionary = state.to_dict()
		check(state.restore_state(saved) == OK, "Craft snapshot round trip: " + id)
		check(not state.commit_formula_craft(signature.ingredients, 1, "craft-" + id, signature.iced).ok, "Old request cannot replay after restore: " + id)
	_test_clues()
	_test_rescue()
	_test_sale()
	_test_maps()
	state.free()
	print("SIGNATURE_RECIPES: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func _test_clues() -> void:
	for id: String in ["S04", "S07", "S08", "S10"]:
		fresh()
		var inventory: WarehouseInventory = state.get_warehouse_inventory()
		var signature := inventory.get_recipe_rules().get_signature(id)
		if id == "S08":
			check(not state.can_discover_signature(id), "S08 requires the real casino outcome")
			inventory.add_ingredient("rainbow_cube", 1)
			check(not state.can_discover_signature(id), "Finding a cube alone does not forge a casino win")
			state.set_flag("day2.s04.casino_reward_received")
		check(inventory.calculate_formula(signature.ingredients, true, signature.iced).signature_id.is_empty(), "Trial cannot bypass a clue: " + id)
		var balance: int = state.get_transactions().get_balance()
		var discovered: Dictionary = state.discover_signature(id)
		check(discovered.ok, "Authored clue unlocks: " + id)
		check(state.get_transactions().get_balance() == balance + 150, "Clue grants 150G: " + id)
		var drink_id := DrinkFormula.key_for(signature.ingredients, signature.iced)
		check(inventory.get_drink_record(drink_id).price == signature.price and inventory.get_drink_stock(drink_id) == 0, "Discovery records recipe without granting a free cup: " + id)
		check(inventory.get_uses(signature.ingredients[0]) == 0, "Clue does not conjure missing ingredients: " + id)
		check(state.discover_signature(id).get("replayed", false) and state.get_transactions().get_balance() == balance + 150, "Re-reading cannot repay: " + id)
		supply(signature.ingredients)
		var crafted: Dictionary = state.commit_formula_craft(signature.ingredients, 1, "clue-remake-" + id, signature.iced)
		check(crafted.ok and crafted.money_delta == 0 and crafted.price == signature.price, "Craft after clue does not double-pay: " + id)
		var saved: Dictionary = state.to_dict()
		check(state.restore_state(saved) == OK, "Clue and craft restore together: " + id)
		check(state.discover_signature(id).get("replayed", false), "Restored clue remains claimed: " + id)
		var forged: Dictionary = saved.duplicate(true)
		forged.economy.signature_rewards[id].receipt = "discover:S01"
		check(state.restore_state(forged) != OK and state.to_dict() == saved, "Forged discovery receipt rejects whole save: " + id)
	fresh()
	var needed: int = WalletTransactions.LIMIT - state.get_transactions().get_balance()
	check(state.commit_story_transaction("signature_test.cap", {}, {}, needed) == OK, "Set an overflow boundary")
	var before: Dictionary = state.to_dict()
	check(not state.discover_signature("S04").ok and state.to_dict() == before, "Overflow leaves quote, recipe, bounty and wallet unchanged")

func _test_rescue() -> void:
	fresh()
	state.current_day = 2
	check(not state.can_discover_signature("S06"), "S06 is locked before rescue")
	state.get_warehouse_inventory().add_ingredient("insomnia_mushroom", 1)
	check(not state.can_discover_signature("S06"), "Possession does not count as rescue")
	check(state.rescue_signature_patient() == OK, "Day-two rescue spends one mushroom dose")
	check(state.get_warehouse_inventory().get_uses("insomnia_mushroom") == 4, "Rescue retains the other four doses")
	check(state.rescue_signature_patient() != OK and state.get_warehouse_inventory().get_uses("insomnia_mushroom") == 4, "Rescue cannot consume twice")
	check(state.discover_signature("S06").ok, "Rescued patient permits seller clue")
	state.current_day = 3
	var saved: Dictionary = state.to_dict()
	check(state.restore_state(saved) == OK and state.can_discover_signature("S06"), "Timely rescue survives a new day and restore")
	fresh()
	state.current_day = 3
	state.get_warehouse_inventory().add_ingredient("insomnia_mushroom", 2)
	check(state.rescue_signature_patient() != OK and not state.discover_signature("S06").ok, "Late mushrooms cannot reopen S06")
	var procurement := Day2Procurement.new()
	procurement.configure(state)
	state.current_day = 2
	check(procurement.fund() == OK and procurement.hire(Day2Procurement.RUNNERS[0]) == OK, "Day-two runner can be hired")
	check(procurement.get_status().return_day == 2 and procurement.get_status().return_phase == "night", "New runner returns before the source cutoff")
	state.set_variable("world.phase", "night")
	procurement.refresh()
	check(procurement.get_status().status == "returned", "Runner settles a real return on day-two night")
	procurement.free()

func _test_sale() -> void:
	fresh()
	var signature: Dictionary = state.get_warehouse_inventory().get_recipe_rules().get_signature("S02")
	supply(signature.ingredients)
	state.confirm_formula(signature.ingredients, "sale-confirm")
	var crafted: Dictionary = state.commit_formula_craft(signature.ingredients, 1, "sale-craft", false)
	var catalog := TaskCatalog.new()
	var catalog_error := catalog.load_json(JSON.stringify({"version": 1, "tasks": [{"id": "signature_test.order", "type": "commission", "title": "爆品销售", "description": "出售黑糖窟窟厚奶", "reveal_when": {"type": "flag", "key": "signature_test.active"}, "activate_when": {"type": "flag", "key": "signature_test.active"}, "complete_when": {"type": "flag", "key": "delivery.signature_test_sale.completed"}, "objectives": [{"id": "sale", "text": "交付", "complete_when": {"type": "flag", "key": "delivery.signature_test_sale.completed"}}], "delivery": {"order_id": "signature_test_sale", "drink": {"formula": signature.ingredients}, "target_object_id": "signature_test_customer"}}]}))
	check(catalog_error == OK, "Configure a real sale with no reward override")
	if catalog_error != OK:
		return
	state.set_flag("signature_test.active")
	var journal := TaskJournal.new()
	journal.configure(catalog, state)
	var delivery := TaskDelivery.new()
	root.add_child(delivery)
	check(delivery.configure(catalog, journal, state, state.get_warehouse_inventory()) == OK, "Bind sale to the shared wallet")
	var before: int = state.get_transactions().get_balance()
	var result := delivery.deliver_to("signature_test_customer", "signature_test_sale")
	check(result.ok and state.get_transactions().get_balance() == before + 8, "Real delivery pays source S02 price 8G")
	check(state.get_warehouse_inventory().get_drink_stock(crafted.id) == 0, "Sale consumes only the finished cup")
	delivery.free()
	journal.free()

func _test_maps() -> void:
	for entry: Array in [["tavern", "SignatureS04", "S04"], ["casino", "SignatureS07", "S07"], ["elder_house", "SignatureS10", "S10"], ["cave", "SignatureS06", "S06"], ["cave", "SignatureS08", "S08"]]:
		var map: RpgChapterMap = load("res://src/levels/rpg_maker/chapter_" + entry[0] + ".tscn").instantiate()
		root.add_child(map)
		var point: SignatureDiscoveryPoint = map.get_node("Interactions/" + entry[1])
		check(point.signature_id == entry[2] and point in map.get_interaction_points(), "Real map exposes clue through its normal interaction list: " + entry[2])
		var reachable := false
		for offset: Vector2 in [Vector2(0, 48), Vector2(48, 0), Vector2(-48, 0), Vector2(0, -48)]:
			reachable = reachable or map.can_stand_at(point.global_position + offset, Vector2(6, 6))
		check(reachable, "At least one real adjacent floor permits interaction: " + entry[2])
		map.free()
