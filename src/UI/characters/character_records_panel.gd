class_name CharacterRecordsPanel
extends VBoxContainer
## Read-only character knowledge browser page. The page owns no chrome; ModalShell provides it.

@onready var _list: ItemList = %Entries
@onready var _title: Label = %Title
@onready var _text: RichTextLabel = %Text
@onready var _summary: Label = %Summary
@onready var _body: BoxContainer = %Body

var _journal: CharacterJournal
var _ids: Array[String] = []
var _selected_id := ""

func _ready() -> void:
	_list.item_selected.connect(_select)
	_list.item_activated.connect(_select)
	visibility_changed.connect(_on_visibility_changed)
	_refresh()

func bind_journal(journal: CharacterJournal) -> void:
	if is_instance_valid(_journal) and _journal.changed.is_connected(_refresh):
		_journal.changed.disconnect(_refresh)
	_journal = journal
	_selected_id = ""
	if is_inside_tree():
		_connect_journal()
	if is_node_ready():
		_refresh()

func _enter_tree() -> void:
	_connect_journal()
	if is_node_ready():
		_refresh.call_deferred()

func _exit_tree() -> void:
	if is_instance_valid(_journal) and _journal.changed.is_connected(_refresh):
		_journal.changed.disconnect(_refresh)

func _connect_journal() -> void:
	if is_instance_valid(_journal) and not _journal.changed.is_connected(_refresh):
		_journal.changed.connect(_refresh)

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
	if not is_node_ready():
		return
	var scroll := _list.get_v_scroll_bar().value
	_list.clear()
	_ids.clear()
	if is_instance_valid(_journal):
		for entry: Dictionary in _journal.get_characters():
			var index := _list.add_item(("● " if not entry.is_read else "") + entry.title)
			_list.set_item_tooltip(index, entry.title + (" · 未读" if not entry.is_read else " · 已读"))
			_ids.append(entry.character_id)
			if entry.character_id == _selected_id:
				_list.select(index) # Programmatic selection emits no item_selected.
	_list.get_v_scroll_bar().value = scroll
	_summary.text = "人物记录 · %d 条 / %d 未读" % [_ids.size(), _journal.get_unread_count() if is_instance_valid(_journal) else 0]
	var selected: Dictionary = _journal.get_character(_selected_id) if is_instance_valid(_journal) else {}
	if selected.is_empty():
		_selected_id = ""
		_title.text = "尚无人物记录" if _ids.is_empty() else "选择一位人物"
		_text.text = "剧情中了解到的人物信息会记录在这里。" if _ids.is_empty() else "选择左侧人物，回顾已知信息。"
		return
	_title.text = selected.title
	var paragraphs := PackedStringArray()
	for record: Dictionary in selected.records:
		paragraphs.append(record.content)
	_text.text = "\n\n".join(paragraphs) if not paragraphs.is_empty() else "暂时没有更多信息。"

func _select(index: int) -> void:
	if not is_visible_in_tree() or not can_process() or not is_instance_valid(_journal) or index < 0 or index >= _ids.size():
		return
	_selected_id = _ids[index]
	_refresh()
	_text.scroll_to_line(0)
	_journal.mark_read(_selected_id)
