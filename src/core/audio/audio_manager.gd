class_name AudioManager
extends Node
## Scene-local, non-positional audio. Music is independent of sound ownership.

signal sound_finished(handle: int, cancelled: bool)

const SILENCE_DB: float = -80.0
const INVALID_HANDLE: int = 0

@export_range(1, 32) var pool_size: int = 8
## Direct resource references are export-safe; the same catalogue serves all APIs.
@export var sounds: Dictionary[String, AudioStream] = {}

var last_error: String = ""
var _music: AudioStreamPlayer
var _music_id: String = ""
var _music_tween: Tween
var _music_action: AudioAction
var _bgm_streams: Dictionary[String, AudioStream] = {}
var _players: Array[AudioStreamPlayer] = []
var _active: Dictionary = {}
var _next_handle: int = 1


func _ready() -> void:
	# BGM and UI remain audible during pause. Each SFX voice overrides this mode.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = AudioStreamPlayer.new()
	_music.name = "MusicPlayer"
	_music.bus = &"Music"
	add_child(_music)
	_music.finished.connect(_on_music_finished)
	for index in range(pool_size):
		var player := AudioStreamPlayer.new()
		player.name = "SoundPlayer%d" % index
		add_child(player)
		player.finished.connect(_on_sound_finished.bind(player))
		_players.append(player)


func register_sound(id: String, stream: AudioStream, bgm_config: Dictionary = {}) -> Error:
	if id.is_empty() or stream == null:
		last_error = "Audio registration requires an id and AudioStream"
		return ERR_INVALID_PARAMETER
	var music_stream: AudioStream
	if not bgm_config.is_empty():
		music_stream = _prepare_bgm(id, stream, bgm_config)
		if music_stream == null:
			return ERR_INVALID_PARAMETER
	sounds[id] = stream
	_bgm_streams.erase(id)
	if music_stream != null:
		_bgm_streams[id] = music_stream
	last_error = ""
	return OK


## Different tracks fade out then fade in, each leg lasting fade_seconds.
## Latest valid request wins. Replaying the current id adjusts volume, not position.
func play_bgm(id: String, fade_seconds: float = 0.5, volume_db: float = 0.0, restart: bool = false) -> Error:
	if not _available() or not _valid_fade(fade_seconds, volume_db):
		return ERR_INVALID_PARAMETER
	var stream := _resolve(id)
	if stream == null:
		return ERR_DOES_NOT_EXIST
	stream = _bgm_streams.get(id, stream)
	if not restart and _music.playing and _music_id == id and _music.stream == stream:
		return fade_bgm(volume_db, fade_seconds)
	_kill_music_tween()
	_music_action = AudioAction.new()
	if _music.playing and fade_seconds > 0.0:
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", SILENCE_DB, fade_seconds)
		_music_tween.tween_callback(_start_music.bind(id, stream, SILENCE_DB))
		_music_tween.tween_property(_music, "volume_db", clampf(volume_db, SILENCE_DB, 6.0), fade_seconds)
	else:
		_start_music(id, stream, SILENCE_DB if fade_seconds > 0.0 else clampf(volume_db, SILENCE_DB, 6.0))
		if fade_seconds > 0.0:
			_music_tween = create_tween()
			_music_tween.tween_property(_music, "volume_db", clampf(volume_db, SILENCE_DB, 6.0), fade_seconds)
	_watch_music_transition()
	return OK


func get_music_action() -> AudioAction:
	return _music_action


func fade_bgm(volume_db: float, seconds: float) -> Error:
	if not _available() or not _valid_fade(seconds, volume_db):
		return ERR_INVALID_PARAMETER
	last_error = ""
	_kill_music_tween()
	_music_action = AudioAction.new()
	if seconds == 0.0:
		_music.volume_db = clampf(volume_db, SILENCE_DB, 6.0)
	else:
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", clampf(volume_db, SILENCE_DB, 6.0), seconds)
	_watch_music_transition()
	return OK


func stop_bgm(fade_seconds: float = 0.0) -> void:
	if not _available() or not _valid_fade(fade_seconds):
		return
	last_error = ""
	_kill_music_tween()
	_music_action = AudioAction.new()
	if fade_seconds > 0.0 and _music.playing:
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", SILENCE_DB, fade_seconds)
		_music_tween.tween_callback(_stop_music)
	else:
		_stop_music()

	_watch_music_transition()


func play_sfx(id: String, owner: RefCounted = null, volume_db: float = 0.0) -> int:
	return _play_sound(_resolve(id), &"SFX", owner, volume_db)


func play_ui(id: String, owner: RefCounted = null, volume_db: float = 0.0) -> int:
	return _play_sound(_resolve(id), &"UI", owner, volume_db)


## Compatibility boundary for legacy story data. Prefer registered ids in new data.
func play_sfx_path(path: String, owner: RefCounted = null) -> int:
	last_error = ""
	if not path.begins_with("res://") or not ResourceLoader.exists(path, "AudioStream"):
		last_error = "Optional sound missing: " + path
		return INVALID_HANDLE
	var stream := load(path) as AudioStream
	if stream == null:
		last_error = "Optional sound is not an AudioStream: " + path
		return INVALID_HANDLE
	return _play_sound(stream, &"SFX", owner, 0.0)


