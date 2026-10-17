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
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://src/gameplay/characters/character_catalog.json"))
	await _test_all_npc_bodies()
	var world := Node2D.new()
	root.add_child(world)
	var director := ActorDirector.new()
	world.add_child(director)
	director.configure(world)
	var used_sources: Dictionary = {}
	for item: Dictionary in catalog:
		var actor: SettlementCharacter = load("res://src/gameplay/characters/%s.tscn" % item.id).instantiate()
		world.add_child(actor)
		check(not actor.accepts_player_input, item.id + " must ignore player input")
		check(actor.collision_layer == 1 << (PlayerController.NPC_LAYER - 1), item.id + " occupies the solid NPC layer")
		actor.hide()
		var hidden_layer := actor.collision_layer
		actor.show()
		check(hidden_layer == 0 and actor.collision_layer != 0, item.id + " only blocks the player while on stage")
		check(director.actor_register(actor.actor_id, actor) == OK, item.id + " register")
		var frames := actor.animated_sprite.sprite_frames
		for animation: StringName in frames.get_animation_names():
			for index in frames.get_frame_count(animation):
				var texture := frames.get_frame_texture(animation, index) as AtlasTexture
				used_sources[texture.atlas.resource_path] = true
				var image := texture.atlas.get_image()
				var region := Rect2i(texture.region)
				check(Rect2i(Vector2i.ZERO, image.get_size()).encloses(region), "%s/%s frame bounds" % [item.id, animation])
				check(image.get_region(region).get_used_rect().has_area(), "%s/%s blank frame" % [item.id, animation])
		var origin := actor.position
		Input.action_press("move_right")
		await physics_frame
		await physics_frame
		Input.action_release("move_right")
		check(actor.position == origin, item.id + " input isolation")
		for direction: StringName in [&"down", &"left", &"right", &"up"]:
			var face := director.actor_face(actor.actor_id, direction)
			await face.wait()
			check(face.succeeded and actor.animated_sprite.animation == StringName("idle_" + direction), item.id + " face " + direction)
		var move := director.actor_move(actor.actor_id, Vector2(48, 0), 120.0)
		await move.wait()
		check(move.succeeded and actor.position.distance_to(Vector2(48, 0)) < 0.6, item.id + " actual director movement")
		actor.queue_free()
		await process_frame
	check(used_sources.size() == 31, "All 31 NPC source sheets must be referenced")
	# An empty world isolates the player-versus-NPC body from walls and furniture.
	var solid_actor: SettlementCharacter = load("res://src/gameplay/characters/common_goblin.tscn").instantiate()
	solid_actor.position = Vector2(300, 300)
	world.add_child(solid_actor)
	var probe: PlayerController = load("res://src/gameplay/player/shop_player.tscn").instantiate()
	probe.position = Vector2(300, 360)
	world.add_child(probe)
	await physics_frame
	check(probe.test_move(probe.global_transform, Vector2(0.0, -60.0)), "Player cannot walk into an on-stage NPC")
	solid_actor.hide()
	await physics_frame
	check(not probe.test_move(probe.global_transform, Vector2(0.0, -60.0)), "Hiding an NPC removes its blocking body")
	probe.queue_free()
	await process_frame
	world.queue_free()
	await process_frame
	var main: MainGame = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await physics_frame
	await physics_frame
	for item: Dictionary in catalog:
		var actor := main.get_actor_director().get_actor(StringName(item.id))
		check(actor != null, item.id + " settlement registered")
		if actor == null:
			continue
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = actor.get_node("CollisionShape2D").shape
		query.transform = actor.get_node("CollisionShape2D").global_transform
		query.collision_mask = 1
		check(actor.get_world_2d().direct_space_state.intersect_shape(query).is_empty(), item.id + " spawn must not overlap walls/furniture")
	var player := main.get_player() as PlayerController
	check(player.get_collision_mask_value(PlayerController.NPC_LAYER), "Player body reacts to NPC actors")
	main.queue_free()
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		var gallery: Node2D = load("res://src/debug/characters/character_gallery.tscn").instantiate()
		root.add_child(gallery)
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png("/tmp/godot_character_gallery.png")
		check(error == OK, "Gallery screenshot")
		gallery.queue_free()
		await process_frame
	print("Characters: %d checks, %d failures" % [checked, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_all_npc_bodies() -> void:
	var scenes: Array[String] = []
	for directory in ["res://src/gameplay/characters", "res://src/debug/actors", "res://src/debug/cinematic"]:
		for file in DirAccess.get_files_at(directory):
			if file.ends_with(".tscn"):
				var candidate: Node = load(directory.path_join(file)).instantiate()
				if candidate is PlayerController and not candidate.accepts_player_input:
					scenes.append(directory.path_join(file))
				candidate.free()
	check(scenes.size() >= 11, "Collision coverage includes catalog, human customer and performance actors")
	var world := Node2D.new()
	root.add_child(world)
	var entities := Node2D.new()
	world.add_child(entities)
	var director := ActorDirector.new()
	world.add_child(director)
	director.configure(entities)
	for path in scenes:
		var spawn := director.actor_spawn(&"npc", load(path), Vector2(300, 300))
		await spawn.wait()
		var actor := director.get_actor(&"npc")
		check(spawn.succeeded and actor != null, path + " spawns through ActorDirector")
		if actor == null:
			continue
		check(actor.collision_mask == 1, path + " only detects the world")
		for player_path in ["res://src/gameplay/player/player.tscn", "res://src/gameplay/player/shop_player.tscn"]:
			var probe: PlayerController = load(player_path).instantiate()
			world.add_child(probe)
			probe.set_physics_process(false)
			await physics_frame
			for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				probe.teleport_to(actor.global_position - direction * 70.0)
				check(probe.test_move(probe.global_transform, direction * 70.0), path + " blocks " + player_path + " from " + str(direction))
			probe.teleport_to(actor.global_position + Vector2(0, 70))
			for tick in 40:
				await physics_frame
				probe.move_direction(Vector2.UP, 1.0 / Engine.physics_ticks_per_second)
			check(probe.position.y > actor.position.y + 8.0, path + " stops actual player movement")
			await director.actor_hide(&"npc").wait()
			await physics_frame
			check(not probe.test_move(probe.global_transform, Vector2(0, -70)), path + " hide removes blocking")
			await director.actor_show(&"npc").wait()
			await physics_frame
			check(probe.test_move(probe.global_transform, Vector2(0, -70)), path + " show restores blocking")
			entities.hide()
			await physics_frame
			check(actor.collision_layer == 0 and not probe.test_move(probe.global_transform, Vector2(0, -70)), path + " hidden parent removes blocking")
			entities.show()
			await physics_frame
			check(probe.test_move(probe.global_transform, Vector2(0, -70)), path + " parent show restores blocking")
			probe.queue_free()
			await process_frame
		director.actor_unregister(&"npc")
		actor.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
