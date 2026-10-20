extends SceneTree

var checked := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checked += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var scene := preload("res://src/gameplay/characters/human_customer.tscn")
	var script := preload("res://src/gameplay/characters/human_customer.gd")
	var world := Node2D.new()
	root.add_child(world)
	var male_count := 0
	seed(20261019)
	for sample in 256:
		var actor = scene.instantiate()
		if actor.get_script() != script:
			check(false, "Customer scene must use the appearance script")
			actor.free()
			quit(1)
			return
		world.add_child(actor)
		var chosen: int = actor.appearance
		male_count += int(chosen == script.Appearance.MALE)
		var frames: SpriteFrames = actor.animated_sprite.sprite_frames
		check(chosen in [script.Appearance.MALE, script.Appearance.FEMALE], "Random appearance resolves once on spawn")
		check(frames == (script.MALE_FRAMES if chosen == script.Appearance.MALE else script.FEMALE_FRAMES), "All animations use the chosen character's frames")
		check(actor.actor_id == &"human_customer", "Both appearances retain the existing order and story target")
		for direction in PlayerController.Facing.values():
			actor.face_direction(direction)
			check(actor.animated_sprite.flip_h == (direction == PlayerController.Facing.LEFT), "Both appearances mirror the left-facing side view")
			actor.move_direction(actor.get_facing_vector(), 1.0 / 60.0)
			check(actor.animated_sprite.animation == StringName("run_" + PlayerController.DIRECTION_NAMES[direction]), "The chosen appearance walks in every direction")
			actor.stop_performance_motion()
			check(actor.animated_sprite.animation == StringName("idle_" + PlayerController.DIRECTION_NAMES[direction]), "Stopping selects the matching idle")
		actor.hide()
		check(actor.collision_layer == 0, "Hidden customers do not block the player")
		actor.show()
		check(actor.appearance == chosen and actor.animated_sprite.sprite_frames == frames and actor.collision_layer == 4, "Movement and hide/show preserve appearance and restore blocking")
		actor.free()
	check(male_count >= 96 and male_count <= 160, "Seeded sample is consistent with equal male/female probability")
	print("Human customer sample: %d male / %d female" % [male_count, 256 - male_count])
	var director := ActorDirector.new()
	world.add_child(director)
	director.configure(world)
	for chosen in [script.Appearance.MALE, script.Appearance.FEMALE]:
		var actor = scene.instantiate()
		actor.appearance = chosen
		world.add_child(actor)
		check(actor.appearance == chosen and not actor.accepts_player_input, "Fixed appearances work without enabling player input")
		check(director.actor_register(&"human_customer", actor) == OK, "Both appearances register with the same Actor ID")
		var origin: Vector2 = actor.position
		Input.action_press("move_right")
		await physics_frame
		await physics_frame
		Input.action_release("move_right")
		check(actor.position == origin, "Neither appearance responds to player movement input")
		var action := director.actor_move(&"human_customer", Vector2(48, 0), 120.0)
		await action.wait()
		check(action.succeeded and actor.appearance == chosen, "ActorDirector movement preserves appearance")
		director.actor_unregister(&"human_customer")
		actor.free()
	var female: SettlementCharacter = preload("res://src/gameplay/characters/human_customer_female.tscn").instantiate()
	world.add_child(female)
	check(female.animated_sprite.sprite_frames == script.FEMALE_FRAMES, "Standalone female preview remains fixed")
	female.free()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for chosen in [script.Appearance.MALE, script.Appearance.FEMALE]:
			var actor = scene.instantiate()
			actor.appearance = chosen
			actor.position = Vector2(180 if chosen == script.Appearance.MALE else 460, 260)
			world.add_child(actor)
			var label := Label.new()
			label.theme = preload("res://src/resources/ui/game_theme.tres")
			label.text = "男顾客 · 50%" if chosen == script.Appearance.MALE else "女顾客 · 50%"
			label.position = actor.position + Vector2(-55, 20)
			world.add_child(label)
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://docs/assets/captures/human_customer_ratio_2026_10_19.png") == OK, "Capture both customer appearances")
	world.queue_free()
	await process_frame
	print("Human customer appearances: %d checks, %d failures" % [checked, failures.size()])
	quit(0 if failures.is_empty() else 1)
