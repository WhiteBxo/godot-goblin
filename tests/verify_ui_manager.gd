extends SceneTree

var checks := 0
var failures: Array[String] = []
var game: MainGame

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)

func frames(count: int = 2) -> void:
	for index in range(count):
		await process_frame

func tap(key: Key, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	game = load("res://src/debug/story/legacy_shop.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	var manager := game.get_ui_manager()
	var dialogue := game.get_dialogue_manager()
	var ui: DialogueUI = game.get_node("PopupLayer/DialogueUI")
	var cancellation_requests: Array[bool] = []
	ui.cancel_requested.connect(func() -> void: cancellation_requests.append(true))
	var shop: ShopUI = game.get_node("HudLayer/ShopUI")
	var popup: ShopPopup = game.get_node("PopupLayer/Modal")
	var player := game.get_player() as PlayerController
	var point: InteractionPoint = game.get_active_level().get_interaction_points()[0]
	check(manager.process_mode == Node.PROCESS_MODE_ALWAYS, "UIManager works during pause")
	check(manager.register_screen(&"shop", popup, &"popup", true) == ERR_ALREADY_EXISTS, "Duplicate registration rejected")
	check(manager.open_screen(&"missing") == ERR_DOES_NOT_EXIST, "Missing screen returns an error")
	manager.close_screen(&"missing")
	check(not manager.has_modal(), "Unknown close is harmless")
	var original_focus := Button.new()
	original_focus.text = "HUD action"
	game.get_node("HudLayer/ShopUI").add_child(original_focus)
	original_focus.grab_focus()
	shop.open(point)
	check(manager.has_modal() and shop.is_open() and not player.movement_enabled, "Shop modal locks gameplay synchronously")
	check(dialogue.start_dialogue("demo.greeting") == ERR_BUSY, "Shop rejects dialogue without cancelling shop")
	check(manager.open_screen(&"shop") == OK, "Repeated open is idempotent")
	var close_button := popup.get_default_focus()
	var outside := Button.new()
	outside.text = "outside"
	game.get_node("HudLayer").add_child(outside)
	outside.grab_focus()
	await frames()
	check(root.gui_get_focus_owner() == close_button, "Modal reclaims attempted outside focus")
	outside.queue_free()
	check(root.gui_get_focus_owner() == close_button, "Shop gets default focus")
	await tap(KEY_TAB)
	check(root.gui_get_focus_owner() == close_button, "Focus cycles within modal")
	await tap(KEY_P)
	check(paused and manager.is_open(&"pause") and shop.is_open(), "P overlays pause without closing shop")
	check(not popup.can_process() and close_button.focus_mode == Control.FOCUS_NONE and close_button.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Covered popup cannot process, focus or receive mouse input")
	var position := player.global_position
	Input.action_press("move_right")
	await create_timer(0.08, true).timeout
	Input.action_release("move_right")
	check(player.global_position == position, "Paused player stays still")
	await tap(KEY_ESCAPE)
	check(not paused and shop.is_open() and not player.movement_enabled, "Esc resumes into shop with gameplay still locked")
	check(root.gui_get_focus_owner() == close_button, "Resume restores shop focus")
	await tap(KEY_ESCAPE)
	check(not shop.is_open() and not paused and not manager.has_modal(), "One Esc closes exactly one layer")
	check(player.movement_enabled, "Last modal restores movement")
	check(root.gui_get_focus_owner() == original_focus, "Closing last modal restores original HUD focus")
	original_focus.queue_free()
	player.set_movement_enabled(false)
	shop.open(point)
	shop.close()
	check(not player.movement_enabled, "Initially disabled movement stays disabled")
	player.set_movement_enabled(true)
	check(dialogue.start_dialogue("demo.greeting") == OK, "Existing dialogue starts through manager")
	shop.open(point)
	check(not shop.is_open() and dialogue.is_active(), "Dialogue rejects shop without cancelling dialogue")
	await frames(3)
	await tap(KEY_P)
	var characters: int = ui.get_node("Panel/Margin/Content/Line/Text").visible_characters
	var line_id := dialogue.get_current_line_id()
	await create_timer(0.12, true).timeout
	check(ui.get_node("Panel/Margin/Content/Line/Text").visible_characters == characters, "Pause freezes the typewriter")
	await tap(KEY_E)
	check(dialogue.get_current_line_id() == line_id and ui.is_revealing(), "Confirm only reaches pause, preserving dialogue progress")
	check(not paused and dialogue.is_active(), "Confirm resumes without cancelling dialogue")
	# Exercise real selectable buttons while preserving the DialogueManager lifecycle.
	ui.present_line("店长", "请选择", null, ["第一项", "第二项", "第三项"])
	ui.reveal_all()
	await frames()
	await tap(KEY_DOWN)
	var selected := root.gui_get_focus_owner()
	check(selected.text == "第二项", "Down moves one choice")
	await tap(KEY_P)
	await tap(KEY_P)
	check(root.gui_get_focus_owner() == selected, "Pause restores selected dialogue choice")
	manager.close_screen(&"dialogue")
	check(not dialogue.is_active() and not manager.has_modal() and player.movement_enabled, "Manager close ends the dialogue session")
	check(cancellation_requests.size() == 1, "Closing through UI emits one cancellation request")
	dialogue.start_dialogue("demo.greeting")
	dialogue.end_dialogue(false)
	check(cancellation_requests.size() == 1, "Normal dialogue completion does not request cancellation")
	await tap(KEY_ESCAPE)
	check(paused, "Esc in gameplay opens pause")
	await tap(KEY_P, true)
	check(paused, "Echo does not toggle pause")
	await tap(KEY_P)
	check(not paused and player.movement_enabled, "P resumes gameplay")
	# Story timer and player lock survive pause and a nested shop UI.
	var story := game.get_story_director()
	check(story.load_events("res://src/debug/interaction/demo_story.json") == OK, "Wait story fixture loads")
	check(story.request_event("feedback.wait") == OK, "Real wait story starts")
	await frames(3)
	manager.set_paused(true)
	await create_timer(0.08, true).timeout
	check(story.is_busy(), "Pause preserves running story")
	manager.set_paused(false)
	check(not player.movement_enabled, "Resuming does not release story movement lock")
	shop.open(point)
	shop.close()
	check(not player.movement_enabled, "Closing modal does not release story movement lock")
	story.cancel_event()
	check(player.movement_enabled, "Cancelling final story lock restores movement")
	# A second independent lock remains after closing a modal.
	var actors := game.get_actor_director()
	var action := actors.actor_move(&"player", player.global_position + Vector2(100, 0), 30.0)
	await frames()
	check(actors.is_actor_controlled(&"player"), "Real actor action claims player")
	shop.open(point)
	shop.close()
	check(actors.is_actor_controlled(&"player") and not player.movement_enabled, "Closing UI preserves actor control and movement lock")
	actors.cancel_action(action)
	check(player.movement_enabled, "Final actor lock release restores movement")
	var custom := Control.new()
	custom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	check(manager.register_screen(&"temporary", custom, &"popup", true) == OK, "Unparented modal can register")
	manager.open_screen(&"temporary")
	custom.queue_free()
	await frames()
	check(not manager.has_modal() and manager.open_screen(&"temporary") == ERR_DOES_NOT_EXIST, "Freed modal unregisters and releases lock")
	if "--capture" in OS.get_cmdline_user_args():
		await capture_visuals(shop, point, manager, dialogue)
	check(dialogue.start_dialogue("demo.greeting") == OK, "Dialogue starts before manager destruction")
	manager.set_paused(true)
	manager.queue_free()
	await frames()
	check(not paused and not dialogue.is_active() and player.movement_enabled, "Manager destruction ends dialogue and releases owned pause and movement lock")
	game.queue_free()
	await frames()
	var host := Node.new()
	root.add_child(host)
	var external := UIManager.new()
	host.add_child(external)
	paused = true
	external.set_paused(false)
	check(paused, "Manager cannot resume externally owned pause")
	external.queue_free()
	await frames()
	check(paused, "Manager destruction preserves external pause")
	paused = false
	host.queue_free()
	print("UI_MANAGER: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func capture_visuals(shop: ShopUI, point: InteractionPoint, manager: UIManager, dialogue: DialogueManager) -> void:
	for size in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1440, 720)]:
		root.size = size
		await create_timer(0.25, true).timeout
		check(root.size == size, "Window accepts requested size: %s" % size)
		print("UI_CAPTURE window=%s viewport=%s" % [root.size, root.get_visible_rect().size])
		point.description = "这是一段用于检查长文本换行与滚动的店铺说明。".repeat(40)
		shop.open(point)
		await frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/goblin-ui-shop-%dx%d.png" % [size.x, size.y])
		manager.set_paused(true)
		await frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/goblin-ui-pause-%dx%d.png" % [size.x, size.y])
		manager.set_paused(false)
		shop.close()
		dialogue.start_dialogue("demo.greeting")
		var ui: DialogueUI = game.get_node("PopupLayer/DialogueUI")
		ui.present_line("店长", "欢迎回来，今天也一起经营小店吧。".repeat(8), null, ["接下新的订单，准备开始今天的工作。".repeat(4), "查看仓库", "稍后再说"])
		ui.reveal_all()
		await frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/goblin-ui-dialogue-%dx%d.png" % [size.x, size.y])
		dialogue.end_dialogue(true)
