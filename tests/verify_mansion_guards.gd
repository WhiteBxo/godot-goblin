extends SceneTree
## Both guards flank the actual doorway, with reachable payment and entry.

var checks := 0
var failures: Array[String] = []
var state: Node
var game: MainGame

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func ticks(count := 6) -> void:
	for index in count:
		await physics_frame

func walk_to(goal: Vector2) -> bool:
	var player := game.get_player()
	var route: PackedVector2Array = game.get_active_level().get_navigation_path(player.global_position, goal)
	check(not route.is_empty(), "Saved floor passages reach the real destination")
	if route.is_empty():
		return false
	for waypoint: Vector2 in route:
		var move := game.get_actor_director().actor_move(&"player", waypoint, 240.0, 2.0)
		await move.wait()
		if not move.succeeded:
			check(false, "Walk without crossing a wall or NPC")
			return false
	var final := game.get_actor_director().actor_move(&"player", goal, 120.0, 2.0)
	await final.wait()
	check(final.succeeded, "Reach the interaction on foot")
	return final.succeeded

func press_e() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = &"interact"
		event.pressed = pressed
		Input.parse_input_event(event)
		await ticks(2)

func _run() -> void:
	Engine.time_scale = 6.0
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/mansion_guards_%d" % OS.get_process_id())
	state = root.get_node("GameState")
	state.reset_state()
	state.select_business_profile("day1")
	state.set_flag("day1.s04.commission_accepted")
	state.set_flag("day1.s05.drunken_paid")
	state.set_story_stage("day1.s05.ready")
	check(state.get_transactions().add_money(30, "verify.mansion_guards.funds").ok, "Prepare an isolated payment wallet")
	check(change_scene_to_file("res://src/core/settlement.tscn") == OK, "Load the formal exterior")
	await scene_changed
	game = current_scene as MainGame
	await ticks(20)
	var map := game.get_active_level() as RpgChapterMap
	var door: SceneExit
	for exit: SceneExit in map.get_scene_exits():
		if exit.interaction_id == &"elder_enter":
			door = exit
	check(door != null, "The actual elder-house door exists")
	if door == null:
		quit(1)
		return
	var left := game.get_actor_director().get_actor(&"mansion_lure") as SettlementCharacter
	var right := game.get_actor_director().get_actor(&"mansion_gate") as SettlementCharacter
	check(left != null and right != null and left.is_visible_in_tree() and right.is_visible_in_tree(), "Both real guards are visible")
	check(left.global_position.x < door.global_position.x and right.global_position.x > door.global_position.x, "Guards flank the actual door, not a remote street")
	for actor: SettlementCharacter in [left, right]:
		check(actor.global_position.distance_to(door.global_position) < 90.0, "Guard stands at the doorstep")
		var anchor := game.get_actor_director().get_position(actor.actor_id)
		check(anchor != null and anchor.global_position == actor.global_position, "Scene restoration uses the new doorstep anchor")
		check(map.can_stand_at(actor.global_position, Vector2(8.5, 5)), "Doorstep guard stands on saved walkable floor")
	var payment: InteractionPoint
	for point: InteractionPoint in map.get_interaction_points():
		if point.interaction_id == &"mansion_payment":
			payment = point
	check(payment != null and payment.required_actors.has(left) and payment.required_actors.has(right), "Payment remains bound to both actual guards")
	if payment == null:
		quit(1)
		return
	check(absf(payment.global_position.x - (left.global_position.x + right.global_position.x) * 0.5) < 1.0, "Payment is between the doorstep guards")
	check(not door.are_conditions_met(state), "The actual door remains locked before paying")
	game.get_player().teleport_to(Vector2(1416, 456))
	if not await walk_to(payment.global_position):
		quit(1)
		return
	await ticks()
	check(payment.is_available() and game.get_shop_interaction().get_target() == payment, "Player actually selects doorstep payment")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.godot/mansion_guards")
		check(root.get_texture().get_image().save_png("res://.godot/mansion_guards/doorstep.png") == OK, "Capture guards at the real doorway")
	var balance: int = state.get_transactions().get_balance()
	await press_e()
	var deadline := Time.get_ticks_msec() + 10000
	while (not state.get_flag("day1.s05.guard_payment_completed") or game.get_story_director().is_busy()) and Time.get_ticks_msec() < deadline:
		var dialogue := game.get_dialogue_manager()
		if dialogue.is_active():
			dialogue.advance()
			dialogue.select_choice(0)
		await process_frame
	check(state.get_flag("day1.s05.guard_payment_completed"), "Real E negotiation pays the doorstep guards")
	check(state.get_transactions().get_balance() == balance - 10, "Payment spends exactly ten G")
	check(door.are_conditions_met(state), "Paying opens the actual nearby door")
	check(not payment.interaction_enabled, "Paid guards no longer steal the nearby door's E prompt")
	await ticks()
	# The door sprite is on the wall tile; E is used from the walkable step below.
	if not await walk_to(door.global_position + Vector2(0, 40)):
		quit(1)
		return
	await ticks()
	check(door.is_available() and game.get_shop_interaction().get_target() == door, "Player walks between both guards onto the real entrance")
	if not door.is_available() or game.get_shop_interaction().get_target() != door:
		quit(1)
		return
	await press_e()
	await scene_changed
	game = current_scene as MainGame
	while game.get_scene_travel().is_busy():
		await process_frame
	check(game.scene_file_path == "res://src/core/elder_house.tscn", "Actual E enters the elder house")
	check(state.get_transactions().get_balance() == balance - 10, "Entry never charges the payment again")
	var outside: SceneExit
	for exit: SceneExit in game.get_active_level().get_scene_exits():
		if exit.interaction_id == &"elder_exit":
			outside = exit
	check(outside != null and game.get_scene_travel().request_exit(outside) == OK, "Return through the real elder-house exit")
	await scene_changed
	game = current_scene as MainGame
	while game.get_scene_travel().is_busy():
		await process_frame
	await ticks()
	for id: StringName in [&"mansion_lure", &"mansion_gate"]:
		var actor := game.get_actor_director().get_actor(id)
		var anchor := game.get_actor_director().get_position(id)
		check(actor.is_visible_in_tree() and actor.global_position == anchor.global_position, "Rebuilt exterior keeps the guard at his doorstep anchor")
	check(state.get_transactions().get_balance() == balance - 10, "Round trip preserves the single payment")
	game.queue_free()
	await process_frame
	print("MANSION_GUARDS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
