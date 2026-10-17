extends Node
## Cross-scene story and economy data. Economy mutations use get_transactions().
## No class_name: GameState is the Autoload name, not a second global class.

signal state_changed
signal event_completed(event_id: String)
signal state_reset
signal state_restored

const SCHEMA_VERSION: int = 2
const MAX_VALUE_DEPTH: int = 32

var current_day: int:
	get:
		return _current_day
	set(value):
		set_current_day(value)

## Empty means no story stage has been selected yet.
var story_stage: String:
	get:
		return _story_stage
	set(value):
		set_story_stage(value)

var _current_day: int = 1
var _story_stage: String = ""
var _flags: Dictionary[String, bool] = {}
var _variables: Dictionary[String, Variant] = {}
var _completed_events: Dictionary[String, bool] = {}
var _economy: WalletTransactions
var _updating_economy: bool = false

func _init() -> void:
	_economy = WalletTransactions.new()
	_economy.name = "WalletTransactions"
	add_child(_economy)
	_economy.changed.connect(_on_economy_changed)

func get_transactions() -> WalletTransactions:
	return _economy

func _on_economy_changed() -> void:
	if not _updating_economy:
		state_changed.emit()

func _publish_economy(before: Dictionary) -> void:
	_updating_economy = true
	_economy.publish_restored(before)
	_updating_economy = false


## Setters return true only when data changed. Invalid input is left untouched.
func set_current_day(value: int) -> bool:
	if value < 1 or value == _current_day:
		return false
	_current_day = value
	state_changed.emit()
	return true


func set_story_stage(value: String) -> bool:
	if value == _story_stage:
		return false
	_story_stage = value
	state_changed.emit()
	return true


func has_flag(key: String) -> bool:
	return _flags.has(key)


func get_flag(key: String, default_value: bool = false) -> bool:
	return _flags.get(key, default_value)


func set_flag(key: String, value: bool = true) -> bool:
	if not _is_namespaced_key(key) or (_flags.has(key) and _flags[key] == value):
		return false
	_flags[key] = value
	state_changed.emit()
	return true


func get_flags() -> Dictionary[String, bool]:
	return _flags.duplicate()


func has_variable(key: String) -> bool:
	return _variables.has(key)


func get_variable(key: String, default_value: Variant = null) -> Variant:
	return _copy_value(_variables.get(key, default_value))


## Values: null, bool, int, finite float, String, Array, string-keyed Dictionary.
## Containers may nest up to MAX_VALUE_DEPTH; Objects and cycles are rejected.
func set_variable(key: String, value: Variant) -> bool:
	if not _is_namespaced_key(key) or not _is_story_value(value):
		return false
	if _variables.has(key) and _same_value(_variables[key], value):
		return false
	_variables[key] = _copy_value(value)
	state_changed.emit()
	return true


func get_variables() -> Dictionary[String, Variant]:
	return _variables.duplicate(true)


func is_event_completed(event_id: String) -> bool:
	return _completed_events.has(event_id)


func complete_event(event_id: String) -> bool:
	if not _is_namespaced_key(event_id) or is_event_completed(event_id):
		return false
	_completed_events[event_id] = true
	state_changed.emit()
	event_completed.emit(event_id)
	return true


func get_completed_events() -> Array[String]:
	var events: Array[String] = []
	events.assign(_completed_events.keys())
	events.sort()
	return events


func reset_state() -> bool:
	if _economy.is_busy():
		return false
	if _current_day == 1 and _story_stage.is_empty() and _flags.is_empty() and _variables.is_empty() and _completed_events.is_empty() and _economy.to_dict() == _economy.get_default_state():
		return false
	var economy_before := _economy.to_dict()
	_economy.restore_state(_economy.get_default_state(), false)
	_current_day = 1
	_story_stage = ""
	_flags.clear()
	_variables.clear()
	_completed_events.clear()
	_publish_economy(economy_before)
	state_changed.emit()
	state_reset.emit()
	return true


## Native Variant snapshot, with independent containers; no file I/O.
func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"current_day": _current_day,
		"story_stage": _story_stage,
		"flags": get_flags(),
		"variables": get_variables(),
		"completed_events": get_completed_events(),
		"economy": _economy.to_dict(),
	}


## Complete replacement, not a merge. Validate before touching live state.
## Valid identical snapshots return OK without signals. Restoring events does
## not emit event_completed, so loading cannot replay one-shot story effects.
func restore_state(data: Dictionary) -> Error:
	if _economy.is_busy():
		return ERR_BUSY
	if not _is_valid_snapshot(data):
		return ERR_INVALID_DATA
	var economy_data: Dictionary = data.get("economy", _economy.get_default_state())
	var restored_events: Dictionary[String, bool] = {}
	for event_id: String in data["completed_events"]:
		restored_events[event_id] = true
	if _current_day == data["current_day"] and _story_stage == data["story_stage"] and _flags == data["flags"] and _same_value(_variables, data["variables"]) and _completed_events == restored_events and _economy.to_dict() == economy_data:
		return OK
	var economy_before := _economy.to_dict()
	if _economy.restore_state(economy_data, false) != OK:
		return ERR_INVALID_DATA
	_current_day = data["current_day"]
	_story_stage = data["story_stage"]
	_flags.assign(data["flags"])
	_variables.assign(data["variables"].duplicate(true))
	_completed_events = restored_events
	_publish_economy(economy_before)
	state_changed.emit()
	state_restored.emit()
	return OK


func _is_valid_snapshot(data: Dictionary) -> bool:
	if data.has("economy") and _economy.validate_state(data.economy) != OK:
		return false
	if not data.has_all(["schema_version", "current_day", "story_stage", "flags", "variables", "completed_events"]):
		return false
	if not data["schema_version"] is int or data["schema_version"] not in [1, SCHEMA_VERSION]:
		return false
	if data.schema_version == SCHEMA_VERSION and not data.has("economy"):
		return false
	if not data["current_day"] is int or data["current_day"] < 1 or not data["story_stage"] is String:
		return false
	if not data["flags"] is Dictionary or not data["variables"] is Dictionary or not data["completed_events"] is Array:
		return false
	for key: Variant in data["flags"]:
		if not key is String or not _is_namespaced_key(key) or not data["flags"][key] is bool:
			return false
	for key: Variant in data["variables"]:
		if not key is String or not _is_namespaced_key(key) or not _is_story_value(data["variables"][key]):
			return false
	var seen_events: Dictionary[String, bool] = {}
	for event_id: Variant in data["completed_events"]:
		if not event_id is String or not _is_namespaced_key(event_id) or seen_events.has(event_id):
			return false
		seen_events[event_id] = true
	return true


func _is_namespaced_key(key: String) -> bool:
	var parts := key.split(".")
	if parts.size() < 2:
		return false
	for part: String in parts:
		if not part.is_valid_identifier():
			return false
	return true


func _is_story_value(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_VALUE_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item: Variant in value:
				if not _is_story_value(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not _is_story_value(value[key], depth + 1):
					return false
			return true
	return false


func _copy_value(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value


## Numeric type changes (including nested int -> float) are meaningful.
func _same_value(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is Array:
		if left.size() != right.size():
			return false
		for index in range(left.size()):
			if not _same_value(left[index], right[index]):
				return false
		return true
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _same_value(left[key], right[key]):
				return false
		return true
	return left == right
