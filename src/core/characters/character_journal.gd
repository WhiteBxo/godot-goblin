class_name CharacterJournal
extends Node
## Character knowledge only; GameState owns progress across scenes and saves.

signal changed

const StateData = preload("res://src/core/game_state.gd")
const STATE_KEY := "characters.entries"

var _state: StateData
var _characters: Dictionary = {}

func configure(state: StateData) -> Error:
	if not is_instance_valid(state) or not _valid_characters(state.get_variable(STATE_KEY, {})):
		return ERR_INVALID_DATA
	_disconnect_state()
	_state = state
	if is_inside_tree():
		_connect_state()
	_refresh()
	return OK

func _enter_tree() -> void:
	_connect_state()
	_refresh()

func _exit_tree() -> void:
	_disconnect_state()

func _connect_state() -> void:
	if is_instance_valid(_state) and not _state.state_changed.is_connected(_refresh):
		_state.state_changed.connect(_refresh)

func _disconnect_state() -> void:
	if is_instance_valid(_state) and _state.state_changed.is_connected(_refresh):
		_state.state_changed.disconnect(_refresh)

func _refresh() -> void:
	var next: Variant = _state.get_variable(STATE_KEY, {}) if is_instance_valid(_state) else {}
	# Generic GameState variables may be edited by developer tools. Hide invalid
	# data and reject writes rather than crashing or overwriting that snapshot.
	if not _valid_characters(next):
		next = {}
	if _characters != next:
		_characters = next
		changed.emit()

## Only unlocked entries are stored. Duplicate unlocks preserve title and read state.
func unlock_character(character_id: String, title: String) -> Error:
	if not StoryLibrary.is_namespaced(character_id) or title.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	var error := _writable()
	if error != OK:
		return error
	var entries: Dictionary = _state.get_variable(STATE_KEY, {})
	if entries.has(character_id):
		return OK
	entries[character_id] = {"title": title, "records": [], "is_read": false}
	return _commit(entries)

## record_id is globally unique. Retrying an existing record in the same entry
## is a no-op, including when the caller supplies different text.
func append_record(character_id: String, record_id: String, content: String) -> Error:
	if not StoryLibrary.is_namespaced(character_id) or not StoryLibrary.is_namespaced(record_id) or content.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	var error := _writable()
	if error != OK:
		return error
	var entries: Dictionary = _state.get_variable(STATE_KEY, {})
	if not entries.has(character_id):
		return ERR_DOES_NOT_EXIST
	for id: String in entries:
		for record: Dictionary in entries[id].records:
			if record.record_id == record_id:
				return OK if id == character_id else ERR_ALREADY_EXISTS
	entries[character_id].records.append({"record_id": record_id, "content": content})
	entries[character_id].is_read = false
	return _commit(entries)

func mark_read(character_id: String) -> Error:
	var error := _writable()
	if error != OK:
		return error
	var entries: Dictionary = _state.get_variable(STATE_KEY, {})
	if not entries.has(character_id):
		return ERR_DOES_NOT_EXIST
	if entries[character_id].is_read:
		return OK
	entries[character_id].is_read = true
	return _commit(entries)

func get_character(character_id: String) -> Dictionary:
	if not _characters.has(character_id):
		return {}
	var entry: Dictionary = _characters[character_id].duplicate(true)
	entry.character_id = character_id
	entry.unlocked = true
	return entry

func get_characters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _characters:
		result.append(get_character(id))
	return result

func get_unread_count() -> int:
	var count := 0
	for entry: Dictionary in _characters.values():
		if not entry.is_read:
			count += 1
	return count

func _writable() -> Error:
	if not is_instance_valid(_state):
		return ERR_UNCONFIGURED
	return OK if _valid_characters(_state.get_variable(STATE_KEY, {})) else ERR_INVALID_DATA

func _commit(entries: Dictionary) -> Error:
	if not _state.set_variable(STATE_KEY, entries):
		return ERR_BUSY
	# Also support configuring and using the service before it enters a scene.
	_refresh()
	return OK

func _valid_characters(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var used_records := {}
	for id: Variant in value:
		if not StoryLibrary.is_namespaced(id):
			return false
		var entry: Variant = value[id]
		if not entry is Dictionary or not entry.get("title") is String or entry.title.strip_edges().is_empty() or not entry.get("is_read") is bool or not entry.get("records") is Array:
			return false
		for record: Variant in entry.records:
			if not record is Dictionary or not StoryLibrary.is_namespaced(record.get("record_id")) or not record.get("content") is String or record.content.strip_edges().is_empty():
				return false
			if used_records.has(record.record_id):
				return false
			used_records[record.record_id] = true
	return true
