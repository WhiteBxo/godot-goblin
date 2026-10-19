class_name PlayerPreferences
extends RefCounted
## Device preferences live outside the game session and survive a new game.

const DEFAULTS := {"music": 1.0, "sound": 1.0, "dialogue_speed": 1.0, "dialogue_auto": 0.0}
const SPEEDS := [0.5, 1.0, 2.0, 0.0]
## 0 disables auto-play; the others are seconds a completed line stays readable.
const AUTO_DELAYS := [0.0, 1.5, 3.0, 5.0]
static var _path := ""
static var _values: Dictionary = {}

static func get_values() -> Dictionary:
	var path: String = ProjectSettings.get_setting("preferences/file", "user://preferences.cfg")
	if path != _path or _values.is_empty():
		_path = path
		_values = DEFAULTS.duplicate()
		var file := ConfigFile.new()
		if file.load(path) == OK:
			for key: String in DEFAULTS:
				var value: Variant = file.get_value("player", key, DEFAULTS[key])
				if _valid(key, value):
					_values[key] = float(value)
	return _values.duplicate()

static func _valid(key: String, value: Variant) -> bool:
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(value):
		return false
	if key == "dialogue_speed":
		return value in SPEEDS
	if key == "dialogue_auto":
		return value in AUTO_DELAYS
	return value >= 0.0 and value <= 1.0

static func save_values(values: Dictionary) -> Error:
	if values.size() != DEFAULTS.size():
		return ERR_INVALID_DATA
	for key: String in values:
		if not DEFAULTS.has(key) or not _valid(key, values[key]):
			return ERR_INVALID_DATA
	get_values()
	var file := ConfigFile.new()
	for key: String in values:
		file.set_value("player", key, float(values[key]))
	var temporary := _path + ".tmp"
	var error := file.save(temporary)
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(_path))
	if error == OK:
		_values = values.duplicate()
		apply_audio()
	return error

static func apply_audio() -> void:
	var values := get_values()
	for name: String in ["Music", "SFX", "UI"]:
		var bus := AudioServer.get_bus_index(name)
		if bus < 0:
			continue
		var volume: float = values.music if name == "Music" else values.sound
		AudioServer.set_bus_mute(bus, is_zero_approx(volume))
		AudioServer.set_bus_volume_linear(bus, volume)
