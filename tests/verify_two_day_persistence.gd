extends SceneTree
## A fresh process restores each real autosave produced by verify_two_day_flow.
var state: Node
var game: MainGame
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
	Engine.time_scale = 6.0
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	ProjectSettings.set_setting("persistence/save_directory", args[0])
	state = root.get_node("GameState")
	var store := GameEntry.create_save_store()
	var loaded := store.load_save(GameEntry.preflight_save)
	check(loaded.error == OK, "Cold process validates real checkpoint")
	if loaded.error != OK:
		quit(1)
		return
	var before := FileAccess.get_file_as_bytes(args[0].path_join("autosave.dat"))
	check(GameEntry.continue_game(self) == OK, "Continue through real host reconstruction")
	for frame in range(600):
		await process_frame
		if current_scene is MainGame and not current_scene.is_session_initializing():
			break
	game = current_scene as MainGame
	check(game != null and not game.is_session_initializing(), "Reconstructed host becomes interactive")
	if game == null:
		quit(1)
		return
	for frame in range(12):
		await process_frame
	check(state.to_dict() == loaded.data.game_state, "Exact wallet, quotes, stock, receipts, tasks and escrow survive cold restore")
	check(FileAccess.get_file_as_bytes(args[0].path_join("autosave.dat")) == before, "Restoring does not rotate or rewrite the checkpoint")
	check(game.get_chapter_gameplay().last_error.is_empty() and game.get_chapter_controller().last_error.is_empty(), "Recovery produces no chapter or route failure")
	check(game.get_player().movement_enabled and not game.get_story_director().is_busy(), "Waiting boundary releases player input")
	check(not game.has_scene_arrival(), "Recovery never fabricates actual entrance travel")
	if args[0].get_file() == "day3_handoff":
		var actions := game.get_chapter_gameplay()
		var ids: Array = actions.get_user_actions().map(func(action: Dictionary) -> String: return action.id)
		check(ids.has("hire:day2_ordinary_a"), "Late hire remains available after closed business is restored")
		actions.perform_user_action("hire:day2_ordinary_a")
		for frame in range(6):
			await process_frame
		check(actions.get_procurement().get_status().status == "hired", "Late hire is a real UI action")
		check(DayPhase.advance_to(state, 3, "night") == OK, "Wait to the allowed third evening")
		for frame in range(10):
			await process_frame
		check(state.get_warehouse_inventory().get_stock("insomnia_mushroom") == 1, "Restored late hire returns a real portion")
		check(game.get_task_delivery().try_submit("day3_procurement", "fat_goblin").ok, "Real restored shop supports last-day handoff")
		for frame in range(10):
			await process_frame
		check(actions.get_procurement().get_status().status == "delivered", "Handoff closes the escrow commission")
	if args[0].get_file() == "day4_expired":
		check(state.current_day == 4 and game.get_chapter_gameplay().get_procurement().get_status().status == "expired", "Expired procurement survives cold restart")
		check(game.get_chapter_gameplay().get_user_actions().is_empty(), "Day4 exposes no new chapter or late hire")
		check(not game.get_task_delivery().try_submit("day3_procurement", "fat_goblin").ok, "Expired handoff cannot consume or complete")
	print("TWO_DAY_PERSISTENCE: %s · %d checks, %d failures" % [args[0].get_file(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
