extends SceneTree

const GOBLIN := preload("res://src/gameplay/characters/common_goblin.gd")
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
	_test_original_palettes()
	for path: String in ["res://src/gameplay/characters/common_goblin.tscn", "res://src/gameplay/characters/rpg_common_goblin.tscn"]:
		for appearance: int in [GOBLIN.Appearance.WITH_BACKPACK, GOBLIN.Appearance.WITHOUT_BACKPACK]:
			var actor = load(path).instantiate()
			actor.appearance = appearance
			root.add_child(actor)
			var sprite: AnimatedSprite2D = actor.animated_sprite
			var frames := sprite.sprite_frames
			for direction: int in [PlayerController.Facing.DOWN, PlayerController.Facing.UP]:
				actor.face_direction(direction)
				actor.move_direction(actor.get_facing_vector(), 1.0 / 60.0)
				var suffix: StringName = PlayerController.DIRECTION_NAMES[direction]
				check(sprite.animation == StringName("run_" + suffix), "Walking still selects original movement")
				actor.stop_performance_motion()
				var animation := StringName("idle_" + suffix)
				check(sprite.animation == animation and not sprite.flip_h, "Stopping selects front/back idle without mirroring")
				var count := frames.get_frame_count(animation)
				check(count == (16 if appearance == GOBLIN.Appearance.WITH_BACKPACK and direction == PlayerController.Facing.DOWN else 8), "Both variants have real front/back idle sequences")
				check(frames.get_animation_loop_mode(animation) == SpriteFrames.LOOP_LINEAR, "Idle loops continuously")
				var distinct: Dictionary = {}
				for index in count:
					var image := frames.get_frame_texture(animation, index).get_image()
					check(image.get_size() == Vector2i(64, 64), "Idle retains native 64px canvas")
					check(image.get_used_rect().has_area(), "Idle frame contains visible art")
					distinct[image.get_data().hex_encode().sha256_text()] = true
					if count == 8:
						check(image.get_used_rect().end.y == 59, "Generated idle feet remain at source baseline")
				check(distinct.size() > 1, "Idle changes artwork rather than repeating a walk still")
				sprite.set_frame_and_progress(0, 0.0)
				await create_timer(0.24).timeout
				check(sprite.frame > 0 and sprite.is_playing(), "Idle visibly advances after movement stops")
				# Crossing the last frame must keep playing the same idle animation.
				sprite.set_frame_and_progress(count - 1, 0.0)
				await sprite.animation_looped
				check(sprite.animation == animation and sprite.is_playing(), "Idle continues across its loop boundary")
			check(actor.appearance == appearance, "Idle playback keeps the selected appearance")
			actor.queue_free()
			await process_frame
	check(GOBLIN.BACKPACK_FRAMES.get_frame_count(&"idle_up") == 1, "Shared original backpack resource is not mutated")
	print("Common goblin idle: %d checks, %d failures" % [checked, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_original_palettes() -> void:
	var sources := {
		&"backpack_idle_up": "res://assets/characters/npc/common_goblin/walk_sheet_03.png",
		&"unpacked_idle_down": "res://assets/characters/goblin_actions/goblin_walk_down.png",
		&"unpacked_idle_up": "res://assets/characters/goblin_actions/goblin_walk_up.png",
	}
	for animation: StringName in sources:
		var original: Image = load(sources[animation]).get_image()
		var palette: Dictionary = {}
		for y in original.get_height():
			for x in original.get_width():
				var color := original.get_pixel(x, y)
				if color.a >= 0.5:
					color.a = 1.0
					palette[color] = true
		var image := (GOBLIN.IDLE_FRAMES.get_frame_texture(animation, 0) as AtlasTexture).atlas.get_image()
		var foreign_colors := 0
		for y in image.get_height():
			for x in image.get_width():
				var color := image.get_pixel(x, y)
				if color.a >= 0.5 and not palette.has(color):
					foreign_colors += 1
		check(foreign_colors == 0, String(animation) + " uses only exact original walk-sheet RGB colors")
