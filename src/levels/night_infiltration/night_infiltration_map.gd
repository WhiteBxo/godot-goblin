class_name NightInfiltrationMap
extends Node2D
## Native reference coordinates; saved floor cells and placed modules are authoritative.

signal travel_requested(destination: StringName, arrival: StringName)
signal elder_door_changed(open: bool)

@export var world_size := Vector2(1678, 937)
@export var elder_door_open := false:
	set(value):
		elder_door_open = value
		if is_node_ready():
			_refresh_door()

func _ready() -> void:
	_refresh_door()

func get_world_bounds() -> Rect2:
	return global_transform * Rect2(Vector2.ZERO, world_size)

func get_camera_bounds() -> Rect2:
	return get_world_bounds()

func get_spawn_position() -> Vector2:
	return $StoryAnchors/ArrivalFromPublicStreet.global_position

func get_story_anchor(id: StringName) -> Marker2D:
	return $StoryAnchors.get_node_or_null(NodePath(id)) as Marker2D

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

func open_elder_door() -> void:
	if elder_door_open:
		return
	elder_door_open = true
	elder_door_changed.emit(true)

func request_public_street() -> void:
	travel_requested.emit(&"public_street", &"from_elder_district")

func _refresh_door() -> void:
	$Objects/ElderDoorClosed.visible = not elder_door_open
	$Objects/ElderDoorOpen.visible = elder_door_open
	$Architecture/ElderDoor/Shape.set_deferred("disabled", elder_door_open)
