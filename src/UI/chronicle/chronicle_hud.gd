class_name ChronicleHUD
extends Button

var _journal: ChronicleJournal

func bind_journal(journal: ChronicleJournal) -> void:
	if is_instance_valid(_journal) and _journal.changed.is_connected(_refresh):
		_journal.changed.disconnect(_refresh)
	_journal = journal
	if is_instance_valid(_journal):
		_journal.changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	var unread := _journal.get_unread_count() if is_instance_valid(_journal) else 0
	text = "见闻录" + (" ● %d" % unread if unread > 0 else "")
