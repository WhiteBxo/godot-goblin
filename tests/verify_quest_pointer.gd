extends SceneTree
## Quest cursor: objective resolution (anchors, actors, regions, doors) and the
## screen-space placement that keeps a chip inside the safe rectangle.

var checks := 0
var failures: Array[String] = []

const POINTER_SCENE := "res://src/UI/hud/quest_pointer.tscn"
const POINT_SCENE := "res://src/gameplay/interaction/interaction_point.tscn"
const EXIT_SCRIPT := "res://src/core/navigation/scene_exit.gd"

class FakeMap extends Node2D:
	var data := {}
	var exits: Array = []
	var anchors := {}
	var shares := false

	func shares_map_world() -> bool:
		return shares

	func get_map_data(_known: Array[String]) -> Dictionary:
		return data

	func get_scene_exits() -> Array:
		return exits

	func get_objective_position(task_id: String, objective_id: String) -> Variant:
		return anchors.get(task_id + ":" + objective_id)

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	check_anchors()
	check_actor()
	check_region()
	check_doors()
	await check_pointer()
	await check_near_hidden()
	print("QUEST_POINTER: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _task(location := "", target := "", revealed := true) -> Dictionary:
	var objective := {"id": "go", "text": "去集市", "revealed": revealed, "location_id": location, "target_point": target}
	var delivery := {"target_object_id": target} if not target.is_empty() else {}
	return {"id": "day1.test", "type": "main", "revealed": revealed,
		"location_id": location, "delivery": delivery,
		"current_objective": objective, "objectives": [objective]}

## A chapter anchor outranks every other address.
func check_anchors() -> void:
	var map := FakeMap.new()
	root.add_child(map)
	map.shares = true
	map.anchors["day1.test:go"] = Vector2(480, 480)
	map.data = {"regions": [{"location_id": "settlement.shop", "name": "奶茶店", "position": Vector2(10, 10)}]}
	var result := TaskGuidance.resolve(_task("settlement.shop"), map, null, Callable(), Callable(), "")
	check(result.get("position") == Vector2(480, 480), "Authored anchor wins over the region entrance")
	check(str(result.get("source")) == "anchor", "Anchor result is labelled as an anchor")
	check(TaskGuidance.resolve(_task("settlement.shop", "", false), map, null, Callable(), Callable(), "").is_empty(), "Unrevealed objectives point at nothing")

## The order target is a live NPC, so the cursor follows it around the room.
func check_actor() -> void:
	var map := FakeMap.new()
	root.add_child(map)
	var point: Node = load(POINT_SCENE).instantiate()
	point.name = "OrderPoint"
	map.add_child(point)
	point.global_position = Vector2(300, 200)
	point.display_name = "胖哥布林"
	point.interaction_id = &"fat_goblin"
	var lookup := func(id: StringName) -> Variant: return point if id == &"fat_goblin" else null
	var result := TaskGuidance.resolve(_task("settlement.shop", "fat_goblin"), map, null, lookup, Callable(), "settlement.shop")
	check(result.get("position") == Vector2(300, 200), "A delivery target resolves to the NPC's point")
	check(result.get("node") == point, "A moving actor keeps a live node reference")
	check(str(result.get("label")) == "胖哥布林", "The cursor names the actor, not the area")

## Only a host that owns the exterior coordinates may use them.
func check_region() -> void:
	var map := FakeMap.new()
	root.add_child(map)
	map.shares = true
	map.data = {"regions": [
		{"location_id": "settlement.yard", "name": "集市 · 裂牙", "position": Vector2(500, 600)}]}
	var result := TaskGuidance.resolve(_task("settlement.yard"), map, null, Callable(), Callable(), "")
	check(result.get("position") == Vector2(500, 600), "Same-world host points at the region entrance")
	check(str(result.get("label")) == "集市", "Region labels drop the branch tail")
	check(TaskGuidance.resolve(_task("settlement.elder"), map, null, Callable(), Callable(), "").is_empty(),
		"An unknown area is hidden instead of aimed at a door")
	var loose := func() -> Array: return ["settlement.yard"]
	map.shares = true
	check(not TaskGuidance.resolve(_task("settlement.yard"), map, null, Callable(), loose, "").is_empty(),
		"An untyped known-location array still reaches a typed map query")
	map.shares = false
	check(TaskGuidance.resolve(_task("settlement.yard"), map, null, Callable(), Callable(), "").is_empty(),
		"An interior host never projects an exterior coordinate")

## Interior hosts send the player to the nearest usable door, and to nothing at
## all when the objective is in this very room.
func check_doors() -> void:
	var map := FakeMap.new()
	root.add_child(map)
	map.shares = false
	var near := _exit("走出奶茶店", Vector2(120, 0))
	map.add_child(near)
	var blocked := _exit("长老居所", Vector2(40, 0))
	var gated: Array[StringName] = [&"elder.allowed"]
	blocked.required_flags = gated
	map.add_child(blocked)
	map.exits = [blocked, near]
	var result := TaskGuidance.resolve(_task("settlement.yard"), map, null, Callable(), Callable(), "settlement.shop")
	check(str(result.get("source")) == "door", "A target in another place points at a door")
	check(result.get("position") == Vector2(120, 0), "A gated door is skipped for an open one")
	check(str(result.get("label")) == "走出奶茶店", "The door keeps its authored name")
	check(TaskGuidance.resolve(_task("settlement.shop"), map, null, Callable(), Callable(), "settlement.shop").is_empty(),
		"An objective inside this room is not pointed at a door")

func _exit(label: String, at: Vector2) -> Node:
	var node: Node = load(POINT_SCENE).instantiate()
	node.set_script(load(EXIT_SCRIPT))
	node.display_name = label
	node.position = at
	return node

func _pointer(player: Node2D, target: Vector2) -> QuestPointer:
	var pointer: QuestPointer = load(POINTER_SCENE).instantiate()
	root.add_child(pointer)
	pointer._player = player
	pointer._game = null
	pointer._enabled = true
	pointer._target = {"kind": 0, "position": target, "label": "集市", "source": "region", "node": null}
	pointer._name.text = "集市"
	return pointer

func _player() -> Node2D:
	var node := Node2D.new()
	node.name = "PlayerFixture"
	root.add_child(node)
	return node

## Off-screen targets become a chip pinned to the edge, facing the target.
func check_pointer() -> void:
	var player := _player()
	player.global_position = Vector2.ZERO
	var pointer := _pointer(player, Vector2(5000, 0))
	await process_frame
	pointer._process(0.016)
	var chip := pointer.get_node("Chip") as PanelContainer
	var limit := pointer.get_viewport_rect().size
	check(chip.visible, "An off-screen target shows the edge chip")
	check(not (pointer.get_node("Marker") as Control).visible, "Only one of the two shapes is shown")
	check(chip.position.x >= 21.0 and chip.position.x + chip.size.x <= limit.x - 21.0,
		"Chip stays inside the safe width")
	check(chip.position.y >= 21.0 and chip.position.y + chip.size.y <= limit.y - 21.0,
		"Chip stays inside the safe height")
	var arrow := pointer.get_node("Chip/Row/Arrow") as Control
	var wanted := ((pointer.get_viewport().get_canvas_transform() * Vector2(5000, 0)) - limit * 0.5).angle()
	check(absf(angle_difference(arrow.rotation, wanted)) < 0.15, "The arrow faces an off-screen target")
	pointer.queue_free()

	# A target above the screen turns the arrow up instead of reusing the old angle.
	var up_player := _player()
	up_player.global_position = Vector2.ZERO
	var up_target := Vector2(0, -5000)
	var up_pointer := _pointer(up_player, up_target)
	await process_frame
	for step in range(30):
		up_pointer._process(0.016)
	var up_arrow := up_pointer.get_node("Chip/Row/Arrow") as Control
	var up_wanted := ((up_pointer.get_viewport().get_canvas_transform() * up_target) - limit * 0.5).angle()
	check(absf(angle_difference(up_arrow.rotation, up_wanted)) < 0.05, "The arrow turns to face an upward target")
	check(absf(up_arrow.rotation) > 1.4, "An upward target reads as an upward arrow")
	up_pointer.queue_free()

## In-screen targets get a small diamond, and interaction range hides both.
func check_near_hidden() -> void:
	var player := _player()
	player.global_position = Vector2.ZERO
	var pointer := _pointer(player, Vector2(20, 0))
	await process_frame
	pointer._process(0.016)
	check(not pointer.is_pointing(), "A target within interaction range retires the cursor")
	pointer.queue_free()
