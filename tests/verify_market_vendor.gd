extends SceneTree
## 集市摊主：第一天不搭理人；第二天先出货，点货才开口，买完落账。
var checks := 0
var failures: Array[String] = []
var state: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count := 8) -> void:
	for i in range(count): await physics_frame

func run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/market_vendor_%d" % OS.get_process_id())
	state = root.get_node("GameState")
	await _visit(1)
	await _visit(2)
	print("MARKET_VENDOR: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _visit(day: int) -> void:
	state.reset_state()
	state.select_business_profile("day1")
	if day == 2:
		check(DayPhase.advance_to(state, 1, "night") == OK and DayPhase.advance_to(state, 2, "day") == OK, "Reach day two through real phase transitions")
	state.set_story_stage("day1.s04.wait_taste" if day == 1 else "day2.s03.travel_tavern")
	var game: MainGame = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(game)
	await frames(16)
	state.set_flag("day1.s04.commission_accepted")
	await frames()
	var chapter := game.get_chapter_gameplay()
	var vendor_id := &"market_vendor_2"
	check(chapter.is_market_vendor(vendor_id), "Chapter data knows the stall keeper")
	# Stand where a player would stand: in front of the stall.
	var point := game.get_delivery_point(vendor_id)
	check(point != null, "Vendor keeps an interaction point")
	if point != null:
		game.get_player().teleport_to(point.global_position + Vector2(0, 28))
	await frames()
	if day == 1:
		check(point != null and not point.interaction_enabled, "Day one stalls cannot be talked to")
		check(chapter.open_market_vendor(vendor_id) == ERR_UNAVAILABLE, "Day one stalls refuse to open their goods")
		check(not game.get_ui_manager().is_open(ScreenIds.MARKET_VENDOR), "No stall window on the first day")
		game.free()
		await frames()
		return
	check(chapter.can_trade_with_vendors(), "Day two stalls trade")
	# Press E on the stall: the host route must open the goods, not a dialogue.
	check(game._route_story_interaction(vendor_id) == OK, "Talking to the stall opens its goods")
	await frames(4)
	var popup: MarketVendorPopup = game.get_node("PopupLayer/MarketVendorPopup")
	var offers := popup.get_offers()
	check(offers.item_count == 3, "The stall lists its three goods")
	check(popup.get_pitch_text() == MarketVendorPopup.BROWSING_HINT, "Opening the stall speaks no sales pitch")
	var view := chapter.get_vendor_view(vendor_id)
	var first: Dictionary = view.products[0]
	check(popup.select_product(str(first.id)), "Player can point at a good")
	check(popup.get_pitch_text() == str(first.pitch), "The vendor only speaks for the chosen good")
	check(state.commit_story_transaction("test.stall_wallet", {}, {}, 500) == OK, "Player carries enough for a purchase")
	var money: int = state.get_transactions().get_balance()
	var quote: Dictionary = state.get_transactions().get_product_quote(str(first.id))
	var stock: int = state.get_warehouse_inventory().get_stock(str(quote.item_id))
	var bought: Dictionary = chapter.buy_from_vendor(str(first.id), 1)
	check(bought.get("ok", false), "Buying the chosen good settles: " + str(bought.get("message", "")))
	check(state.get_transactions().get_balance() == money - int(quote.unit_price), "The stall charges the real quote")
	check(state.get_warehouse_inventory().get_stock(str(quote.item_id)) == stock + 1, "The good lands in the shared warehouse")
	# 真实路径：在摊位上按下购买，摊子收起，摊主用其他 NPC 同款对话窗口把那句话说完。
	check(game._route_story_interaction(vendor_id) == OK, "The stall opens again after a sale")
	await frames(4)
	check(popup.select_product(str(first.id)), "Pick a good from the reopened stall")
	popup._buy.pressed.emit()
	await frames(8)
	check(not game.get_ui_manager().is_open(ScreenIds.MARKET_VENDOR), "A settled sale closes the stall before speaking")
	var dialogue: DialogueManager = game.get_dialogue_manager()
	check(dialogue.is_active(), "The keeper keeps talking after the sale")
	if dialogue.is_active():
		var line: Dictionary = dialogue._dialogue["lines"][dialogue.get_current_line_id()]
		check(str(line.get("speaker", "")) == str(view.get("title", "")), "The parting line belongs to that stall keeper")
		check(not str(line.get("text", "")).is_empty(), "The parting line is authored in the stall data")
		dialogue.end_dialogue(true)
	await frames(2)
	var mushroom: Dictionary = {}
	for product: Dictionary in view.products:
		if str(product.id) == "market_insomnia_mushroom":
			mushroom = product
	if not mushroom.is_empty():
		check(str(mushroom.pitch).contains("醒神菇"), "The mushroom keeps its own line")
	game.free()
	await frames()
