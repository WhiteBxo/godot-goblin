extends SceneTree

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)


func _delay(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout


func _wait_for_gap(music: TitleMusic) -> void:
	music.seek(music.stream.get_length() - 0.15)
	var timer := music.get_node("ReplayTimer") as Timer
	var deadline := Time.get_ticks_msec() + 2000
	while timer.is_stopped() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not music.playing, "Real Ogg reaches its natural end")


func _run() -> void:
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/title_music_%d" % OS.get_process_id())
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	# Drain the engine's initial loading frame before timing playback. Its delta
	# can exceed one second and expire a new timer before the first Tween tick.
	await process_frame
	await process_frame
	var music_bus := AudioServer.get_bus_index(&"Music")
	var bus_volume := AudioServer.get_bus_volume_db(music_bus)
	_check(change_scene_to_file(GameEntry.TITLE_SCENE) == OK, "Load real title")
	await scene_changed
	var title := current_scene as TitleMenu
	var music := title.get_node("TitleMusic") as TitleMusic
	var timer := music.get_node("ReplayTimer") as Timer
	var stream := music.stream as AudioStreamOggVorbis
	_check(stream != null and stream.get_length() > 1.0, "User Ogg imports and decodes")
	_check(not stream.loop and stream.beat_count == 0, "Imported track has no native or beat looping")
	var settings := ConfigFile.new()
	_check(settings.load("res://assets/audio/music/start.ogg.import") == OK, "Import configuration exists")
	_check(settings.get_value("params", "loop") == false, "Import loop is explicitly disabled")
	_check(music.bus == &"Music" and music.max_polyphony == 1, "One non-positional Music voice")
	_check(music.playing and music.volume_linear < 0.1, "Entry automatically starts quietly")
	await _delay(1.0)
	_check(music.volume_linear > 0.05 and music.volume_db < music.target_volume_db, "Volume rises during fade-in")
	await _delay(1.15)
	_check(is_equal_approx(music.volume_db, music.target_volume_db), "Two-second fade reaches configured volume")
	await _wait_for_gap(music)
	_check(timer.one_shot and is_equal_approx(timer.wait_time, 15.0) and timer.time_left > 14.5, "Natural finish schedules a 15-second gap")
	await _delay(14.0)
	_check(not music.playing and timer.time_left > 0.0, "Still silent before 15 seconds")
	await _delay(1.25)
	_check(music.playing and music.get_playback_position() < 1.0, "Restarts from beginning after full gap")
	_check(music.volume_db < music.target_volume_db, "Replay also fades in")
	# Leave while the incoming fade is active; duplicate button requests are ignored.
	var state := root.get_node("GameState")
	_check(state.begin_business_transaction(), "Reserve session to exercise failed navigation")
	title._request_new_game()
	title._request_new_game()
	await _delay(0.2)
	_check(title._starting and music._leaving and music.playing, "Departure locks input while fading")
	await _delay(0.4)
	_check(current_scene == title and not title._starting and music.playing, "Failed navigation restores title and music")
	state.end_business_transaction()
	await _wait_for_gap(music)
	await music.fade_out()
	_check(timer.is_stopped() and not music.playing, "Leaving during silence cancels pending replay immediately")
	await _delay(0.1)
	_check(not music.playing, "Cancelled replay remains silent")
	music.play_from_start()
	await _wait_for_gap(music)
	var old_music: WeakRef = weakref(music)
	var old_timer: WeakRef = weakref(timer)
	_check(GameEntry.return_to_title(self) == OK, "Reenter title through navigation")
	await scene_changed
	await process_frame
	_check(old_music.get_ref() == null and old_timer.get_ref() == null, "Scene exit frees playback and pending timer")
	music = current_scene.get_node("TitleMusic") as TitleMusic
	_check(music.playing and music.get_playback_position() < 1.0, "Returning title starts a fresh track")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(music_bus), bus_volume), "Fades preserve shared Music bus volume")
	# Let the audio thread release its last decoder before stopping the test process.
	current_scene.queue_free()
	await _delay(0.2)
	print("TITLE_MUSIC: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
