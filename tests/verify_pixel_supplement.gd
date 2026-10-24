extends SceneTree
## Retained frames, actual NPC playback, directional movement and optional render.

const IDS := ["market_mother", "common_goblin", "common_goblin", "casino_poet", "market_vendor_1", "market_vendor_2", "market_vendor_3", "casino_sentry"]
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
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	root.content_scale_size = Vector2i(1250, 760)
	var background := ColorRect.new()
	background.color = Color(0.88, 0.84, 0.74)
	background.size = Vector2(1250, 760)
	root.add_child(background)
	var world := Node2D.new()
	root.add_child(world)
	var director := ActorDirector.new()
	world.add_child(director)
	director.configure(world)
	var actors: Array[SettlementCharacter] = []
	for index in IDS.size():
		var id: String = IDS[index]
		var actor: SettlementCharacter = load("res://src/gameplay/characters/rpg_%s.tscn" % id).instantiate()
		if id == "common_goblin":
			actor.appearance = 1 if index == 1 else 2
		actor.actor_id = StringName("supplement_%d" % index)
		actor.position = Vector2(150 + index % 4 * 300, 250 + index / 4 * 330)
		actor.scale = Vector2(2, 2)
		world.add_child(actor)
		check(director.actor_register(actor.actor_id, actor) == OK, "Register supplied appearance: " + id)
		check(not actor.accepts_player_input and actor.collision_mask == 1, "NPC keeps input and collision isolation: " + id)
		var frames := actor.animated_sprite.sprite_frames
		for animation: StringName in frames.get_animation_names():
			check(frames.get_frame_count(animation) > 0, "Animation is populated: " + String(animation))
			for frame in frames.get_frame_count(animation):
				var texture := frames.get_frame_texture(animation, frame) as AtlasTexture
				check(texture != null and Rect2(Vector2.ZERO, texture.atlas.get_size()).encloses(texture.region), "Frame fits its original atlas")
				if texture != null:
					var used := texture.get_image().get_used_rect()
					check(used.has_area() and used.end.y <= texture.get_height() - 2, "Every native frame has visible artwork above the feet anchor")
		for direction: String in ["down", "up", "right", "left"]:
			await director.actor_face(actor.actor_id, StringName(direction)).wait()
			check(actor.animated_sprite.flip_h == ((direction == "right") if actor.side_faces_left else (direction == "left")), "Direction uses the actor's own mirror convention")
			if not (id == "casino_sentry" and direction in ["right", "left"]):
				check(frames.get_frame_count("idle_" + direction) > 1, "Supplied idle is a real sequence")
		await director.actor_face(actor.actor_id, &"down").wait()
		if id == "casino_sentry":
			for emote: StringName in [&"emote_laugh", &"emote_sit"]:
				check(not frames.get_animation_loop(emote), "Sentry emote can complete through ActorDirector")
				var action := director.actor_animate(actor.actor_id, emote)
				await action.wait()
				check(action.succeeded, "Supplied emote completes: " + String(emote))
		var label := Label.new()
		label.theme = load("res://src/resources/ui/game_theme.tres")
		label.text = actor.display_name + ("（背包）" if index == 1 else "（无背包）" if index == 2 else "")
		label.position = actor.position + Vector2(-100, 25)
		world.add_child(label)
		actors.append(actor)
	await physics_frame
	await physics_frame
	for actor: SettlementCharacter in actors:
		actor.animated_sprite.set_frame_and_progress(0, 0.0)
	await create_timer(0.4).timeout
	for actor: SettlementCharacter in actors:
		check(actor.animated_sprite.frame > 0 and actor.animated_sprite.is_playing(), "New idle visibly advances: " + actor.display_name)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://.godot/pixel_supplement/npc_preview.png") == OK, "Capture updated runtime characters")
	world.free()
	background.free()
	await process_frame
	print("PIXEL_SUPPLEMENT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
