class_name TaskGuidance
extends RefCounted
## Read-only: the current objective projected onto a point the HUD can draw.
##
## This never writes progress and never guesses a location. It answers one
## question — "where should the cursor point right now?" — in this order:
##   1. an authored anchor for this exact objective (chapter scenes provide one),
##   2. the thing the order is handed to (an NPC interaction point),
##   3. the area entrance, but only when the map and the player share a world,
##   4. a door, when the target simply is not in this room.
## A target that falls through all four is hidden rather than guessed: aimless
## arrows cost more trust than a missing one.

enum Kind { POINT, DOOR }

static func resolve(task: Dictionary, level: Object, player: Node2D,
		point_lookup: Callable, known: Callable, current_location: String) -> Dictionary:
	if task.is_empty() or not bool(task.get("revealed", false)):
		return {}
	var objective: Dictionary = task.get("current_objective", {})
	if objective.is_empty() or not bool(objective.get("revealed", false)):
		return {}
	if not is_instance_valid(level):
		return {}
	# Authored anchors are the most specific answer a chapter scene can give.
	var anchor := _anchor(level, task, objective)
	if not anchor.is_empty():
		return anchor
	var exact := _exact_point(task, objective, point_lookup)
	if not exact.is_empty():
		return exact
	var location: String = str(objective.get("location_id", ""))
	if location.is_empty():
		location = str(task.get("location_id", ""))
	if location.is_empty():
		return {}
	# Same world: the area entrance is a straight walk, so point at it.
	if shares_world_map(level):
		for region: Dictionary in _regions(level, known):
			if str(region.get("location_id", "")) == location:
				return _point(region.get("position", Vector2.ZERO), _short_name(str(region.get("name", ""))), "region")
		return {}
	# Interior hosts: an exterior coordinate would land on the wrong floor.
	if location == current_location:
		return {}
	return _nearest_door(level, player)

## True only when map positions and the player's own position share one origin.
## Hosts answer for themselves so a new room scene never teaches this file a type.
static func shares_world_map(level: Object) -> bool:
	if level.has_method("shares_map_world"):
		return bool(level.call("shares_map_world"))
	return false

static func _anchor(level: Object, task: Dictionary, objective: Dictionary) -> Dictionary:
	if not level.has_method("get_objective_position"):
		return {}
	var point: Variant = level.call("get_objective_position", str(task.get("id", "")), str(objective.get("id", "")))
	if point is Vector2:
		return _point(point, "", "anchor")
	return {}

## The delivery target outranks a hand-authored point: it is a live NPC.
static func _exact_point(task: Dictionary, objective: Dictionary, lookup: Callable) -> Dictionary:
	if not lookup.is_valid():
		return {}
	var ids: Array[String] = []
	var delivery: Dictionary = task.get("delivery", {})
	if delivery.has("target_object_id"):
		ids.append(str(delivery.target_object_id))
	if objective.has("target_point"):
		ids.append(str(objective.target_point))
	for id: String in ids:
		if id.is_empty():
			continue
		var point: Variant = lookup.call(StringName(id))
		if point is InteractionPoint and is_instance_valid(point) and point.is_inside_tree():
			return _point(point.global_position, point.display_name, "actor", Kind.POINT, point)
	return {}

static func _regions(level: Object, known: Callable) -> Array:
	if not level.has_method("get_map_data"):
		return []
	var ids: Array = known.call() if known.is_valid() else []
	var data: Variant = level.call("get_map_data", ids)
	return data.get("regions", []) if data is Dictionary else []

static func _nearest_door(level: Object, player: Node2D) -> Dictionary:
	if not level.has_method("get_scene_exits"):
		return {}
	var host := level as Node
	var state := host.get_node_or_null("/root/GameState") if host != null else null
	var best: SceneExit = null
	var best_distance := INF
	for exit: Variant in level.call("get_scene_exits"):
		if not exit is SceneExit or not is_instance_valid(exit):
			continue
		if not exit.are_conditions_met(state):
			continue
		var distance := 0.0
		if is_instance_valid(player):
			distance = exit.global_position.distance_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = exit
	if best == null:
		return {}
	return _point(best.global_position, best.display_name, "door", Kind.DOOR)

static func _point(position: Vector2, label: String, source: String, kind := Kind.POINT, node: Node2D = null) -> Dictionary:
	return {"kind": kind, "position": position, "label": label, "source": source, "node": node}

## Map labels carry a " · 分店名" tail the cursor cannot afford.
static func _short_name(name: String) -> String:
	var head := name.get_slice(" · ", 0)
	return head if not head.is_empty() else name
