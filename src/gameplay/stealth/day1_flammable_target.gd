class_name Day1FlammableTarget
extends Area2D
## An explicitly approved hit volume attached to existing scenery. No fire simulation.

@export var target_id: StringName
@export_multiline var design_reference: String
@export_range(0.05, 30.0) var confusion_seconds := 5.0
@export_range(1.0, 1200.0) var confusion_radius := 420.0
var remaining := 0.0

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	monitoring = false

func is_confirmed() -> bool:
	if target_id == &"" or design_reference.strip_edges().is_empty() or confusion_seconds <= 0.0 or confusion_radius <= 0.0:
		return false
	for owner_id: int in get_shape_owners():
		if not is_shape_owner_disabled(owner_id) and shape_owner_get_shape_count(owner_id) > 0:
			return true
	return false

func ignite() -> bool:
	if not is_confirmed() or remaining > 0.0 or not is_visible_in_tree():
		return false
	remaining = confusion_seconds
	queue_redraw()
	return true

func advance(delta: float) -> void:
	remaining = maxf(0.0, remaining - delta)
	queue_redraw()

func reset_target() -> void:
	remaining = 0.0
	queue_redraw()

func _draw() -> void:
	if remaining > 0.0:
		# A temporary impact cue; the existing object remains the visual authority.
		draw_circle(Vector2(0, -12), 18.0, Color(1.0, 0.3, 0.05, 0.65))
		draw_circle(Vector2(0, -18), 9.0, Color(1.0, 0.8, 0.2, 0.8))
