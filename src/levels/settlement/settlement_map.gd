class_name SettlementMap
extends Node2D
## Saved TileMapLayer cells and scene instances are the editable map authority.

@export var world_size := Vector2(8192, 9216)

func get_world_bounds() -> Rect2:
	return global_transform * Rect2(Vector2.ZERO, world_size)

func get_camera_bounds() -> Rect2:
	return get_world_bounds()

func get_spawn_position() -> Vector2:
	return $Spawn.global_position

func get_interaction_points() -> Array[InteractionPoint]:
	var points: Array[InteractionPoint] = []
	for child in $InteractionPoints.get_children():
		if child is InteractionPoint:
			points.append(child)
	return points

func get_gather_points() -> Array[GatherPoint]:
	var points: Array[GatherPoint] = []
	var container := get_node_or_null("GatherPoints")
	if container == null:
		return points
	for child in container.get_children():
		if child is GatherPoint:
			points.append(child)
	return points

func get_zone_at(world_position: Vector2) -> String:
	for zone: Node2D in $Districts.get_children():
		var area: Rect2 = zone.get_meta("footprint", Rect2(110, 80, 1320, 840))
		if area.has_point(zone.to_local(world_position)):
			return str(zone.get_meta("display_name", zone.name))
	return "洞窟街道"

func get_story_anchor(id: StringName) -> Marker2D:
	return $StoryAnchors.get_node_or_null(NodePath(id)) as Marker2D
