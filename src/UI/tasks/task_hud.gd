class_name TaskHUD
extends HBoxContainer
## Read-only task and wallet projections; the host handles navigation.

signal tasks_requested

@onready var _title: Label = $TaskCard/Margin/Content/Title
@onready var _objective: Label = $TaskCard/Margin/Content/Objective
var _journal: TaskJournal
var _orders: OrderBoardModel
var _wallet: WalletTransactions
var _signature := ""
var _balance_text := ""
var _shown := false
## Dialogue, documents and menus own the frame while they are open; the
## objective strip returns afterwards instead of stacking under the shade.
var _obscured := false

func bind_wallet(wallet: WalletTransactions) -> void:
	if is_instance_valid(_wallet) and _wallet.changed.is_connected(_refresh):
		_wallet.changed.disconnect(_refresh)
	_wallet = wallet
	if is_inside_tree():
		_connect_wallet()
	_refresh()

func get_task_button() -> Button:
	return $TaskCard/OpenTasks

func _connect_wallet() -> void:
	if is_instance_valid(_wallet) and not _wallet.changed.is_connected(_refresh):
		_wallet.changed.connect(_refresh)

func set_obscured(value: bool) -> void:
	if _obscured == value:
		return
	_obscured = value
	_refresh()

func bind_orders(orders: OrderBoardModel) -> void:
	if is_instance_valid(_orders) and _orders.changed.is_connected(_refresh):
		_orders.changed.disconnect(_refresh)
	_orders = orders
	if is_inside_tree():
		_connect_orders()
	_refresh()

func bind_journal(journal: TaskJournal) -> void:
	_disconnect_journal()
	_journal = journal
	if is_inside_tree():
		_connect_journal()
	_refresh()

func _enter_tree() -> void:
	_connect_wallet()
	_connect_journal()
	_connect_orders()
	if not get_viewport().size_changed.is_connected(_resize_card):
		get_viewport().size_changed.connect(_resize_card)
	if is_node_ready():
		_resize_card()
		_refresh()

func _ready() -> void:
	get_task_button().pressed.connect(func() -> void: tasks_requested.emit())
	_objective.max_lines_visible = 2
	_objective.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_resize_card()
	_refresh()

func _exit_tree() -> void:
	if is_instance_valid(_wallet) and _wallet.changed.is_connected(_refresh):
		_wallet.changed.disconnect(_refresh)
	_disconnect_journal()
	if is_instance_valid(_orders) and _orders.changed.is_connected(_refresh):
		_orders.changed.disconnect(_refresh)
	if get_viewport().size_changed.is_connected(_resize_card):
		get_viewport().size_changed.disconnect(_resize_card)

func _connect_journal() -> void:
	if is_instance_valid(_journal) and not _journal.projection_changed.is_connected(_refresh):
		_journal.projection_changed.connect(_refresh)

func _connect_orders() -> void:
	if is_instance_valid(_orders) and not _orders.changed.is_connected(_refresh):
		_orders.changed.connect(_refresh)

func _disconnect_journal() -> void:
	if is_instance_valid(_journal) and _journal.projection_changed.is_connected(_refresh):
		_journal.projection_changed.disconnect(_refresh)

func _resize_card() -> void:
	offset_right = offset_left + minf(380.0, maxf(1.0, get_viewport_rect().size.x - 120.0))

func get_objective_summary() -> Dictionary:
	return {"title": _title.text, "objective": _objective.text}

func _refresh() -> void:
	if not is_node_ready():
		return
	$Wallet.visible = is_instance_valid(_wallet)
	if is_instance_valid(_wallet):
		$Wallet/Content/Balance.text = WalletTransactions.format_money(_wallet.get_balance())
	var task: Dictionary = _journal.get_current_main_task() if is_instance_valid(_journal) else {}
	var entry := _orders.get_tracked_entry() if is_instance_valid(_orders) else {}
	visible = not _obscured and (not task.is_empty() or not entry.is_empty() or is_instance_valid(_wallet))
	$TaskCard.visible = not task.is_empty() or not entry.is_empty()
	if not entry.is_empty() and task.is_empty():
		var others := -1
		for order: Dictionary in _orders.get_entries():
			if order.status == "active":
				others += 1
		$TaskCard/Margin/Content/Heading.text = "追踪订单" + (" · 另有 %d 单" % others if others > 0 else "")
		_title.text = entry.title
		_objective.text = "还缺：" + entry.missing_text if not entry.missing_text.is_empty() else entry.hint
		_after_refresh()
		return
	$TaskCard/Margin/Content/Heading.text = "当前任务 · 点击查看 [J]"
	if task.is_empty():
		_title.text = ""
		_objective.text = ""
		_after_refresh()
		return
	_title.text = task.title
	var objective: Dictionary = task.current_objective
	if objective.is_empty():
		_objective.text = "目标已达成，等待后续剧情。"
		_after_refresh()
		return
	_objective.text = objective.text
	if objective.target != null:
		_objective.text += "  %s / %s" % [String.num(objective.progress).trim_suffix(".0"), String.num(objective.target).trim_suffix(".0")]
	_after_refresh()

## Presentation only: a new objective or a new balance nudges the strip once so
## the change is noticed without taking the pointer away from the world.
func _after_refresh() -> void:
	if not visible:
		_shown = false
		modulate.a = 1.0
		return
	if not _shown:
		_shown = true
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.12)
	var signature := "%s|%s|%s" % [$TaskCard/Margin/Content/Heading.text, _title.text, _objective.text]
	if not _signature.is_empty() and signature != _signature:
		_nudge($TaskCard, Vector2(1.015, 1.015), Vector2(0.0, 0.5))
	_signature = signature
	var balance: String = $Wallet/Content/Balance.text
	if not _balance_text.is_empty() and balance != _balance_text:
		_nudge($Wallet, Vector2(1.1, 1.1), Vector2(0.5, 0.5))
	_balance_text = balance

func _nudge(control: Control, scale_to: Vector2, pivot: Vector2) -> void:
	if control.size == Vector2.ZERO:
		return
	if not control.is_inside_tree():
		return
	var previous: Tween = null
	if control.has_meta(&"ui_nudge"):
		previous = control.get_meta(&"ui_nudge") as Tween
	if previous != null and previous.is_valid():
		previous.kill()
	control.pivot_offset = control.size * pivot
	control.scale = Vector2.ONE
	var tween := control.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", scale_to, 0.10)
	tween.tween_property(control, "scale", Vector2.ONE, 0.16)
	control.set_meta(&"ui_nudge", tween)
