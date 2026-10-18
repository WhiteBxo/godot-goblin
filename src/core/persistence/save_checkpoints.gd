class_name SaveCheckpoints
extends RefCounted
## Authored recovery boundaries, not a serialization of the scene tree.

const DEFAULT_PATH := "res://src/resources/persistence/checkpoints.json"
const KEYS := ["id", "scene", "entrance", "stage", "after_event", "before_event", "required_flags", "recovery"]
const SCENES := ["res://src/core/main.tscn", "res://src/core/settlement.tscn"]
var last_error := ""
var _entries: Array[Dictionary] = []

func _init(path: String = DEFAULT_PATH) -> void:
	var parser := JSON.new()
	if not FileAccess.file_exists(path) or parser.parse(FileAccess.get_file_as_string(path)) != OK:
		last_error = "检查点配置无法读取。"
		return
	load_data(parser.data)

func load_data(data: Variant) -> Error:
	if not data is Dictionary or data.size() != 2 or data.get("version") != 1 or not data.get("checkpoints") is Array:
		return _invalid()
	var entries: Array[Dictionary] = []
	var ids := {}
	for entry: Variant in data.checkpoints:
		if not entry is Dictionary or entry.size() != KEYS.size() or not entry.has_all(KEYS):
			return _invalid()
		for key: String in ["id", "scene", "entrance", "stage", "after_event", "before_event", "recovery"]:
			if not entry[key] is String:
				return _invalid()
		if entry.id.is_empty() or ids.has(entry.id) or entry.scene not in SCENES or entry.recovery not in ["opening", "shop", "chapter"] or not entry.required_flags is Array:
			return _invalid()
		for flag: Variant in entry.required_flags:
			if not flag is String or not StoryLibrary.is_namespaced(flag):
				return _invalid()
		ids[entry.id] = true
		entries.append(entry.duplicate(true))
	_entries = entries
	last_error = ""
	return OK

func get_checkpoint(id: String) -> Dictionary:
	for entry: Dictionary in _entries:
		if entry.id == id:
			return entry.duplicate(true)
	return {}

func find_checkpoint(snapshot: Dictionary, scene: String) -> Dictionary:
	for entry: Dictionary in _entries:
		if entry.scene == scene and matches(entry, snapshot):
			return entry.duplicate(true)
	return {}

func matches(entry: Dictionary, snapshot: Dictionary) -> bool:
	if entry.is_empty() or snapshot.get("story_stage") != entry.stage:
		return false
	var business: Variant = snapshot.get("business")
	if not business is Dictionary or business.get("profile_id") != "day1":
		return false
	var events: Variant = snapshot.get("completed_events")
	var flags: Variant = snapshot.get("flags")
	var variables: Variant = snapshot.get("variables")
	if not events is Array or not flags is Dictionary or not variables is Dictionary:
		return false
	var phase: Variant = variables.get(DayPhase.PHASE_VARIABLE, "night" if flags.get(DayPhase.NIGHT_FLAG, false) else "day")
	if phase not in ["day", "night"] or (flags.has(DayPhase.NIGHT_FLAG) and flags[DayPhase.NIGHT_FLAG] != (phase == "night")):
		return false
	if not entry.after_event.is_empty() and entry.after_event not in events:
		return false
	if not entry.before_event.is_empty() and entry.before_event in events:
		return false
	for flag: String in entry.required_flags:
		if not flags.get(flag, false):
			return false
	return true

func validate_checkpoint(id: String, snapshot: Dictionary) -> Error:
	return OK if matches(get_checkpoint(id), snapshot) else ERR_INVALID_DATA

func _invalid() -> Error:
	last_error = "检查点配置无效。"
	return ERR_INVALID_DATA
