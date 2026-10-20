extends SceneTree
## Day-two special (goblin) orders, played the way a player meets them: publish the
## business stage, let the customer walk in, accept the slip, craft the demanded
## flavor, deliver, and check the money lands. Also proves the demand is answerable
## from the settlement's gather points instead of a hand-stocked inventory.
var checks := 0
var failures := 0
var _state: Node
var _game: MainGame

const SPECIALS := [
	{"order": "day2_special_sour", "group": "festival", "actor": "day2_festival_1", "story": true,
		"materials": ["creamer_milk_tea_base", "moss_green"]},
	{"order": "day2_special_herbal", "group": "elder", "actor": "day2_elder_1", "story": true,
		"materials": ["creamer_milk_tea_base", "insomnia_mushroom"]},
	{"order": "day2_special_wine", "group": "emissary", "actor": "day2_emissary_0", "story": true,
		"materials": ["creamer_milk_tea_base", "goblin_firebrew"]},
	{"order": "day2_special_smoky", "group": "rumor", "actor": "day2_rumor_1", "story": true,
		"materials": ["creamer_milk_tea_base", "scorch_tongue_pepper"]},
	{"order": "day2_special_spicy", "group": "ordinary_b", "actor": "day2_ordinary_b", "story": false,
		"materials": ["creamer_milk_tea_base", "goblin_firebrew", "scorch_tongue_pepper"]},
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

func _wait_status(scheduler: BusinessScheduler, group: String, want: String, ms := 12000) -> String:
	var deadline := Time.get_ticks_msec() + ms
	while str(scheduler.get_group(group).get("status")) != want and Time.get_ticks_msec() < deadline:
		await process_frame
	return str(scheduler.get_group(group).get("status"))

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/special_orders_%d" % OS.get_process_id())
	_state = root.get_node("GameState")
	_state.start_new_game()
	_state.select_business_profile("day1")
	_state.current_day = 2
	_state.set_story_stage("day2.s02.open")
	_state.set_flag("day2.s02.open")
	change_scene_to_file("res://src/core/main.tscn")
	await scene_changed
	await frames(6)
	_game = current_scene as MainGame
	check(_game != null, "Shop host loads")
	if _game == null:
		print("SPECIAL_ORDERS: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	var chapter := _game.get_chapter_gameplay()
	check(chapter != null and chapter.get_scheduler() != null, "Day-two business session is configured")
	var scheduler := chapter.get_scheduler()
	var inventory: WarehouseInventory = _state.get_warehouse_inventory()
	var production: TeaProduction = _state.get_tea_production()
	var director := _game.get_actor_director()
	# The demand must be answerable by something a player can actually pick up:
	# settlement gather points, or the day-one gift of 老火烧.
	var gathered := _gathered_items()
	for id: String in ["moss_green", "insomnia_mushroom", "scorch_tongue_pepper"]:
		check(id in gathered, "Settlement gather points yield %s" % id)
	for entry: Dictionary in SPECIALS:
		var unsourced: Array[String] = []
		for id: String in entry.materials:
			if id != "creamer_milk_tea_base" and id not in gathered and id != "goblin_firebrew":
				unsourced.append(id)
		check(unsourced.is_empty(), "Every demanded ingredient has a real source: %s %s" % [entry.order, str(unsourced)])
		for id: String in entry.materials:
			inventory.add_ingredient(id, 2)
	var earned := 0
	for entry: Dictionary in SPECIALS:
		var order_id := str(entry.order)
		var group := str(entry.group)
		# Exactly what the story does: publish the stage, then walk the customer in.
		check(scheduler.publish_stage(_stage_of(group)) == OK, "Publish the business stage for " + group)
		if bool(entry.story):
			scheduler.request_arrival(group)
		check(await _wait_status(scheduler, group, "waiting") == "waiting", "Customer walks in and waits: " + group)
		var actor := director.get_actor(StringName(entry.actor))
		check(actor != null and actor.visible, "The customer who asked stands in the shop: " + entry.actor)
		_game.get_order_board().refresh()
		await frames(2)
		var view: Dictionary = _game.get_order_board().get_entry(order_id)
		check(not view.is_empty() and view.get("status") == "available", "Special slip is offered on the board: " + order_id)
		check(_game.get_task_delivery().accept_order(order_id) == OK, "Player accepts the special slip: " + order_id)
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

func _stage_of(group: String) -> String:
	return "festival" if group in ["festival", "ordinary_a", "ordinary_b", "ordinary_c"] else group

## Reads the settlement map's gather points straight from the scene text, so the
## sourcing check cannot drift when the map is rearranged.
func _gathered_items() -> Array[String]:
	var text := FileAccess.get_file_as_string("res://src/levels/rpg_maker/chapter_cave.tscn")
	var found: Array[String] = []
	var needle := "item_id = \""
	var index := text.find(needle)
	while index >= 0:
		var start := index + needle.length()
		var end := text.find("\"", start)
		if end < 0:
			break
		var id := text.substr(start, end - start)
		if id not in found:
			found.append(id)
		index = text.find(needle, end)
	return found
