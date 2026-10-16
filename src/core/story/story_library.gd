class_name StoryLibrary
extends RefCounted
## Validates the entire catalogue before replacing live event data.

var last_error: String = ""
var _events: Dictionary = {}


func load_file(path: String) -> Error:
	last_error = ""
	if not FileAccess.file_exists(path):
		last_error = "Story file does not exist: " + path
		return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "Cannot open story file: " + path
		return FileAccess.get_open_error()
	return load_json(file.get_as_text())


func load_json(text: String) -> Error:
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		last_error = "JSON line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return error
	if not _validate(json.data):
		return ERR_INVALID_DATA
	_events = json.data["events"].duplicate(true)
	last_error = ""
	return OK


func get_event(id: String) -> Dictionary:
	return _events.get(id, {}).duplicate(true)


func get_event_ids() -> Array:
	return _events.keys()


static func is_namespaced(value: Variant) -> bool:
	if not value is String or value.split(".").size() < 2:
		return false
	for part: String in value.split("."):
		if not part.is_valid_identifier():
			return false
	return true


func _invalid(context: String, message: String) -> bool:
	last_error = context + ": " + message
	return false


func _keys(data: Dictionary, allowed: Array, context: String) -> bool:
	for key: Variant in data:
		if key not in allowed:
			return _invalid(context, "Unknown field '%s'" % key)
	return true


func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(value)


func _validate(data: Variant) -> bool:
	if not data is Dictionary or not _number(data.get("version")) or data["version"] != 1 or not data.get("events") is Dictionary:
		return _invalid("Story", "Expected version 1 and an events dictionary")
	if not _keys(data, ["version", "events"], "Story"):
		return false
	for id: Variant in data["events"]:
		if not is_namespaced(id):
			return _invalid("Story", "Event IDs must be namespaced identifiers: %s" % id)
		var event: Variant = data["events"][id]
		if not event is Dictionary:
			return _invalid(id, "Expected an event object")
		if not _keys(event, ["once", "trigger", "conditions", "steps"], id):
			return false
		if not event.get("once", true) is bool or not event.get("trigger", "") is String:
			return _invalid(id, "once must be bool; trigger must be a string")
		if not _conditions(event.get("conditions", {}), id, false):
			return false
		if not event.get("steps") is Array or event["steps"].is_empty():
			return _invalid(id, "Expected a non-empty steps array")
		for index in range(event["steps"].size()):
			if not _step(event["steps"][index], "%s/steps[%d]" % [id, index]):
				return false
	return true


func _conditions(data: Variant, context: String, allow_choice: bool = true) -> bool:
	if not data is Dictionary:
		return _invalid(context, "conditions/when must be an object")
	if not _keys(data, ["day", "stage", "flags", "completed_events", "not_completed_events", "choice"], context):
		return false
	if data.has("day") and (not _number(data["day"]) or data["day"] < 1 or floor(data["day"]) != data["day"]):
		return _invalid(context, "day must be a positive integer")
	if data.has("stage") and not data["stage"] is String:
		return _invalid(context, "stage must be a string")
	var flags: Variant = data.get("flags", {})
	if not flags is Dictionary:
		return _invalid(context, "flags must be an object")
	for key: Variant in flags:
		if not is_namespaced(key) or not flags[key] is bool:
			return _invalid(context, "flags require namespaced keys and bool values")
	for field: String in ["completed_events", "not_completed_events"]:
		var ids: Variant = data.get(field, [])
		if not ids is Array:
			return _invalid(context, field + " must be an array")
		for id: Variant in ids:
			if not is_namespaced(id):
				return _invalid(context, field + " requires namespaced event IDs")
	if data.has("choice"):
		if not allow_choice:
			return _invalid(context, "choice is local to a sequence; use it in step when")
		var choice: Variant = data["choice"]
		if not choice is Dictionary or not choice.has_all(["dialogue", "line", "id"]):
			return _invalid(context, "choice requires dialogue, line and id")
		if not _keys(choice, ["dialogue", "line", "id"], context):
			return false
		for field: String in ["dialogue", "line", "id"]:
			if not choice[field] is String or choice[field].is_empty():
				return _invalid(context, "choice fields must be non-empty strings")
	return true


func _step(step: Variant, context: String) -> bool:
	if not step is Dictionary or not step.get("command") is String:
		return _invalid(context, "Expected a command object")
	var fields: Array = ["command", "when"]
	match step["command"]:
		"dialogue":
			fields.append("id")
			if not step.get("id") is String or step["id"].is_empty():
				return _invalid(context, "dialogue requires a non-empty id")
		"wait":
			fields.append("seconds")
			if not _number(step.get("seconds")) or step["seconds"] < 0:
				return _invalid(context, "wait requires finite seconds >= 0")
		"set_flag":
			fields.append_array(["key", "value"])
			if not is_namespaced(step.get("key")) or not step.get("value", true) is bool:
				return _invalid(context, "set_flag requires a namespaced key and bool value")
		"set_stage":
			fields.append("value")
			if not step.get("value") is String:
				return _invalid(context, "set_stage requires a string value")
		"play_sfx":
			fields.append_array(["path", "id"])
			if step.has("id") == step.has("path"):
				return _invalid(context, "play_sfx requires exactly one of id or path")
			if step.has("id") and (not step["id"] is String or step["id"].is_empty()):
				return _invalid(context, "play_sfx requires a non-empty id")
			if step.has("path") and (not step["path"] is String or not step["path"].begins_with("res://")):
				return _invalid(context, "play_sfx requires a res:// path")
		_:
			return _invalid(context, "Unknown command '%s'" % step["command"])
	return _keys(step, fields, context) and _conditions(step.get("when", {}), context)
