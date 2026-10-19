extends SceneTree

const StateData = preload("res://src/core/game_state.gd")
const FIXTURE := "res://tests/fixtures/task_panel_tasks.json"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)

func frames(count: int = 4) -> void:
	for index in range(count):
		await process_frame

func tap(key: Key, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/task_panel")
	root.get_texture().get_image().save_png("res://.godot/task_panel/" + label + ".png")

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	root.content_scale_size = Vector2i(640, 360)
	root.size = Vector2i(640, 360)
	await _test_projection_and_panel()
	await _test_material_panel()
	for path: String in ["res://src/debug/story/legacy_shop.tscn", "res://src/core/settlement.tscn"]:
		await _test_host(path)
	await _test_demo()
	print("TASK_PANEL: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_projection_and_panel() -> void:
	var state: StateData = root.get_node("GameState")
	state.reset_state()
	var catalog := TaskCatalog.new()
	check(catalog.load_file(FIXTURE) == OK, "Isolated task catalog loads")
	var journal := TaskJournal.new()
	root.add_child(journal)
	journal.configure(catalog, state)
	var panel: TaskPopup = load("res://src/UI/tasks/task_popup.tscn").instantiate()
	panel.bind_journal(journal) # Pre-tree binding must not connect twice.
	root.add_child(panel)
	panel.show()
	await frames()
	var list: ItemList = panel.get_entries()
	var title: Label = panel.get_detail_title()
	var text: RichTextLabel = panel.get_detail_text()
	var body: BoxContainer = panel.get_body()
	check(list.item_count == 0 and title.text == "暂无任务记录", "Inactive tasks stay out of the empty browser")
	check(journal.get_task("panel.hidden").delivery.is_empty(), "Hidden delivery IDs are masked in projection")
	state.set_flag("task.panel.active")
	state.set_variable("task.panel.count", 1)
	await frames()
	check(list.item_count == 4 and title.text.contains("第一笔订单"), "Multiple active tasks appear and the first is selected")
	check(list.get_item_text(0).begins_with("主线 · ") and list.get_item_text(1).begins_with("支线 · "), "List distinguishes main tasks and commissions in catalog order")
	check(text.text.contains("可选") and text.text.contains("未完成") and text.text.contains("糖浆 × 1"), "Details include objectives, optional marks and configured reward")
	check(text.text.contains("交付对象待确认") and text.text.contains("成品待确认") and not text.text.contains("fat_goblin"), "Missing display names never expose internal IDs")
	var view := journal.get_task("panel.main")
	check(view.delivery == {"target_object_id": "fat_goblin", "product_id": "pearl_milk_tea"}, "Projection exposes only the two delivery presentation IDs")
	view.delivery.product_id = "mutated"
	check(journal.get_task("panel.main").delivery.product_id == "pearl_milk_tea", "Delivery projection is isolated from caller mutation")
	var names := {"fat_goblin": "胖哥布林"}
	panel.set_delivery_names(names, {"pearl_milk_tea": "珍珠奶茶"})
	names.fat_goblin = "mutated"
	check(text.text.contains("胖哥布林") and text.text.contains("珍珠奶茶"), "Injected NPC and item names are copied for display")
	var snapshot := state.to_dict()
	list.item_selected.emit(2)
	check(title.text == "???" and not text.text.contains("交付对象") and not text.text.contains("隐藏奖励说明"), "Unrevealed task omits delivery and masks reward")
	state.set_flag("task.panel.revealed")
	check(text.text.contains("交付对象待确认") and text.text.contains("奖励：???") and not text.text.contains("隐藏地点"), "Task reveal exposes delivery but respects separate objective and reward masks")
	state.set_flag("task.panel.objective_revealed")
	state.set_flag("task.panel.reward_revealed")
	check(text.text.contains("隐藏地点") and text.text.contains("隐藏奖励说明"), "Independent reveal updates the selected detail immediately")
	state.restore_state(snapshot)
	list.item_selected.emit(3)
	check(text.text.contains("暂无奖励说明") and not text.text.contains("交付对象"), "Non-delivery tasks handle absent rewards without inventing them")
	list.item_selected.emit(1)
	await frames()
	check(text.text.contains("1 / 3") and list.get_item_tooltip(1) == title.text, "Counter and long-title tooltip are available")
	text.get_v_scroll_bar().value = 60
	await frames()
	var scroll := text.get_v_scroll_bar().value
	check(scroll > 0, "Long details have an independent scrollbar")
	state.set_variable("task.panel.count", 2)
	await frames()
	check(title.text.contains("聚落补给") and text.text.contains("2 / 3") and is_equal_approx(text.get_v_scroll_bar().value, scroll), "Same-task progress refresh preserves selection and detail scroll")
	list.item_selected.emit(0)
	await frames()
	check(text.get_v_scroll_bar().value == 0, "Switching tasks resets detail scroll to the top")
	state.apply_flags({"task.panel.board": true, "task.panel.delivery": true})
	check(text.text.contains("已完成") and text.text.contains("等待后续剧情") and list.item_count == 4, "All required objectives wait for explicit final completion")
	state.set_flag("task.panel.main_done")
	check(list.item_count == 4 and title.text.contains("第一笔订单") and text.text.contains("任务结果：已完成"), "Completed selection remains in history with its durable result")
	state.restore_state(snapshot)
	list.item_selected.emit(0)
	await capture("01_multi_task")
	list.grab_focus()
	await tap(KEY_DOWN)
	check(title.text.contains("聚落补给"), "Native arrow key selection updates detail")
	await tap(KEY_TAB)
	check(root.gui_get_focus_owner() != list and panel.is_ancestor_of(root.gui_get_focus_owner()), "Tab navigates within task controls")
	await capture("02_long_detail")
	for dimensions: Vector2i in [Vector2i(320, 360), Vector2i(640, 360)]:
		root.content_scale_size = dimensions
		root.size = dimensions
		await frames(6)
		check(body.vertical == (dimensions.x < 480), "Responsive list direction at " + str(dimensions))
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(panel.get_panel_rect()), "Panel stays within viewport at " + str(dimensions))
		check(text.size.y > 40 and text.size.x > 100, "Detail retains usable scrolling area at " + str(dimensions))
		if dimensions.x < 480:
			check(is_equal_approx(list.size.y, 88.0), "Narrow list height is 88 logical pixels")
			await capture("03_narrow")
			list.item_selected.emit(3)
			list.ensure_current_is_visible()
			await frames()
			state.set_flag("task.panel.simple_done")
			await frames()
			check(list.is_selected(3) and text.text.contains("任务结果：已完成") and list.item_count == 4, "Completing a scrolled selection preserves the selected history entry")
			state.restore_state(snapshot)
	var before_read := state.to_dict()
	panel.hide()
	list.item_selected.emit(3)
	panel.show()
	panel.set_delivery_names({"fat_goblin": "胖哥布林"}, {"pearl_milk_tea": "珍珠奶茶"})
	journal.refresh()
	check(state.to_dict() == before_read, "Open, close, select and refresh do not change facts or inventory")
	panel.bind_journal(journal)
	panel.bind_journal(journal)
	check(journal.projection_changed.get_connections().size() == 1, "Rebinding keeps exactly one panel subscription")
	root.remove_child(panel)
	check(journal.projection_changed.get_connections().is_empty(), "Panel disconnects on leaving the tree")
	state.set_variable("task.panel.count", 3)
	root.add_child(panel)
	panel.show()
	check(journal.projection_changed.get_connections().size() == 1, "Reentering the tree reconnects once")
	list.item_selected.emit(1)
	check(text.text.contains("3 / 3"), "Reentered panel displays latest facts")
	var other := TaskJournal.new()
	root.add_child(other)
	other.configure(catalog, state)
	panel.bind_journal(other)
	check(journal.projection_changed.get_connections().is_empty() and other.projection_changed.get_connections().size() == 1, "Switching journals disconnects the previous source")
	state.reset_state()
	check(list.item_count == 0 and title.text == "暂无任务记录", "Reset clears the visible activity browser")
	state.restore_state(snapshot)
	check(list.item_count == 4, "Restore reconstructs the active list")
	panel.bind_journal(null)
	check(list.item_count == 0 and other.projection_changed.get_connections().is_empty(), "Unbinding clears details and disconnects safely")
	panel.free()
	other.free()
	journal.free()
	state.reset_state()

func _test_material_panel() -> void:
	var state: StateData = root.get_node("GameState")
	state.reset_state()
	var catalog := TaskCatalog.new()
	check(catalog.load_file("res://src/resources/tasks/tasks.json") == OK, "Real material commission catalog loads")
	var journal := TaskJournal.new()
	root.add_child(journal)
	journal.configure(catalog, state)
	var panel: TaskPopup = load("res://src/UI/tasks/task_popup.tscn").instantiate()
	panel.bind_journal(journal)
	root.add_child(panel)
	panel.show()
	state.set_flag("world.phase.night")
	state.set_flag("task.tavern.insomnia.active")
	var view := journal.get_task("tavern.insomnia_order")
	check(view.delivery.has("items") and view.delivery.items.get("insomnia_mushroom") == 3, "Material projection exposes the configured item quantities")
	view.delivery.items.insomnia_mushroom = 99
	check(journal.get_task("tavern.insomnia_order").delivery.items.insomnia_mushroom == 3, "Material projection is independent of caller mutation")
	panel.set_delivery_names({"tavern": "酒馆"}, {"insomnia_mushroom": "醒神菇"})
	await frames()
	var text: RichTextLabel = panel.get_detail_text()
	check(text.text.contains("交付对象：酒馆") and text.text.contains("醒神菇 × 3"), "Material task panel displays target, item name and quantity")
	check(not text.text.contains("insomnia_mushroom") and not text.text.contains("成品待确认"), "Material details never leak internal item IDs or use finished-product placeholders")
	panel.free()
	journal.free()
	state.reset_state()

func _test_host(path: String) -> void:
	var state: StateData = root.get_node("GameState")
	state.reset_state()
	var game: MainGame = load(path).instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	var ui := game.get_ui_manager()
	var book := game.get_node("PopupLayer/HandbookPanel") as HandbookPanel
	var panel := book.get_tasks_page()
	var history := book.get_order_history_page()
	var player := game.get_player() as PlayerController
	check(game.open_tasks() == OK and panel.get_entries().item_count == 0, "Empty task log opens without inventing a task")
	check(not player.movement_enabled, "Task log owns the normal modal movement lock")
	await tap(KEY_ESCAPE)
	check(not ui.has_modal() and player.movement_enabled, "Esc releases task log input")
	state.set_flag("task.shop.first_order.active")
	check(panel.get_entries().item_count == 0, "Milk orders do not leak into the protagonist's task log")
	check(game.open_game_menu() == OK, "Open the game menu")
	game.get_game_menu().navigation_requested.emit(ScreenIds.ORDER_HISTORY)
	check(ui.is_open(ScreenIds.HANDBOOK) and book.get_pages().current_tab == 4, "Menu opens separate milk order history")
	check(history.get_entries().item_count == 1, "Accepted milk order is recorded in its own page")
	var before := state.to_dict()
	history.get_entries().item_selected.emit(0)
	check(state.to_dict() == before, "Reading an order record never accepts or delivers it")
	await tap(KEY_P)
	check(paused and not book.can_process(), "Pause freezes the shared history modal")
	await tap(KEY_ESCAPE)
	check(not paused and ui.is_open(ScreenIds.HANDBOOK), "Resume restores the history page")
	ui.close_screen(ScreenIds.ORDER_HISTORY)
	await frames()
	check(ui.is_open(ScreenIds.CHAPTER_ACTIONS), "History returns to its originating menu")
	ui.close_screen(ScreenIds.CHAPTER_ACTIONS)
	var task := game.get_task_journal().get_task("shop.first_order")
	var order: String = game.get_order_board().get_task_entry(task.id).order_id
	var product: String = task.delivery.product_id
	var recipe := game.get_tea_production().get_recipe_by_product(product)
	check(recipe != null and game.get_tea_production().craft(recipe.materials).ok, "Prepare the actual recorded product")
	check(game.get_task_delivery().try_submit(order, task.delivery.target_object_id).ok, "Recorded order completes through actual delivery")
	check(game.get_order_board().get_entry(order).status == "completed", "Order model retains the completed state")
	check(game.open_tasks() == OK and panel.get_entries().item_count == 0, "Completed milk orders remain separate from task log")
	ui.close_screen(ScreenIds.TASKS)
	check(ui.open_screen(ScreenIds.ORDER_HISTORY) == OK, "Reopen milk history")
	check(history.get_entries().get_item_text(0).begins_with("[已完成]"), "Completed order remains visible in history")
	ui.close_screen(ScreenIds.ORDER_HISTORY)
	var catalog := TaskCatalog.new()
	catalog.load_file(FIXTURE)
	game.get_task_journal().configure(catalog, state)
	state.set_flag("task.panel.active")
	check(game.open_tasks() == OK and panel.get_entries().item_count > 0, "Protagonist tasks appear in the task log")
	var main := game.get_task_journal().get_task("panel.counter")
	var seen := false
	for i in range(panel.get_entries().item_count):
		seen = seen or panel.get_entries().get_item_text(i).contains(String(main.title).replace("\n", " "))
	check(seen, "World task remains visible while milk orders are separated")
	ui.close_screen(ScreenIds.TASKS)
	game.free()
	await frames()
	check(not paused, "Host teardown leaves no owned pause")

func _test_demo() -> void:
	var state: StateData = root.get_node("GameState")
	state.set_flag("test.panel.before_demo")
	var snapshot := state.to_dict()
	var demo: Node = load("res://src/debug/tasks/task_panel_demo.tscn").instantiate()
	root.add_child(demo)
	await frames()
	var game := demo.get_child(0) as MainGame
	check(game.get_ui_manager().is_open(&"tasks") and game.get_task_journal().get_active_tasks().size() == 4, "F6 demo opens the multi-task fixture")
	await capture("05_demo")
	demo.free()
	await frames()
	check(state.to_dict() == snapshot, "Leaving the demo restores the original session")
