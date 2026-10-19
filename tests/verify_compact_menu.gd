extends "res://tests/verify_two_day_polish.gd"
## Real checkpoint -> menu navigation -> actual close-shop action, no fake facts.

func tap(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)
	await frames(2)
	event = InputEventAction.new()
	event.action = action
	root.push_input(event)
	await frames(4)

func picture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/compact_menu")
	root.get_texture().get_image().save_png("res://.godot/compact_menu/" + name + ".png")

func _run() -> void:
	var directory := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--fixtures="):
			directory = argument.trim_prefix("--fixtures=")
	if directory.is_empty():
		quit(2)
		return
	var game := await _load_fixture(directory, "wait_close")
	var state := root.get_node("GameState")
	var ui := game.get_ui_manager()
	var menu := game.get_game_menu()
	check(not menu.is_visible_in_tree(), "Idle gameplay has no chapter sidebar")
	check(not game.get_node("HudLayer/MapButton").visible, "Map is consolidated in the menu")
	check(not game.get_business_hud().get_node("BusinessBalance").visible, "Idle wallet is consolidated in the menu")
	check(not game.get_node("HudLayer/SaveStatus").visible, "Save timestamp is consolidated in the menu and pause")
	var saved_text := game.get_save_coordinator().get_status_text()
	game.get_save_coordinator().status_changed.emit("自动保存失败，原存档已保留。")
	check(game.get_node("HudLayer/SaveStatus").visible, "Save errors remain visible without opening a menu")
	game.get_save_coordinator().status_changed.emit(saved_text)
	check(game.get_node("HudLayer/SaveStatus").visible, "Successful save shows a short confirmation toast")
	await create_timer(2.7).timeout
	check(not game.get_node("HudLayer/SaveStatus").visible, "Save toast clears itself and the timestamp returns to the menu")
	var task := game.get_node("HudLayer/TaskHUD") as TaskHUD
	check(task.size.y <= 36 and task.get_objective_summary().objective.length() > 20, "One-line objective retains its full text for the menu")
	await picture("idle_1280")
	var before: Dictionary = state.to_dict()
	game.get_node("HudLayer/HandbookHUD").grab_focus()
	await tap(&"ui_accept")
	check(ui.is_open(ScreenIds.CHAPTER_ACTIONS) and not game.get_player().movement_enabled, "Upper-right menu opens through keyboard and owns input")
	check(state.to_dict() == before, "Opening the menu changes no gameplay facts")
	var page: Control = menu.get_node("ModalShell").get_content()
	check(page.get_node("Scroll").size.y > 100 and page.get_node("Scroll/Content/Objective").size.y > 0, "Full objective and chapter actions have a visible scroll area")
	await picture("menu_1280")
	var original_size := root.size
	root.size = Vector2i(640, 360)
	await frames(8)
	check(root.get_visible_rect().encloses(menu.get_default_focus().get_global_rect()), "Small viewport retains visible close/focus control")
	await picture("menu_640")
	root.size = original_size
	await frames(5)
	for destination: StringName in [ScreenIds.INVENTORY, ScreenIds.MAP, ScreenIds.TASKS, ScreenIds.SETTINGS]:
		var button := menu.get_navigation_button(destination)
		check(button != null and not button.disabled, "Available destination is reachable: " + destination)
		button.grab_focus()
		await tap(&"ui_accept")
		var expected: StringName = ScreenIds.MENU_SETTINGS if destination == ScreenIds.SETTINGS else ScreenIds.HANDBOOK if destination == ScreenIds.TASKS else destination
		check(ui.is_open(expected) and not game.get_player().movement_enabled, "Destination opens with input lock: " + destination)
		check(not paused, "Menu settings/navigation do not implicitly pause the world")
		await tap(&"ui_cancel")
		check(ui.is_open(ScreenIds.CHAPTER_ACTIONS) and not game.get_player().movement_enabled, "Back returns to the menu: " + destination)
	await tap(&"ui_cancel")
	check(not ui.has_modal() and game.get_player().movement_enabled, "Closing menu restores world input")
	check(game.open_game_menu() == OK, "Menu can be reopened")
	await frames(5)
	var close := menu.get_action_button("day2.close")
	check(close != null and not close.disabled, "Close-shop action is available inside menu")
	close.grab_focus()
	await tap(&"ui_accept")
	check(state.get_flag("day2.s02.closed") and not ui.is_open(ScreenIds.CHAPTER_ACTIONS), "Menu action really closes business and returns to gameplay")
	game.free()
	print("COMPACT_MENU: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
