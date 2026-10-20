extends SceneTree
## Day-two special (goblin) orders: each optional slip must be acceptable while its
## customer stands in the shop, must pay the confirmed formula price instead of a
## flat 3G, and must leave the planned story orders untouched.
var checks := 0
var failures := 0
var _state: Node
var _game: MainGame

const SPECIALS := [
	{"order": "day2_special_sour", "actor": "day2_festival_1", "materials": ["creamer_milk_tea_base", "moss_green"]},
	{"order": "day2_special_herbal", "actor": "day2_elder_1", "materials": ["creamer_milk_tea_base", "insomnia_mushroom"]},
	{"order": "day2_special_wine", "actor": "day2_emissary_0", "materials": ["creamer_milk_tea_base", "goblin_firebrew"]},
	{"order": "day2_special_smoky", "actor": "day2_rumor_1", "materials": ["creamer_milk_tea_base", "scorch_tongue_pepper"]},
	{"order": "day2_special_spicy", "actor": "day2_ordinary_b", "materials": ["creamer_milk_tea_base", "goblin_firebrew", "scorch_tongue_pepper"]},
]

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 4) -> void:
	for i in range(count):
		await process_frame

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/special_orders_%d" % OS.get_process_id())
	_state = root.get_node("GameState")
	_state.start_new_game()
	_state.select_business_profile("day1")
	_state.current_day = 2
	_state.set_story_stage("day2.s02.open")
	_state.set_flag("day2.s02.open")
	_state.set_flag("day2.s04.casino_reward_received")
	change_scene_to_file("res://src/core/main.tscn")
	await scene_changed
	await frames(4)
	_game = current_scene as MainGame
	check(_game != null, "Shop host loads")
	if _game == null:
		_finish()
		return
	var inventory: WarehouseInventory = _state.get_warehouse_inventory()
	var production: TeaProduction = _state.get_tea_production()
	var director := _game.get_actor_director()
	for entry: Dictionary in SPECIALS:
		for id: String in entry.materials:
			inventory.add_ingredient(id, 3)
	# Everyone on stage, so the optional slips are offered while the player is here.
	for entry: Dictionary in SPECIALS:
		var actor := director.get_actor(StringName(entry.actor))
		check(actor != null, "Host registers " + entry.actor)
		if actor != null:
			actor.show()
	await frames()
	# Actors were shown by hand, so the cached board has to be rebuilt once.
	_game.get_order_board().refresh()
	await frames()
	var earned := 0
	for entry: Dictionary in SPECIALS:
		var order_id := str(entry.order)
		var entry_view: Dictionary = _game.get_order_board().get_entry(order_id)
		check(not entry_view.is_empty() and entry_view.get("status") == "available", "Special slip is on the day-two board: " + order_id)
		var board_error: Error = _game.get_task_delivery().accept_order(order_id)
		check(board_error == OK, "Player accepts the special slip: " + order_id)
		if board_error != OK:
			continue
		var materials: Array[String] = []
		materials.assign(entry.materials)
		check(_state.confirm_formula(materials, "special.price." + order_id).get("ok", false), "Formula price is fixed before selling: " + order_id)
		var cup: Dictionary = production.craft_formula(materials, 1, "special.craft." + order_id)
		check(cup.get("ok", false), "Crafting the demanded flavor succeeds: " + order_id)
		if not cup.get("ok", false):
			continue
		var price: int = int(cup.get("price", 0))
		check(price > 3, "A special cup is worth more than a flat 3G order: %s = %dG" % [order_id, price])
		var before: int = _state.get_transactions().get_balance()
		var delivery: Dictionary = _game.get_task_delivery().try_submit(order_id, str(entry.actor), str(cup.id))
		check(delivery.get("ok", false), "Delivery settles at the confirmed price: " + order_id + " " + str(delivery.get("message", "")))
		var paid: int = _state.get_transactions().get_balance() - before
		check(paid == price, "Special order pays its formula price (%s: %dG)" % [order_id, paid])
		check(_state.get_flag("delivery." + order_id + ".completed"), "Delivery receipt is stored: " + order_id)
		earned += paid
	check(earned >= 60, "Five special orders are worth at least 60G in one day (%dG)" % earned)
	print("SPECIAL_ORDERS: %d checks, %d failures (earned %dG)" % [checks, failures, earned])
	quit(0 if failures == 0 else 1)

func _finish() -> void:
	print("SPECIAL_ORDERS: %d checks, %d failures" % [checks, failures])
	quit(1)
