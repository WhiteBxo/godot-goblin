extends SceneTree

const LIBRARY: SoundLibrary = preload("res://src/resources/audio/sound_library.tres")
const MANAGER := preload("res://src/core/audio/audio_manager.tscn")
const DEMO := preload("res://src/debug/audio/sound_library_demo.tscn")
var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	var audio := MANAGER.instantiate() as AudioManager
	root.add_child(audio)
	_check(LIBRARY.register_all(audio).is_empty(), "All assets register")
	var owner := RefCounted.new()
	var total := 0
	for entry in LIBRARY.entries:
		var streams: Array = entry["streams"]
		_check(audio.sounds.has(entry["id"]), "Base ID registered")
		var previous := ""
		for attempt in range(20):
			var chosen := LIBRARY.choose_variant(entry["id"], previous)
			_check(audio.sounds.has(chosen), "Variant exists")
			_check(streams.size() == 1 or chosen != previous, "No adjacent repeated variant")
			previous = chosen
		for index in range(streams.size()):
			total += 1
			var id := SoundLibrary.variant_id(entry["id"], index, streams.size())
			var stream := audio.sounds[id] as AudioStreamWAV
			_check(stream != null and stream.get_length() > .02, "WAV loads with duration: " + id)
			_check(stream.format == AudioStreamWAV.FORMAT_16_BITS, "Uncompressed PCM import: " + id)
			_check((stream.loop_mode == AudioStreamWAV.LOOP_FORWARD) == bool(entry["loop"]), "Imported loop flag: " + id)
			var handle := audio.play_ui(id, owner) if id.begins_with("ui.") else audio.play_sfx(id, owner)
			await process_frame
			_check(handle > 0 and audio.get_active_sound_count(owner) == 1, "Real service playback: " + id)
			audio.stop_sound(handle)
			audio.stop_sound(handle)
			_check(audio.get_active_sound_count(owner) == 0, "Stop is idempotent: " + id)
	_check(total == 31, "31 resources")
	var first := audio.play_sfx("player.step_wood", owner)
	var second := audio.play_sfx("player.step_wood", owner)
	_check(first > 0 and second != first and audio.get_active_sound_count(owner) == 2, "Repeated overlap")
	audio.stop_owned(owner)
	audio.play_sfx("ambience.cave", owner)
	await create_timer(12.2).timeout
	_check(audio.get_active_sound_count(owner) == 1, "Ambience remains playing past a full loop")
	audio.stop_owned(owner)
	audio.play_ui("ui.hover", owner)
	await create_timer(.4).timeout
	_check(audio.get_active_sound_count(owner) == 0, "Natural completion recycles")
	_check(audio.play_sfx("unknown") == 0, "Missing ID safe")
	_check(audio.play_sfx_path("res://assets/audio/absent.wav") == 0, "Missing resource safe")
	_check(LIBRARY.choose_variant("unknown").is_empty(), "Unknown variant safe")
	var broken := SoundLibrary.new()
	broken.entries = [{"id": "broken", "streams": [null]}]
	_check(broken.register_all(audio).size() == 1 and not audio.sounds.has("broken"), "Null stream safely reported")
	_check(LIBRARY.register_all(null).size() == 1, "Missing service safe")
	audio.free()
	var demo := DEMO.instantiate()
	root.add_child(demo)
	await process_frame
	_check(demo._rows.size() == 31, "Demo lists all files")
	demo._filter(1)
	_check(demo._visible_rows.size() == 7, "UI category contains seven variants")
	demo.start_sequence()
	var deadline := Time.get_ticks_msec() + 6000
	while demo._continuous and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not demo._continuous and demo.audio.get_active_sound_count() == 0, "Sequence finishes naturally")
	demo._filter(5)
	demo._list.select(3)
	demo.play_selected()
	_check(demo.audio.get_active_sound_count() == 1, "Loop preview starts")
	demo._volume.value = -18
	_check(demo.audio.get_active_sound_count() == 1 and demo._volume_label.text.contains("-18"), "Volume restarts single preview")
	demo.stop_preview()
	_check(demo.audio.get_active_sound_count() == 0, "Loop preview stops")
	demo.start_sequence()
	# Jump to a looping row to exercise the real six-second audition timeout.
	demo.stop_preview()
	demo._continuous = true
	demo._sequence_index = 3
	demo._play(3)
	await create_timer(6.3).timeout
	_check(demo._sequence_index == 4 and demo.audio.get_active_sound_count() == 1, "Loop sequence advances after six seconds")
	demo.stop_preview()
	demo.start_sequence()
	demo.stop_preview()
	await create_timer(.4).timeout
	_check(not demo._continuous and demo.audio.get_active_sound_count() == 0, "Stop cancels sequence timer")
	demo._missing_probe()
	_check(demo._status.text.contains("安全跳过"), "Demo reports missing resource")
	demo._filter(0)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("goblin_sound_library.png"))
	demo.free()
	await process_frame
	print("Sound Library: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)
