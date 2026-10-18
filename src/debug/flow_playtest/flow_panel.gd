extends Control
## Nonmodal Debug display. Requests only; business rules belong to the session.

signal action_requested(action: String)

const Fixture = preload("res://src/debug/flow_playtest/flow_fixture.gd")
const Session = preload("res://src/debug/flow_playtest/flow_session.gd")
const ACTIONS := [
	["start", "营业开始"], ["orders", "订单板 · 接单"], ["make", "制作台 · 制作"], ["deliver", "真实交付"],
	["close", "主动关店"], ["buy", "酒馆购买"], ["one", "测试赌场 · 第 1 局"], ["two", "测试赌场 · 第 2 局"],
	["debt", "交酒 · 免除测试债务"], ["storage", "真实仓库"], ["restart", "重新试玩"]]

var _buttons: Dictionary = {}
var _instruction: Label
var _stats: Label
var _log: Label
var _fixture: Label
var _location: Label

func _ready() -> void:
	theme = preload("res://src/resources/ui/game_theme.tres")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 16
	margin.offset_top = 8
	margin.offset_right = -16
	margin.offset_bottom = -8
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_label(column, "独立流程试玩 · TEST", &"Title")
	_label(column, "Debug 专用 · 隔离内存会话 · 测试场景，不读写正式存档", &"Warning")
	_stats = _label(column, "", &"H2")
	_instruction = _label(column, "", &"Success")
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 310
	row.add_child(left)
	_fixture = _label(left, "", &"Hint")
	var grid := GridContainer.new()
	grid.columns = 2
	left.add_child(grid)
	for entry: Array in ACTIONS:
		var button := Button.new()
		button.text = entry[1]
		button.custom_minimum_size = Vector2(152, 24)
		button.pressed.connect(func() -> void: action_requested.emit(entry[0]))
		grid.add_child(button)
		_buttons[entry[0]] = button
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	_location = _label(right, "测试柜台 · 顾客尚未到达", &"Badge")
	var actor_space := Control.new()
	actor_space.custom_minimum_size.y = 78
	actor_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(actor_space)
	_label(right, "最近真实回执", &"H2")
	_log = _label(right, "等待玩家营业开始", &"Hint")

func refresh(session: Session, modal: bool) -> void:
	var stage := session.stage
	var wallet := session.state.get_transactions()
	_stats.text = "测试余额 %d  |  测试债务 %d  |  %s" % [wallet.get_balance(), session.get_test_debt(), "夜晚" if DayPhase.is_night(session.state) else "白天"]
	_instruction.text = session.INSTRUCTIONS[stage]
	_fixture.text = "测试订单：珍珠奶茶 ×1，交付 +%d\n固定净结算：+%d / -%d；首局另奖糖浆 ×1\n免债夹具：交测试酒 ×1 → 免债 %d" % [Fixture.ORDER_REWARD, Fixture.WIN, Fixture.LOSS, Fixture.TEST_DEBT]
	var enabled := {"start": stage == Session.Stage.READY, "orders": stage in [Session.Stage.ORDER, Session.Stage.MAKE, Session.Stage.DELIVER],
		"make": stage == Session.Stage.MAKE, "deliver": stage == Session.Stage.DELIVER, "close": stage == Session.Stage.CLOSE,
		"buy": stage == Session.Stage.TAVERN, "one": stage == Session.Stage.ROUND_ONE, "two": stage == Session.Stage.ROUND_TWO,
		"debt": stage == Session.Stage.DEBT, "storage": true, "restart": stage not in [Session.Stage.ARRIVING, Session.Stage.DEPARTING]}
	for id: String in _buttons:
		_buttons[id].disabled = modal or not enabled[id]
	var quote := wallet.get_product_quote(Fixture.TAVERN_PRODUCT)
	_buttons.buy.text = "测试酒 %d币 · 库存%d" % [quote.unit_price, quote.stock] if quote.ok else "报价不可用"
	_log.text = "\n".join(session.receipts.slice(maxi(0, session.receipts.size() - 4)))
	_location.text = "测试场景 · 酒馆 / 赌场 / 债权人" if stage >= Session.Stage.TAVERN else "测试场景 · 顾客柜台"

func get_button(action: String) -> Button:
	return _buttons.get(action)

func _label(parent: Node, value: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = value
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
