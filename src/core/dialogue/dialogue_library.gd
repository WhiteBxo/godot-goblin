class_name DialogueLibrary
extends RefCounted
## JSON parsing and validation are separate from runtime dialogue flow.

var last_error: String = ""
var _dialogues: Dictionary = {}


func load_file(path: String) -> Error:
	last_error = ""
	if not FileAccess.file_exists(path):
		last_error = "Dialogue file does not exist: " + path
		return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "Cannot open dialogue file: " + path
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
	_dialogues = json.data["dialogues"].duplicate(true)
	last_error = ""
	return OK


func has_dialogue(id: String) -> bool:
	return _dialogues.has(id)


func get_dialogue(id: String) -> Dictionary:
	return _dialogues.get(id, {}).duplicate(true)


func _invalid(message: String) -> bool:
	last_error = message
	return false


func _validate(data: Variant) -> bool:
	if not data is Dictionary or typeof(data.get("version")) not in [TYPE_INT, TYPE_FLOAT] or data["version"] != 1 or not data.get("dialogues") is Dictionary:
		return _invalid("Expected version 1 and a dialogues dictionary")
	for id: Variant in data["dialogues"]:
		if not id is String or id.is_empty():
			return _invalid("Dialogue IDs must be non-empty strings")
		var dialogue: Variant = data["dialogues"][id]
		if not dialogue is Dictionary or not dialogue.get("lines") is Dictionary:
			return _invalid("%s: expected a lines dictionary" % id)
		var lines: Dictionary = dialogue["lines"]
		if not dialogue.get("start") is String or not lines.has(dialogue["start"]):
			return _invalid("%s: start must name an existing line" % id)
		for line_id: Variant in lines:
			var line: Variant = lines[line_id]
			if not line_id is String or line_id.is_empty() or not line is Dictionary:
				return _invalid("%s: invalid line ID or line object" % id)
			if not line.get("speaker") is String or not line.get("text") is String:
				return _invalid("%s/%s: speaker and text must be strings" % [id, line_id])
			var portrait: Variant = line.get("portrait", "")
			if not portrait is String:
				return _invalid("%s/%s: portrait must be a resource path" % [id, line_id])
			if not portrait.is_empty() and (not portrait.begins_with("res://") or not ResourceLoader.exists(portrait, "Texture2D")):
				return _invalid("%s/%s: portrait texture does not exist" % [id, line_id])
			if not _valid_next(line.get("next", ""), lines):
				return _invalid("%s/%s: next must be empty or name an existing line" % [id, line_id])
			var choices: Variant = line.get("choices", [])
			if not choices is Array or (not choices.is_empty() and line.has("next")):
				return _invalid("%s/%s: use choices or next, not both" % [id, line_id])
			var seen: Dictionary[String, bool] = {}
			for choice: Variant in choices:
				if not choice is Dictionary or not choice.get("id") is String or choice["id"].is_empty() or seen.has(choice["id"]):
					return _invalid("%s/%s: choice IDs must be unique non-empty strings" % [id, line_id])
				if not choice.get("text") is String or choice["text"].is_empty() or not _valid_next(choice.get("next", ""), lines):
					return _invalid("%s/%s: invalid choice text or next" % [id, line_id])
				seen[choice["id"]] = true
	return true


func _valid_next(value: Variant, lines: Dictionary) -> bool:
	return value is String and (value.is_empty() or lines.has(value))
