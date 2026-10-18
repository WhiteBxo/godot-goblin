class_name TaskPanel
extends VBoxContainer
## Read-only activity browser page. Facts and reveal rules belong to TaskJournal.
## The page owns no chrome: ModalShell provides the shade, panel, header and close button.

@onready var _list: ItemList = %Entries
@onready var _body: BoxContainer = %Body
@onready var _title: Label = %Title
@onready var _text: RichTextLabel = %Text
@onready var _summary: Label = %Summary

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

func get_entries() -> ItemList:
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
	var list_scroll := _list.get_v_scroll_bar().value
	_list.clear()
	_ids.clear()
	var tasks: Array[Dictionary] = []
	if is_instance_valid(_journal):
		tasks = _journal.get_visible_tasks()
	for task in tasks:
		var label := ("主线 · " if task.type == "main" else "委托 · ") + String(task.title).replace("\n", " ")
		if task.status != "active":
			label = "[" + _status_text(task.status) + "] " + label
		var index := _list.add_item(label)
		_list.set_item_tooltip(index, label if task.status != "active" else task.title)
		_ids.append(task.id)
	var choose_first := _selected_id not in _ids
	if choose_first:
		_selected_id = _ids[0] if not _ids.is_empty() else ""
	_summary.text = "任务记录 · %d" % _ids.size()
	if _ids.is_empty():
		_title.text = "暂无活动任务"
		_title.tooltip_text = ""
		_set_detail("接取任务后，可在这里查看目标、交付对象和奖励。")
		return
	var selected_index := _ids.find(_selected_id)
	_list.select(selected_index) # select() does not emit item_selected.
	if choose_first:
		_list.ensure_current_is_visible.call_deferred()
	else:
		_list.get_v_scroll_bar().set_deferred("value", list_scroll)
	_show_task(tasks[selected_index])

func _number(value: float) -> String:
	return String.num(value).trim_suffix(".0")

func _show_task(task: Dictionary) -> void:
	_title.text = task.title
	_title.tooltip_text = task.title
	if task.status in ["completed", "failed", "expired", "cancelled"]:
		var lines := PackedStringArray([task.description, "", "任务结果：" + _status_text(task.status)])
		var result: Dictionary = task.get("result", {})
		if not result.is_empty():
			lines.append("结算时间：第 %d 天 · %s" % [result.day, "白天" if result.phase == "day" else "夜晚"])
			if not result.reason.is_empty():
				lines.append("原因：" + result.reason)
		_set_detail("\n".join(lines))
		return
	var order := _orders.get_task_entry(task.id) if is_instance_valid(_orders) else {}
	if not order.is_empty():
		var ready: bool = order.ready or order.status == "completed"
		var lines := PackedStringArray([task.description, "", "订单进度",
			("[已完成] " if order.accepted or order.status == "completed" else "[未完成] ") + "接取订单",
			("[已完成] " if ready else "[未完成] ") + "备齐所需物品",
			("[已完成] " if order.status == "completed" else "[未完成] ") + "交付并结算", ""])
		for item: Dictionary in order.items:
			lines.append("%s%s  %d / %d" % ["交付成品：" if not order.product_id.is_empty() else "交付物资：", item.name, item.owned, item.needed])
		lines.append("\n交付对象：" + order.target_name)
		lines.append("下一步：" + order.hint)
		lines.append("\n奖励：" + order.rewards)
		_set_detail("\n".join(lines))
		return
	var lines := PackedStringArray([task.description, "", "目标"])
	for objective: Dictionary in task.objectives:
		var line := ("[已完成] " if objective.completed else "[未完成] ") + String(objective.text)
		if not objective.required:
			line += "（可选）"
		if objective.target != null:
			line += "  %s / %s" % [_number(objective.progress), _number(objective.target)]
		lines.append(line)
	if task.current_objective.is_empty():
		lines.append("目标已达成，等待后续剧情。")
	if not task.delivery.is_empty():
		lines.append("\n交付对象：" + String(_target_names.get(task.delivery.target_object_id, "交付对象待确认")))
		if task.delivery.has("uses"):
			var uses := PackedStringArray()
			for id: String in task.delivery.uses:
				uses.append("%s × %s 次" % [_product_names.get(id, "物资待确认"), _number(task.delivery.uses[id])])
			lines.append("使用物资：" + "、".join(uses))
		elif task.delivery.has("items"):
			var materials := PackedStringArray()
			for id: String in task.delivery.items:
				materials.append("%s × %s" % [_product_names.get(id, "物资待确认"), _number(task.delivery.items[id])])
			lines.append("交付物资：" + "、".join(materials))
		elif task.delivery.has("drink"):
			lines.append("交付饮品：" + DrinkFormula.requirement_text(task.delivery.drink, _product_names))
		else:
			lines.append("交付成品：" + String(_product_names.get(task.delivery.product_id, "成品待确认")))
	lines.append("\n奖励：" + String(task.rewards.get("text", "暂无奖励说明")))
	_set_detail("\n".join(lines))

func _set_detail(content: String) -> void:
	var same_task := _displayed_id == _selected_id
	var scroll := _text.get_v_scroll_bar().value if same_task else 0.0
	if _text.text != content or not same_task:
		_text.text = content
		_text.get_v_scroll_bar().set_deferred("value", scroll)
	_displayed_id = _selected_id

func _select(index: int) -> void:
	if not is_visible_in_tree() or not can_process() or index < 0 or index >= _ids.size():
		return
	_selected_id = _ids[index]
	_refresh()

func _status_text(status: String) -> String:
	return {"completed": "已完成", "failed": "已失败", "expired": "已过期", "cancelled": "已取消"}.get(status, "进行中")
