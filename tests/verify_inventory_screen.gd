extends SceneTree
## Portable warehouse: one shared inventory, opened without walking to a storage point.
## Covers the standalone screen composition plus both formal hosts.

var _checks: int = 0
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames(count: int = 2) -> void:
	for index in range(count):
		await process_frame

func _tap(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	await _test_screen_composition()
	await _test_portable_session("res://src/debug/story/legacy_shop.tscn")
	await _test_portable_session("res://src/core/settlement.tscn")
	print("INVENTORY_SCREEN: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	quit(0 if _failures.is_empty() else 1)

func _test_screen_composition() -> void:
	var inventory := WarehouseInventory.new()
	var screen: InventoryPanel = preload("res://src/UI/inventory/inventory_panel.tscn").instantiate()
	root.add_child(screen)
	screen.configure(inventory)
	await process_frame
	var page := screen.get_warehouse_panel()
	_check(page != null and page is WarehousePanel, "Portable screen hosts the shared warehouse page")
	_check(page.get_list().item_count == 6, "Portable screen lists the six configured ingredients")
	_check(screen.get_default_focus() == page.get_list(), "Portable screen focuses the item list")
	_check(screen.uses_native_gui_input(), "List and filter keep native key navigation")
	_check(inventory.add_ingredient("black_tea", 1) and "红茶  13" in page.get_list().get_item_text(0), "Portable screen refreshes from the shared inventory")
	_check(screen.get_shell().get_content() == page, "Warehouse page fills the modal shell body")
	screen.queue_free()
	inventory.free()
	await _frames()

func _test_portable_session(scene_path: String) -> void:
	root.get_node("GameState").start_new_game()
	root.size = Vector2i(1280, 720)
	var main: MainGame = load(scene_path).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames()
	var manager := main.get_ui_manager()
	var inventory := main.get_warehouse_inventory()
	var page := main.get_inventory_panel()
	var player := main.get_player() as PlayerController
	_check(page != null and page.get_list().item_count == 6, "Portable warehouse exists in the host: " + scene_path)
	_check(not manager.is_open(ScreenIds.INVENTORY), "Portable warehouse starts closed")
	_check(main.open_inventory() == OK and manager.is_open(ScreenIds.INVENTORY), "Portable warehouse opens without an interaction point")
	_check(page.is_visible_in_tree() and not player.movement_enabled, "Open portable warehouse uses the modal and movement lock")
	_check(main.open_inventory() == ERR_BUSY, "Second open request is rejected while open")
	inventory.add_ingredient("black_tea", 1)
	_check("红茶  13" in page.get_list().get_item_text(0), "Open portable warehouse reacts to stock changes")
	inventory.try_consume({"black_tea": 13})
	_check("缺货" in page.get_list().get_item_text(0), "Emptying a stack updates the open list")
	inventory.add_ingredient("black_tea", 13)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for size: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
			root.size = size
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/inventory_%s_%dx%d.png" % [scene_path.get_file().get_basename(), size.x, size.y])
		root.size = Vector2i(1280, 720)
	await _tap(KEY_ESCAPE)
	_check(not manager.is_open(ScreenIds.INVENTORY) and player.movement_enabled, "Esc closes the portable warehouse and restores movement")
	await _tap(KEY_B)
	_check(manager.is_open(ScreenIds.INVENTORY) and not player.movement_enabled, "B opens the portable warehouse from the world")
	await _tap(KEY_B)
	_check(manager.is_open(ScreenIds.INVENTORY), "B while open never stacks a second warehouse")
	manager.close_screen(ScreenIds.INVENTORY)
	manager.set_paused(true)
	_check(main.open_inventory() == ERR_BUSY, "Paused session refuses the portable warehouse")
	manager.set_paused(false)
	_check(main.open_inventory() == OK and manager.is_open(ScreenIds.INVENTORY), "Portable warehouse reopens after pause")
	var shop := main.get_shop_ui()
	if shop != null:
		_check(shop.get_popup().get_warehouse_panel() != page, "Shop storage keeps its own page instance")
		_check(shop.get_popup().get_warehouse_panel().get_list().get_item_text(0) == page.get_list().get_item_text(0), "Both entries read the same committed stock")
	manager.close_screen(ScreenIds.INVENTORY)
	_check(player.movement_enabled, "Closing the portable warehouse restores movement")
	main.queue_free()
	await _frames()
