class_name MilkTeaShop
extends Node2D

## Pixels inset from the background edges: left, top, right, bottom.
@export var boundary_insets := Vector4(95.0, 120.0, 82.0, 21.0)

func _ready() -> void:
	_fit_boundaries()

func get_world_bounds() -> Rect2:
	var background: Sprite2D = $Background
	return background.global_transform * background.get_rect()

func _fit_boundaries() -> void:
	var background: Sprite2D = $Background
	var bounds: Rect2 = background.transform * background.get_rect()
	_set_boundary($WallsAndFurniture/NorthWall, Rect2(bounds.position, Vector2(bounds.size.x, boundary_insets.y)))
	_set_boundary($WallsAndFurniture/WestWall, Rect2(bounds.position, Vector2(boundary_insets.x, bounds.size.y)))
	_set_boundary($WallsAndFurniture/EastWall, Rect2(Vector2(bounds.end.x - boundary_insets.z, bounds.position.y), Vector2(boundary_insets.z, bounds.size.y)))
	_set_boundary($WallsAndFurniture/SouthBoundary, Rect2(Vector2(bounds.position.x, bounds.end.y - boundary_insets.w), Vector2(bounds.size.x, boundary_insets.w)))

func _set_boundary(collider: CollisionShape2D, bounds: Rect2) -> void:
	# Each level instance owns its shapes, so resizing one never changes another.
	var shape := RectangleShape2D.new()
	shape.size = bounds.size
	collider.shape = shape
	collider.position = bounds.get_center()

func get_spawn_position() -> Vector2:
	return $Spawn.global_position

func get_interaction_points() -> Array[InteractionPoint]:
	var points: Array[InteractionPoint] = []
	for child in $InteractionPoints.get_children():
		if child is InteractionPoint:
			points.append(child)
	return points
