class_name StoryAudioAdapter
extends RefCounted
## Keeps story lifetime/legacy data separate from the audio service.

var last_error: String = ""
var _audio: AudioManager
var _owner := RefCounted.new()


func _init(audio: AudioManager) -> void:
	_audio = audio


func play_sfx(step: Dictionary) -> bool:
	if not is_instance_valid(_audio) or not _audio.is_inside_tree() or _audio.is_queued_for_deletion():
		last_error = "Optional audio service unavailable"
		return false
	var handle: int
	if step.has("id"):
		handle = _audio.play_sfx(step["id"], _owner)
	else:
		handle = _audio.play_sfx_path(step["path"], _owner)
	last_error = _audio.last_error
	return handle != AudioManager.INVALID_HANDLE


func stop_owned() -> void:
	if is_instance_valid(_audio):
		_audio.stop_owned(_owner)
