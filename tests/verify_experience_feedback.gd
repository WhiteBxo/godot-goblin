extends SceneTree
## Real services: cosmetic feedback must preserve transactions, ownership and pause.

var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func frames(count := 3) -> void:
	for index in range(count):
		await process_frame

func _run() -> void:
	var state := root.get_node("GameState")
	state.start_new_game()
	await _wallet_feedback(state)
	await _soundscape(state)
	await _guard_feedback()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _capture_formal_stealth(state)
	state.start_new_game()
	print("EXPERIENCE_FEEDBACK: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _wallet_feedback(state: Node) -> void:
	var hud: Day1BusinessHUD = load("res://src/UI/milk_tea/day1_business_hud.tscn").instantiate()
	root.add_child(hud)
	var wallet: WalletTransactions = state.get_transactions()
	hud.configure(wallet, state.get_warehouse_inventory(), state)
	var snapshot: Dictionary = state.to_dict()
	check(wallet.add_money(3, "feedback.credit").ok, "Fixture credit commits")
	await frames()
	check("+3G" in hud.get_node("BusinessBalance").text, "Successful sale shows a positive delta")
	check(not wallet.spend_money(1000, "feedback.failed").ok, "Insufficient funds rejected")
	await frames()
	check("+3G" in hud.get_node("BusinessBalance").text, "Failed payment does not invent a balance change")
	check(state.restore_state(snapshot) == OK, "Original snapshot restores")
	await frames()
	check("+3G" not in hud.get_node("BusinessBalance").text and "-3G" not in hud.get_node("BusinessBalance").text, "Restore clears transient feedback without showing phantom spending")
	check(state.commit_story_transaction("feedback.grant", {}, {}, 20) == OK, "Story grant commits through existing transaction")
	await frames()
	check("+20G" in hud.get_node("BusinessBalance").text, "Story grants also show their true delta")
	wallet.spend_money(10, "feedback.debit")
	await frames()
	check("-10G" in hud.get_node("BusinessBalance").text, "Successful payment shows actual cost")
	state.start_new_game()
	await frames()
	check("-10G" not in hud.get_node("BusinessBalance").text, "New game clears old feedback")
	hud.free()

func _soundscape(state: Node) -> void:
	var audio := AudioManager.new()
	root.add_child(audio)
	var library: SoundLibrary = load("res://src/resources/audio/sound_library.tres")
	check(library.register_all(audio).is_empty(), "Existing audio catalogue registers")
	var player: PlayerController = load("res://src/gameplay/player/shop_player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	var soundscape := SceneSoundscape.new()
	root.add_child(soundscape)
	soundscape.configure(audio, player, state, library, "shop")
	soundscape.set_physics_process(false)
	check(audio.get_active_sound_count() == 1, "Shop starts exactly one ambience loop")
	var before: Dictionary = state.to_dict()
	for index in range(8):
		player.position.x += 8
		soundscape._physics_process(1.0 / 60.0)
	check(audio.get_active_sound_count() == 2, "Walking one stride produces one footstep")
	var count := audio.get_active_sound_count()
	for index in range(20):
		soundscape._physics_process(1.0 / 60.0)
	check(audio.get_active_sound_count() == count, "Standing still produces no steps")
	player.teleport_to(Vector2(2000, 2000))
	soundscape._physics_process(1.0 / 60.0)
	check(audio.get_active_sound_count() == count, "Teleport does not produce a footstep burst")
	player.set_movement_enabled(false)
	player.position.x += 100
	soundscape._physics_process(1.0 / 60.0)
	check(audio.get_active_sound_count() == count, "Locked movement is silent")
	check(state.to_dict() == before, "Soundscape never changes game state")
	soundscape.set_physics_process(true)
	paused = true
	var last_position := soundscape._last_position
	player.position.x += 10
	await frames()
	check(soundscape._last_position == last_position, "Soundscape processing respects pause")
	for voice: Dictionary in audio._active.values():
		check(voice.player.stream_paused, "World sound pauses with gameplay")
	paused = false
	soundscape.set_physics_process(false)
	var loop := soundscape._ambient_handle
	check(DayPhase.enter_night(state), "Night transition succeeds")
	check(soundscape._ambient_handle != loop and soundscape._ambient_handle != 0, "Night replaces only the ambient voice")
	var current: Dictionary = audio._active[soundscape._ambient_handle]
	check(is_equal_approx(current.player.volume_db, -29.0), "Night uses the quieter shop ambience")
	var other_owner := RefCounted.new()
	var other := audio.play_sfx("ambience.cave", other_owner)
	soundscape.free()
	check(audio._active.has(other) and audio.get_active_sound_count() == 1, "Leaving the scene cleans owned loops and steps, preserving unrelated audio")
	player.free()
	audio.free()
	state.start_new_game()

func _guard_feedback() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var player: PlayerController = load("res://src/gameplay/player/shop_player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.position = Vector2(300, 0)
	var actor: SettlementCharacter = load("res://src/gameplay/characters/guard.tscn").instantiate()
	world.add_child(actor)
	actor.face_direction(PlayerController.Facing.RIGHT)
	var guard := Day1GuardResponse.new()
	guard.actor = actor
	guard.sight_range = 200
	guard.discovery_seconds = 1.0
	world.add_child(guard)
	guard.capture_checkpoint()
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.position = Vector2(100, 0)
	var collider := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10, 500)
	collider.shape = rectangle
	wall.add_child(collider)
	world.add_child(wall)
	await physics_frame
	await physics_frame
	guard.set_feedback_enabled(true)
	guard.advance(0.01, player, world.get_world_2d().direct_space_state)
	check(guard._sight_polygon.size() > 3, "Active watch has a sight outline")
	var clipped := true
	for point: Vector2 in guard._sight_polygon:
		clipped = clipped and point.x <= 95.1
	check(clipped, "Visible cone stops at the same world wall that blocks detection")
	player.position = Vector2(50, 0)
	guard.advance(0.4, player, world.get_world_2d().direct_space_state)
	check(guard.state == Day1GuardResponse.State.ALERT and "40%" in guard.get_feedback_text(), "Warning reports actual detection progress")
	check(guard.distract(Vector2(50, 40)), "Coin distraction is accepted")
	check("分心" in guard.get_feedback_text() and "4.0" in guard.get_feedback_text(), "Distraction text reports actual remaining time")
	guard.advance(1, player, world.get_world_2d().direct_space_state)
	check("3.0" in guard.get_feedback_text(), "Distraction countdown follows the gameplay timer")
	guard.set_feedback_enabled(false)
	check(guard._sight_polygon.is_empty(), "Leaving active stealth clears its overlay")
	check(guard.state == Day1GuardResponse.State.DISTRACTED and guard.remaining == 3, "Hiding feedback never changes guard state")
	world.free()

func _capture_formal_stealth(state: Node) -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	state.start_new_game()
	state.select_business_profile("day1")
	state.set_flag("day1.s04.commission_accepted")
	state.set_story_stage("day1.s05.ready")
	DayPhase.enter_night(state)
	var game: MainGame = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(8)
	var service := game.get_stealth_service()
	var guard: Day1GuardResponse = service.get_setup().guards[0]
	var player := game.get_player() as PlayerController
	root.size = Vector2i(640, 360)
	# Start just outside the actual sight range; approach uses the real detector.
	player.teleport_to(guard.actor.global_position + guard.actor.get_facing_vector() * 145)
	await frames(8)
	await _capture("stealth_watch")
	player.teleport_to(guard.actor.global_position + guard.actor.get_facing_vector() * 75)
	for index in range(10):
		await physics_frame
	check(guard.state == Day1GuardResponse.State.ALERT, "Formal guard enters warning before discovery")
	await _capture("stealth_alert")
	var deadline := Time.get_ticks_msec() + 2000
	while service.status != Day1StealthService.Status.FAILED and Time.get_ticks_msec() < deadline:
		await physics_frame
	check(service.status == Day1StealthService.Status.FAILED and guard.actor.display_name in service.message, "Real failure identifies the detecting guard")
	await _capture("stealth_failed")
	var hud: Control = game.get_node("HudLayer/Day1StealthHUD")
	check(hud.get_global_rect().encloses(hud.get_node("Panel").get_global_rect()), "Failure panel fits 640 by 360")
	check(service.retry_attempt() == OK and service.status == Day1StealthService.Status.RUNNING, "Real failure retries without a presentation lock")
	check(not hud.get_node("Panel/Content/Actions/Retry").has_focus(), "Retry presentation never grabs keyboard focus automatically")
	current_scene = null
	game.free()
	await frames()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var directory := "/tmp/goblin_experience_20261019/captures"
	DirAccess.make_dir_recursive_absolute(directory)
	check(root.get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK, "Captured " + label)
