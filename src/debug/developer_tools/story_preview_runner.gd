extends SceneTree
## A separate Godot process owns its own GameState. No live-session rollback or
## production save file is required for repeatable cinematic previews.

var _request: Dictionary
var _game: MainGame
var _label: Label
var _rebuilding := false
var _r_down := false
var _auto := false
var _started := 0
var _catalogs: Array[String] = []
var _finished := false
var _repeat := 1
var _capture := false
var _captured := false

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	if not OS.has_feature("debug") or not OS.has_feature("editor"):
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if data is Dictionary and data.get("format") == StoryProject.FORMAT:
		var project := StoryProject.new()
		if args.size() < 2 or project.open_project(args[0]) != OK:
			printerr("STORY_PREVIEW: expected project.json event_id [--auto] ", project.last_error)
			quit(1)
			return
		var document := project.snapshot()
		if not document.previews.has(args[1]):
			printerr("STORY_PREVIEW: event has no preview fixture: ", args[1])
			quit(1)
			return
		data = project.compile()
		data["scene"] = document.manifest.scene
		data["event"] = args[1]
		data["fixture"] = document.previews[args[1]]
	if not data is Dictionary or not data.has_all(["story", "dialogue", "scene", "event", "fixture"]):
		printerr("STORY_PREVIEW: invalid request")
		quit(1)
		return
	_request = data
	_auto = "--auto" in args
	_capture = "--capture" in args
	if "--repeat" in args and args.find("--repeat") + 1 < args.size():
		_repeat = clampi(int(args[args.find("--repeat") + 1]), 1, 10)
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	var layer := CanvasLayer.new()
	layer.layer = 60
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(layer)
	var shell := PanelContainer.new()
	shell.theme = load("res://src/resources/ui/game_theme.tres")
	layer.add_child(shell)
	shell.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var panel := HBoxContainer.new()
	shell.add_child(panel)
	_label = Label.new()
	_label.theme = load("res://src/resources/ui/game_theme.tres")
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_label)
	var replay := Button.new()
	replay.text = "重演 [R]"
	replay.theme = _label.theme
	replay.pressed.connect(_rebuild)
	panel.add_child(replay)
	await _rebuild()

func _rebuild() -> void:
	if _rebuilding:
		return
	_rebuilding = true
	_finished = false
	paused = false
	if is_instance_valid(_game):
		_game.get_audio_manager().stop_bgm(0.0)
		await create_timer(0.05).timeout
		_game.queue_free()
		await process_frame
		await process_frame
	var state: Node = root.get_node("GameState")
	state.start_new_game()
	var scene := load(_request.scene) as PackedScene
	if scene == null:
		_fail("预览宿主不存在")
		return
	_game = scene.instantiate() as MainGame
	if _game == null:
		_fail("预览宿主需要 MainGame")
		return
	root.add_child(_game)
	current_scene = _game
	# Stop automatic opening before its first process tick. The already deferred
	# checkpoint projection is allowed to finish before applying the preview fixture.
	var controller := _game.get_day1_controller()
	if controller != null:
		controller.set_process(false)
	await process_frame
	await process_frame
	if _game.get_story_director() == null or _game.get_dialogue_manager() == null or _game.get_actor_director() == null:
		_fail("预览宿主缺少剧情、对白或角色服务")
		return
	if _game.get_gameplay_bridge() != null:
		_game.get_gameplay_bridge().stop(true)
	_game.get_story_director().cancel_event("Preview rebuild")
	var director := _game.get_story_director()
	if _request.fixture.has("business_profile") and state.get_business_profile() != _request.fixture.business_profile:
		_fail("预览宿主未使用要求的经营配置")
		return
	var conditions: Dictionary = _request.story.events[_request.event].get("conditions", {})
	state.set_current_day(int(conditions.get("day", 1)))
	state.set_story_stage(conditions.get("stage", ""))
	for id: String in conditions.get("completed_events", []):
		state.complete_event(id)
	for key: String in conditions.get("flags", {}):
		state.set_flag(key, conditions.flags[key])
	for key: String in _request.fixture.get("flags", {}):
		state.set_flag(key, _request.fixture.flags[key])
	if _request.fixture.has("bgm"):
		_game.get_audio_manager().play_bgm(_request.fixture.bgm, 0.0, -12.0)
	var actors := _game.get_actor_director()
	for id: String in _request.fixture.get("actors", {}):
		var placement: Dictionary = _request.fixture.actors[id]
		var actor := actors.get_actor(StringName(id))
		var marker := actors.get_position(StringName(placement.get("marker", "")))
		if actor == null or marker == null:
			_fail("预览绑定缺失：%s / %s" % [id, placement.get("marker", "")])
			return
		actor.teleport_to(marker.global_position)
		actor.visible = placement.get("visible", true)
	for kind: String in ["story", "dialogue"]:
		var file := "user://story_editor/runner_%d_%s.json" % [OS.get_process_id(), kind]
		DirAccess.make_dir_recursive_absolute("user://story_editor")
		var handle := FileAccess.open(file, FileAccess.WRITE)
		if handle == null:
			_fail("无法写入临时预览目录")
			return
		handle.store_string(JSON.stringify(_request[kind]))
		handle.close()
		if file not in _catalogs:
			_catalogs.append(file)
		var error: Error = director.load_events(file) if kind == "story" else _game.get_dialogue_manager().load_dialogues(file)
		if error != OK:
			_fail("预览数据加载失败：" + error_string(error))
			return
	director.event_finished.connect(_on_finished)
	_label.text = "独立演出预览 · %s · R 重演" % _request.event
	_started = Time.get_ticks_msec()
	_rebuilding = false
	var error := director.request_event(_request.event)
	if error != OK:
		_fail(director.last_error)

func _process(_delta: float) -> bool:
	var down := Input.is_physical_key_pressed(KEY_R)
	if down and not _r_down and not _request.is_empty():
		_rebuild.call_deferred()
	_r_down = down
	if _auto and not _rebuilding and not _finished and is_instance_valid(_game):
		if _game.get_dialogue_manager().is_active():
			if _capture and not _captured and DisplayServer.get_name() != "headless":
				_captured = true
				_capture_frame.call_deferred()
			_game.get_dialogue_manager().advance()
		if Time.get_ticks_msec() - _started > 60000:
			_fail("预览超时")
	return false

func _on_finished(id: String, succeeded: bool, reason: String) -> void:
	if _rebuilding:
		return
	_finished = true
	_label.text = "%s · %s · R 重演" % [id, "完成" if succeeded else reason]
	print("STORY_PREVIEW: %s %s %s" % [id, succeeded, reason])
	if _auto:
		if succeeded and _repeat > 1:
			_repeat -= 1
			_rebuild.call_deferred()
		else:
			_finish_auto.call_deferred(0 if succeeded else 1)

func _capture_frame() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/story_preview.png")

func _fail(message: String) -> void:
	_rebuilding = false
	_finished = true
	printerr("STORY_PREVIEW: " + message)
	if is_instance_valid(_label):
		_label.text = message
	if _auto:
		_finish_auto.call_deferred(1)

func _finish_auto(code: int) -> void:
	if is_instance_valid(_game):
		_game.get_audio_manager().stop_bgm(0.0)
		# Audio playback is released by the mix thread, not the scene frame queue.
		await create_timer(0.05).timeout
		_game.queue_free()
		await process_frame
		await process_frame
	quit(code)

func _finalize() -> void:
	for file: String in _catalogs:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
