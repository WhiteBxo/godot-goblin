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
	if not _keys(data, ["day", "stage", "flags", "completed_events", "not_completed_events", "choice", "items"], context):
		return false
	if data.has("items") and not _item_counts(data["items"]):
		return _invalid(context, "items requires item IDs mapped to positive integer counts")
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
		"chapter_action":
			fields.append("id")
			if not is_namespaced(step.get("id")):
				return _invalid(context, "chapter_action requires a namespaced action id")
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
		"chronicle_unlock", "chronicle_append":
			fields.append("entry_id")
			if not is_namespaced(step.get("entry_id")):
				return _invalid(context, "chronicle requires a namespaced entry_id")
			if step.command == "chronicle_unlock":
				fields.append("title")
				if not _text(step.get("title")):
					return _invalid(context, "chronicle_unlock requires a non-empty title")
			else:
				fields.append_array(["record_id", "content"])
				if not is_namespaced(step.get("record_id")) or not _text(step.get("content")):
					return _invalid(context, "chronicle_append requires a namespaced record_id and non-empty content")
		"character_unlock", "character_append":
			fields.append("character_id")
			if not is_namespaced(step.get("character_id")):
				return _invalid(context, "character requires a namespaced character_id")
			if step.command == "character_unlock":
				fields.append("name")
				if not _text(step.get("name")):
					return _invalid(context, "character_unlock requires a non-empty name")
			else:
				fields.append_array(["record_id", "content"])
				if not is_namespaced(step.get("record_id")) or not _text(step.get("content")):
					return _invalid(context, "character_append requires a namespaced record_id and non-empty content")
		"play_sfx":
			fields.append_array(["path", "id", "wait"])
			if not step.get("wait", false) is bool:
				return _invalid(context, "wait must be bool")
			if step.has("id") == step.has("path"):
				return _invalid(context, "play_sfx requires exactly one of id or path")
			if step.has("id") and (not step["id"] is String or step["id"].is_empty()):
				return _invalid(context, "play_sfx requires a non-empty id")
			if step.has("path") and (not step["path"] is String or not step["path"].begins_with("res://")):
				return _invalid(context, "play_sfx requires a res:// path")
		"pay_items":
			fields.append_array(["items", "receipt", "set_flags"])
			if not _item_counts(step.get("items")):
				return _invalid(context, "pay_items requires item IDs mapped to positive integer counts")
			if not is_namespaced(step.get("receipt")):
				return _invalid(context, "pay_items requires a namespaced receipt")
			var facts: Variant = step.get("set_flags", {})
			if not facts is Dictionary:
				return _invalid(context, "set_flags must be an object")
			for key: Variant in facts:
				if not is_namespaced(key) or not facts[key] is bool or key == step.receipt:
					return _invalid(context, "set_flags requires namespaced keys, bool values and no receipt")
		"grant_money":
			fields.append_array(["amount", "receipt"])
			var amount: Variant = step.get("amount")
			if not _number(amount) or amount < 1 or floor(amount) != amount or amount > 2147483647:
				return _invalid(context, "grant_money requires a positive bounded integer amount")
			if not is_namespaced(step.get("receipt")):
				return _invalid(context, "grant_money requires a namespaced receipt")
		"unlock_map":
			fields.append("locations")
			var locations: Variant = step.get("locations", [])
			if not locations is Array:
				return _invalid(context, "unlock_map locations must be an array")
			for location: Variant in locations:
				if not is_namespaced(location):
					return _invalid(context, "unlock_map requires namespaced location IDs")
		"tavern_purchase":
			fields.append_array(["product_id", "quantity", "receipt"])
			if not _text(step.get("product_id")):
				return _invalid(context, "tavern_purchase requires a non-empty product_id")
			if not _number(step.get("quantity")) or step.quantity < 1 or floor(step.quantity) != step.quantity:
				return _invalid(context, "tavern_purchase quantity must be a positive integer")
			if not is_namespaced(step.get("receipt")):
				return _invalid(context, "tavern_purchase requires a namespaced receipt")
		"casino_settle":
			fields.append_array(["step", "reason"])
			if step.get("step") not in ["first_loss", "second_win", "waive"]:
				return _invalid(context, "casino_settle requires first_loss, second_win or waive")
			if step.get("step") == "waive" and not _text(step.get("reason")):
				return _invalid(context, "casino_settle waive requires a non-empty reason")
		"business":
			fields.append_array(["action", "stage_id", "group_id"])
			if step.get("action") not in ["publish", "request_arrival", "confirm_arrival",
					"request_departure", "confirm_departure", "close"]:
				return _invalid(context, "business requires a known action")
			if step.action == "publish" and not _text(step.get("stage_id")):
				return _invalid(context, "business publish requires a non-empty stage_id")
			if step.action in ["request_arrival", "confirm_arrival", "request_departure", "confirm_departure"] \
					and not _text(step.get("group_id")):
				return _invalid(context, "business customer actions require a non-empty group_id")
		"set_phase":
			fields.append("phase")
			if step.get("phase") not in ["day", "night"]:
				return _invalid(context, "set_phase requires day or night")
		"title_card":
			fields.append_array(["text", "subtitle", "seconds", "wait"])
			if not _text(step.get("text")) or (step.has("subtitle") and not step.subtitle is String):
				return _invalid(context, "title_card requires non-empty text; subtitle must be text")
			if not _number(step.get("seconds", 2.5)) or step.get("seconds", 2.5) <= 0.0:
				return _invalid(context, "title_card seconds must be finite and positive")
			if not step.get("wait", true) is bool:
				return _invalid(context, "wait must be bool")
		"actor_spawn", "actor_move", "actor_face", "actor_emote", "actor_show", "actor_hide", "actor_animate", "camera_focus", "camera_move", "camera_shake", "camera_zoom", "camera_reset", "play_bgm", "stop_bgm", "fade_bgm":
			return _cinematic_step(step, context)
		_:
			return _invalid(context, "Unknown command '%s'" % step["command"])
	return _keys(step, fields, context) and _conditions(step.get("when", {}), context)


