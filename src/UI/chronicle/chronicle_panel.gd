class_name ChroniclePanel
extends VBoxContainer
## Read-only chronicle browser page. The page owns no chrome; ModalShell provides it.

@onready var _list: ItemList = %Entries
@onready var _title: Label = %Title
@onready var _text: RichTextLabel = %Text
@onready var _summary: Label = %Summary
@onready var _body: BoxContainer = %Body
@onready var _detail: Control = %Detail

var _journal: ChronicleJournal
var _ids: Array[String] = []
var _selected_id := ""
## Only a genuinely different entry turns the page; a journal refresh of the
## entry already on screen must leave the words still.
var _shown_id := ""

func _ready() -> void:
	_list.item_selected.connect(_select)
	_list.item_activated.connect(_select)
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
	_summary.text = "异世界见闻录 · %d 条 / %d 未读" % [_ids.size(), _journal.get_unread_count() if is_instance_valid(_journal) else 0]
	var selected: Dictionary = _journal.get_entry(_selected_id) if is_instance_valid(_journal) else {}
	if selected.is_empty():
		_selected_id = ""
		_title.text = "尚无见闻" if _ids.is_empty() else "选择一条见闻"
		_text.text = "在旅途中发现的见闻会记录在这里。" if _ids.is_empty() else "点击左侧条目，回顾已记录的内容。"
		_turn_page(str(selected.get("entry_id", "")))
		return
	_title.text = selected.title
	var paragraphs := PackedStringArray()
	for record: Dictionary in selected.records:
		paragraphs.append(record.content)
	_text.text = "\n\n".join(paragraphs) if not paragraphs.is_empty() else "暂时没有记录。"
	_turn_page(str(selected.get("entry_id", "")))

## The reading pane opens on the new entry instead of swapping the sentences
## under the eye. Alpha and scale only, so the split layout never reflows.
func _turn_page(entry_id: String) -> void:
	var changed := entry_id != _shown_id
	_shown_id = entry_id
	if changed:
		UIFlourish.reveal(_detail, 0.99)

func _select(index: int) -> void:
	if not is_visible_in_tree() or not can_process() or not is_instance_valid(_journal) or index < 0 or index >= _ids.size():
		return
	_selected_id = _ids[index]
	_refresh()
	_text.scroll_to_line(0)
	_journal.mark_read(_selected_id)
