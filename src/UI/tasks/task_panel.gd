class_name TaskPanel
extends Control
## Read-only activity browser. All facts and reveal rules belong to TaskJournal.

signal close_requested

@onready var _list: ItemList = $Margin/Panel/Margin/Content/Body/Entries
@onready var _body: BoxContainer = $Margin/Panel/Margin/Content/Body
@onready var _title: Label = $Margin/Panel/Margin/Content/Body/Detail/Title
@onready var _text: RichTextLabel = $Margin/Panel/Margin/Content/Body/Detail/Text
@onready var _summary: Label = $Margin/Panel/Margin/Content/Header/Summary
@onready var _close: Button = $Margin/Panel/Margin/Content/Header/Close

var _embedded_close: Button

var _journal: TaskJournal
var _ids: Array[String] = []
var _selected_id := ""
var _displayed_id := ""
var _target_names: Dictionary = {}
var _product_names: Dictionary = {}

func _enter_tree() -> void:
	_connect_journal()
	if not get_viewport().size_changed.is_connected(_resize_panel):
		get_viewport().size_changed.connect(_resize_panel)
	if is_node_ready():
		_resize_panel()
		_refresh()

func _ready() -> void:
	_list.item_selected.connect(_select)
	_list.item_activated.connect(_select)
	_close.pressed.connect(func() -> void: close_requested.emit())
	visibility_changed.connect(_on_visibility_changed)
	_resize_panel()
	_refresh()

func _exit_tree() -> void:
	_disconnect_journal()
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

func set_delivery_names(target_names: Dictionary, product_names: Dictionary) -> void:
	if _target_names == target_names and _product_names == product_names:
		return
	_target_names = target_names.duplicate(true)
	_product_names = product_names.duplicate(true)
	_refresh()

func uses_native_gui_input() -> bool:
	return true

func get_default_focus() -> Control:
	return _list if _list.item_count > 0 else (_embedded_close if is_instance_valid(_embedded_close) else _close)

func _connect_journal() -> void:
	if is_instance_valid(_journal) and not _journal.projection_changed.is_connected(_refresh):
		_journal.projection_changed.connect(_refresh)

func _disconnect_journal() -> void:
	if is_instance_valid(_journal) and _journal.projection_changed.is_connected(_refresh):
		_journal.projection_changed.disconnect(_refresh)

func _resize_panel() -> void:
	var narrow := get_viewport_rect().size.x < 480.0
	_body.vertical = narrow
	_list.custom_minimum_size = Vector2(0, 88) if narrow else Vector2(180, 0)
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
		tasks = _journal.get_active_tasks()
	for task in tasks:
		var label := ("主线 · " if task.type == "main" else "委托 · ") + String(task.title).replace("\n", " ")
		var index := _list.add_item(label)
		_list.set_item_tooltip(index, task.title)
		_ids.append(task.id)
	var choose_first := _selected_id not in _ids
	if choose_first:
		_selected_id = _ids[0] if not _ids.is_empty() else ""
	_summary.text = "活动任务 · %d" % _ids.size()
	if _ids.is_empty():
		_title.text = "暂无活动任务"
		_title.tooltip_text = ""
		_set_detail("接取任务后，可在这里查看目标、交付对象和奖励。")
		if _list.has_focus():
			get_default_focus().grab_focus()
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
		if task.delivery.has("items"):
			var materials := PackedStringArray()
			for id: String in task.delivery.items:
				materials.append("%s × %s" % [_product_names.get(id, "物资待确认"), _number(task.delivery.items[id])])
			lines.append("交付物资：" + "、".join(materials))
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

## Reuse the browser inside a shared modal without nested chrome.
func set_embedded(close_button: Button) -> void:
	_embedded_close = close_button
	$Dim.hide()
	$Margin/Panel/Margin/Content/Header.hide()
	$Margin/Panel/Margin/Content/Hint.hide()
	for side: String in ["left", "top", "right", "bottom"]:
		$Margin.add_theme_constant_override("margin_" + side, 0)
	$Margin/Panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