func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()


func _item_counts(value: Variant) -> bool:
	if not value is Dictionary or value.is_empty():
		return false
	for id: Variant in value:
		var count: Variant = value[id]
		if not _text(id) or not _number(count) or count < 1 or floor(count) != count:
			return false
	return true


func _target(value: Variant) -> bool:
	return _text(value) or (value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]))


func _cinematic_step(step: Dictionary, context: String) -> bool:
	var command: String = step.command
	var fields: Array = ["command", "when", "wait"]
	if not step.get("wait", true) is bool:
		return _invalid(context, "wait must be bool")
	if command.begins_with("actor_"):
		fields.append("actor")
		if not _text(step.get("actor")):
			return _invalid(context, "actor requires a non-empty registered ID")
	match command:
		"actor_spawn", "actor_move":
			fields.append("target")
			if not _target(step.get("target")):
				return _invalid(context, "target requires a position ID or finite [x, y]")
			if command == "actor_spawn":
				fields.append("scene")
				if not _text(step.get("scene")) or not step.scene.begins_with("res://") or not step.scene.ends_with(".tscn"):
					return _invalid(context, "scene requires a res:// .tscn path")
			else:
				fields.append_array(["speed", "timeout"])
				for field: String in ["speed", "timeout"]:
					if not _number(step.get(field, 1.0)) or step.get(field, 1.0) <= 0.0:
						return _invalid(context, field + " must be finite and positive")
		"actor_face":
			fields.append("direction")
			if step.get("direction") not in ["up", "down", "left", "right"]:
				return _invalid(context, "direction must be up/down/left/right")
		"actor_emote":
			fields.append_array(["symbol", "duration"])
			if not _text(step.get("symbol", "!")):
				return _invalid(context, "symbol must be non-empty text")
		"actor_animate":
			fields.append_array(["animation", "hold"])
			if not _text(step.get("animation")) or not step.get("hold", false) is bool:
				return _invalid(context, "actor_animate requires an animation name; hold must be bool")
		"camera_focus":
			fields.append_array(["actor", "target", "duration"])
			if step.has("actor") == step.has("target") or (step.has("actor") and not _text(step.actor)) or (step.has("target") and not _target(step.target)):
				return _invalid(context, "focus requires exactly one actor ID or target")
		"camera_move":
			fields.append_array(["target", "duration"])
			if not _target(step.get("target")):
				return _invalid(context, "camera_move requires a position ID or finite [x, y]")
		"camera_shake":
			fields.append_array(["intensity", "duration", "decay"])
			for field: String in ["intensity", "decay"]:
				if not _number(step.get(field, 1.0)) or step.get(field, 1.0) < 0.0:
					return _invalid(context, field + " must be finite and nonnegative")
		"camera_zoom":
			fields.append_array(["value", "duration"])
			if not _number(step.get("value")) or step.value <= 0.0:
				return _invalid(context, "zoom value must be finite and positive")
		"play_bgm":
			fields.append_array(["id", "fade", "volume_db"])
			if not _text(step.get("id")):
				return _invalid(context, "play_bgm requires a non-empty audio ID")
		"stop_bgm":
			fields.append("fade")
		"fade_bgm":
			fields.append_array(["volume_db", "fade"])
			if not _number(step.get("volume_db")):
				return _invalid(context, "fade_bgm requires finite volume_db")
	for field: String in ["duration", "fade", "volume_db"]:
		if step.has(field) and (not _number(step[field]) or (field != "volume_db" and step[field] < 0.0)):
			return _invalid(context, field + " must be finite; times must be nonnegative")
	if command == "actor_emote" and step.get("duration", 0.8) <= 0.0:
		return _invalid(context, "emote duration must be positive")
	return _keys(step, fields, context) and _conditions(step.get("when", {}), context)
