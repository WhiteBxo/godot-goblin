extends SceneTree
## Dedicated appearance, directional animation and inherited NPC rules.

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
	var map: Node = load("res://src/levels/rpg_maker/chapter_cave.tscn").instantiate()
	var bound: SettlementCharacter = map.get_node("Characters/DrunkenGuard")
	check(bound.actor_id == &"drunken_guard" and bound.scene_file_path.ends_with("rpg_drunken_guard.tscn"), "Formal map binds the portrait-matched guard under the existing story ID")
	check(not bound.visible and bound.active_phase == "night", "Authored night visibility remains configured")
	map.free()
	var world := Node2D.new()
	root.add_child(world)
	var actor: SettlementCharacter = load("res://src/gameplay/characters/rpg_drunken_guard.tscn").instantiate()
	world.add_child(actor)
	check(not actor.accepts_player_input and actor.collision_mask == 1 and actor.collision_layer == 4, "Guard keeps NPC input and collision rules")
	var frames := actor.animated_sprite.sprite_frames
	for animation: StringName in frames.get_animation_names():
		check(frames.get_frame_count(animation) > 0, "Populated animation: " + animation)
		for index in frames.get_frame_count(animation):
			var texture := frames.get_frame_texture(animation, index) as AtlasTexture
			check(texture.atlas.resource_path.begins_with("res://assets/characters/npc/drunken_guard/"), "Guard uses its own atlas")
			check(texture.get_size() == Vector2(128, 128) and texture.get_image().get_used_rect().has_area(), "Native frame is complete and nonempty")
	var director := ActorDirector.new()
	world.add_child(director)
	director.configure(world)
	director.actor_register(actor.actor_id, actor)
	for direction: StringName in [&"down", &"right", &"left", &"up"]:
		await director.actor_face(actor.actor_id, direction).wait()
		check(actor.animated_sprite.flip_h == (direction == &"left"), "East source mirrors only for west")
		check(frames.get_frame_count("run_" + direction) == 4, "Four real walk frames in every direction")
	var origin := actor.position
	var move := director.actor_move(actor.actor_id, origin + Vector2(32, 0), 64.0)
	await move.wait()
	check(move.succeeded and actor.position.distance_to(origin + Vector2(32, 0)) < 3, "Portrait-matched guard can actually walk")
	actor.hide()
	check(actor.collision_layer == 0, "Hidden guard relinquishes NPC collision")
	world.queue_free()
	await process_frame
	await process_frame
	print("DRUNKEN_GUARD: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
