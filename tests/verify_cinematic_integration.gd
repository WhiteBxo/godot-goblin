extends SceneTree

var _checks := 0
var _failures: Array[String] = []
var _game: MainGame
var _story: StoryDirector
var _actors: ActorDirector
var _cameras: CameraDirector
var _audio: AudioManager
var _state: Node
var _steps: Array[String] = []
var _results: Array[bool] = []
var _path := "user://godot-goblin-cinematic-%d.json" % OS.get_process_id()

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames(count: int = 3) -> void:
	for index in range(count):
		await process_frame

func _until(predicate: Callable, message: String, seconds: float = 3.0) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(predicate.call(), message)

func _data(steps: Array) -> String:
	return JSON.stringify({"version": 1, "events": {"cinematic.test": {"once": false, "steps": steps}}})

func _start(steps: Array) -> void:
	_steps.clear()
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string(_data(steps))
	file.close()
	_check(_story.load_events(_path) == OK, "Fixture validates: " + _story.last_error)
	_check(_story.request_event("cinematic.test") == OK, "Fixture starts")

func _new_game() -> void:
	_game = load("res://src/debug/story/legacy_shop.tscn").instantiate()
	root.add_child(_game)
	_story = _game.get_story_director()
	_actors = _game.get_actor_director()
	_cameras = _game.get_camera_director()
	_audio = _game.get_audio_manager()
	AudioDemoTones.populate(_audio)
	_story.step_started.connect(func(_id: String, _index: int, command: String) -> void: _steps.append(command))
	_story.event_finished.connect(func(_id: String, ok: bool, _reason: String) -> void: _results.append(ok))
	var marker := Marker2D.new()
	marker.position = Vector2(950, 560)
	_game.get_active_level().add_child(marker)
	_actors.register_position(&"test_position", marker)

func _dispose() -> void:
	_game.queue_free()
	await _frames()

