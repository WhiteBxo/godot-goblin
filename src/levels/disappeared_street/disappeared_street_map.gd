class_name DisappearedStreetMap
extends Node2D
## The saved TileMapLayer and placed module scenes are the editor authority.

@export var world_size := Vector2(1536, 1280)

func get_world_bounds() -> Rect2:
	return global_transform * Rect2(Vector2.ZERO, world_size)

func get_camera_bounds() -> Rect2:
	return get_world_bounds()

func get_spawn_position() -> Vector2:
	return $Spawn.global_position

func get_interaction_points() -> Array[InteractionPoint]:
	var points: Array[InteractionPoint] = []
	for child: Node in $InteractionPoints.get_children():
		if child is InteractionPoint:
			points.append(child)
	return points

func has_floor_at(world_position: Vector2) -> bool:
	var floor_layer: TileMapLayer = $Ground
	return floor_layer.get_cell_source_id(floor_layer.local_to_map(floor_layer.to_local(world_position))) >= 0

func can_stand_at(world_position: Vector2, half_size: Vector2) -> bool:
	for corner: Vector2 in [Vector2(-half_size.x, -half_size.y), Vector2(half_size.x, -half_size.y), Vector2(-half_size.x, half_size.y), half_size]:
		if not has_floor_at(world_position + corner):
			return false
	return true
