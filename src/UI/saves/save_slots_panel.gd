class_name SaveSlotsPanel
extends UIScreen
## Shared title/paused view. File and session mutations stay in the services.

signal dismissed
signal load_requested(slot_id: String)

var _manager: UIManager
var _id: StringName
var _save: Callable
var _can_save: Callable
var _saving := false
var _entries: Array[Dictionary] = []
var _pending := ""
var _busy := false
var _list: ItemList
var _message: Label
var _action: Button
var _confirmation: HBoxContainer

func _ready() -> void:
	var page: Control = $ModalShell.get_content()
	_list = page.get_node("Slots")
	_message = page.get_node("Message")
	_action = page.get_node("Actions/Action")
	_confirmation = page.get_node("Confirmation")
	page.get_node("Modes/Save").pressed.connect(func() -> void: open_mode(true))
	page.get_node("Modes/Load").pressed.connect(func() -> void: open_mode(false))
	_list.item_selected.connect(func(_index: int) -> void: _update_action())
	_list.item_activated.connect(func(_index: int) -> void: _request_action())
	_action.pressed.connect(_request_action)
	_confirmation.get_node("Confirm").pressed.connect(_confirm_action)
	_confirmation.get_node("Cancel").pressed.connect(_cancel_confirmation)
	$ModalShell.close_requested.connect(_close)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh())
	refresh()

func configure(save: Callable, can_save: Callable) -> void:
	_save = save
	_can_save = can_save

func bind_ui(manager: UIManager, id: StringName) -> void:
	_manager = manager
	_id = id

func open_mode(saving: bool) -> void:
	_saving = saving and _save.is_valid()
	refresh()

func refresh() -> void:
	if not is_node_ready():
		return
	_busy = false
	_pending = ""
	_confirmation.hide()
	var page: Control = $ModalShell.get_content()
	page.get_node("Modes/Save").visible = _save.is_valid()
	page.get_node("Modes/Save").disabled = _saving
	page.get_node("Modes/Load").disabled = not _saving
	$ModalShell.set_title("保存游戏" if _saving else "读取存档")
	_entries = GameEntry.create_save_library().get_entries(GameEntry.preflight_save)
	_list.clear()
	var first := -1
	for entry in _entries:
		var detail := "空槽位"
		if entry.valid:
			var local_time: int = entry.saved_at + int(Time.get_time_zone_from_system().bias) * 60
			var date := Time.get_datetime_dict_from_unix_time(local_time)
			var place: String = {"main": "奶茶店", "settlement": "聚落", "tavern": "酒馆", "casino": "赌场"}.get(String(entry.scene).get_file().get_basename(), "场景入口")
			detail = "%02d-%02d %02d:%02d:%02d · 第%d天%s · %s%s" % [date.month, date.day, date.hour, date.minute, date.second, entry.day, "夜晚" if entry.phase == "night" else "白天", place, " · 使用备份" if entry.used_backup else ""]
		elif entry.occupied:
			detail = "损坏或版本不兼容"
		_list.add_item(entry.label + "   " + detail)
		var enabled: bool = entry.manual if _saving else entry.valid
		_list.set_item_disabled(_list.item_count - 1, not enabled)
		if enabled and first == -1:
			first = _list.item_count - 1
	if first >= 0:
		_list.select(first)
	_message.text = "手动存档不会被自动保存覆盖。所有存档均从安全检查点入口恢复。" if _saving else "自动存档 1 最新；2、3 保留更早记录。读取会放弃尚未保存的进度。"
	_update_action()

func _selected() -> Dictionary:
	var selected := _list.get_selected_items()
	return _entries[selected[0]] if not selected.is_empty() else {}

func _update_action() -> void:
	var entry := _selected()
	var page: Control = $ModalShell.get_content()
	page.get_node("Modes/Save").disabled = _saving or _busy or not _pending.is_empty()
	page.get_node("Modes/Load").disabled = not _saving or _busy or not _pending.is_empty()
	$ModalShell.get_close_button().disabled = _busy
	_action.text = "保存到此槽位" if _saving else "读取此存档"
	_action.disabled = _busy or not _pending.is_empty() or entry.is_empty() or (not entry.manual if _saving else not entry.valid)
	if _saving and (not _can_save.is_valid() or not _can_save.call()):
		_action.disabled = true
		_message.text = "当前正在对白、演出、潜入或切换中，暂时无法保存。请返回游戏并到达安全检查点。"
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if _busy or not _pending.is_empty() else Control.MOUSE_FILTER_STOP
	_list.focus_mode = Control.FOCUS_NONE if _busy or not _pending.is_empty() else Control.FOCUS_ALL

func _request_action() -> void:
	if _busy or _action.disabled:
		return
	var entry := _selected()
	if _saving and not entry.occupied:
		_write(entry.id, false)
		return
	_pending = entry.id
	_message.text = "覆盖“%s”？原有存档将保留一份备份。" % entry.label if _saving else "读取“%s”？尚未保存的进度将丢失。" % entry.label
	_confirmation.show()
	_update_action()
	_confirmation.get_node("Cancel").grab_focus()

func _confirm_action() -> void:
	if _pending.is_empty() or _busy:
		return
	var id := _pending
	_pending = ""
	_confirmation.hide()
	if _saving:
		_write(id, true)
	else:
		_busy = true
		_update_action()
		load_requested.emit(id)

func _write(id: String, overwrite: bool) -> void:
	var error: Error = _save.call(id, overwrite) if _save.is_valid() else ERR_UNAVAILABLE
	refresh()
	_message.text = "保存成功。" if error == OK else ("槽位已有存档，请重新选择并确认覆盖。" if error == ERR_ALREADY_EXISTS else "保存失败，原有存档已保留。请到安全检查点或检查磁盘空间后重试。")
	_action.grab_focus()

func show_load_error(error: Error) -> void:
	_busy = false
	_message.text = "存档无法恢复，原有文件与当前进度已保留。" if error != ERR_BUSY else "正在处理上一项操作，请稍后重试。"
	_update_action()
	_action.grab_focus()

func _cancel_confirmation() -> void:
	_pending = ""
	_confirmation.hide()
	_message.text = "已取消，原有存档与当前进度已保留。"
	_update_action()
	_action.grab_focus()

func request_back() -> bool:
	if _busy:
		return true
	if not _pending.is_empty():
		_cancel_confirmation()
		return true
	return false

func _close() -> void:
	if request_back():
		return
	if _manager != null:
		_manager.close_screen(_id)
	else:
		hide()
		dismissed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if _manager == null and is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()

func get_default_focus() -> Control:
	return _list if _list != null else null

func uses_native_gui_input() -> bool:
	return true

func on_ui_closed() -> void:
	_pending = ""
	_busy = false
