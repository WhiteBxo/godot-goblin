extends Node
## Debug composition/fixture adapter. Every business step consumes a real result.

signal changed

const Fixture = preload("res://src/debug/flow_playtest/flow_fixture.gd")
const StateData = preload("res://src/core/game_state.gd")
enum Stage { READY, ARRIVING, ORDER, MAKE, DELIVER, DEPARTING, CLOSE, TAVERN, ROUND_ONE, ROUND_TWO, DEBT, COMPLETE, ERROR }
const INSTRUCTIONS := ["点击营业开始", "顾客正在走向柜台…", "打开订单板，接取测试订单", "打开制作台，手动制作 1 杯",
	"成品已入库；点击真实交付", "交付已结算；顾客正在离开…", "顾客已离开；请主动关店", "已进入夜晚；购买测试酒",
	"手动结算第 1 局：固定净赢", "手动结算第 2 局：固定净输", "交出刚买的测试酒，免除测试债务", "试玩完成；可查仓库或重新试玩", "流程失败；请重新试玩"]

var state: StateData
var journal: TaskJournal
var delivery: TaskDelivery
var orders: OrderBoardModel
var stage: Stage = Stage.READY
var receipts: Array[String] = []
var _arrive: Callable
var _depart: Callable

func configure(arrive: Callable, depart: Callable) -> void:
	_arrive = arrive
	_depart = depart
	state = StateData.new(Fixture.menu())
	state.name = "IsolatedTestState"
	add_child(state)
	var catalog := Fixture.catalog()
	journal = TaskJournal.new()
	add_child(journal)
	var error := journal.configure(catalog, state)
	assert(error == OK)
	delivery = TaskDelivery.new()
	add_child(delivery)
	error = delivery.configure(catalog, journal, state, state.get_warehouse_inventory())
	assert(error == OK)
	orders = OrderBoardModel.new()
	add_child(orders)
	orders.configure(catalog, journal, state, state.get_warehouse_inventory(), state.get_tea_production(), delivery)
	orders.set_target_names({Fixture.CUSTOMER: "测试顾客", Fixture.CREDITOR: "测试债权人"})

func start_business() -> void:
	if stage != Stage.READY:
		return
	_advance(Stage.ARRIVING, "测试营业开始（手动）")
	var ok: bool = await _arrive.call()
	if not is_inside_tree():
		return
	if not ok or not state.set_flag(Fixture.ARRIVAL):
		_advance(Stage.ERROR, "顾客到达动作失败；未开放接单")
		return
	_advance(Stage.ORDER, "ActorAction：测试顾客真实到达柜台")

func accept_order(id: String) -> void:
	if stage == Stage.ORDER and id == Fixture.ORDER and delivery.accept_order(id) == OK:
		_advance(Stage.MAKE, "TaskDelivery：测试订单已接取")

func craft(materials: Array[String], quantity: int) -> Dictionary:
	if stage != Stage.MAKE or quantity != 1:
		return {"ok": false, "message": "本试玩仅制作已接订单的 1 杯。"}
	var result := state.get_tea_production().make_drink(materials, Fixture.ORDER)
	if result.ok:
		_advance(Stage.DELIVER, "TeaProduction：扣除原料、成品入库；尚未交付")
	return result

func submit_delivery() -> void:
	if stage != Stage.DELIVER:
		return
	var result := delivery.try_submit(Fixture.ORDER, Fixture.CUSTOMER)
	if not result.ok:
		_note(result.message)
		return
	_advance(Stage.DEPARTING, "TaskDelivery：消耗成品；测试收入 +%d" % result.money_delta)
	var ok: bool = await _depart.call()
	if is_inside_tree():
		_advance(Stage.CLOSE if ok else Stage.ERROR, "ActorAction：测试顾客已离场" if ok else "离场失败；禁止关店")

func close_business() -> void:
	if stage == Stage.CLOSE and DayPhase.enter_night(state):
		_advance(Stage.TAVERN, "DayPhase：主动关店，白天 → 夜晚")

func purchase() -> void:
	if stage != Stage.TAVERN:
		return
	var result := state.get_transactions().purchase(Fixture.TAVERN_PRODUCT, 1, "test.flow.purchase")
	if result.ok:
		_advance(Stage.ROUND_ONE, "Wallet：测试酒入库；余额 %d" % result.balance)
	else:
		_note(result.message)

func settle_round(index: int) -> void:
	if (index == 1 and stage != Stage.ROUND_ONE) or (index == 2 and stage != Stage.ROUND_TWO) or index not in [1, 2]:
		return
	var wallet := state.get_transactions()
	var result := wallet.claim_reward(Fixture.WIN_REWARD, "test.flow.round_one") if index == 1 else wallet.spend_money(Fixture.LOSS, "test.flow.round_two")
	if result.ok:
		_advance(Stage.ROUND_TWO if index == 1 else Stage.DEBT,
			"Wallet：测试局 %d 净额 %+d；余额 %d" % [index, result.money_delta, result.balance])
	else:
		_note(result.message)

func waive_debt() -> void:
	if stage != Stage.DEBT:
		return
	# No formal debt service exists. The fixture is an item hand-in, using the
	# same atomic delivery/receipt path as real tasks; never set its done flag here.
	if not delivery.is_order_accepted(Fixture.DEBT_ORDER):
		if delivery.accept_order(Fixture.DEBT_ORDER) != OK:
			return
	var result := delivery.try_submit(Fixture.DEBT_ORDER, Fixture.CREDITOR)
	if result.ok:
		_advance(Stage.COMPLETE, "TaskDelivery：测试酒 -1；免除测试债务 %d，回执已写入" % Fixture.TEST_DEBT)
	else:
		_note(result.message)

func get_test_debt() -> int:
	return 0 if state.get_flag("delivery." + Fixture.DEBT_ORDER + ".completed") else Fixture.TEST_DEBT

func _advance(next: Stage, receipt: String) -> void:
	stage = next
	_note(receipt)

func _note(receipt: String) -> void:
	receipts.append(receipt)
	changed.emit()