func _run() -> void:
	_state = root.get_node("GameState")
	var snapshot: Dictionary = _state.to_dict()
	_validate()
	_new_game()
	await _ordering()
	await _audio_steps()
	await _conflicts()
	await _cancellation()
	await _dispose()
	await _lifecycle()
	await _demo()
	_state.restore_state(snapshot)
	# AudioServer releases stopped playback on its mixer thread, after node cleanup.
	await create_timer(0.1).timeout
	DirAccess.remove_absolute(_path)
	print("CINEMATIC_INTEGRATION: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _validate() -> void:
	var library := StoryLibrary.new()
	_check(library.load_file("res://src/resources/story/cinematic_opening.json") == OK, "Complete opening JSON validates")
	for step: Dictionary in [
		{"command": "actor_spawn", "actor": "npc", "scene": "res://src/debug/cinematic/customer.tscn", "target": "door"},
		{"command": "actor_move", "actor": "npc", "target": [5, 8], "wait": false},
		{"command": "actor_face", "actor": "npc", "direction": "up"},
		{"command": "actor_emote", "actor": "npc"},
		{"command": "actor_show", "actor": "npc"}, {"command": "actor_hide", "actor": "npc"},
		{"command": "camera_focus", "actor": "npc"}, {"command": "camera_focus", "target": "door"},
		{"command": "camera_move", "target": [0, 1], "duration": 0},
		{"command": "camera_shake", "intensity": 0, "decay": 0, "duration": 0},
		{"command": "camera_zoom", "value": 1.5}, {"command": "camera_reset"},
		{"command": "play_bgm", "id": "test.music", "wait": false},
		{"command": "stop_bgm", "fade": 0}, {"command": "fade_bgm", "volume_db": -20},
		{"command": "play_sfx", "path": "res://old.wav", "wait": true}
	]:
		_check(library.load_json(_data([step])) == OK, "Accept command: %s" % step)
	for bad: Dictionary in [
		{"command": "actor_move", "actor": "", "target": "door"},
		{"command": "actor_move", "actor": "npc", "target": [1]},
		{"command": "actor_move", "actor": "npc", "target": [true, 1]},
		{"command": "actor_move", "actor": "npc", "target": "door", "speed": 0},
		{"command": "actor_move", "actor": "npc", "target": "door", "timeout": -1},
		{"command": "actor_spawn", "actor": "npc", "scene": "user://bad.tscn", "target": "door"},
		{"command": "actor_spawn", "actor": "npc", "scene": "res://bad.png", "target": "door"},
		{"command": "actor_face", "actor": "npc", "direction": "north"},
		{"command": "actor_emote", "actor": "npc", "duration": 0},
		{"command": "actor_emote", "actor": "npc", "symbol": " "},
		{"command": "camera_focus", "actor": "npc", "target": "door"},
		{"command": "camera_focus"}, {"command": "camera_move", "target": [1, "x"]},
		{"command": "camera_zoom", "value": 0}, {"command": "camera_shake", "intensity": -1},
		{"command": "camera_shake", "decay": -1}, {"command": "camera_reset", "duration": 1},
		{"command": "camera_reset", "wait": 1}, {"command": "camera_shake", "duration": -1},
		{"command": "actor_hide", "actor": "npc", "node_path": "../Player"},
		{"command": "play_bgm", "id": ""}, {"command": "fade_bgm", "volume_db": true},
		{"command": "stop_bgm", "fade": -1}, {"command": "play_sfx", "id": "test.sfx", "wait": "false"}
	]:
		_check(library.load_json(_data([bad])) == ERR_INVALID_DATA and "steps[0]" in library.last_error, "Reject with step context: %s" % bad)
		_check(not library.get_event("cinematic.test").is_empty(), "Rejected load preserves prior catalogue")

func _ordering() -> void:
	var player := _game.get_player() as PlayerController
	var notices: Array[ActorAction] = []
	var listen := func(action: ActorAction) -> void:
		if action not in notices:
			notices.append(action)
			action.finished.emit(action) # Duplicate inside the real completion dispatch.
	_actors.action_finished.connect(listen)
	_start([
		{"command": "actor_face", "actor": "player", "direction": "right"},
		{"command": "actor_move", "actor": "player", "target": "test_position", "speed": 180},
		{"command": "camera_focus", "actor": "player", "duration": 0},
		{"command": "camera_zoom", "value": 1, "duration": 0.15},
		{"command": "actor_hide", "actor": "player"},
		{"command": "actor_show", "actor": "player"},
		{"command": "camera_reset"},
	])
	_check(not player.movement_enabled, "MainGame locks before first step")
	await _until(func() -> bool: return _actors.is_actor_controlled(&"player") and _steps.has("actor_move"), "Blocking move begins")
	await create_timer(0.08).timeout
	_check(_steps == ["actor_face", "actor_move"], "Blocking move withholds subsequent dispatch")
	await _until(func() -> bool: return not _story.is_busy(), "Blocking sequence finishes")
	_check(_results.back() and player.global_position.distance_to(Vector2(950, 560)) <= 0.5 and player.visible, "Movement uses real controller and visibility actions complete")
	_check(player.movement_enabled and _cameras.get_camera().mode == BoundedFollowCamera.Mode.FOLLOW, "Finish restores control and camera")
	var count := _results.size()
	for action in notices.duplicate():
		action.finished.emit(action)
		action.finished.emit(action)
	await _frames()
	_check(_results.size() == count, "Duplicate completion cannot re-finish or dispatch")
	_actors.action_finished.disconnect(listen)
	_start([
		{"command": "actor_emote", "actor": "player", "duration": 0.35, "wait": false},
		{"command": "camera_move", "target": [1000, 560], "duration": 0.25, "wait": false},
		{"command": "camera_zoom", "value": 1.1, "duration": 0.25, "wait": false},
		{"command": "camera_shake", "duration": 0.25, "wait": false},
		{"command": "set_stage", "value": "cinematic.parallel"},
	])
	await _until(func() -> bool: return _state.story_stage == "cinematic.parallel", "Non-blocking actions immediately permit later step")
	_check(_story.is_busy() and _actors.is_actor_controlled(&"player"), "Tail drains visual actions and retains input lock")
	await _until(func() -> bool: return not _story.is_busy(), "All parallel visual actions drain")
	_check(_results.back() and _steps == ["actor_emote", "camera_move", "camera_zoom", "camera_shake", "set_stage"], "Non-blocking completion never skips or duplicates a step")

func _audio_steps() -> void:
	var snapshots: Dictionary = {}
	var observe := func(_id: String, _index: int, command: String) -> void: snapshots[command] = _audio.get_bgm_state()
	_story.step_started.connect(observe)
	_start([
		{"command": "play_bgm", "id": "demo.music_a", "fade": 0.12},
		{"command": "fade_bgm", "volume_db": -18, "fade": 0.12},
		{"command": "stop_bgm", "fade": 0.12},
		{"command": "play_sfx", "id": "demo.ui", "wait": true},
		{"command": "set_stage", "value": "cinematic.audio_done"},
	])
	await _until(func() -> bool: return _steps.has("fade_bgm"), "BGM fade-in result unlocks next step")
	_check(is_zero_approx(snapshots["fade_bgm"].volume_db), "BGM completion follows fade-in")
	await _until(func() -> bool: return _steps.has("stop_bgm"), "Explicit fade settles")
	_check(is_equal_approx(snapshots["stop_bgm"].volume_db, -18), "Fade result matches target volume")
	await _until(func() -> bool: return _steps.has("play_sfx"), "Fade-out settles before sound step")
	_check(not _audio.get_bgm_state().playing and _state.story_stage != "cinematic.audio_done", "Stop waits and SFX waits for actual voice")
	await _until(func() -> bool: return not _story.is_busy(), "Natural sound completion unblocks story")
	_check(_results.back(), "Audio sequence succeeds")
	_story.step_started.disconnect(observe)
	_start([{"command": "play_bgm", "id": "missing.optional"}, {"command": "play_sfx", "path": "res://missing.wav", "wait": true}])
	await _until(func() -> bool: return not _story.is_busy(), "Missing optional audio settles without hang")
	_check(_results.back(), "Optional audio compatibility preserved")
	_start([{"command": "play_bgm", "id": "demo.music_a", "fade": 1, "wait": false}, {"command": "stop_bgm", "fade": 0}])
	await _until(func() -> bool: return not _story.is_busy(), "Intentional BGM replacement is safe")
	_check(_results.back() and not _audio.get_bgm_state().playing, "Music transition replacement never advances stale step")
	var owner := RefCounted.new()
	_audio.play_sfx("demo.story", owner)
	_audio.play_sfx("demo.story", owner)
	var stop_again := func(_handle: int, _cancelled: bool) -> void: _audio.stop_owned(owner)
	_audio.sound_finished.connect(stop_again)
	_audio.stop_owned(owner)
	_audio.sound_finished.disconnect(stop_again)
	_check(_audio.get_active_sound_count(owner) == 0, "Reentrant sound completion safely stops remaining owned voices")

func _conflicts() -> void:
	_start([{"command": "actor_emote", "actor": "player", "duration": 1, "wait": false}, {"command": "actor_face", "actor": "player", "direction": "up"}])
	_check(_story.request_event("cinematic.test") == ERR_BUSY, "Duplicate event rejected synchronously")
	await _until(func() -> bool: return not _story.is_busy(), "Actor conflict fails instead of hanging")
	_check(not _results.back() and not _actors.is_actor_controlled(&"player"), "Failure cancels preceding owned action")
	_start([
		{"command": "camera_move", "target": [900, 550], "duration": 1, "wait": false},
		{"command": "camera_move", "target": "test_position", "duration": 0},
		{"command": "camera_shake", "duration": 1, "wait": false},
		{"command": "camera_reset"},
	])
	await _until(func() -> bool: return not _story.is_busy(), "Camera replacement and reset complete")
	_check(_results.back() and _cameras.get_camera().mode == BoundedFollowCamera.Mode.FOLLOW and _cameras.get_camera().offset == Vector2.ZERO, "Owned camera replacement/reset retires old callbacks")
	for bad: Dictionary in [
		{"command": "actor_move", "actor": "missing", "target": "test_position"},
		{"command": "actor_spawn", "actor": "player", "scene": "res://src/debug/cinematic/customer.tscn", "target": "test_position"},
		{"command": "actor_spawn", "actor": "new", "scene": "res://missing.tscn", "target": "test_position"},
		{"command": "camera_focus", "actor": "missing"},
		{"command": "camera_move", "target": "missing"},
	]:
		_start([bad])
		await _until(func() -> bool: return not _story.is_busy(), "Bad runtime reference settles")
		_check(not _results.back() and "steps[0]" in _story.last_error, "Bad runtime reference has diagnostic")

func _cancellation() -> void:
	var player := _game.get_player() as PlayerController
	var interaction: ShopInteraction = _game.get_node("Systems/ShopInteraction")
	for command: String in ["actor_move", "actor_emote", "camera_move", "camera_shake", "camera_zoom", "play_bgm", "play_sfx"]:
		var step: Dictionary
		match command:
			"actor_move": step = {"command": command, "actor": "player", "target": [1100, 560], "speed": 20}
			"actor_emote": step = {"command": command, "actor": "player", "duration": 2}
			"camera_move": step = {"command": command, "target": [1100, 560], "duration": 2}
			"camera_shake": step = {"command": command, "duration": 2}
			"camera_zoom": step = {"command": command, "value": 1.2, "duration": 2}
			"play_bgm": step = {"command": command, "id": "demo.music_a", "fade": 2}
			"play_sfx": step = {"command": command, "id": "demo.story", "wait": true}
		_start([step, {"command": "set_stage", "value": "cinematic.stale"}])
		await _until(func() -> bool: return not _steps.is_empty(), "Cancel case dispatched: " + command)
		await _frames()
		var count := _results.size()
		_story.cancel_event()
		_story.cancel_event()
		_check(_results.size() == count + 1 and not _results.back(), "Cancel settles once: " + command)
		_check(player.movement_enabled and interaction.is_input_enabled() and not _actors.is_actor_controlled(&"player"), "Cancel releases MainGame lock: " + command)
		var position := player.global_position
		await _frames(5)
		_check(player.global_position == position and _state.story_stage != "cinematic.stale" and _cameras.get_camera().mode == BoundedFollowCamera.Mode.FOLLOW and _cameras.get_camera().offset == Vector2.ZERO, "No stale movement/camera/callback: " + command)
		_check(_audio.get_active_sound_count() == 0 and not _audio.get_bgm_state().playing, "Cancel stops owned audio")
	player.set_movement_enabled(false)
	interaction.set_input_enabled(false)
	_start([{"command": "camera_zoom", "value": 1, "duration": 1}])
	_story.cancel_event()
	_check(not player.movement_enabled and not interaction.is_input_enabled(), "Restore preserves pre-existing disabled inputs")
	player.set_movement_enabled(true)
	interaction.set_input_enabled(true)
	_start([{"command": "play_bgm", "id": "demo.music_a", "fade": 0}, {"command": "wait", "seconds": 1}])
	await _until(func() -> bool: return _steps.has("wait"), "Music owner established")
	_audio.play_bgm("demo.music_b", 0)
	_story.cancel_event()
	_check(_audio.get_bgm_state().playing and _audio.get_bgm_state().id == "demo.music_b", "Cancel preserves newer external BGM owner")
	_audio.stop_bgm()
	_start([{"command": "actor_emote", "actor": "player", "duration": 1}])
	await _frames()
	_story.cancel_event()
	_start([{"command": "camera_shake", "duration": 0.1}, {"command": "set_stage", "value": "cinematic.retry"}])
	await _until(func() -> bool: return not _story.is_busy(), "New generation completes despite old deferred signals")
	_check(_results.back() and _state.story_stage == "cinematic.retry", "Stale cancellation cannot affect retry")
	var cancel_on_claim := func(_id: StringName, controlled: bool) -> void:
		if controlled:
			_story.cancel_event("Reentrant actor listener")
	_actors.actor_control_changed.connect(cancel_on_claim)
	_start([{"command": "actor_face", "actor": "player", "direction": "left"}])
	await _until(func() -> bool: return not _story.is_busy(), "Synchronous actor claim cancellation settles")
	_check(not _actors.is_actor_controlled(&"player") and player.movement_enabled, "Cancelled dispatch cannot retain a just-created actor action")
	_actors.actor_control_changed.disconnect(cancel_on_claim)
	var spawn := _actors.actor_spawn(&"external", load("res://src/debug/cinematic/customer.tscn"), Vector2(1100, 560))
	await spawn.wait()
	var external := _actors.actor_emote(&"external", "?", 1)
	_start([{"command": "wait", "seconds": 1}])
	_story.cancel_event()
	_check(not external.completed and _actors.is_actor_controlled(&"external"), "Cancelling story preserves external actor action")
	_actors.cancel_action(external)
	var external_actor := _actors.get_actor(&"external")
	_actors.actor_unregister(&"external")
	external_actor.queue_free()

func _lifecycle() -> void:
	for removed: String in ["actor", "marker", "actors", "cameras", "camera", "story", "audio", "scene", "held_target", "player"]:
		_new_game()
		var spawn := _actors.actor_spawn(&"npc", load("res://src/debug/cinematic/customer.tscn"), Vector2(1100, 560))
		await spawn.wait()
		_check(spawn.succeeded, "Lifecycle cast spawns")
		var step := {"command": "actor_move", "actor": "npc", "target": "test_position", "speed": 20}
		if removed == "player":
			step.actor = "player"
		if removed in ["cameras", "camera", "held_target"]:
			step = {"command": "camera_focus", "actor": "npc", "duration": 0 if removed == "held_target" else 1}
		elif removed == "audio":
			step = {"command": "play_sfx", "id": "demo.story", "wait": true}
		_start([step, {"command": "wait", "seconds": 1}])
		await _until(func() -> bool: return not _steps.is_empty(), "Lifecycle action starts")
		if removed == "held_target":
			await _until(func() -> bool: return _steps.has("wait"), "Focus completes and holds live target")
		var player := _game.get_player() as PlayerController
		var count := _results.size()
		match removed:
			"actor", "held_target": _actors.get_actor(&"npc").queue_free()
			"player": player.queue_free()
			"marker": _actors.get_position(&"test_position").queue_free()
			"actors": _actors.queue_free()
			"cameras": _cameras.queue_free()
			"camera": _cameras.get_camera().queue_free()
			"story": _story.queue_free()
			"audio": _audio.queue_free()
			"scene": _game.queue_free()
		await _until(func() -> bool: return _results.size() > count, "Removing %s cancels event" % removed)
		_check(_results.size() == count + 1 and not _results.back(), "Lifecycle emits one failure: " + removed)
		if removed != "scene":
			if removed == "player":
				_check(_game.get_player() == null and (_game.get_node("Systems/ShopInteraction") as ShopInteraction).is_input_enabled(), "Deleted player safely releases interaction lock")
			else:
				_check(player.movement_enabled, "Lifecycle releases input: " + removed)
			if removed == "story":
				var point := (_game.get_active_level() as MilkTeaShop).get_interaction_points()[0]
				player.global_position = point.global_position
				for index in range(4):
					await physics_frame
				point.interact()
				var shop_ui: ShopUI = _game.get_node("HudLayer/ShopUI")
				_check(shop_ui.is_open() and _game.get_story_director() == null, "Deleted StoryDirector preserves existing interaction fallback")
				shop_ui.close()
			if removed in ["actors", "cameras", "camera"]:
				_start([{"command": "wait", "seconds": 0}])
				await _until(func() -> bool: return not _story.is_busy(), "Unrelated story can finish after service deletion")
				_check(_results.back(), "Deleted service cannot leave a stale MainGame callback")
			await _dispose()
		else:
			await _frames()

func _demo() -> void:
	var demo: Node = load("res://src/debug/cinematic/cinematic_demo.tscn").instantiate()
	root.add_child(demo)
	_game = demo.get_node("MainGame")
	_story = _game.get_story_director()
	var manager := _game.get_dialogue_manager()
	var ui: DialogueUI = _game.get_node("PopupLayer/DialogueUI")
	var commands: Array[String] = []
	_story.step_started.connect(func(_id: String, _index: int, command: String) -> void: commands.append(command))
	var started := Time.get_ticks_msec()
	var deadline := started + 35000
	var dialogue_started := 0
	var last_id := ""
	var captured := false
	while _story.is_busy() and Time.get_ticks_msec() < deadline:
		if manager.is_active():
			if last_id.is_empty():
				last_id = manager.get_current_line_id()
				dialogue_started = Time.get_ticks_msec()
			if Time.get_ticks_msec() - dialogue_started >= 4000:
				ui.reveal_all()
				manager.advance()
		else:
			last_id = ""
		var live_customer := _game.get_actor_director().get_actor(&"customer")
		if "--capture" in OS.get_cmdline_user_args() and not captured and live_customer != null and live_customer.get_node_or_null("ActorEmote") != null:
			# Freeze only for capture, so a slow renderer cannot miss the emote frame.
			paused = true
			await RenderingServer.frame_post_draw
			_check(root.get_texture().get_image().save_png("/private/tmp/cinematic-opening.png") == OK, "Demo capture saves")
			paused = false
			captured = true
		await process_frame
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	print("CINEMATIC_OPENING_DURATION: %.2fs" % seconds)
	_check(not _story.is_busy() and _story.last_error.is_empty(), "Complete JSON demo succeeds: " + _story.last_error)
	_check(seconds >= 20 and seconds <= 30, "Opening lasts 20-30 seconds with four-second readings (%.2fs)" % seconds)
	_check(commands.count("actor_move") == 2 and commands.count("dialogue") == 2 and commands.has("camera_reset"), "All opening phases came from JSON")
	var customer := _game.get_actor_director().get_actor(&"customer")
	_check(customer != null and customer.global_position.distance_to(Vector2(1100, 610)) <= 0.5, "Customer arrives at counter through real shop collision")
	_check((_game.get_player() as PlayerController).movement_enabled and _game.get_camera_director().get_camera().mode == BoundedFollowCamera.Mode.FOLLOW, "Demo restores movement and follow")
	demo.play()
	await _frames()
	_story.cancel_event()
	_check((_game.get_player() as PlayerController).movement_enabled, "Replay can be cancelled")
	demo.queue_free()
	await _frames()
