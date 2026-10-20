extends SceneTree
## Real host selection and document-close reward routing for every source clue.
## Each host runs through a real scene change: a fifth host boot in one process
## crashes this engine build during teardown, so the rescue menu lives in
## verify_signature_rescue.gd and starts from a clean process.
var checks := 0
var failures := 0
var _game: MainGame

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 6) -> void:
	for i in range(count):
		await physics_frame

func tap(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

## Loads a host the way the player reaches it, so only one MainGame tree is ever alive.
func open_scene(scene_name: String) -> bool:
	if change_scene_to_file("res://src/core/" + scene_name + ".tscn") != OK:
		return false
	await scene_changed
	await frames(2)
	_game = current_scene as MainGame
	return _game != null

func run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	var state := root.get_node("GameState")
	state.reset_state()
	state.set_flag("day2.s04.casino_reward_received")
	state.get_warehouse_inventory().add_ingredient("rainbow_cube", 1)
	for entry: Array in [["tavern", "S04", "SignatureS04"], ["casino", "S07", "SignatureS07"], ["elder_house", "S10", "SignatureS10"], ["settlement", "S08", "SignatureS08"]]:
		if not await open_scene(entry[0]):
			check(false, "Real host opens: " + entry[1])
			continue
		var game := _game
		var point: SignatureDiscoveryPoint = game.get_active_level().get_node("Interactions/" + entry[2])
		var player: PlayerController = game.get_player()
		player.teleport_to(point.global_position + Vector2(0, 20))
		await frames()
		check(point.is_available(), "Physical overlap opens source clue: " + entry[1])
		var before: int = state.get_transactions().get_balance()
		await tap(&"interact")
		await frames()
		check(game.get_shop_ui().is_open() and state.get_transactions().get_balance() == before, "E opens a document before paying its reward: " + entry[1])
		check(game.get_shop_ui().get_popup().is_visible_in_tree(), "Discovery content is visible: " + entry[1])
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/signature_" + entry[1] + "_document.png")
		game.get_shop_ui().close()
		await frames()
		check(state.get_transactions().is_signature_discovered(entry[1]) and state.get_transactions().get_balance() == before + 150, "Closing the actual host document commits exactly one bounty: " + entry[1])
	print("SIGNATURE_INTERACTION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
