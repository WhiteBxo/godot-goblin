extends SceneTree
## Phase 1 contract: generated data, portion uses and complete-session migration.

const MENUS: PackedStringArray = ["res://src/resources/milk_tea/basic_menu.tres", "res://src/resources/milk_tea/day1_menu.tres"]
const ROLES: Dictionary = {"F04": "lure", "F07": "toxic", "F12": "burn", "C10": "corrode", "C03": "paralyze", "F11": "hallucinate", "C08": "burst", "C05": "sticky", "C09": "contagion", "C07": "mine", "F08": "vortex", "F10": "phantom"}
const ITEM := "mint_syrup"
var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	_test_catalog()
	_test_uses()
	_test_inventory_restore()
	_test_wallet()
	_test_session_restore()
	await _test_ui()
	print("RECIPE_DATA: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	quit(0 if _failures.is_empty() else 1)

func _test_catalog() -> void:
	var tuning: ThrowTuning = load("res://src/resources/milk_tea/throw_tuning.tres")
	_check(tuning != null and tuning.effects.size() == 6 and tuning.modifiers.size() == 6, "Tuning loads all twelve roles")
	_check(tuning.effects.lure.pulse_seconds == 1.0 and tuning.effects.toxic.repel and tuning.effects.paralyze.stun, "Day 1 effect data retains lure, repel and stun contracts")
	_check(tuning.modifiers.phantom.silent and tuning.modifiers.phantom.ignore_walls, "Phantom carries silence and wall bypass")
	_check(tuning.max_area_cells >= 1.0 and tuning.max_duration >= tuning.base_duration, "Tuning bounds are usable")
	_check(not tuning.is_known_kind("unknown") and tuning.display_name("unknown").is_empty(), "Unknown roles have no effect or label")
	for path: String in MENUS:
		var inventory := WarehouseInventory.new(load(path))
		var rows := {}
		var roles := 0
		for ingredient: IngredientDefinition in (load(path) as TeaMenu).ingredients:
			for source: String in ingredient.source_ids:
				if not source.begins_with("C") and not source.begins_with("F"):
					continue
				_check(not rows.has(source), "Sheet rows map once: " + source)
				rows[source] = ingredient
				_check(ingredient.uses_per_portion == 5, "New sheet ingredient has five uses: " + source)
				_check(ingredient.get_taste().size() == 6, "All six tastes are available: " + source)
				_check(ingredient.throw_kind == ROLES.get(source, ""), "Only mapped ingredients carry throw roles: " + source)
				if not ingredient.throw_kind.is_empty():
					roles += 1
					_check(tuning.is_known_kind(ingredient.throw_kind) and not tuning.display_name(ingredient.throw_kind).is_empty(), "Mapped role resolves tuning: " + source)
				if ingredient.can_be_base:
					_check(ingredient.base_suffix in IngredientDefinition.BASE_SUFFIXES and ingredient.throw_kind.is_empty(), "Bases keep a naming suffix and carry no throw role: " + source)
		_check(rows.size() == 22 and roles == 12, "Both menus cover 22 ingredients and exactly twelve throw roles")
		_check(rows.F09.market_price == -1 and rows.F09.can_be_base and not rows.F09.free_recipe_allowed and rows.F09.throw_kind.is_empty(), "F09 stays story-only with unknown market price and no throw buff")
		_check(rows.C06.throw_kind.is_empty() and rows.F02.throw_kind.is_empty(), "Unmapped additives cannot stack buffs")
		_check(inventory.get_uses_per_portion("black_tea") == 1 and inventory.get_uses("black_tea") == 12, "Legacy teaching ingredient keeps one use per portion")
		var copy := inventory.get_definition(ITEM)
		copy.recipe_flavors.append("mutated")
		copy.sweetness = 99
		_check(inventory.get_definition(ITEM).sweetness == 3 and not "mutated" in inventory.get_definition(ITEM).recipe_flavors, "New definition fields are independent copies")
		inventory.free()

func _test_uses() -> void:
	var inventory := WarehouseInventory.new()
	var notifications: Array[Dictionary] = []
	inventory.try_consume({"ice": inventory.get_stock("ice")})
	inventory.try_consume({ITEM: inventory.get_stock(ITEM)})
	inventory.add_ingredient(ITEM, 2)
	inventory.changed.connect(func() -> void: notifications.append(inventory.to_dict()))
	_check(inventory.try_spend_uses({ITEM: 2}), "Repeated additive consumes two individual uses")
	var view := inventory.get_ingredient_view(ITEM)
	_check(inventory.get_stock(ITEM) == 2 and view.uses == 8 and view.current_portion_uses == 3, "Two portions retain three current and eight total uses")
	_check(notifications.size() == 1, "Grouped use spending publishes once")
	var before := inventory.to_dict()
	for bad: Variant in [null, [], {}, {ITEM: 0}, {ITEM: -1}, {ITEM: true}, {ITEM: 1.0}, {ITEM: "1"}, {ITEM: 9}, {ITEM: WarehouseInventory.MAX_QUANTITY + 1}, {"unknown": 1}, {ITEM: 1, "ice": 1}]:
		_check(not inventory.try_spend_uses(bad) and inventory.to_dict() == before, "Invalid, undiscovered or insufficient use request is atomic: " + str(bad))
	for bad: Variant in [null, [], {"unknown": 1}, {"pearl_milk_tea": true}]:
		_check(not inventory.try_spend_uses({ITEM: 1}, bad) and inventory.to_dict() == before, "Invalid output never consumes inputs")
	inventory.set_session_locked(true)
	_check(not inventory.try_spend_uses({ITEM: 1}) and inventory.restore_state(before) == ERR_BUSY, "Session replacement lock protects use spending and restore")
	inventory.set_session_locked(false)
	_check(notifications.size() == 1, "Rejected requests never notify")
	_check(inventory.try_spend_uses({ITEM: 5}, {"pearl_milk_tea": 1}) and inventory.get_stock(ITEM) == 1 and inventory.get_uses(ITEM) == 3 and inventory.get_stock("pearl_milk_tea") == 1, "Cross-portion spending and output are visible in one commit")
	_check(inventory.try_spend_uses({ITEM: 3}) and inventory.get_stock(ITEM) == 0 and inventory.to_dict().ingredients[ITEM].used == 0, "Exact exhaustion removes the portion and clears opened state")
	_check(inventory.is_discovered(ITEM), "Exhausted ingredients remain discovered")
	inventory.try_consume({ITEM: inventory.get_stock(ITEM)})
	inventory.add_ingredient(ITEM, 2)
	inventory.try_spend_uses({ITEM: 2})
	inventory.add_ingredient(ITEM, 1)
	_check(inventory.get_stock(ITEM) == 3 and inventory.get_uses(ITEM) == 13, "Restocking preserves the opened portion")
	_check(inventory.try_consume({ITEM: 2}) and inventory.get_stock(ITEM) == 1 and inventory.get_uses(ITEM) == 3, "Legacy whole-portion consumption removes unopened portions first")
	_check(inventory.try_exchange({ITEM: 1}, {ITEM: 1}) and inventory.get_uses(ITEM) == 5, "Removing the last opened portion and gaining a new one clears its spent uses")
	var full := inventory.to_dict()
	full.ingredients[ITEM].quantity = WarehouseInventory.MAX_QUANTITY
	inventory.restore_state(full)
	before = inventory.to_dict()
	_check(inventory.get_uses(ITEM) == int(WarehouseInventory.MAX_QUANTITY) * 5, "Use totals do not overflow the portion limit")
	_check(not inventory.try_spend_uses({ITEM: 1}, {ITEM: 1}) and inventory.to_dict() == before, "Output overflow preserves every input")
	_check(inventory.try_spend_uses({ITEM: 5}, {ITEM: 1}) and inventory.to_dict() == before, "Capacity check accounts for a consumed portion of the same item")
	_check(inventory.try_spend_uses({"black_tea": 1}) and inventory.get_stock("black_tea") == 11, "Single-use teaching items still consume one portion")
	inventory.free()

func _old_inventory(snapshot: Dictionary) -> Dictionary:
	var legacy := snapshot.duplicate(true)
	legacy.schema_version = 1
	legacy.erase("drinks")
	legacy.erase("encyclopedia")
	for entry: Dictionary in legacy.ingredients.values():
		entry.erase("used")
	return legacy

func _test_inventory_restore() -> void:
	var inventory := WarehouseInventory.new()
	inventory.try_consume({ITEM: inventory.get_stock(ITEM)})
	inventory.add_ingredient(ITEM, 2)
	var legacy := _old_inventory(inventory.to_dict())
	var original := legacy.duplicate(true)
	inventory.try_spend_uses({ITEM: 2})
	var partial := inventory.to_dict()
	_check(inventory.restore_state(JSON.parse_string(JSON.stringify(partial))) == OK, "Opened portions survive JSON numeric round trip")
	_check(inventory.get_uses(ITEM) == 8, "Restore retains spent uses")
	_check(inventory.restore_state(legacy) == OK and inventory.get_uses(ITEM) == 10 and legacy == original, "Old whole portions migrate without mutating the caller")
	var valid := inventory.to_dict()
	for used: Variant in [-1, 5, 1.5, true, "1", INF, NAN]:
		var invalid := valid.duplicate(true)
		invalid.ingredients[ITEM].used = used
		_check(inventory.restore_state(invalid) == ERR_INVALID_DATA and inventory.to_dict() == valid, "Invalid spent-use counts reject atomically: " + str(used))
	var empty := valid.duplicate(true)
	empty.ingredients[ITEM].quantity = 0
	empty.ingredients[ITEM].used = 1
	_check(inventory.restore_state(empty) == ERR_INVALID_DATA, "An empty portion cannot be opened")
	var mixed := legacy.duplicate(true)
	mixed.ingredients[ITEM]["used"] = 2
	_check(inventory.restore_state(mixed) == ERR_INVALID_DATA and inventory.to_dict() == valid, "Migration rejects mixed schemas instead of erasing spent uses")
	var missing := valid.duplicate(true)
	missing.ingredients[ITEM].erase("used")
	_check(inventory.restore_state(missing) == ERR_INVALID_DATA, "Current schema must explicitly include used counts")
	inventory.free()

func _test_wallet() -> void:
	var menu: TeaMenu = WarehouseInventory.CATALOG.duplicate(true)
	menu.products = {"mint": {"item_id": ITEM, "price": 0}}
	var wallet := WalletTransactions.new(menu)
	var inventory := wallet.get_inventory()
	inventory.try_consume({ITEM: inventory.get_stock(ITEM)})
	_check(wallet.purchase("mint", 2, "uses.purchase").ok, "Wallet can purchase new five-use portions")
	inventory.try_spend_uses({ITEM: 2})
	_check(wallet.purchase("mint", 1, "uses.restock").ok and inventory.get_uses(ITEM) == 13, "Wallet restocking preserves partial uses")
	var draft := wallet.prepare_delivery({ITEM: 2}, {}, 0, "uses.delivery")
	_check(not draft.is_empty() and draft.inventory.ingredients[ITEM].quantity == 1 and draft.inventory.ingredients[ITEM].used == 2, "Delivery preparation retains the opened portion when unopened ones suffice")
	_check(wallet.restore_state(draft) == OK and inventory.get_uses(ITEM) == 3, "Prepared delivery restores a consistent partial portion")
	draft = wallet.prepare_delivery({ITEM: 1}, {}, 0, "uses.last_delivery")
	_check(wallet.restore_state(draft) == OK and inventory.get_uses(ITEM) == 0, "Last-portion delivery clears the spent counter")
	var legacy := wallet.to_dict()
	legacy.inventory = _old_inventory(legacy.inventory)
	_check(wallet.restore_state(legacy) == OK, "Standalone wallet accepts an old inventory sub-snapshot")
	wallet.free()

func _test_session_restore() -> void:
	var state: Node = load("res://src/core/game_state.gd").new()
	state.select_business_profile("day1")
	var inventory: WarehouseInventory = state.get_warehouse_inventory()
	inventory.try_consume({ITEM: inventory.get_stock(ITEM)})
	inventory.add_ingredient(ITEM, 2)
	inventory.try_spend_uses({ITEM: 2})
	state.set_flag("test.uses", true)
	var partial: Dictionary = state.to_dict()
	var signals_seen: Array[int] = []
	state.state_restored.connect(func() -> void: signals_seen.append(inventory.get_uses(ITEM)))
	inventory.try_spend_uses({ITEM: 1})
	_check(state.restore_state(partial) == OK and signals_seen == [8] and state.get_flag("test.uses"), "Whole-session restore publishes flags and partial uses together")
	var legacy := partial.duplicate(true)
	legacy.schema_version = 3
	legacy.business.inventory = _old_inventory(legacy.business.inventory)
	legacy.economy.inventory = _old_inventory(legacy.economy.inventory)
	var original := legacy.duplicate(true)
	_check(state.restore_state(legacy) == OK and inventory.get_uses(ITEM) == 10 and state.get_business_profile() == "day1", "Existing v3 sessions migrate both inventory copies and preserve the profile")
	_check(state.restore_state(legacy) == OK and signals_seen == [8, 10] and legacy == original, "Repeated legacy restore is silent and input remains unchanged")
	var inconsistent := legacy.duplicate(true)
	inconsistent.business.inventory.ingredients[ITEM].quantity += 1
	var before: Dictionary = state.to_dict()
	_check(state.restore_state(inconsistent) == ERR_INVALID_DATA and state.to_dict() == before, "Mismatched old inventory copies reject before mutation")
	var broken := partial.duplicate(true)
	broken.business.inventory.ingredients[ITEM].used = 5
	broken.economy.inventory = broken.business.inventory.duplicate(true)
	_check(state.restore_state(broken) == ERR_INVALID_DATA and state.to_dict() == before, "Bad nested used count rejects the complete session")
	legacy.schema_version = 2
	legacy.business.erase("profile_id")
	legacy.business.inventory.ingredients.erase("strange_coin")
	legacy.economy.inventory.ingredients.erase("strange_coin")
	_check(state.restore_state(legacy) == OK and state.get_business_profile() == "tutorial" and inventory.get_uses(ITEM) == 10 and inventory.get_stock("strange_coin") == 0, "Older v2 sessions migrate missing coins and portion uses together")
	_check(state.start_new_game() == OK and inventory.get_uses(ITEM) == 25 and inventory.get_uses("black_tea") == 12, "New game resets partial uses and legacy stock")
	state.free()

func _test_ui() -> void:
	var inventory := WarehouseInventory.new()
	inventory.try_consume({ITEM: inventory.get_stock(ITEM)})
	inventory.add_ingredient(ITEM, 2)
	inventory.try_spend_uses({ITEM: 2})
	var panel := WarehousePanel.new()
	root.add_child(panel)
	panel.configure(inventory)
	for index in range(panel.get_list().item_count):
		if panel.get_list().get_item_metadata(index) == ITEM:
			panel.get_list().select(index)
			panel.get_list().item_selected.emit(index)
			_check("本份余 3 次" in panel.get_list().get_item_text(index), "Warehouse list shows the current portion's remaining uses")
	_check("本份剩余 3 次" in panel.get_details().text and "总剩余 8 次" in panel.get_details().text, "Warehouse details distinguish current and total uses")
	inventory.try_spend_uses({ITEM: 3})
	_check("本份剩余 5 次" in panel.get_details().text and "总剩余 5 次" in panel.get_details().text, "Inventory notifications advance the displayed current portion")
	inventory.try_spend_uses({ITEM: 5})
	_check("缺货" in panel.get_details().text and "总剩余 0 次" in panel.get_details().text, "Exhausted ingredient remains visible with zero uses")
	panel.free()
	inventory.free()
	await process_frame
