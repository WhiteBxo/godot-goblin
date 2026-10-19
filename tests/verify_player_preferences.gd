extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var directory := OS.get_cache_dir().path_join("goblin_preferences_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("preferences.cfg")
	ProjectSettings.set_setting("preferences/file", path)
	ProjectSettings.set_setting("persistence/save_directory", directory)
	check(PlayerPreferences.get_values() == PlayerPreferences.DEFAULTS, "Missing preferences use defaults")
	var values := {"music": 0.5, "sound": 0.25, "dialogue_speed": 0.0}
	check(PlayerPreferences.save_values(values) == OK, "Preferences save independently of the game session")
	check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Music")), 0.5), "Music applies to Music bus")
	check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("UI")), 0.25), "Sound volume also controls UI effects")
	var bytes := FileAccess.get_file_as_bytes(path)
	check(PlayerPreferences.save_values({"music": -1, "sound": 0.0, "dialogue_speed": 0.0}) == ERR_INVALID_DATA and FileAccess.get_file_as_bytes(path) == bytes, "Invalid values preserve the saved file")
	ProjectSettings.set_setting("preferences/file", path + ".missing")
	PlayerPreferences.get_values()
	ProjectSettings.set_setting("preferences/file", path)
	check(PlayerPreferences.get_values() == values, "A fresh load restores selected values")
	var state := root.get_node("GameState")
	state.start_new_game()
	check(PlayerPreferences.get_values() == values, "New game preserves device preferences")
	var dialogue: DialogueUI = load("res://src/UI/dialogue/dialogue_ui.tscn").instantiate()
	root.add_child(dialogue)
	dialogue.present_line("测试", "立即显示全文，保留继续与选择。", null, [])
	check(not dialogue.is_revealing(), "Instant text preference reveals without changing dialogue progression")
	dialogue.free()
	var title: TitleMenu = load("res://src/UI/title/title_menu.tscn").instantiate()
	root.add_child(title)
	await process_frame
	var settings_button: Button = title.get_node("Center/Panel/Margin/Content/Settings")
	settings_button.pressed.emit()
	await process_frame
	check(not title.get_node("Center").visible and title._settings.visible, "Title opens settings without background focus targets")
	var panel: Control = title._settings
	var page: Control = panel.get_node("ModalShell").get_content()
	page.get_node("Music/Value").select(0)
	panel.get_node("ModalShell").close_requested.emit()
	await process_frame
	check(PlayerPreferences.get_values() == values and get_root().gui_get_focus_owner() == settings_button, "Cancel discards unapplied changes and restores title focus")
	settings_button.pressed.emit()
	page.get_node("Music/Value").select(0)
	page.get_node("Apply").pressed.emit()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Applying zero volume actually mutes music")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/two_day_polish/settings.png")
	title.free()
	PlayerPreferences.save_values(PlayerPreferences.DEFAULTS)
	ProjectSettings.clear("preferences/file")
	PlayerPreferences.apply_audio()
	print("PLAYER_PREFERENCES: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
