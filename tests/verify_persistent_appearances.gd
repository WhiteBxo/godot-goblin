extends SceneTree

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
	var state := root.get_node("GameState")
	GameEntry._save_session_active = true
	var world := Node2D.new()
	root.add_child(world)
	var scenes := [preload("res://src/gameplay/characters/human_customer.tscn"), preload("res://src/gameplay/characters/common_goblin.tscn")]
	var first_choices: Array[int] = []
	state.set_variable("visuals.appearance_seed", 20261020)
	for scene in scenes:
		var actor: SettlementCharacter = scene.instantiate()
		world.add_child(actor)
		first_choices.append(actor.get("appearance"))
		actor.free()
	var snapshot: Dictionary = state.to_dict()
	for iteration in range(16):
		state.set_variable("visuals.appearance_seed", randi())
		check(state.restore_state(snapshot) == OK, "Replace the entire state from a saved snapshot")
		for index in range(scenes.size()):
			var actor: SettlementCharacter = scenes[index].instantiate()
			world.add_child(actor)
			check(actor.get("appearance") == first_choices[index], "Human and goblin appearance survives reconstruction and unrelated RNG changes")
			actor.free()
	check(state.to_dict() == snapshot, "Appearance reconstruction never mutates the loaded snapshot")
	snapshot.variables.erase("visuals.appearance_seed")
	check(state.restore_state(snapshot) == OK, "Legacy snapshot has no appearance seed")
	var legacy := -1
	for iteration in range(8):
		var actor: SettlementCharacter = scenes[0].instantiate()
		world.add_child(actor)
		if legacy == -1:
			legacy = actor.get("appearance")
		check(actor.get("appearance") == legacy, "Legacy appearance fallback is stable without resaving")
		actor.free()
	check(state.to_dict() == snapshot, "Legacy compatibility does not silently rewrite state")
	var male := 0
	for session_seed in range(256):
		state.set_variable("visuals.appearance_seed", session_seed)
		var actor: SettlementCharacter = scenes[0].instantiate()
		world.add_child(actor)
		male += int(actor.get("appearance") == 1)
		actor.free()
	check(male >= 96 and male <= 160, "Saved seeds retain equal male and female probability across sessions")
	world.free()
	print("PERSISTENT_APPEARANCES: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
