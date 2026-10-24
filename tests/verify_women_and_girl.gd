extends SceneTree
## Focused appearance checks, real movement, formal bindings and optional captures.

const IDS := ["market_mother", "prayer_woman", "goblin_girl"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count := 4) -> void:
	for index in count:
		await physics_frame

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	ProjectSettings.set_setting("persistence/save_directory", "user://verification/appearances_%d" % OS.get_process_id())
	var world := Node2D.new()
	root.add_child(world)
	var director := ActorDirector.new()
	world.add_child(director)
	director.configure(world)
	for id: String in IDS:
		var actor: SettlementCharacter = load("res://src/gameplay/characters/rpg_%s.tscn" % id).instantiate()
		world.add_child(actor)
		check(actor.actor_id == StringName(id) and not actor.accepts_player_input, "Independent NPC identity: " + id)
		check(director.actor_register(actor.actor_id, actor) == OK, "Register updated appearance: " + id)
		var resource := actor.animated_sprite.sprite_frames
		for animation: StringName in resource.get_animation_names():
			check(resource.get_frame_count(animation) > 0 and resource.get_animation_loop(animation), "Playable animation: %s/%s" % [id, animation])
			for index in resource.get_frame_count(animation):
				var texture := resource.get_frame_texture(animation, index) as AtlasTexture
				check(texture != null, "Frame is an atlas texture")
				if texture == null:
					quit(1)
					return
				var image := texture.get_image()
				var rect := image.get_used_rect()
				check(Rect2i(Vector2i.ZERO, texture.atlas.get_size()).encloses(Rect2i(texture.region)), "Frame stays inside atlas")
				var feet := texture.get_height() - 2
				var bottom_min := feet - 4 if id == "market_mother" and String(animation).begins_with("run_") else feet
				check(rect.has_area() and rect.position.x >= 2 and rect.end.x <= texture.get_width() - 2 and rect.end.y >= bottom_min and rect.end.y <= feet, "Artwork stays aligned, retaining native foot bounce")
		for direction: String in ["down", "up", "right", "left"]:
			check(resource.has_animation("idle_" + direction) and resource.has_animation("run_" + direction), "Four-way movement contract")
			await director.actor_face(actor.actor_id, StringName(direction)).wait()
			var mirror := direction == "right" if actor.side_faces_left else direction == "left"
			check(actor.animated_sprite.flip_h == mirror, "Side direction uses the matching mirror: " + direction)
		var origin := actor.position
		Input.action_press("move_right")
		await frames()
		Input.action_release("move_right")
		check(actor.position == origin, "NPC ignores player input")
		for direction: Vector2 in [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]:
			var action := director.actor_move(actor.actor_id, actor.position + direction * 12, 60.0)
			await frames(2)
			check(String(actor.animated_sprite.animation).begins_with("run_"), "Public movement plays locomotion")
			await action.wait()
			check(action.succeeded, "Public movement reaches target")
		check(actor.position.distance_to(origin) < 2, "Four directions return to the starting position")
		actor.hide()
		check(actor.collision_layer == 0, "Hidden NPC does not block")
		director.actor_unregister(actor.actor_id)
		actor.free()
	world.free()
	# Dialogue source bindings must match both days, including every mother line.
	for name: String in ["day1_stages_03_06", "day2_stages_01_05"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/resources/dialogue/%s.json" % name))
		var mothers := 0
		for dialogue: Dictionary in data.dialogues.values():
			for line: Dictionary in dialogue.lines.values():
				if line.speaker == "哥布林母亲":
					mothers += 1
					check(line.get("portrait") == "res://assets/characters/npc/market_mother/portrait.png", "Mother has her own portrait in " + name)
		check(mothers == 7, "All seven mother lines are bound")
	var state := root.get_node("GameState")
	state.reset_state()
	state.select_business_profile("day1")
	state.set_story_stage("day1.s04.wait_taste")
	state.set_flag("day1.s04.commission_accepted")
	var game: MainGame = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(game)
	await frames(16)
	var mother := game.get_actor_director().get_actor(&"market_mother") as SettlementCharacter
	var companion := game.get_actor_director().get_actor(&"prayer_woman") as SettlementCharacter
	var girl := game.get_actor_director().get_actor(&"village_child") as SettlementCharacter
	check(mother != null and companion != null and girl != null, "Formal settlement registers all three characters")
	if mother == null or companion == null or girl == null:
		quit(1)
		return
	check(mother.animated_sprite.sprite_frames != companion.animated_sprite.sprite_frames, "Formal mother no longer shares companion artwork")
	check(girl.get_interaction_feedback_rect().size.y < mother.get_interaction_feedback_rect().size.y, "Girl remains smaller than adults")
	for id: StringName in [&"market_mother", &"prayer_woman", &"village_child"]:
		var actor := game.get_actor_director().get_actor(id)
		game.get_player().teleport_to(actor.global_position + Vector2(0, 28))
		await frames()
		var point := game.get_delivery_point(String(id))
		check(point != null and point.is_available(), "Existing interaction remains reachable: " + String(id))
		if point == null:
			quit(1)
			return
		point.interact()
		await frames()
		check(game.get_dialogue_manager().is_active(), "Real interaction opens the updated character dialogue")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			var target_line: String = {&"market_mother": "line_2", &"prayer_woman": "line_3", &"village_child": "line_1"}[id]
			for index in 12:
				if game.get_dialogue_manager().get_current_line_id() == target_line:
					break
				game.get_dialogue_manager().advance()
			check(game.get_dialogue_manager().get_current_line_id() == target_line, "Capture the intended speaker")
			await create_timer(0.5).timeout
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("res://.godot/%s_updated.png" % id) == OK, "Capture actual settlement dialogue")
		for index in 600:
			if not game.get_story_director().is_busy():
				break
			game.get_dialogue_manager().advance()
			game.get_dialogue_manager().select_choice(0)
			await process_frame
		check(not game.get_story_director().is_busy() and game.get_story_director().last_error.is_empty(), "Conversation returns control")
	game.free()
	await frames()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		var preview: Node2D = load("res://src/debug/characters/women_and_girl_preview.tscn").instantiate()
		root.add_child(preview)
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://.godot/women_and_girl_preview.png") == OK, "Render the updated portraits and animations")
		preview.queue_free()
		await frames()
	print("Women and girl: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
