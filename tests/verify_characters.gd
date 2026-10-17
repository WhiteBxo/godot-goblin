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
