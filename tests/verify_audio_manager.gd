extends SceneTree

var _checks: int = 0
var _failures: Array[String] = []
var _audio: AudioManager


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)


func _delay(seconds: float = 0.08) -> void:
	await create_timer(seconds).timeout


func _until(predicate: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec() + 2500
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(predicate.call(), message)


func _run() -> void:
	_audio = load("res://src/core/audio/audio_manager.tscn").instantiate()
	_audio.pool_size = 3
	root.add_child(_audio)
	AudioDemoTones.populate(_audio)
	for bus: StringName in [&"Music", &"SFX", &"UI"]:
		var index := AudioServer.get_bus_index(bus)
		_check(index > 0 and AudioServer.get_bus_send(index) == &"Master", "%s bus routes to Master" % bus)
	_test_validation()
	await _delay() # Let the first frame/resource setup settle before measuring Tween time.
	await _test_music()
	await _test_pool()
	await _test_story()
	_audio.queue_free()
	await process_frame
	await _test_demo()
	print("AUDIO_MANAGER: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _test_validation() -> void:
	var library := StoryLibrary.new()
	var valid := {"version": 1, "events": {"audio.test": {"steps": [{"command": "play_sfx", "id": "demo.low"}]}}}
	_check(library.load_json(JSON.stringify(valid)) == OK, "Story accepts logical sound id")
	for bad: Dictionary in [{"id": ""}, {"id": 3}, {}, {"id": "demo.low", "path": "res://test.wav"}, {"path": "user://bad.wav"}]:
		bad["command"] = "play_sfx"
		valid["events"]["audio.test"]["steps"] = [bad]
		_check(library.load_json(JSON.stringify(valid)) == ERR_INVALID_DATA, "Story rejects ambiguous/invalid audio reference: %s" % bad)
	_check(_audio.play_bgm("missing", 0.0) != OK and not _audio.get_bgm_state()["playing"], "Missing BGM safely rejects")
	_check(_audio.play_sfx("missing") == 0 and _audio.get_active_sound_count() == 0, "Missing SFX consumes no slot")
	_check(_audio.register_sound("bad", null) == ERR_INVALID_PARAMETER, "Null registration rejects")
	_check(_audio.play_bgm("demo.music_a", -1.0) != OK, "Negative fade rejects")
	_check(_audio.play_bgm("demo.music_a", NAN) != OK, "Non-finite fade rejects")


func _test_music() -> void:
	_check(_audio.play_bgm("demo.music_a", 0.6) == OK, "Music starts with fade-in")
	_check(_audio.get_bgm_state()["volume_db"] == -80.0, "Fade-in starts at silence floor")
	await _delay(0.10)
	var volume: float = _audio.get_bgm_state()["volume_db"]
	_check(volume > -80.0 and volume < 0.0, "Fade-in has intermediate volume")
	await _delay(0.7)
	_check(is_zero_approx(_audio.get_bgm_state()["volume_db"]), "Fade-in reaches target")
	_check(_audio.play_bgm("missing", 0.1) != OK and _audio.get_bgm_state()["id"] == "demo.music_a", "Missing replacement preserves current BGM")
	_audio.play_bgm("demo.music_b", 0.12)
	await _delay(0.06)
	_check(_audio.get_bgm_state()["id"] == "demo.music_a" and _audio.get_bgm_state()["volume_db"] < 0.0, "Switch fades old track before replacing")
	await _delay(0.25)
	_check(_audio.get_bgm_state()["id"] == "demo.music_b" and is_zero_approx(_audio.get_bgm_state()["volume_db"]), "Switch fades new track to target")
	await _delay(0.12)
	var position := _audio._music.get_playback_position()
	_audio.play_bgm("demo.music_b", 0.0)
	_check(_audio._music.get_playback_position() >= position, "Same-id playback does not restart")
	_audio.play_bgm("demo.music_a", 0.2)
	_audio.play_bgm("demo.music_b", 0.0)
	await _delay(0.45)
	_check(_audio.get_bgm_state()["id"] == "demo.music_b", "Superseded switch never starts stale track")
	_audio.stop_bgm(0.2)
	await _delay(0.06)
	_check(_audio.get_bgm_state()["playing"] and _audio.get_bgm_state()["volume_db"] < 0.0, "Stop fades before stopping")
	_audio.play_bgm("demo.music_a", 0.0)
	await _delay(0.24)
	_check(_audio.get_bgm_state()["playing"] and _audio.get_bgm_state()["id"] == "demo.music_a", "New playback cancels pending stop")
	_audio.fade_bgm(-18.0, 0.1)
	await _delay(0.15)
	_check(is_equal_approx(_audio.get_bgm_state()["volume_db"], -18.0), "Explicit fade reaches requested volume")
	_audio.stop_bgm(0.1)
	await _delay(0.15)
	_check(not _audio.get_bgm_state()["playing"] and _audio.get_bgm_state()["id"] == "", "Fade-out clears stopped music")
	_audio.play_bgm("demo.music_a", 0.0)
	_audio.play_bgm("demo.music_b", 0.1)
	_audio.stop_bgm()
	await _delay(0.25)
	_check(not _audio.get_bgm_state()["playing"], "Immediate stop cancels pending switch")
	_audio.register_sound("short", AudioDemoTones.sample_clip(preload("res://assets/audio/ui/confirm.wav"), 0.06))
	_audio.play_bgm("short", 0.0)
	_audio.play_bgm("demo.music_b", 0.15)
	await _delay(0.4)
	_check(_audio.get_bgm_state()["id"] == "demo.music_b", "Short outgoing track finishing does not cancel switch")


func _test_pool() -> void:
	var owner := RefCounted.new()
	var other := RefCounted.new()
	var one := _audio.play_sfx("demo.story", owner)
	var two := _audio.play_sfx("demo.story", other)
	var three := _audio.play_ui("demo.ui")
	_check(one > 0 and two > one and three > two and _audio.get_active_sound_count() == 3, "Three concurrent voices have unique handles")
	_check(_audio._active[one]["player"].bus == &"SFX" and _audio._active[three]["player"].bus == &"UI", "Voices use correct buses")
	_check(_audio.play_sfx("demo.low") == 0 and _audio.get_active_sound_count() == 3, "Full pool drops new sound without stealing")
	_audio.stop_owned(null)
	_check(_audio.get_active_sound_count() == 3, "Null owner cannot stop unrelated sounds")
	_audio.stop_owned(owner)
	_check(_audio.get_active_sound_count() == 2 and _audio.get_active_sound_count(other) == 1, "Owner cancellation preserves other owners and UI")
	var reused := _audio.play_sfx("demo.story", owner)
	_check(reused > three and _audio._players.size() == 3, "Stopped slot reused without creating nodes")
	_audio.stop_sound(one)
	_check(_audio.get_active_sound_count(owner) == 1, "Stale handle cannot stop reused slot")
	await _delay(0.25)
	_check(_audio.get_active_sound_count() == 2, "Natural UI finish recycles voice")
	_audio.stop_owned(owner, 0.2)
	await _delay(0.08)
	_check(_audio.get_active_sound_count(owner) == 1 and _audio._active[reused]["player"].volume_db < 0.0, "Owned fade has intermediate volume")
	_audio.stop_sound(reused)
	var fresh := _audio.play_sfx("demo.story", owner)
	await _delay(0.25)
	_check(_audio._active.has(fresh) and is_zero_approx(_audio._active[fresh]["player"].volume_db), "Cancelled fade never affects reused voice")
	_audio.stop_owned(owner)
	_audio.stop_owned(other)
	_audio.play_sfx("demo.low")
	await _delay(0.65)
	_check(_audio.get_active_sound_count() == 0, "Natural SFX finish returns slot")
	one = _audio.play_sfx("demo.story", owner)
	two = _audio.play_ui("demo.ui")
	paused = true
	_audio.stop_owned(owner, 0.1)
	_audio.fade_bgm(-12.0, 0.1)
	await _delay(0.25)
	_check(_audio._active.has(one) and _audio._active[one]["player"].stream_paused, "SFX and its fade pause with world")
	_check(not _audio._active.has(two), "UI audio continues during pause")
	_check(_audio.get_bgm_state()["playing"] and is_equal_approx(_audio.get_bgm_state()["volume_db"], -12.0), "BGM and fade continue during pause")
	paused = false
	await _delay(0.2)
	_check(_audio.get_active_sound_count(owner) == 0, "SFX fade resumes and recycles slot")


func _test_story() -> void:
	var state: Node = root.get_node("GameState")
	var before: Dictionary = state.to_dict()
	var game: MainGame = load("res://src/debug/story/legacy_shop.tscn").instantiate()
	root.add_child(game)
	var audio := game.get_audio_manager()
	AudioDemoTones.populate(audio)
	var director := game.get_story_director()
	_check(director.load_events("res://tests/fixtures/audio_events.json") == OK, "Audio story fixture loads")
	audio.play_bgm("demo.music_a", 0.0)
	var independent := audio.play_sfx("demo.story")
	director.request_event("audio.owned")
	await _until(func() -> bool: return audio.get_active_sound_count() == 3, "Director plays logical id and legacy path through adapter")
	_check(director.is_busy(), "Owned sounds play during active story")
	director.cancel_event()
	_check(audio.get_active_sound_count() == 1 and audio._active.has(independent), "Cancel stops only story-owned voices")
	_check(audio.get_bgm_state()["playing"] and audio.get_bgm_state()["id"] == "demo.music_a", "Story cancel leaves scene BGM playing")
	audio.stop_sound(independent)
	var skipped: Array[String] = []
	director.step_skipped.connect(func(_id: String, _index: int, reason: String) -> void: skipped.append(reason))
	director.request_event("audio.missing")
	await _until(func() -> bool: return not director.is_busy(), "Missing-audio story finishes")
	_check(not director.is_busy() and state.get_flag("audio.after_missing") and skipped.size() == 3, "Missing id, path and wrong-type resource skip and story advances")
	director.request_event("audio.finish")
	await _until(func() -> bool: return not director.is_busy(), "Successful audio story finishes")
	_check(not director.is_busy() and audio.get_active_sound_count() == 0, "Successful story finish also cleans owned voices")
	var first := StoryAudioAdapter.new(audio)
	var second := StoryAudioAdapter.new(audio)
	first.play_sfx({"id": "demo.story"})
	second.play_sfx({"id": "demo.story"})
	first.stop_owned()
	_check(audio.get_active_sound_count() == 1, "Separate adapters have isolated ownership")
	second.stop_owned()
	var handles: Array[int] = []
	for index in range(audio.pool_size):
		handles.append(audio.play_sfx("demo.story"))
	var skip_count := skipped.size()
	director.request_event("audio.finish")
	await _until(func() -> bool: return not director.is_busy(), "Pool-full story still finishes")
	_check(skipped.size() == skip_count + 1 and audio.get_active_sound_count() == audio.pool_size, "Pool-full story skips without stopping independent voices")
	for handle in handles:
		audio.stop_sound(handle)
	director.set_audio_adapter(null)
	director.request_event("audio.finish")
	await _until(func() -> bool: return not director.is_busy(), "Story without adapter still finishes")
	_check(skipped.size() == skip_count + 2, "No adapter produces a skipped step")
	director.set_audio_adapter(StoryAudioAdapter.new(audio))
	director.request_event("audio.owned")
	await _delay(0.1)
	director.queue_free()
	await process_frame
	_check(audio.get_active_sound_count() == 0 and audio.get_bgm_state()["playing"], "Director removal cleans sounds and preserves BGM")
	game.queue_free()
	await process_frame
	game = load("res://src/debug/story/legacy_shop.tscn").instantiate()
	root.add_child(game)
	director = game.get_story_director()
	director.load_events("res://tests/fixtures/audio_events.json")
	audio = game.get_audio_manager()
	AudioDemoTones.populate(audio)
	director.request_event("audio.owned")
	await _delay(0.1)
	audio.queue_free()
	await process_frame
	director.cancel_event()
	director.request_event("audio.finish")
	await _delay(0.2)
	_check(not director.is_busy(), "Removed audio service never blocks or crashes story")
	game.queue_free()
	await process_frame
	state.restore_state(before)


func _test_demo() -> void:
	var demo: Node = load("res://src/debug/audio/audio_demo.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	var audio: AudioManager = demo.get_node("AudioManager")
	_check(audio.sounds.has_all(["demo.music_a", "demo.music_b", "demo.low", "demo.high", "demo.ui", "demo.story", "music.daily_milk_tea"]), "Standalone scene initializes without MainGame")
	audio.play_bgm("demo.music_a", 0.0)
	audio.play_bgm("demo.music_b", 0.05)
	audio.play_sfx("demo.low")
	audio.play_sfx("demo.high")
	_check(audio.get_active_sound_count() == 2, "Standalone scene supports overlap")
	await _delay(0.15)
	_check(audio.get_bgm_state()["id"] == "demo.music_b", "Standalone scene supports music switching")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/audio-demo.png")
	audio.stop_bgm(0.1)
	demo.queue_free()
	await process_frame
	await _delay(0.2)
	_check(not is_instance_valid(audio), "Scene exit frees active players and pending fades")
