extends SceneTree

var failures: Array[String] = []
var checked := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checked += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var director := ActorDirector.new()
	world.add_child(director)
	director.configure(world)
	for path in ["res://src/gameplay/characters/casino_sentry.tscn", "res://src/gameplay/characters/rpg_casino_sentry.tscn"]:
		var actor: SettlementCharacter = load(path).instantiate()
		world.add_child(actor)
		check(actor.actor_id == &"casino_sentry" and not actor.accepts_player_input, "Sentry has an independent NPC identity")
		check(director.actor_register(actor.actor_id, actor) == OK, "Register sentry")
		var frames := actor.animated_sprite.sprite_frames
		var counts := {"down": 13, "right": 15, "left": 15, "up": 10}
		for direction: String in counts:
			check(frames.get_frame_count("run_" + direction) == counts[direction], "Keep every supplied walk frame: " + direction)
			check(frames.get_frame_count("idle_" + direction) == 1, "Missing idle uses one matching walk frame")
			for index in frames.get_frame_count("run_" + direction):
				var texture := frames.get_frame_texture("run_" + direction, index) as AtlasTexture
				var image := texture.atlas.get_image()
				check(Rect2i(Vector2i.ZERO, image.get_size()).encloses(Rect2i(texture.region)), "Frame stays within source sheet")
				check(image.get_region(Rect2i(texture.region)).get_used_rect().has_area(), "Frame contains character pixels")
			await director.actor_face(actor.actor_id, StringName(direction)).wait()
			check(actor.animated_sprite.flip_h == (direction == "left"), "Side view mirrors only to the left")
			check(is_equal_approx(actor.animated_sprite.scale.x * 64.0, 128.0), "Base sprite keeps the established proportions")
		var origin := actor.position
		Input.action_press("move_right")
		await physics_frame
		await physics_frame
		Input.action_release("move_right")
		check(actor.position == origin, "NPC ignores player movement input")
		var move := director.actor_move(actor.actor_id, origin + Vector2(48, 0), 120.0)
		await move.wait()
		check(move.succeeded, "Sentry moves through the public ActorDirector API")
		check(actor.collision_layer == 4 and actor.collision_mask == 1, "Visible NPC occupies only the NPC layer and detects the world")
		actor.hide()
		check(actor.collision_layer == 0, "Hidden sentry stops blocking the player")
		director.actor_unregister(actor.actor_id)
		actor.free()
	var guard: SettlementCharacter = load("res://src/gameplay/characters/guard.tscn").instantiate()
	var texture := guard.get_node("Visual/AnimatedSprite2D").sprite_frames.get_frame_texture("idle_down", 0) as AtlasTexture
	check(guard.actor_id == &"guard" and texture.atlas.resource_path.begins_with("res://assets/characters/npc/guard/"), "Original guard retains its own sprite sheets")
	guard.free()
	world.free()
	var manager := DialogueManager.new()
	check(manager.speaker_portraits["侍卫"] == manager.speaker_portraits["护卫"], "Both source names map to the sentry illustration")
	check(manager.speaker_portraits["侍卫"] != manager.speaker_portraits["守卫"], "Sentry illustration is independent of the original guard")
	manager.free()
	var game: MainGame = load("res://src/core/casino.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await physics_frame
	await physics_frame
	var sentry := game.get_actor_director().get_actor(&"casino_sentry") as SettlementCharacter
	check(sentry != null, "Formal casino host registers the sentry")
	if sentry != null:
		var marker: Marker2D
		for candidate: Marker2D in game.get_active_level().get_story_positions():
			if candidate.name == &"casino_guard_a":
				marker = candidate
		check(marker != null and sentry.global_position == marker.global_position, "Sentry uses the existing casino guard anchor")
		var query := PhysicsShapeQueryParameters2D.new()
		var feet := sentry.get_node("CollisionShape2D") as CollisionShape2D
		query.shape = feet.shape
		query.transform = feet.global_transform
		query.collision_mask = 1
		check(sentry.get_world_2d().direct_space_state.intersect_shape(query).is_empty(), "Casino sentry does not overlap walls or furniture")
		check(sentry.get_node("Visual").scale == Vector2(0.5, 0.5), "Formal casino uses the RPG character scale")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			game.get_player().teleport_to(sentry.global_position + Vector2(96, 64))
			await create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("res://.godot/sentry_inspect/casino.png") == OK, "Capture sentry in the formal casino")
	game.queue_free()
	await process_frame
	print("Casino sentry: %d checks, %d failures" % [checked, failures.size()])
	quit(0 if failures.is_empty() else 1)
