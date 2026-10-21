extends SceneTree

var checks := 0
var failures: Array[String] = []
var calls: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count: int = 3) -> void:
	for index in range(count):
		await physics_frame
		await process_frame

func has_sound(audio: AudioManager, id: String) -> bool:
	var library: SoundLibrary = load("res://src/resources/audio/sound_library.tres")
	for entry in library.entries:
		if entry.id == id:
			for voice: Dictionary in audio._active.values():
				if voice.player.stream in entry.streams:
					return true
	return false

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	await test_audio()
	await test_ui()
	await test_host("res://src/debug/story/legacy_shop.tscn")
	await test_host("res://src/core/settlement.tscn")
	print("INTERACTION_AUDIO: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_audio() -> void:
	var audio: AudioManager = load("res://src/core/audio/audio_manager.tscn").instantiate()
	root.add_child(audio)
	var feedback: InteractionAudio = load("res://src/core/audio/interaction_audio.tscn").instantiate()
	root.add_child(feedback)
	check(feedback.configure(audio).is_empty(), "Catalogue registers without errors")
	for event: String in feedback.event_sounds:
		check(audio.sounds.has(feedback.event_sounds[event]), "Registered event: " + event)
	var handle := feedback.play_event("craft_success")
	check(handle != 0 and has_sound(audio, "shop.sealer"), "Craft uses a real catalogue stream")
	check(audio._active[handle].player.bus == &"SFX" and audio._active[handle].player.volume_db == -6.0, "World routing and volume")
	check(feedback.play_event("craft_success") == 0, "Duplicate same-frame result is silent")
	handle = feedback.play_sound("story.page_turn", "UI")
	check(handle != 0 and audio._active[handle].player.bus == &"UI", "Non-UI ID respects explicit UI route")
	handle = feedback.play_sound("ui.hover")
	check(handle != 0 and audio._active[handle].player.volume_db == -14.0, "Hover uses quieter volume")
	handle = feedback.play_focus()
	check(handle != 0 and audio._active[handle].player.volume_db == feedback.focus_volume_db, "World focus tick uses its own quiet volume")
	check(feedback.play_focus() == 0, "Rapid focus changes stay throttled")
	handle = feedback.play_blip()
	check(handle != 0 and audio._active[handle].player.volume_db == feedback.blip_volume_db, "Dialogue blip uses its own quiet volume")
	check(feedback.play_event("unknown") == 0 and feedback.play_sound("missing") == 0, "Unknown mapping safely skips playback")
	feedback.repeat_guard_ms = 0
	feedback.configure(audio)
	var previous: AudioStream
	for index in range(8):
		handle = feedback.play_sound("player.step_wood")
		var stream: AudioStream = audio._active[handle].player.stream
		check(stream != previous, "Variants do not repeat consecutively")
		previous = stream
		audio.stop_sound(handle)
	var other := RefCounted.new()
	var unrelated := audio.play_sfx("story.knock", other)
	feedback.configure(audio)
	check(audio.get_active_sound_count() == 1 and audio._active.has(unrelated), "Reconfigure stops only feedback voices")
	var wallet := WalletTransactions.new()
	root.add_child(wallet)
	wallet.transaction_finished.connect(feedback.on_transaction_finished)
	check(wallet.add_money(1, "audio_test").ok and has_sound(audio, "shop.coins"), "Actual transaction success has coins")
	feedback.configure(audio)
	var balance := wallet.get_balance()
	check(not wallet.add_money(1, "audio_test").ok and wallet.get_balance() == balance and has_sound(audio, "ui.failure") and not has_sound(audio, "shop.coins"), "Duplicate transaction sounds failure without another payment")
	wallet.free()
	feedback.free()
	check(audio._active.has(unrelated) and audio.get_active_sound_count() == 1, "Exit preserves another owner's voice")
	audio.free()
	await frames(1)

func record(id: String, bus: String) -> void:
	calls.append(id + ":" + bus)

func test_ui() -> void:
	var scope := Control.new()
	root.add_child(scope)
	var feedback := UIAudioFeedback.new()
	root.add_child(feedback)
	feedback.configure(record, [scope])
	var button := Button.new()
	scope.add_child(button)
	var transient := Button.new()
	scope.add_child(transient)
	transient.free()
	await frames(1)
	calls.clear()
	button.button_down.emit()
	check(calls == ["ui.confirm:UI"], "Dynamically created button is bound")
	feedback.configure(record, [scope])
	calls.clear()
	button.button_down.emit()
	check(calls.size() == 1, "Reconfigure does not duplicate callbacks")
	button.disabled = true
	button.button_down.emit()
	button.disabled = false
	button.hide()
	button.button_down.emit()
	button.show()
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.button_down.emit()
	check(calls.size() == 1, "Disabled, hidden and covered buttons remain silent")
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_entered.emit()
	check(calls.size() == 1, "Programmatic focus is silent")
	Input.action_press("ui_down")
	button.focus_entered.emit()
	Input.action_release("ui_down")
	check(calls.back() == "ui.hover:UI", "Keyboard focus has hover feedback")
	button.set_meta("ui_press_sound", "")
	var count := calls.size()
	button.button_down.emit()
	check(calls.size() == count, "Business-owned choice sound can mute generic press")
	button.set_meta("ui_press_sound", "ui.cancel")
	button.button_down.emit()
	check(calls.back() == "ui.cancel:UI", "Close button overrides confirmation")
	var list := ItemList.new()
	scope.add_child(list)
	await frames(1)
	list.item_selected.emit(0)
	check(calls.back() == "ui.confirm:UI", "Dynamic list selection is bound")
	feedback.free()
	scope.free()
	await frames(1)

func test_host(path: String) -> void:
	var state := root.get_node("GameState")
	state.reset_state()
	var game: MainGame = load(path).instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	var audio := game.get_audio_manager()
	var feedback: InteractionAudio = game.get_node("Systems/InteractionAudio")
	check(audio.sounds.has("shop.sealer"), "Host registers catalogue without Day1: " + path)
	for point: InteractionPoint in game.get_active_level().get_interaction_points():
		if point.interaction_id not in [&"orders", &"storage", &"tea_station"]:
			continue
		game.get_player().global_position = point.global_position + Vector2(0, -40)
		await frames()
		feedback.configure(audio)
		point.interact()
		check(game.get_shop_ui().is_open() and has_sound(audio, point.success_sound), "Real point opens with configured sound: " + str(point.interaction_id))
		feedback.configure(audio)
		game.get_shop_ui().close()
		check(has_sound(audio, "ui.cancel"), "Shop close has cancel sound")
		await frames()
	feedback.configure(audio)
	var ui := game.get_shop_ui()
	var materials: Array[String] = ["black_tea", "creamer", "pearl", "syrup"]
	ui.craft_requested.emit(materials, 1)
	check(has_sound(audio, "shop.sealer") and game.get_warehouse_inventory().get_stock("pearl_milk_tea") == 1, "Actual craft produces product and plays sealer")
	feedback.configure(audio)
	var before := game.get_warehouse_inventory().to_dict()
	var invalid: Array[String] = []
	ui.craft_requested.emit(invalid, 1)
	check(has_sound(audio, "ui.failure") and not has_sound(audio, "shop.sealer") and before == game.get_warehouse_inventory().to_dict(), "Failed craft has only failure result and preserves stock")
	feedback.configure(audio)
	game.get_task_delivery().accept_order("order_001")
	var result := game.get_task_delivery().try_deliver("order_001", "pearl_milk_tea", "fat_goblin")
	check(result.ok and has_sound(audio, "shop.coins"), "Actual delivery plays reward sound")
	feedback.configure(audio)
	result = game.get_task_delivery().try_deliver("order_001", "pearl_milk_tea", "fat_goblin")
	check(not result.ok and has_sound(audio, "ui.failure") and not has_sound(audio, "shop.coins"), "Repeated delivery plays failure")
	feedback.configure(audio)
	var manager := game.get_ui_manager()
	manager.set_paused(true)
	check(paused and has_sound(audio, "ui.confirm"), "Pause opens with feedback")
	var count := audio.get_active_sound_count()
	manager.set_paused(true)
	check(audio.get_active_sound_count() == count, "Repeated pause is silent")
	var handle := feedback.play_sound("story.page_turn", "UI")
	check(handle != 0 and audio._active[handle].player.can_process(), "UI voice can process during pause")
	feedback.configure(audio)
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.physical_keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	key = InputEventKey.new()
	key.keycode = KEY_E
	key.physical_keycode = KEY_E
	Input.parse_input_event(key)
	await process_frame
	check(not paused and has_sound(audio, "ui.cancel"), "Real keyboard activation resumes with cancel")
	if game.get_gathering_service() != null:
		state.set_flag("world.phase.night")
		# The confirm sound belongs to the interaction layer, so drive the real
		# gather point instead of calling the service directly (which never sounds).
		var gather: GatherPoint = null
		for point: GatherPoint in game.get_active_level().get_gather_points():
			if point.interaction_id == &"night_gather_0":
				gather = point
		check(gather != null, "Night gather point is registered on the chapter map")
		if gather != null:
			game.get_player().global_position = gather.global_position + Vector2(0, -40)
			await frames()
			feedback.configure(audio)
			gather.interact()
			check(game.get_warehouse_inventory().get_stock("moss_green") >= 2 and has_sound(audio, "ui.confirm"),
				"Successful harvest confirms actual result")
			feedback.configure(audio)
			gather.interact()
			check(not has_sound(audio, "ui.confirm"), "Spent harvest never sounds success")
	game.free()
	await frames()
	state.reset_state()
