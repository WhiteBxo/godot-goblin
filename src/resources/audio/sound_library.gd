class_name SoundLibrary
extends Resource
## Export-tracked stream references; no playback nodes or bus configuration here.

@export var entries: Array[Dictionary] = []


func register_all(audio: AudioManager) -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_instance_valid(audio):
		errors.append("AudioManager unavailable")
		return errors
	for entry in entries:
		var id := str(entry.get("id", ""))
		var streams: Array = entry.get("streams", [])
		if entry.has("path"):
			var path: Variant = entry["path"]
			if not _audio_path_exists(entry):
				errors.append("Invalid or missing audio path: %s (%s)" % [id, path])
				continue
			var loaded := load(path) as AudioStream
			if loaded == null:
				errors.append("Failed to load AudioStream: %s (%s)" % [id, path])
				continue
			streams = [loaded]
		if id.is_empty() or streams.is_empty():
			errors.append("Invalid sound entry: " + id)
			continue
		for index in range(streams.size()):
			var stream := streams[index] as AudioStream
			var variant := variant_id(id, index, streams.size())
			if stream == null:
				errors.append("Missing AudioStream: " + variant)
				continue
			var bgm_config: Dictionary = {}
			# Existing WAV loop labels are metadata; preserve their imported behavior.
			if entry.has("loop_offset") or ((entry.has("path") or stream is AudioStreamOggVorbis) and entry.has("loop")):
				bgm_config = {"loop": entry.get("loop", true), "loop_offset": entry.get("loop_offset", 0.0)}
			if audio.register_sound(variant, stream, bgm_config) != OK:
				errors.append(audio.last_error)
				continue
			if index == 0 and variant != id:
				audio.register_sound(id, stream, bgm_config)
	return errors


func choose_variant(id: String, previous: String = "") -> String:
	for entry in entries:
		if entry.get("id", "") != id:
			continue
		if entry.has("path"):
			return id if _audio_path_exists(entry) else ""
		var streams: Array = entry.get("streams", [])
		var choices: Array[String] = []
		for index in range(streams.size()):
			var candidate := variant_id(id, index, streams.size())
			if streams[index] is AudioStream and candidate != previous:
				choices.append(candidate)
		if not choices.is_empty():
			return choices.pick_random()
		if streams.size() == 1 and streams[0] is AudioStream:
			return id
	return ""


func _audio_path_exists(entry: Dictionary) -> bool:
	var path: Variant = entry.get("path")
	return not entry.has("streams") and path is String and path.begins_with("res://") and ResourceLoader.exists(path, "AudioStream")


static func variant_id(id: String, index: int, count: int) -> String:
	return id if count == 1 else "%s.%02d" % [id, index + 1]
