class_name TaskHUD
extends HBoxContainer
## Read-only task projection; the host handles navigation and owns the wallet.

signal tasks_requested

@onready var _heading: Label = %Heading
@onready var _title: Label = $TaskCard/Margin/Content/HeadingRow/Title
@onready var _objective: Label = $TaskCard/Margin/Content/Objective
@onready var _sep: Label = $TaskCard/Margin/Content/HeadingRow/Sep
var _journal: TaskJournal
var _orders: OrderBoardModel
var _signature := ""
var _shown := false
## Dialogue, documents and menus own the frame while they are open; the
## objective strip returns afterwards instead of stacking under the shade.
var _obscured := false

func get_task_button() -> Button:
	return $TaskCard/OpenTasks

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
	_connect_journal()
	_connect_orders()
	if not get_viewport().size_changed.is_connected(_resize_card):
		get_viewport().size_changed.connect(_resize_card)
	if is_node_ready():
		_resize_card()
		_refresh()

func _ready() -> void:
	get_task_button().pressed.connect(func() -> void: tasks_requested.emit())
	_objective.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_resize_card()
	_refresh()

func _exit_tree() -> void:
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
	# A block in the corner, not a banner across the top: the day and the task
	# share one line, the objective gets the width to wrap to two. The height is
	# whatever those lines need — the container clamps it to its own minimum, so
	# an empty objective leaves a shorter card instead of a taller empty one.
	var limit := maxf(180.0, get_viewport_rect().size.x * 0.45)
	offset_right = offset_left + minf(252.0, limit)
	# Height follows the wrapped text, so it has to be measured after the label
	# has been shaped at its final width — one frame later, not in the same pass.
	_fit_height.call_deferred()

func _fit_height() -> void:
	var card: Control = $TaskCard
	var height: float = card.get_combined_minimum_size().y
	if height > 0.0 and not is_equal_approx(offset_bottom - offset_top, height):
		offset_bottom = offset_top + height

func get_objective_summary() -> Dictionary:
	return {"title": _title.text, "objective": _objective.text}

func _refresh() -> void:
	if not is_node_ready():
		return
	var task: Dictionary = _journal.get_current_main_task() if is_instance_valid(_journal) else {}
	var entry := _orders.get_tracked_entry() if is_instance_valid(_orders) else {}
	var has_task := not task.is_empty()
	var has_entry := not entry.is_empty()
	visible = not _obscured and (has_task or has_entry)
	$TaskCard.visible = has_task or has_entry
	_heading.text = _day_label()
	# The strip carries one sentence. Orders keep a second line only because the
	# missing amount is a number the player acts on.
	if has_entry and not has_task:
		var others := -1
		for order: Dictionary in _orders.get_entries():
			if order.status == "active":
				others += 1
		_heading.text = "订单" + (" · 另有 %d 单" % others if others > 0 else "")
		_title.text = entry.title
		_objective.text = "还缺：" + entry.missing_text if not entry.missing_text.is_empty() else entry.hint
		_after_refresh()
		return
	if not has_task:
		_title.text = ""
		_objective.text = ""
		_after_refresh()
		return
	var objective: Dictionary = task.current_objective
	if objective.is_empty():
		_title.text = task.title
		_objective.text = "目标已达成，等待后续剧情"
		_after_refresh()
		return
	_title.text = task.title
	_objective.text = str(objective.text)
	if objective.target != null:
		var progress_text := "%s / %s" % [String.num(objective.progress).trim_suffix(".0"), String.num(objective.target).trim_suffix(".0")]
		_objective.text += "  " + progress_text
	_after_refresh()

## The strip opens with where the player is in the run, not with a label that
## repeats itself every frame.
func _day_label() -> String:
	var state := get_node_or_null("/root/GameState")
	if state != null and state.get("current_day") != null:
		return "DAY %d" % int(state.get("current_day"))
	return "当前任务"

## Presentation only: a new objective or a new balance nudges the strip once so
## the change is noticed without taking the pointer away from the world.
func _after_refresh() -> void:
	_sep.visible = not _title.text.is_empty() and not _objective.text.is_empty()
	if visible:
		_resize_card()
	if not visible:
		_shown = false
		modulate.a = 1.0
		return
	if not _shown:
		_shown = true
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.12)
	var signature := "%s|%s|%s" % [_heading.text, _title.text, _objective.text]
	if not _signature.is_empty() and signature != _signature:
		_nudge($TaskCard, Vector2(1.015, 1.015), Vector2(0.0, 0.5))
	_signature = signature

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
