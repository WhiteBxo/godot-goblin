class_name MilkTeaShop
extends Node2D

## Exclude the painted outer frame from the camera without changing furniture coordinates.
@export var camera_insets := Vector4(112.0, 54.0, 112.0, 10.0)

func get_world_bounds() -> Rect2:
	var background: Sprite2D = $Background
	return background.global_transform * background.get_rect()

func get_camera_bounds() -> Rect2:
	var background: Sprite2D = $Background
	var bounds: Rect2 = background.transform * background.get_rect()
	bounds.position += Vector2(camera_insets.x, camera_insets.y)
	bounds.size -= Vector2(camera_insets.x + camera_insets.z, camera_insets.y + camera_insets.w)
	return global_transform * bounds

func get_spawn_position() -> Vector2:
	return $Spawn.global_position

func get_scene_entrance(id: StringName) -> SceneEntrance:
	for child in $SceneEntrances.get_children():
		if child is SceneEntrance and child.entrance_id == id:
			return child
	return null

func get_scene_exits() -> Array[SceneExit]:
	var exits: Array[SceneExit] = []
	for child in $SceneExits.get_children():
		if child is SceneExit:
			exits.append(child)
	return exits

func get_interaction_points() -> Array[InteractionPoint]:
	var points: Array[InteractionPoint] = []
	for child in $InteractionPoints.get_children():
		if child is InteractionPoint:
			points.append(child)
	return points
