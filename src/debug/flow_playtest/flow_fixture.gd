extends RefCounted
## TEST ONLY. All missing business rules and economic values live here.

const ORDER := "test_flow_tea"
const CUSTOMER := "test_flow_customer"
const DEBT_ORDER := "test_flow_waiver"
const CREDITOR := "test_flow_creditor"
const PRODUCT := "pearl_milk_tea"
const TAVERN_PRODUCT := "test_flow_wine"
const WINE := "goblin_firebrew"
const INITIAL_BALANCE := 40
const ORDER_REWARD := 20
const WINE_PRICE := 9
const WIN := 12
const LOSS := 7
const TEST_DEBT := 60
const ARRIVAL := "test.flow.customer_arrived"
const ACCEPTED := "test.flow.tea_accepted"
const DELIVERED := "test.flow.tea_delivered"
const WAIVED := "test.flow.debt_waived"
const WIN_REWARD := "test_flow_round_one"
const CUSTOMER_SCENE := preload("res://src/gameplay/characters/human_customer.tscn")
const DOOR := Vector2(605, 200)
const COUNTER := Vector2(480, 200)
const CUSTOMER_SCALE := Vector2(0.55, 0.55)
const MOVE_SPEED := 100.0

static func menu() -> TeaMenu:
	var result := TeaProduction.CATALOG.duplicate() as TeaMenu
	result.initial_balance = INITIAL_BALANCE
	result.initial_stock = {"black_tea": 2, "creamer": 2, "pearl": 2, "syrup": 2}
	result.orders = [{"id": ORDER, "name": "测试珍珠奶茶", "product_id": PRODUCT, "accepted_flag": ACCEPTED}]
	result.products = {TAVERN_PRODUCT: {"item_id": WINE, "price": WINE_PRICE, "stock": 1}}
	result.transaction_rewards = {WIN_REWARD: {"money": WIN, "items": {"syrup": 1}}}
	return result

static func catalog() -> TaskCatalog:
	var tea := _task("test.flow.tea", "【测试订单】珍珠奶茶 ×1", ACCEPTED, DELIVERED,
		{"order_id": ORDER, "product_id": PRODUCT, "target_object_id": CUSTOMER},
		{"text": "测试收入 %d；真实交付后到账" % ORDER_REWARD, "money": ORDER_REWARD})
	tea.reveal_when = {"type": "flag", "key": ARRIVAL}
	var debt := _task("test.flow.debt", "【测试债务】以测试酒换免除", "test.flow.waiver_accepted", WAIVED,
		{"order_id": DEBT_ORDER, "items": {WINE: 1}, "target_object_id": CREDITOR},
		{"text": "免除测试债务 %d；无正式债务规则" % TEST_DEBT, "money": 0})
	debt.reveal_when = {"type": "flag", "key": DayPhase.NIGHT_FLAG}
	var result := TaskCatalog.new()
	var error := result.load_json(JSON.stringify({"version": 1, "tasks": [tea, debt]}))
	assert(error == OK, result.last_error)
	return result

static func _task(id: String, title: String, active: String, done: String, delivery: Dictionary, rewards: Dictionary) -> Dictionary:
	return {"id": id, "type": "commission", "title": title,
		"description": "仅独立 Debug 流程使用的测试夹具，不代表正式订单、奖励或规则。",
		"activate_when": {"type": "flag", "key": active}, "complete_when": {"type": "flag", "key": done},
		"objectives": [{"id": "deliver", "text": title, "complete_when": {"type": "flag", "key": done}}],
		"delivery": delivery, "rewards": rewards}
