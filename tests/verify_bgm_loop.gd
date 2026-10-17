extends SceneTree

const OGG_PATH := "res://tests/fixtures/bgm_intro_loop.ogg"
var _checks := 0
var _failures := 0
var _audio: AudioManager


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)


func _delay(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	_audio = load("res://src/core/audio/audio_manager.tscn").instantiate()
	root.add_child(_audio)
	var source := load(OGG_PATH) as AudioStreamOggVorbis
	_check(source != null and source.get_length() > 1.0, "Real Ogg fixture loads")
	if source == null:
		quit(1)
		return
	var original_loop := source.loop
	var original_offset := source.loop_offset
	var library := SoundLibrary.new()
	library.entries = [
		{"id": "intro", "path": OGG_PATH, "loop": true, "loop_offset": 0.4},
		{"id": "whole", "streams": [source], "loop": true},
		{"id": "once", "streams": [source], "loop": false},
	]
	_check(library.register_all(_audio).is_empty(), "Path and resource entries register")
	_check(library.choose_variant("intro") == "intro", "Path catalogue resolves logical ID")
	_check(source.loop == original_loop and source.loop_offset == original_offset, "Shared source remains unchanged")
	_check(_audio.sounds["intro"] == source, "SFX/UI catalogue retains original source")
	var sfx := _audio.play_sfx("intro")
	var ui := _audio.play_ui("intro")
	_check(_audio._active[sfx].player.stream == source and _audio._active[ui].player.stream == source, "SFX and UI players use original stream")
	_audio.stop_sound(sfx)
	_audio.stop_sound(ui)
	_audio.play_bgm("intro", 0.0)
	var intro := _audio._music.stream as AudioStreamOggVorbis
	_check(intro != source and intro.loop and is_equal_approx(intro.loop_offset, 0.4), "BGM has isolated native loop settings")
	_check(intro.beat_count == 0 and _audio._music.bus == &"Music", "File end and Music routing preserved")
	_check(_audio._music.get_playback_position() < 0.2, "Initial playback begins at Intro")
	# Observe two real decoder wraps; no test seek or script restart drives looping.
	var wraps := 0
	var previous := 0.0
	var deadline := Time.get_ticks_msec() + 4500
	while wraps < 2 and Time.get_ticks_msec() < deadline:
		await process_frame
		var position := _audio._music.get_playback_position()
		if position < previous - 0.3:
			wraps += 1
			_check(position >= 0.38 and position < 0.65, "Decoder wraps to Loop Start, skipping Intro")
		previous = position
	_check(wraps == 2 and _audio._music.playing, "Intro followed by repeated native loops")
	var playback := _audio._music.get_stream_playback()
	_audio.play_bgm("intro", 0.0, -9.0)
	_check(_audio._music.get_stream_playback() == playback, "Same ID preserves decoder and Intro progress")
	_check(is_equal_approx(_audio._music.volume_db, -9.0), "Repeated request adjusts volume")
	_audio.play_bgm("intro", 0.0, 0.0, true)
	_check(_audio._music.get_playback_position() < 0.2, "Explicit restart begins at Intro")
	_audio.play_bgm("whole", 0.0)
	_check(is_zero_approx(_audio._music.stream.loop_offset), "Omitted loop_offset defaults to zero")
	wraps = 0
	previous = 0.0
	deadline = Time.get_ticks_msec() + 2500
	while wraps == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
		var position := _audio._music.get_playback_position()
		if position < previous - 0.5:
			wraps += 1
			_check(position < 0.2, "Whole track wraps to zero")
		previous = position
	_check(wraps == 1 and _audio._music.playing, "Whole track loops past file end")
	_audio.play_bgm("intro", 0.05, -6.0)
	await _delay(0.15)
	_check(_audio.get_bgm_state().id == "intro" and _audio._music.get_playback_position() < 0.3, "Switch back starts Intro after fade-out")
	_check(is_equal_approx(_audio._music.volume_db, -6.0), "Switch fade-in reaches target")
	_audio.fade_bgm(-18.0, 0.1)
	await _delay(0.15)
	_check(is_equal_approx(_audio._music.volume_db, -18.0), "Configured BGM volume fade works")
	_audio.stop_bgm(0.1)
	await _delay(0.15)
	_check(not _audio._music.playing, "Configured BGM fades out and stops")
	_audio.play_bgm("once", 0.0)
	_check(not _audio._music.stream.loop, "loop=false overrides stream loop")
	await _delay(1.5)
	_check(not _audio._music.playing and _audio.get_bgm_state().id.is_empty(), "Non-looping BGM ends naturally")
	# Force imported metadata on a private source to verify the EOF policy.
	var beats := source.duplicate() as AudioStreamOggVorbis
	beats.bpm = 120.0
	beats.beat_count = 1
	beats.loop = true
	_check(_audio.register_sound("beats", beats, {"loop": false}) == OK, "Explicit non-looping configuration registers")
	_audio.play_bgm("beats", 0.0)
	_check(_audio._music.stream.beat_count == 0 and not _audio._music.stream.loop and beats.beat_count == 1 and beats.loop, "Beat and loop overrides are isolated")
	await _delay(0.7)
	_check(_audio._music.playing, "Imported beat metadata cannot truncate file end")
	await _delay(0.8)
	_check(not _audio._music.playing, "loop=false disables an originally looping source")
	_audio.play_bgm("intro", 0.0)
	for offset: Variant in [-1.0, source.get_length(), source.get_length() + 1.0, NAN, INF, "0.4", true]:
		_check(_audio.register_sound("intro", source, {"loop_offset": offset}) != OK and not _audio.last_error.is_empty(), "Invalid offset rejected safely: %s" % offset)
	_check(_audio.register_sound("bad_bool", source, {"loop": "true"}) != OK, "Invalid loop type rejected")
	var wav := AudioDemoTones.tone(220.0, 1.0)
	_check(_audio.register_sound("unsupported", wav, {"loop_offset": 0.4}) != OK and _audio.last_error.contains("AudioStreamOggVorbis"), "Unsupported format has clear diagnostic")
	library.entries = [
		{"id": "missing", "path": "res://tests/fixtures/missing.ogg", "loop": true},
		{"id": "wrong_type", "path": "res://src/core/audio/audio_manager.gd", "loop": true},
		{"id": "bad_path", "path": 42},
		{"id": "both", "path": OGG_PATH, "streams": [source]},
		{"id": "bad_offset", "path": OGG_PATH, "loop_offset": -1.0},
	]
	_check(library.register_all(_audio).size() == 5, "Missing, wrong-type, ambiguous paths and invalid offsets reported")
	_check(_audio.play_bgm("missing", 0.0) != OK and _audio.get_bgm_state().id == "intro", "Invalid replacement preserves active BGM")
	_check(_audio._music.stream == intro, "Invalid re-registration preserves original BGM configuration")
	# Exercise the same adapter used by StoryDirector without changing JSON.
	var adapter := StoryAudioAdapter.new(_audio)
	var action := adapter.request({"command": "play_bgm", "id": "whole", "fade": 0.05})
	await _delay(0.15)
	_check(action.completed and action.succeeded and _audio.get_bgm_state().id == "whole", "Story adapter switches configured BGM")
	action = adapter.request({"command": "stop_bgm", "fade": 0.05})
	await _delay(0.1)
	_check(action.completed and action.succeeded and not _audio._music.playing, "Story adapter stops configured BGM")
	adapter.stop_owned()
	_audio.free()
	await _delay(0.1) # Allow mixer and deferred action notifications to release playback.
	print("BGM_LOOP: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
