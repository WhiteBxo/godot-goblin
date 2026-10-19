extends SceneTree
## Restore an immutable fixture into a disposable save directory in this process.

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	if not DebugRuntime.is_enabled() or not OS.has_feature("editor"):
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	var loaded := SaveStore.new(args[0]).load_save(GameEntry.preflight_save)
	if loaded.error != OK:
		printerr("FLOW_TEST: 无效检查点 ", args[0])
		quit(1)
		return
	var directory := "user://developer_flow/play_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var store := SaveStore.new(directory)
	if store.save(loaded.data.game_state, loaded.data.checkpoint_id) != OK:
		quit(1)
		return
	ProjectSettings.set_setting("persistence/save_directory", directory)
	var error := GameEntry.continue_game(self)
	if error != OK:
		printerr("FLOW_TEST: 恢复失败 ", error_string(error))
		quit(1)
		return
	for frame in range(600):
		await process_frame
		if current_scene is MainGame and not current_scene.is_session_initializing():
			print("FLOW_TEST: 独立试玩已恢复；存档目录 ", ProjectSettings.globalize_path(directory))
			return
	printerr("FLOW_TEST: 现场初始化超时")
	quit(1)
