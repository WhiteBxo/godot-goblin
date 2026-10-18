extends SceneTree
## End-to-end UI/service integration, independent of formal maps and story.

const Host = preload("res://src/debug/flow_playtest/flow_playtest.gd")
const Session = preload("res://src/debug/flow_playtest/flow_session.gd")
const Fixture = preload("res://src/debug/flow_playtest/flow_fixture.gd")
const StateData = preload("res://src/core/game_state.gd")
const SCENE := "res://src/debug/flow_playtest/flow_playtest.tscn"
var _checks := 0
var _failures: Array[String] = []
var _host: Host
var _formal: Dictionary
var _captures := false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames() -> void:
	for index in range(4):
		await process_frame

func _capture(id: String) -> void:
	if not _captures:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/goblin_flow_" + id + ".png")

func _button(action: String) -> void:
	var button := _host.panel.get_button(action)
	_check(not button.disabled, "Enabled player action: " + action)
	_click(button)

func _click(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.pressed = pressed
		root.push_input(event, true)

func _wait_stage(stage: Session.Stage) -> void:
	for frame in range(420):
		if _host.session.stage == stage or _host.session.stage == Session.Stage.ERROR:
			break
		await physics_frame
	_check(_host.session.stage == stage, "Actor actions settle before stage %s" % stage)
	await _frames()

func _close_modal() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = &"ui_cancel"
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	await _frames()
	_check(not _host.ui.has_modal(), "Esc closes the real UIManager modal")

func _run() -> void:
	_captures = "--flow-captures" in OS.get_cmdline_user_args()
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	_formal = root.get_node("GameState").to_dict()
	var default_menu: TeaMenu = TeaProduction.CATALOG
	var default_stock := default_menu.initial_stock.duplicate(true)
	_check(default_menu.products.is_empty(), "Formal menu has no fixture products")
	_check(change_scene_to_file(SCENE) == OK, "F6 scene loads")
	await scene_changed
	await _frames()
	_host = current_scene as Host
	if not OS.has_feature("debug"):
		_check(not is_instance_valid(_host), "Release does not construct the Debug host")
		quit(0 if _failures.is_empty() else 1)
		return
	var session := _host.session
	var state := session.state
	var wallet := state.get_transactions()
	var inventory := state.get_warehouse_inventory()
	var defaults := state.to_dict()
	_check(state != root.get_node("GameState") and wallet.get_inventory() == inventory and state.get_tea_production().get_inventory() == inventory, "One isolated state owns the real shared wallet/inventory/production")
	_check(wallet.get_balance() == Fixture.INITIAL_BALANCE and session.get_test_debt() == Fixture.TEST_DEBT, "Central fixture supplies test starting amounts")
	_check(session.stage == Session.Stage.READY and _host.actors.get_actor(StringName(Fixture.CUSTOMER)) == null, "No autoplay before the player starts business")
	for entry: Array in _host.panel.ACTIONS:
		_check(_host.panel.get_button(entry[0]).get_global_rect().end.y <= 356, "Dashboard button fits the 640×360 viewport: " + entry[0])
	_check(_host.panel.get_button("deliver").disabled and _host.panel.get_button("close").disabled, "Premature delivery/closing are visibly disabled")
	session.close_business()
	session.purchase()
	session.settle_round(2)
	session.waive_debt()
	_check(state.to_dict() == defaults, "Out-of-order requests cannot skip the flow")
	await _capture("ready")
	_button("start")
	_check(session.stage == Session.Stage.ARRIVING and not state.get_flag(Fixture.ARRIVAL), "Arrival fact waits for actual movement")
	await _wait_stage(Session.Stage.ORDER)
	var customer := _host.actors.get_actor(StringName(Fixture.CUSTOMER))
	_check(customer.global_position.distance_to(Fixture.COUNTER) < 3 and customer.visible, "Real customer reaches the test counter")
	await _capture("customer")
	_button("orders")
	await _frames()
	_check(_host.shop_ui.is_open() and _host.ui.has_modal() and _host.panel.get_button("close").disabled, "Real order modal locks dashboard actions")
	await _capture("orders")
	await _close_modal()
	_check(session.stage == Session.Stage.ORDER and not session.delivery.is_order_accepted(Fixture.ORDER), "Cancelling the order board accepts nothing")
	_button("orders")
	var board := _host.shop_ui.get_popup().get_page().get_order_board_page()
	_check(board.select_order(Fixture.ORDER), "Real board exposes the fixture order")
	_click(board.get_ticket().get_primary_button())
	_check(session.stage == Session.Stage.MAKE and session.delivery.is_order_accepted(Fixture.ORDER), "Real order board acceptance advances the flow")
	await _close_modal()
	var accepted := state.to_dict()
	_check(not session.delivery.try_submit(Fixture.ORDER, Fixture.CUSTOMER).ok and state.to_dict() == accepted, "Accepted order without a carried cup cannot deliver")
	_button("make")
	await _frames()
	var crafting := _host.shop_ui.get_popup().get_page().get_order_crafting_page()
	_check(crafting.select_order(Fixture.ORDER), "Real crafting page offers the accepted fixture")
	var rejected_materials: Array[String] = ["black_tea"]
	_host.shop_ui.formula_requested.emit(rejected_materials, false)
	_check(state.to_dict() == accepted, "Free formula route cannot bypass the fixed test order or consume its ingredients")
	await _capture("making")
	_click(crafting.get_ticket().get_primary_button())
	_check(session.stage == Session.Stage.DELIVER and inventory.get_stock(Fixture.PRODUCT) == 1, "Crafting UI creates a real carried cup")
	_check(wallet.get_balance() == Fixture.INITIAL_BALANCE and not state.get_flag(Fixture.DELIVERED), "Crafting grants no delivery completion or revenue")
	_check(inventory.get_stock("black_tea") == 1 and inventory.get_stock("syrup") == 1, "Real ingredients are consumed")
	var crafted := state.to_dict()
	_check(not session.delivery.try_submit(Fixture.ORDER, "wrong_target").ok and state.to_dict() == crafted, "Wrong delivery target consumes nothing")
	_check(not session.craft(["black_tea"], 1).ok and state.to_dict() == crafted, "Repeated/stale craft does not alter inventory")
	await _close_modal()
	_button("storage")
	await _frames()
	await _capture("storage")
	await _close_modal()
	_button("deliver")
	_check(session.stage == Session.Stage.DEPARTING and state.get_flag("delivery." + Fixture.ORDER + ".completed"), "Real delivery receipt precedes customer departure")
	_check(wallet.get_balance() == 60 and inventory.get_stock(Fixture.PRODUCT) == 0, "Atomic delivery consumes cup and pays exactly 20 test currency")
	session.submit_delivery()
	_check(not session.delivery.try_submit(Fixture.ORDER, Fixture.CUSTOMER).ok and wallet.get_balance() == 60, "Duplicate delivery cannot pay twice")
	await _wait_stage(Session.Stage.CLOSE)
	_check(not customer.visible and not customer.get_collision_layer_value(3) and not DayPhase.is_night(state), "Customer really leaves; business remains open awaiting player closure")
	_button("close")
	_check(DayPhase.is_night(state) and session.stage == Session.Stage.TAVERN, "Manual close uses real DayPhase transition")
	var quote := wallet.get_product_quote(Fixture.TAVERN_PRODUCT)
	_check(wallet.get_product_quotes() == [quote] and quote.unit_price == 9 and quote.stock == 1, "Latest quote APIs expose fixture price and live stock")
	_check(wallet.spend_money(60, "test.failure.drain").ok, "Prepare a real insufficient-funds condition")
	var empty_wallet := state.to_dict()
	session.purchase()
	_check(session.stage == Session.Stage.TAVERN and state.to_dict() == empty_wallet, "Failed purchase cannot advance or consume merchant stock")
	_check(wallet.add_money(60, "test.failure.refund").ok, "Restore test funds through a real receipt")
	_button("buy")
	_check(wallet.get_balance() == 51 and inventory.get_stock(Fixture.WINE) == 1 and wallet.get_product_quote(Fixture.TAVERN_PRODUCT).stock == 0, "Purchase charges real quote and commits item/live merchant stock")
	var bought := state.to_dict()
	_check(not wallet.purchase(Fixture.TAVERN_PRODUCT, 1, "test.flow.purchase").ok and state.to_dict() == bought, "Repeated purchase is idempotent")
	_button("one")
	_check(wallet.get_balance() == 63 and inventory.get_stock("syrup") == 2, "Fixed first settlement grants real money and item reward")
	var first := state.to_dict()
	_check(not wallet.claim_reward(Fixture.WIN_REWARD, "another.claim").ok and state.to_dict() == first, "Reward cannot be reclaimed under another request ID")
	_button("two")
	_check(wallet.get_balance() == 56 and session.stage == Session.Stage.DEBT, "Second fixed settlement really debits 7")
	session.settle_round(2)
	_check(wallet.get_balance() == 56, "Second round cannot settle twice")
	_button("debt")
	_check(session.stage == Session.Stage.COMPLETE and session.get_test_debt() == 0 and inventory.get_stock(Fixture.WINE) == 0, "Waiver fixture consumes purchased wine through real delivery")
	_check(state.get_flag("delivery." + Fixture.DEBT_ORDER + ".completed") and state.get_flag(Fixture.WAIVED) and wallet.get_balance() == 56, "Debt completion derives from delivery receipt; no extra money awarded")
	var complete := state.to_dict()
	session.waive_debt()
	_check(state.to_dict() == complete, "Waiver cannot execute twice")
	await _frames()
	await _capture("complete")
	_check(root.get_node("GameState").to_dict() == _formal, "Entire flow never changes formal autoload state")
	_check(default_menu.initial_stock == default_stock and default_menu.products.is_empty(), "Fixture never edits the shared formal Resource")
	_check(state.start_new_game() == OK and state.to_dict() == defaults, "Injected session reset retains fixture configuration")
	_check(state.restore_state(complete) == OK and state.to_dict() == complete, "Injected session restores its own complete snapshot")
	_check(reload_current_scene() == OK, "F6 host can be reloaded")
	await scene_changed
	await _frames()
	_host = current_scene as Host
	_check(_host.session.stage == Session.Stage.READY and _host.session.state.to_dict() == defaults, "Replay creates a fresh isolated session")
	_check(root.get_node("GameState").to_dict() == _formal, "Replay preserves formal state")
	# Exit during a live arrival, checking action/subscription cleanup as well.
	_host.session.start_business()
	await physics_frame
	_host.queue_free()
	await _frames()
	_check(root.get_node("GameState").to_dict() == _formal, "Exiting mid-action also leaves formal state untouched")
	print("FLOW_PLAYTEST: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