func stop_sound(handle: int, fade_seconds: float = 0.0, cancelled: bool = true) -> void:
	if not _active.has(handle) or not _valid_fade(fade_seconds):
		return
	var voice: Dictionary = _active[handle]
	var tween: Tween = voice["tween"]
	if tween != null:
		tween.kill()
	var player: AudioStreamPlayer = voice["player"]
	if fade_seconds > 0.0:
		tween = player.create_tween()
		voice["tween"] = tween
		tween.tween_property(player, "volume_db", SILENCE_DB, fade_seconds)
		tween.tween_callback(stop_sound.bind(handle))
		return
	# stop() does not emit finished; explicitly return this voice to the pool.
	player.stop()
	player.stream = null
	_active.erase(handle)
	sound_finished.emit(handle, cancelled)


## Null is reserved for unowned scene/UI sounds and never means "stop all".
func stop_owned(owner: RefCounted, fade_seconds: float = 0.0) -> void:
	if owner == null:
		return
	for handle: int in _active.keys():
		if _active.has(handle) and _active[handle]["owner"] == owner:
			stop_sound(handle, fade_seconds)


func get_active_sound_count(owner: RefCounted = null) -> int:
	if owner == null:
		return _active.size()
	var count := 0
	for voice: Dictionary in _active.values():
		if voice["owner"] == owner:
			count += 1
	return count


func get_bgm_state() -> Dictionary:
	return {"id": _music_id, "playing": is_instance_valid(_music) and _music.playing,
		"volume_db": _music.volume_db if is_instance_valid(_music) else SILENCE_DB}


func _available() -> bool:
	if not is_node_ready() or not is_inside_tree() or is_queued_for_deletion():
		last_error = "AudioManager is not ready"
		return false
	return true


func _valid_fade(seconds: float, volume_db: float = 0.0) -> bool:
	if not is_finite(seconds) or seconds < 0.0 or not is_finite(volume_db):
		last_error = "Audio requires finite volume and fade seconds >= 0"
		return false
	return true


func _resolve(id: String) -> AudioStream:
	last_error = ""
	var stream: AudioStream = sounds.get(id)
	if stream == null:
		last_error = "Unknown or empty audio id: " + id
	return stream


## Only the BGM copy receives loop overrides; SFX/UI keep the original stream.
func _prepare_bgm(id: String, stream: AudioStream, config: Dictionary) -> AudioStream:
	var offset: Variant = config.get("loop_offset", 0.0)
	var looping: Variant = config.get("loop", true)
	var length := stream.get_length()
	if not (offset is float or offset is int) or not is_finite(float(offset)):
		last_error = "BGM %s: loop_offset must be a finite number in seconds" % id
	elif not looping is bool:
		last_error = "BGM %s: loop must be a bool" % id
	elif offset < 0.0 or not is_finite(length) or length <= 0.0 or offset >= length:
		last_error = "BGM %s: loop_offset must satisfy 0 <= offset < duration (%s seconds)" % [id, length]
	elif not stream is AudioStreamOggVorbis:
		last_error = "BGM %s: loop overrides require AudioStreamOggVorbis; unsupported format %s" % [id, stream.get_class()]
	else:
		var music_stream := stream.duplicate() as AudioStreamOggVorbis
		if music_stream != null:
			music_stream.loop = looping
			music_stream.loop_offset = float(offset)
			# REAPER file end is the loop end, regardless of imported beat metadata.
			music_stream.beat_count = 0
			return music_stream
		last_error = "BGM %s: failed to duplicate AudioStreamOggVorbis" % id
	push_warning(last_error)
	return null


func _play_sound(stream: AudioStream, bus: StringName, owner: RefCounted, volume_db: float) -> int:
	if stream == null or not _available() or not _valid_fade(0.0, volume_db):
		return INVALID_HANDLE
	var player: AudioStreamPlayer
	for candidate in _players:
		var used := false
		for voice: Dictionary in _active.values():
			if voice["player"] == candidate:
				used = true
				break
		if not used:
			player = candidate
			break
	if player == null:
		last_error = "Sound pool is full; optional sound skipped"
		return INVALID_HANDLE
	player.process_mode = Node.PROCESS_MODE_ALWAYS if bus == &"UI" else Node.PROCESS_MODE_PAUSABLE
	player.bus = bus
	player.volume_db = clampf(volume_db, SILENCE_DB, 6.0)
	player.stream = stream
	var handle := _next_handle
	_next_handle += 1
	_active[handle] = {"player": player, "owner": owner, "tween": null}
	player.play()
	last_error = ""
	return handle


func _on_sound_finished(player: AudioStreamPlayer) -> void:
	for handle: int in _active.keys():
		if _active[handle]["player"] == player:
			stop_sound(handle, 0.0, false)
			return


func _start_music(id: String, stream: AudioStream, volume_db: float) -> void:
	_music.stop()
	_music.stream = stream
	_music.volume_db = volume_db
	_music_id = id
	_music.play()


func _stop_music() -> void:
	_music.stop()
	_music.stream = null
	_music_id = ""


func _on_music_finished() -> void:
	# A short non-looping track may finish during a switch: preserve its pending Tween.
	_music_id = ""


func _watch_music_transition() -> void:
	if _music_tween != null and _music_tween.is_valid():
		if not _music_tween.finished.is_connected(_music_action.settle.bind(true)):
			_music_tween.finished.connect(_music_action.settle.bind(true))
	else:
		_music_action.settle(true)


func _kill_music_tween() -> void:
	if _music_action != null:
		_music_action.settle(false, "Music transition replaced or cancelled")
	if _music_tween != null:
		_music_tween.kill()
		_music_tween = null


func _exit_tree() -> void:
	_kill_music_tween()
	for handle: int in _active.keys():
		stop_sound(handle)
