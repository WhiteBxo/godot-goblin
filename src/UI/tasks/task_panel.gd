class_name TaskPanel
extends VBoxContainer
## Shared read-only projection, configured by the containing handbook page.
@export_enum("all", "tasks", "milk_orders") var content_filter := "all"
## Read-only activity browser page. Facts and reveal rules belong to TaskJournal.
## The page owns no chrome: ModalShell provides the shade, panel, header and close button.

@onready var _list: TaskList = %Entries
@onready var _body: BoxContainer = %Body
@onready var _kind: Label = %Kind
@onready var _title: Label = %Title
@onready var _text: RichTextLabel = %Text
@onready var _summary: Label = %Summary
@onready var _detail: Control = %Detail

var _journal: TaskJournal
var _orders: OrderBoardModel
var _ids: Array[String] = []
var _selected_id := ""
var _displayed_id := ""
var _target_names: Dictionary = {}
var _product_names: Dictionary = {}

func _enter_tree() -> void:
	_connect_journal()
	if is_instance_valid(_orders) and not _orders.changed.is_connected(_refresh):
		_orders.changed.connect(_refresh)
	if not get_viewport().size_changed.is_connected(_resize_panel):
		get_viewport().size_changed.connect(_resize_panel)
	if is_node_ready():
		_resize_panel()
		_refresh()

func _ready() -> void:
	_list.item_selected.connect(_select)
	_list.item_activated.connect(_select)
	visibility_changed.connect(_on_visibility_changed)
	_resize_panel()
	_refresh()

func _exit_tree() -> void:
	_disconnect_journal()
	if is_instance_valid(_orders) and _orders.changed.is_connected(_refresh):
		_orders.changed.disconnect(_refresh)
	if get_viewport().size_changed.is_connected(_resize_panel):
		get_viewport().size_changed.disconnect(_resize_panel)

func bind_journal(journal: TaskJournal) -> void:
	_disconnect_journal()
	_journal = journal
	_selected_id = ""
	_displayed_id = ""
	if is_inside_tree():
		_connect_journal()
	_refresh()

func bind_orders(orders: OrderBoardModel) -> void:
	if is_instance_valid(_orders) and _orders.changed.is_connected(_refresh):
		_orders.changed.disconnect(_refresh)
	_orders = orders
	if is_instance_valid(_orders):
		_orders.changed.connect(_refresh)
	_refresh()

func set_delivery_names(target_names: Dictionary, product_names: Dictionary) -> void:
	if _target_names == target_names and _product_names == product_names:
		return
	_target_names = target_names.duplicate(true)
	_product_names = product_names.duplicate(true)
	_refresh()

func uses_native_gui_input() -> bool:
	return true

func get_default_focus() -> Control:
	return _list if _list.item_count > 0 else null

func get_entries() -> TaskList:
	return _list

func get_detail_title() -> Label:
	return _title

func get_detail_text() -> RichTextLabel:
	return _text

func get_summary() -> Label:
	return _summary

func get_body() -> BoxContainer:
	return _body

func _connect_journal() -> void:
	if is_instance_valid(_journal) and not _journal.projection_changed.is_connected(_refresh):
		_journal.projection_changed.connect(_refresh)

func _disconnect_journal() -> void:
	if is_instance_valid(_journal) and _journal.projection_changed.is_connected(_refresh):
		_journal.projection_changed.disconnect(_refresh)

func _resize_panel() -> void:
	var narrow := get_viewport_rect().size.x < 480.0
	_body.vertical = narrow
	_list.custom_minimum_size = Vector2(0, 88) if narrow else Vector2(176, 0)
	_list.size_flags_vertical = Control.SIZE_FILL if narrow else Control.SIZE_EXPAND_FILL

func _on_visibility_changed() -> void:
	if is_node_ready() and visible:
		_refresh()

