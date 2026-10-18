class_name Day1DestructibleTarget
extends Area2D
## Explicitly bound meltable scenery. Never infers material from a node's name.

signal melted

@export var target_id: StringName
@export_multiline var design_reference: String
@export_range(0.1, 100.0) var durability := 2.0
@export var blocker: CollisionObject2D
@export var visual: CanvasItem
var damage := 0.0
var destroyed := false
var _blocker_layer := 0
var _visual_visible := true

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	monitoring = false
	if is_instance_valid(blocker):
		_blocker_layer = blocker.collision_layer
	if is_instance_valid(visual):
		_visual_visible = visual.visible

func is_confirmed() -> bool:
	if target_id == &"" or design_reference.strip_edges().is_empty() or durability <= 0.0 or not is_instance_valid(blocker):
		return false
	for owner_id: int in get_shape_owners():
		if not is_shape_owner_disabled(owner_id) and shape_owner_get_shape_count(owner_id) > 0:
			return true
	return false

func corrode(amount: float) -> bool:
	if not is_confirmed() or destroyed or not is_visible_in_tree() or amount <= 0.0:
		return false
	damage = minf(durability, damage + amount)
	if damage >= durability:
		destroyed = true
		blocker.collision_layer = 0
		collision_layer = 0
		if is_instance_valid(visual):
			visual.hide()
		melted.emit()
	queue_redraw()
	return true

func reset_target() -> void:
	damage = 0.0
	destroyed = false
	collision_layer = 1
	if is_instance_valid(blocker):
		blocker.collision_layer = _blocker_layer
	if is_instance_valid(visual):
		visual.visible = _visual_visible
	queue_redraw()

func _draw() -> void:
	if damage > 0.0 and not destroyed:
		draw_circle(Vector2.ZERO, 12.0, Color.YELLOW_GREEN)
