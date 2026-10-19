extends "res://tests/verify_day1_playability.gd"
## The same public counter handles story service and later real material delivery.

func _run() -> void:
	Engine.time_scale = 6.0
	var source := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--from-save="):
			source = argument.trim_prefix("--from-save=")
	if source.is_empty():
		printerr("Provide --from-save=<real day3_handoff checkpoint directory>")
		quit(2)
		return
	var directory := OS.get_cache_dir().path_join("goblin_counter_service_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(directory)
	check(DirAccess.copy_absolute(source.path_join("autosave.dat"), directory.path_join("autosave.dat")) == OK, "Isolate the real third-day checkpoint")
	ProjectSettings.set_setting("persistence/save_directory", directory)
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	state = root.get_node("GameState")
	check(GameEntry.continue_game(self) == OK, "Continue actual third-day save")
	await scene_changed
	attach()
	while game.is_session_initializing():
		await process_frame
	check(DayPhase.advance_to(state, 3, "night") == OK, "Wait until the allowed third evening")
	await travel("shop_exit")
	for point: GatherPoint in game.get_gathering_service().get_points():
		check(game.get_gathering_service().harvest(point.interaction_id).ok, "Collect actual festival materials")
	await travel("tavern_enter")
	var balance := game.get_transactions().get_balance()
	await use_service_point(&"tavern")
	check(state.get_flag("day3.festival.delivered"), "Physical E at the public counter delivers to the real tavern owner")
	check(game.get_transactions().get_balance() == balance + 60, "Counter delivery pays exactly 60G")
	var snapshot: Dictionary = state.to_dict()
	await use_service_point(&"tavern")
	check(state.to_dict() == snapshot, "Repeated counter E cannot deliver or pay twice")
	game.queue_free()
	await frames(10)
	print("COUNTER_SERVICE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