func _refresh() -> void:
	if not is_node_ready():
		return
	# The list is rebuilt row by row, so remember which row held the focus and
	# hand it back afterwards; otherwise a refresh would strand keyboard users.
	var focused_row := _list.focused_row()
	var list_scroll := _list.get_v_scroll_bar().value
	_list.clear()
	_ids.clear()
	var tasks: Array[Dictionary] = []
	if is_instance_valid(_journal):
		tasks = _journal.get_visible_tasks()
	if content_filter != "all":
		tasks = tasks.filter(func(task: Dictionary) -> bool:
			var milk: bool = task.delivery.has("product_id") or task.delivery.has("drink")
			if content_filter == "tasks":
				return not milk
			if not milk:
				return false
			var order := _orders.get_task_entry(task.id) if is_instance_valid(_orders) else {}
			return task.status != "active" or order.get("accepted", false))
	for task in tasks:
		var label := ("" if content_filter == "milk_orders" else ("主线 · " if task.type == "main" else "支线 · ")) + String(task.title).replace("\n", " ")
		# 主线、支线与已结束的任务用不同的行色，扫一眼就能分出轻重。
		var kind := "main" if task.type == "main" else "side"
		if task.status != "active":
			label = "[" + _status_text(task.status) + "] " + label
			kind = "done"
		var index := _list.add_item(label, kind)
		_list.set_item_tooltip(index, label if task.status != "active" else task.title)
		_ids.append(task.id)
	var choose_first := _selected_id not in _ids
	if choose_first:
		_selected_id = _ids[0] if not _ids.is_empty() else ""
	_summary.text = ("奶茶订单 · %d" if content_filter == "milk_orders" else "任务日志 · %d") % _ids.size()
	if _ids.is_empty():
		_title.text = "暂无奶茶订单记录" if content_filter == "milk_orders" else "暂无任务记录"
		_title.tooltip_text = ""
		_kind.visible = false
		_set_detail("已接取与已结束的奶茶订单会保存在这里。" if content_filter == "milk_orders" else "需要完成和已经完成的任务会记录在这里。")
		return
	var selected_index := _ids.find(_selected_id)
	_list.select(selected_index) # select() does not emit item_selected.
	if choose_first:
		_list.ensure_current_is_visible.call_deferred()
	else:
		_list.get_v_scroll_bar().set_deferred("value", list_scroll)
	_show_task(tasks[selected_index])
	if focused_row >= 0:
		_list.focus_row(focused_row)

func _number(value: float) -> String:
	return String.num(value).trim_suffix(".0")

func _show_task(task: Dictionary) -> void:
	_title.text = task.title
	_title.tooltip_text = task.title
	_show_kind(task)
	if task.status in ["completed", "failed", "expired", "cancelled"]:
		_set_detail(_terminal_text(task))
		return
	var order := _orders.get_task_entry(task.id) if is_instance_valid(_orders) else {}
	if not order.is_empty():
		_set_detail(_order_text(task, order))
		return
	_set_detail(_objective_text(task))

## 标题前的类型徽标：主线用金色、支线用暗色，奶茶订单页没有这一栏。
func _show_kind(task: Dictionary) -> void:
	var main: bool = task.type == "main"
	_kind.visible = content_filter != "milk_orders"
	_kind.text = "主线" if main else "支线"
	_kind.theme_type_variation = &"BadgeMain" if main else &"BadgeMuted"

## 已结束的任务只留结论、时间与原因，过程目标不再重复一遍。
func _terminal_text(task: Dictionary) -> String:
	var lines := PackedStringArray()
	if content_filter == "milk_orders":
		var entry := _orders.get_task_entry(task.id) if is_instance_valid(_orders) else {}
		lines.append(TaskText.field("饮品", str(entry.get("title", task.title))))
		lines.append(TaskText.field("顾客", str(entry.get("target_name", "未知顾客"))))
		lines.append("")
		lines.append(TaskText.field("订单状态", _status_text(task.status)))
		lines.append(TaskText.field("报酬", str(entry.get("rewards", task.rewards.get("text", "—"))), true))
	else:
		lines.append(TaskText.paint(String(task.description), TaskText.Tokens.TEXT_DIM))
		lines.append("")
		lines.append(TaskText.verdict("任务结果：已完成" if task.status == "completed" else "任务结果：" + _status_text(task.status)))
	var result: Dictionary = task.get("result", {})
	if not result.is_empty():
		lines.append(TaskText.field("结算时间", "第 %d 天 · %s" % [result.day, "白天" if result.phase == "day" else "夜晚"]))
		if not result.reason.is_empty():
			lines.append(TaskText.field("原因", result.reason))
	return "\n".join(lines)

