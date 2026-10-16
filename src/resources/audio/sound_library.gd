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
		if id.is_empty() or streams.is_empty():
			errors.append("Invalid sound entry: " + id)
			continue
		for index in range(streams.size()):
			var stream := streams[index] as AudioStream
			var variant := variant_id(id, index, streams.size())
			if stream == null:
				errors.append("Missing AudioStream: " + variant)
				continue
			if audio.register_sound(variant, stream) != OK:
				errors.append(audio.last_error)
			if index == 0 and variant != id:
				audio.register_sound(id, stream)
	return errors


func choose_variant(id: String, previous: String = "") -> String:
	for entry in entries:
		if entry.get("id", "") != id:
			continue
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


static func variant_id(id: String, index: int, count: int) -> String:
	return id if count == 1 else "%s.%02d" % [id, index + 1]
