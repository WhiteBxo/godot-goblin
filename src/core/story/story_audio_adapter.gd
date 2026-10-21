class_name StoryAudioAdapter
extends RefCounted
## Keeps story lifetime/legacy data separate from the audio service.

var last_error: String = ""
var _audio: AudioManager
var _owner := RefCounted.new()
var _voices: Dictionary = {}
var _music_action: AudioAction


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


## Number of live voices still owned by this adapter. Cancellation must bring this to
## zero; a plain "active voices" count also includes ambience and unrelated one-shots,
## which makes it a misleading leak check.
func owned_voice_count() -> int:
	if not is_instance_valid(_audio):
		return 0
	return _audio.get_active_sound_count(_owner)


func stop_owned(preserve_music: bool = false) -> void:
	if is_instance_valid(_audio):
		_audio.stop_owned(_owner)
		if not preserve_music and _music_action != null and _audio.is_inside_tree() and _audio.get_music_action() == _music_action:
			_audio.stop_bgm()
	_music_action = null
	_on_audio_exiting()
	if is_instance_valid(_audio):
		if _audio.sound_finished.is_connected(_on_sound_finished):
			_audio.sound_finished.disconnect(_on_sound_finished)
		if _audio.tree_exiting.is_connected(_on_audio_exiting):
			_audio.tree_exiting.disconnect(_on_audio_exiting)


## Optional resources settle successfully with a diagnostic; caller emits skipped.
func request(step: Dictionary) -> AudioAction:
	last_error = ""
	var action := AudioAction.new()
	if not is_instance_valid(_audio) or not _audio.is_inside_tree() or _audio.is_queued_for_deletion():
		last_error = "Optional audio service unavailable"
		action.settle(true)
		return action
	if step.command == "play_sfx":
		var handle := _audio.play_sfx(step.id, _owner) if step.has("id") else _audio.play_sfx_path(step.path, _owner)
		last_error = _audio.last_error
		if handle == AudioManager.INVALID_HANDLE:
			action.settle(true)
		else:
			_voices[handle] = action
			if not _audio.sound_finished.is_connected(_on_sound_finished):
				_audio.sound_finished.connect(_on_sound_finished)
			if not _audio.tree_exiting.is_connected(_on_audio_exiting):
				_audio.tree_exiting.connect(_on_audio_exiting)
		return action
	var error: Error = OK
	match step.command:
		"play_bgm": error = _audio.play_bgm(step.id, step.get("fade", 0.5), step.get("volume_db", 0.0))
		"fade_bgm": error = _audio.fade_bgm(step.volume_db, step.get("fade", 0.5))
		"stop_bgm": _audio.stop_bgm(step.get("fade", 0.0))
	last_error = _audio.last_error
	if error != OK:
		action.settle(true)
		return action
	_music_action = _audio.get_music_action()
	return _music_action


func _on_sound_finished(handle: int, cancelled: bool) -> void:
	if _voices.has(handle):
		var action: AudioAction = _voices[handle]
		_voices.erase(handle)
		action.settle(not cancelled, "Sound stopped" if cancelled else "")


func _on_audio_exiting() -> void:
	for action: AudioAction in _voices.values():
		action.settle(false, "AudioManager exited")
	_voices.clear()