## 交付型任务先看订单走到哪一步，再看还差什么。
func _order_text(task: Dictionary, order: Dictionary) -> String:
	var ready: bool = order.ready or order.status == "completed"
	var lines := PackedStringArray()
	lines.append(TaskText.paint(String(task.description), TaskText.Tokens.TEXT_DIM))
	lines.append("")
	lines.append(TaskText.section("订单进度"))
	lines.append(TaskText.objective(order.accepted or order.status == "completed", "接取订单"))
	lines.append(TaskText.objective(ready, "备齐所需物品"))
	lines.append(TaskText.objective(order.status == "completed", "交付并结算"))
	lines.append("")
	for item: Dictionary in order.items:
		lines.append(TaskText.field("交付成品" if not order.product_id.is_empty() else "交付物资",
			"%s  %d / %d" % [item.name, item.owned, item.needed]))
	lines.append(TaskText.field("交付对象", str(order.target_name)))
	lines.append(TaskText.field("下一步", str(order.hint)))
	var rewards := str(order.get("rewards", ""))
	if not rewards.is_empty():
		lines.append("")
		lines.append(TaskText.field("奖励", rewards, true))
	return "\n".join(lines)

## 普通任务：目标逐条列出，完成与未完成各有各的颜色，可选目标带标注。
func _objective_text(task: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(TaskText.paint(String(task.description), TaskText.Tokens.TEXT_DIM))
	lines.append("")
	var objectives: Array = task.objectives
	var completed := 0
	for objective: Dictionary in objectives:
		if objective.completed:
			completed += 1
	lines.append(TaskText.section("目标", "已完成 %d / %d" % [completed, objectives.size()]))
	for objective: Dictionary in objectives:
		var progress := ""
		if objective.target != null:
			progress = "%s / %s" % [_number(objective.progress), _number(objective.target)]
		lines.append(TaskText.objective(bool(objective.completed), String(objective.text), not bool(objective.required), progress))
		# 任务指引是“怎么操作”，任务项目是“要做什么”；两者分开写，目标行不混入按键提示。
		var hint := String(objective.get("hint", ""))
		if not hint.is_empty():
			lines.append(TaskText.hint(hint))
	if task.current_objective.is_empty():
		lines.append(TaskText.paint("目标已达成，等待后续剧情。", TaskText.Tokens.ACCENT))
	var fields := PackedStringArray()
	if not task.delivery.is_empty():
		fields.append(TaskText.field("交付对象", String(_target_names.get(task.delivery.target_object_id, "未知"))))
		if task.delivery.has("uses"):
			var uses := PackedStringArray()
			for id: String in task.delivery.uses:
				uses.append("%s × %s 次" % [_product_names.get(id, "未知物资"), _number(task.delivery.uses[id])])
			fields.append(TaskText.field("使用物资", "、".join(uses)))
		elif task.delivery.has("items"):
			var materials := PackedStringArray()
			for id: String in task.delivery.items:
				materials.append("%s × %s" % [_product_names.get(id, "未知物资"), _number(task.delivery.items[id])])
			fields.append(TaskText.field("交付物资", "、".join(materials)))
		elif task.delivery.has("drink"):
			fields.append(TaskText.field("交付饮品", DrinkFormula.requirement_text(task.delivery.drink, _product_names)))
		else:
			fields.append(TaskText.field("交付成品", String(_product_names.get(task.delivery.product_id, "未知成品"))))
	# 没有配置奖励的任务不写奖励行，也不拿占位文案凑数。
	var reward_text := String(task.rewards.get("text", ""))
	if not reward_text.is_empty():
		fields.append(TaskText.field("奖励", reward_text, true))
	if not fields.is_empty():
		lines.append("")
		lines.append_array(fields)
	return "\n".join(lines)

func _set_detail(content: String) -> void:
	var same_task := _displayed_id == _selected_id
	var scroll := _text.get_v_scroll_bar().value if same_task else 0.0
	if _text.text != content or not same_task:
		_text.text = content
		_text.get_v_scroll_bar().set_deferred("value", scroll)
	# Another task opens instead of swapping the words under the eye; a journal
	# refresh of the task already on screen leaves it still.
	if not same_task:
		UIFlourish.reveal(_detail, 0.99)
	_displayed_id = _selected_id

func _select(index: int) -> void:
	if not is_visible_in_tree() or not can_process() or index < 0 or index >= _ids.size():
		return
	# Re-selecting the row that is already open must not rebuild the list: the
	# rows are the focus targets now, and rebuilding would drop the focus.
	if _ids[index] == _selected_id and _displayed_id == _selected_id:
		return
	_selected_id = _ids[index]
	_refresh()

func _status_text(status: String) -> String:
	return {"completed": "已完成", "failed": "已失败", "expired": "已过期", "cancelled": "已取消"}.get(status, "进行中")
