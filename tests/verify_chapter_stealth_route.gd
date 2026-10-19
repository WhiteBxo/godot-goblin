extends SceneTree
## Actual input, floor collision and guard sensing from the shop door to the
## negotiated entrance and back. No teleport is used to complete this route.
var game: MainGame
var state: Node
var checks := 0
var failures: Array[String] = []
var automatic_dialogue := true
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
func frames(count := 6) -> void:
	for i in range(count):
		await physics_frame
func _process(_delta: float) -> bool:
	if automatic_dialogue and is_instance_valid(game):
		var dialogue := game.get_dialogue_manager()
		if dialogue != null and dialogue.is_active():
			dialogue.advance()
			dialogue.select_choice(0)
	return false
func stop_input() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)
func walk_to(goal: Vector2) -> bool:
	var map := game.get_active_level() as RpgChapterMap
	var player: PlayerController = game.get_player()
	var path := map.get_navigation_path(player.global_position, goal)
	check(not path.is_empty(), "Floor route exists to " + str(goal))
	if path.is_empty(): return false
	path.append(goal)
	Input.action_press("player_sneak")
	for target: Vector2 in path:
		var budget := 720
		while player.global_position.distance_to(target) > 5.0 and budget > 0:
			budget -= 1
			stop_input()
			if player.movement_enabled:
				# Modal story locks clear held inputs; keep holding Ctrl after release.
				Input.action_press("player_sneak")
				var offset := target - player.global_position
				if absf(offset.x) > 3: Input.action_press("move_right" if offset.x > 0 else "move_left")
				if absf(offset.y) > 3: Input.action_press("move_down" if offset.y > 0 else "move_up")
			var stealth := game.get_stealth_service()
			if stealth != null and stealth.status == Day1StealthService.Status.FAILED:
				check(false, "Route discovered near " + str(player.global_position) + " / " + stealth.message)
				stop_input()
				return false
			await physics_frame
		if budget == 0:
			check(false,"Movement blocked near " + str(player.global_position) + " toward " + str(target))
			stop_input()
			return false
	stop_input()
	Input.action_release("player_sneak")
	print("WALKED ",goal)
	return true
func wait_quiet() -> void:
	for i in range(2400):
		await physics_frame
		if not game.get_story_director().is_busy() and not game.get_dialogue_manager().is_active():return
	check(false,"Story releases player control")
func exit_through(id: String) -> bool:
	var point: SceneExit
	for exit: SceneExit in game.get_active_level().get_scene_exits():
		if String(exit.interaction_id) == id: point = exit
	if point == null or not await walk_to(point.global_position): return false
	var error := game.get_scene_travel().request_exit(point)
	check(error == OK,"Actual scene travel through " + id)
	if error != OK:return false
	await scene_changed
	game = current_scene as MainGame
	await frames(20)
	return true
func run() -> void:
	Engine.time_scale = 6.0
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/stealth_route_%d" % OS.get_process_id())
	state = root.get_node("GameState")
	state.reset_state()
	state.select_business_profile("day1")
	state.set_story_stage("day1.s05.ready")
	DayPhase.advance_to(state,1,"night")
	state.commit_story_transaction("route.funding",{},{},71,{}, {"day1.s04.commission_accepted":true})
	check(change_scene_to_file("res://src/core/settlement.tscn") == OK,"Load the real exterior")
	await scene_changed
	game = current_scene as MainGame
	await frames(20)
	for waypoint: Vector2 in [Vector2(1176,1392),Vector2(1320,1392),Vector2(1320,984),Vector2(1176,648)]:
		if not await walk_to(waypoint):
			quit(1);return
	var stealth := game.get_stealth_service()
	check(stealth.select_throwable(&"coin") == OK and stealth.request_throw(Vector2(1128,456)) == OK, "A real coin distracts the entrance watch")
	await frames(40)
	if not await walk_to(Vector2(1320,648)) or not await walk_to(Vector2(1368,456)):
		quit(1);return
	await wait_quiet()
	check(state.get_flag("day1.s05.drunken_paid"),"Physical approach triggers and pays the drunken guard")
	if not await walk_to(Vector2(1752,504)):
		quit(1);return
	check(game.get_story_director().request_interaction("mansion_payment") == OK,"Reach the real pair payment position")
	await wait_quiet()
	check(state.get_flag("day1.s05.guard_payment_completed"),"Pair accepts the real 10G payment")
	if not await exit_through("elder_enter"):
		quit(1);return
	check(game.get_stealth_service() == null,"Interior has no stealth failure")
	for point: InteractionPoint in game.get_active_level().get_interaction_points():
		if point is StoryInteractionPoint and String(point.interaction_id) in ["day1_elder_document","day1_blood_storage"]:
			if not await walk_to(point.global_position + Vector2(0,32)):
				quit(1);return
			await frames()
			check(point.is_available() and point.resolve().ok,"Physically reach and collect " + String(point.interaction_id))
	if not await exit_through("elder_exit") or not await walk_to(Vector2(1176,648)):
		quit(1);return
	await frames(20)
	check(state.get_flag("day1.s05.escape_completed"),"Return on foot completes escape")
	check(state.get_transactions().get_balance() == 41,"One distraction and the two payments fit the real mission budget")
	# A depleted attempt can always return to its initial resources and position.
	check(game.get_stealth_service().retry_attempt() == OK,"Retry remains available after resource use")
	await frames(20)
	check(state.get_transactions().get_balance() == 71 and not state.get_flag("day1.s05.guard_payment_completed") and not state.get_flag("day1.s05.blood_acquired"),"Retry restores resources and both-room mission facts")
	stealth = game.get_stealth_service()
	check(stealth.select_throwable(&"coin") == OK, "Select real retry coins")
	for i in range(7):
		check(stealth.request_throw(Vector2(1128,456)) == OK, "Spend another real distraction")
		await frames(25)
	check(state.get_transactions().get_balance() == 1, "Player can exhaust the mission budget without a permanent dead end")
	check(stealth.retry_attempt() == OK and state.get_transactions().get_balance() == 71, "Depleted attempt restores the complete starting budget")
	stop_input()
	print("CHAPTER_STEALTH_ROUTE: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
