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
	check(not game.has_node("HudLayer/MapButton"), "Map is consolidated in the menu")
	check(game.get_node("HudLayer/WalletHUD").is_visible_in_tree(), "Wallet chip stays visible next to the menu while a task is tracked")
	check(not game.get_node("HudLayer/SaveStatus").visible, "Save timestamp is consolidated in the menu and pause")
	var saved_text := game.get_save_coordinator().get_status_text()
	game.get_save_coordinator().status_changed.emit("自动保存失败，原存档已保留。")
	check(game.get_node("HudLayer/SaveStatus").visible, "Save errors remain visible without opening a menu")
	game.get_save_coordinator().status_changed.emit(saved_text)
	check(game.get_node("HudLayer/SaveStatus").visible, "Successful save shows a short confirmation toast")
	await create_timer(2.7).timeout
	check(not game.get_node("HudLayer/SaveStatus").visible, "Save toast clears itself and the timestamp returns to the menu")
	var task := game.get_node("HudLayer/TaskHUD") as TaskHUD
	check(task.get_task_button().is_visible_in_tree() and not task.get_objective_summary().title.is_empty(), "Current task title and clickable task log remain visible")
	var fat := game.get_actor_director().get_actor(&"fat_goblin")
	var rest := game.get_actor_director().get_position(&"day2_bedroom_rest")
	check(fat != null and rest != null and fat.global_position.is_equal_approx(rest.global_position), "Day 2 fat goblin rests at the bedroom marker")
	check(not fat.get_node("InteractionPoint").interaction_enabled, "Resting fat goblin offers no stale interaction")
	check(game.get_story_director().request_interaction("fat_goblin") == ERR_DOES_NOT_EXIST, "Day 2 never replays a Day 1 fat-goblin event")
	var wallet_hud := game.get_node("HudLayer/WalletHUD")
	var balance: Label = wallet_hud.get_node("Row/Balance")
	var wallet := game.get_transactions()
	check(balance.text == WalletTransactions.format_money(wallet.get_balance()), "Persistent balance projects the real wallet")
	check(wallet.add_money(1, "compact.credit").ok, "Balance test commits a real credit")
	await create_timer(0.45).timeout
	check(balance.text == WalletTransactions.format_money(wallet.get_balance()), "Persistent balance follows committed transactions")
	check(wallet.spend_money(1, "compact.debit").ok, "Balance test returns the credited coin")
	await create_timer(3.0).timeout
	check(wallet_hud.is_visible_in_tree(), "Gold balance persists after transaction feedback fades")
	await picture("idle_1280")
	var task_before: Dictionary = state.to_dict()
	var click := task.get_task_button().get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = click
		event.global_position = click
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await frames(2)
	check(ui.is_open(ScreenIds.HANDBOOK) and game.get_node("PopupLayer/HandbookPanel").get_pages().current_tab == 0, "Clicking the task card opens the task log directly")
	check(not game.get_player().movement_enabled and state.to_dict() == task_before, "Task-card navigation locks movement without changing facts")
	await tap(&"ui_cancel")
	check(not ui.has_modal() and game.get_player().movement_enabled and task.is_visible_in_tree(), "Closing the task log restores the HUD and movement")
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
	await frames()
	game = await _load_fixture(directory, "wait_special")
	fat = game.get_actor_director().get_actor(&"fat_goblin")
	rest = game.get_actor_director().get_position(&"day2_bedroom_rest")
	check(fat.global_position.is_equal_approx(rest.global_position) and not fat.get_node("InteractionPoint").interaction_enabled, "Returning to the shop before guard delivery keeps the fat goblin resting")
	await picture("returned_shop")
	game.free()
	await frames()
	game = await _load_fixture(directory, "wait_guard")
	var objective: Dictionary = game.get_task_journal().get_current_main_task().current_objective
	check(objective.get("id") == "deliver" and objective.get("text") == "将奶茶提交给守卫", "Prepared guard drink has the requested delivery instruction")
	await picture("guard_delivery")
	game.free()
	print("COMPACT_MENU: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
