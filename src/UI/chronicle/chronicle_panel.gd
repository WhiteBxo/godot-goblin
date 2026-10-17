class_name ChroniclePanel
extends Control

signal close_requested

@onready var _list: ItemList = $Margin/Panel/Margin/Content/Body/Entries
@onready var _title: Label = $Margin/Panel/Margin/Content/Body/Detail/Title
@onready var _text: RichTextLabel = $Margin/Panel/Margin/Content/Body/Detail/Text
@onready var _summary: Label = $Margin/Panel/Margin/Content/Header/Summary
@onready var _close: Button = $Margin/Panel/Margin/Content/Header/Close

var _embedded_close: Button

var _journal: ChronicleJournal
var _ids: Array[String] = []
var _selected_id := ""

func _ready() -> void:
	_list.item_selected.connect(_select)
	_list.item_activated.connect(_select)
	_close.pressed.connect(func() -> void: close_requested.emit())
	visibility_changed.connect(_on_visibility_changed)
	_refresh()

func bind_journal(journal: ChronicleJournal) -> void:
	if is_instance_valid(_journal) and _journal.changed.is_connected(_refresh):
		_journal.changed.disconnect(_refresh)
	_journal = journal
	_selected_id = ""
	if is_instance_valid(_journal):
		_journal.changed.connect(_refresh)
	if is_node_ready():
		_refresh()

func uses_native_gui_input() -> bool:
	return true

func get_default_focus() -> Control:
	return _list if _list.item_count > 0 else (_embedded_close if is_instance_valid(_embedded_close) else _close)

func _on_visibility_changed() -> void:
	if is_node_ready() and not is_visible_in_tree():
		_selected_id = ""
		_refresh()

func _refresh() -> void:
	var scroll := _list.get_v_scroll_bar().value
	_list.clear()
	_ids.clear()
	if is_instance_valid(_journal):
		for entry: Dictionary in _journal.get_entries():
			var index := _list.add_item(("● " if not entry.is_read else "") + entry.title)
			_list.set_item_tooltip(index, entry.title + (" · 未读" if not entry.is_read else " · 已读"))
			_ids.append(entry.entry_id)
			if entry.entry_id == _selected_id:
				_list.select(index) # Programmatic selection emits no item_selected.
	_list.get_v_scroll_bar().value = scroll
	_summary.text = "见闻录 · %d 条 / %d 未读" % [_ids.size(), _journal.get_unread_count() if is_instance_valid(_journal) else 0]
	var selected: Dictionary = _journal.get_entry(_selected_id) if is_instance_valid(_journal) else {}
	if selected.is_empty():
		_selected_id = ""
		_title.text = "尚无见闻" if _ids.is_empty() else "选择一条见闻"
		_text.text = "在旅途中发现的见闻会记录在这里。" if _ids.is_empty() else "点击左侧条目，回顾已记录的内容。"
		return
	_title.text = selected.title
	var paragraphs := PackedStringArray()
	for record: Dictionary in selected.records:
		paragraphs.append(record.content)
	_text.text = "\n\n".join(paragraphs) if not paragraphs.is_empty() else "暂时没有记录。"

func _select(index: int) -> void:
	if not is_visible_in_tree() or not can_process() or not is_instance_valid(_journal) or index < 0 or index >= _ids.size():
		return
	_selected_id = _ids[index]
	_refresh()
	_text.scroll_to_line(0)
	_journal.mark_read(_selected_id)

## Reuse the browser inside a shared modal without nested chrome.
func set_embedded(close_button: Button) -> void:
	_embedded_close = close_button
	$Dim.hide()
	$Margin/Panel/Margin/Content/Header.hide()
	$Margin/Panel/Margin/Content/Hint.hide()
	for side: String in ["left", "top", "right", "bottom"]:
		$Margin.add_theme_constant_override("margin_" + side, 0)
	$Margin/Panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
