extends Node
## An isolated Release verification project uses this scene as its main scene.

var _checks := 0
var _failures := 0
var _directory := "user://verification/save_export_%d" % OS.get_process_id()
var _tree: SceneTree

func _ready() -> void:
	_tree = get_tree()
	# Keep the probe alive while it switches the actual game scenes.
	_tree.current_scene = null
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr(message)

func _ready_session() -> bool:
	for index in range(240):
		await _tree.process_frame
		if _tree.current_scene is MainGame and not _tree.current_scene.is_session_initializing():
			return true
	return false

func _run() -> void:
	_tree.create_timer(30.0).timeout.connect(func() -> void: _tree.quit(1))
	ProjectSettings.set_setting("persistence/save_directory", _directory)
	ProjectSettings.set_setting("debug/developer_tools/enabled", true)
	check(OS.has_feature("release"), "Use a real Release export template")
	check(not DebugRuntime.is_enabled(), "Release refuses developer-tools override")
	check(FileAccess.file_exists(SaveCheckpoints.DEFAULT_PATH), "Export includes checkpoint JSON")
	check(not FileAccess.file_exists("res://tests/verify_save_game.gd"), "Export excludes test scripts")
	var error := GameEntry.start_new_game(_tree)
	check(error == OK, "Release starts a new saved session")
	if error != OK or not await _ready_session():
		check(false, "Release finishes new-game initialization")
		_finish()
		return
	var stored := GameEntry.create_save_store().load_save()
	check(stored.error == OK and stored.data.checkpoint_id == "day1.initial.shop", "Release writes its initial complete checkpoint")
	check(_tree.current_scene.get_node_or_null("Systems/DeveloperTools") == null, "Release host omits developer tools")
	check(GameEntry.return_to_title(_tree) == OK, "Release returns to title")
	await _tree.scene_changed
	check(_tree.current_scene.get_node("Center/Panel/Margin/Content/Continue").visible, "Release title offers Continue")
	error = GameEntry.continue_game(_tree)
	check(error == OK, "Release begins full restoration")
	if error == OK:
		check(await _ready_session(), "Release completes checkpoint restoration")
		check(_tree.root.get_node("GameState").to_dict() == stored.data.game_state, "Release exactly restores the saved full snapshot")
		check(_tree.current_scene.get_player().movement_enabled, "Release unlocks the restored player")
	for name: String in ["autosave.dat", "autosave.bak", "autosave.tmp", "autosave.bak.tmp"]:
		if FileAccess.file_exists(_directory.path_join(name)):
			DirAccess.remove_absolute(_directory.path_join(name))
	DirAccess.remove_absolute(_directory)
	_finish()

func _finish() -> void:
	print("SAVE_EXPORT: %s (%d checks, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	_tree.quit(0 if _failures == 0 else 1)
