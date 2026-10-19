extends SceneTree
## Body feel is presentation only: it may stretch, squash and step-bob the
## player, but must always settle on the authored size and on whole pixels.

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func frames(count: int) -> void:
	for index in range(count):
		await process_frame

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	await _exercise(Vector2.ONE, "full-size")
	await _exercise(Vector2(0.5, 0.5), "half-size")
	print("PLAYER_BODY_FEEL: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

## [param base] is the authored visual scale. Inherited players shrink the rig
## to 0.5 for the smaller rooms, so reactions must scale relative to it.
func _exercise(base: Vector2, label: String) -> void:
	var player: ShopPlayer = load("res://src/gameplay/player/shop_player.tscn").instantiate()
	var visual: Node2D = player.get_node("Visual")
	visual.scale = base
	root.add_child(player)
	current_scene = player
	await frames(6)
	var shadow: Node2D = player.get_node("Shadow")
	var feel := visual as PlayerBodyFeel
	check(feel != null, "The visual node carries the body feel (%s)" % label)
	if feel == null:
		player.queue_free()
		return
	# Drive movement directly so the physics tick cannot decelerate underneath us.
	player.accepts_player_input = false
	var shadow_base := shadow.scale

	check(visual.scale.is_equal_approx(base) and is_zero_approx(visual.position.y), "A standing body keeps its authored size (%s)" % label)
	check(shadow.scale.is_equal_approx(shadow_base), "A standing body leaves the shadow alone (%s)" % label)

	player.move_direction(Vector2.RIGHT, 0.1)
	await frames(2)
	check(visual.scale.y > base.y and visual.scale.x < base.x, "Pushing off stretches the body (%s)" % label)
	check(shadow.scale.x < shadow_base.x, "Pushing off narrows the shadow (%s)" % label)
	await frames(60)
	check(visual.scale.is_equal_approx(base), "The push-off settles on the authored size (%s)" % label)
	check(shadow.scale.is_equal_approx(shadow_base), "The push-off returns the shadow to its base scale (%s)" % label)

	var offsets := {}
	for index in range(120):
		await process_frame
		offsets[visual.position.y] = true
	var whole_pixels := true
	for offset: float in offsets:
		whole_pixels = whole_pixels and (is_zero_approx(offset) or is_equal_approx(offset, -feel.step_bob))
	check(whole_pixels and offsets.size() > 1, "The walk bob alternates on whole pixels (%s)" % label)

	player.move_direction(Vector2.ZERO, 0.12)
	await frames(2)
	check(visual.scale.x > base.x and visual.scale.y < base.y, "Braking squashes the body (%s)" % label)
	check(visual.position.y >= 0.0, "Braking drops the body instead of lifting it (%s)" % label)
	await frames(60)
	check(visual.scale.is_equal_approx(base), "The brake settles on the authored size (%s)" % label)
	check(is_zero_approx(visual.position.y), "The brake puts the feet back on the ground (%s)" % label)

	player.move_direction(Vector2.LEFT, 0.1)
	await frames(2)
	check(visual.scale.y > base.y, "The second push-off still reacts after a brake (%s)" % label)
	player.claim_performance_control(self)
	await frames(3)
	check(visual.scale.is_equal_approx(base) and is_zero_approx(visual.position.y), "A story pose returns the body to its authored size without a brake (%s)" % label)
	check(shadow.scale.is_equal_approx(shadow_base), "A story pose returns the shadow to its base scale (%s)" % label)
	player.release_performance_control(self)

	player.movement_enabled = false
	player.move_direction(Vector2.RIGHT, 0.1)
	await frames(2)
	check(visual.scale.is_equal_approx(base) and is_zero_approx(visual.position.y), "A locked body keeps the authored size (%s)" % label)
	player.movement_enabled = true
	player.queue_free()
	await frames(2)
