extends SceneTree
## Ambient walking must actually move townsfolk, keep them on ground the map
## accepts, and never reuse the player-facing market gate that talks to the HUD.

const CHAPTER := "res://src/levels/rpg_maker/chapter_cave.tscn"
const WANDER := "res://src/gameplay/characters/ambient_wander.gd"
const WALKER := "res://src/gameplay/characters/prayer_man.tscn"
const FOOT := Vector2(5.0, 4.0)
## Mounted routes: an authored radius per character, all with multi-frame walks.
const MOUNTED := {
	"Characters/Drunk/Wander": 20.0,
	"Characters/PrayerMan/Wander": 16.0,
	"Characters/PrayerWoman/Wander": 16.0,
	"Characters/WarehouseGuard1/Wander": 20.0,
	"Characters/WarehouseGuard2/Wander": 20.0,
	"Characters/MarketBoy/Wander": 28.0,
	"Characters/VillageChild/Wander": 30.0,
}

var failures: Array[String] = []
var checked := 0

class StubFloor extends Node2D:
	var walkable := Rect2(-30.0, -30.0, 60.0, 60.0)
	func is_walkable_at(world_position: Vector2, half_size: Vector2) -> bool:
		return walkable.encloses(Rect2(world_position - half_size, half_size * 2.0))
	func can_stand_at(world_position: Vector2, half_size: Vector2) -> bool:
		return is_walkable_at(world_position, half_size)

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checked += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	_test_chapter_bindings()
	_test_market_gate_is_silent_for_npc_probes()
	await _test_walk_cycle()
	await _test_chapter_townsfolk_walk()
	print("ambient wander checks=%d failures=%d" % [checked, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_chapter_bindings() -> void:
	var packed := load(CHAPTER) as PackedScene
	check(packed != null, "chapter cave scene loads")
	if packed == null:
		return
	var scene := packed.instantiate()
	for path: String in MOUNTED:
		var wander := scene.get_node_or_null(path)
		check(wander != null, "wander mounted at " + path)
		if wander == null:
			continue
		check(is_equal_approx(float(wander.get("radius")), MOUNTED[path]), "authored radius at " + path)
		var actor := wander.get_parent() as SettlementCharacter
		check(actor != null, "wander parent is a settlement character: " + path)
		if actor == null:
			continue
		var sprite := actor.get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
		check(sprite != null, "character keeps its animated sprite: " + path)
		if sprite == null:
			continue
		var frames := sprite.sprite_frames
		var longest := 0
		for direction: StringName in PlayerController.DIRECTION_NAMES:
			var animation := StringName("run_%s" % direction)
			if frames != null and frames.has_animation(animation):
				longest = maxi(longest, frames.get_frame_count(animation))
		check(longest >= 2, "multi-frame walk animation at " + path)
	scene.free()

## The market gate emits a HUD warning, so an NPC probing a step must use the
## silent query while the player keeps the reporting one.
func _test_market_gate_is_silent_for_npc_probes() -> void:
	var map := RpgChapterMap.new()
	map.market_only = true
	map.first_visit_bounds = Rect2(0.0, 0.0, 32.0, 32.0)
	var reports := [0]
	map.market_boundary_reached.connect(func() -> void: reports[0] += 1)
	var outside := Vector2(4096.0, 4096.0)
	check(not map.is_walkable_at(outside, FOOT), "outside market is not walkable")
	check(reports[0] == 0, "npc probe must not report the market boundary")
	check(not map.can_stand_at(outside, FOOT), "player query still rejects outside market")
	check(reports[0] == 1, "player query still reports the market boundary")
	map.free()

func _test_walk_cycle() -> void:
	var ground := StubFloor.new()
	root.add_child(ground)
	var wall := StaticBody2D.new()
	var wall_shape := CollisionShape2D.new()
	var wall_box := RectangleShape2D.new()
	wall_box.size = Vector2(20.0, 20.0)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	ground.add_child(wall)
	wall.global_position = Vector2(24.0, 0.0)
	var blocked := Rect2(Vector2(14.0, -10.0), Vector2(20.0, 20.0))
	var actor: SettlementCharacter = load(WALKER).instantiate()
	ground.add_child(actor)
	actor.global_position = Vector2.ZERO
	var route := Node.new()
	route.set_script(load(WANDER))
	route.set("radius", 40.0)
	route.set("speed", 40.0)
	route.set("minimum_pause", 0.1)
	route.set("maximum_pause", 0.2)
	actor.add_child(route)
	var start := actor.global_position
	var moved := false
	var walked := false
	var escaped := false
	var crossed_wall := false
	for index in 720:
		await physics_frame
		if actor.global_position.distance_to(start) > 4.0:
			moved = true
		if String(actor.animated_sprite.animation).begins_with("run_"):
			walked = true
		var footprint := Rect2(actor.global_position - FOOT, FOOT * 2.0)
		if not ground.walkable.encloses(footprint):
			escaped = true
		if blocked.intersects(footprint):
			crossed_wall = true
	check(moved, "ambient wander moves the body")
	check(walked, "walk animation plays while moving")
	check(not escaped, "wander stays inside walkable ground")
	check(not crossed_wall, "wander never plans a step into a solid body")
	ground.free()

## The authored scene is the real contract: every mounted townsfolk must leave
## its post and reach its walk cycle within a few seconds of play.
func _test_chapter_townsfolk_walk() -> void:
	var packed := load(CHAPTER) as PackedScene
	if packed == null:
		check(false, "chapter cave scene loads for the walking pass")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var start: Dictionary[StringName, Vector2] = {}
	var walked: Dictionary[StringName, bool] = {}
	for path: String in MOUNTED:
		var actor := scene.get_node(path).get_parent() as SettlementCharacter
		if actor == null:
			continue
		start[actor.actor_id] = actor.global_position
		walked[actor.actor_id] = false
	for index in 480:
		await physics_frame
		for path: String in MOUNTED:
			var actor := scene.get_node(path).get_parent() as SettlementCharacter
			if actor == null:
				continue
			var animation := String(actor.animated_sprite.animation)
			if animation.begins_with("run_") or animation.begins_with("walk_"):
				walked[actor.actor_id] = true
	for path: String in MOUNTED:
		var actor := scene.get_node(path).get_parent() as SettlementCharacter
		if actor == null:
			continue
		var travelled := actor.global_position.distance_to(start[actor.actor_id])
		check(travelled > 2.0, "%s leaves its post (%.1f px)" % [path, travelled])
		check(walked[actor.actor_id], "%s reaches its walk cycle" % path)
	scene.free()
	await process_frame
