class_name Day1ThrowProjectile
extends Node2D
## Swept world-layer collision, advanced by the service in physics time.

var kind: StringName
var destination := Vector2.ZERO
var speed := 520.0
var finished := false

func advance(delta: float, space: PhysicsDirectSpaceState2D) -> Dictionary:
	if finished:
		return {}
	var next := global_position.move_toward(destination, speed * delta)
	var query := PhysicsRayQueryParameters2D.create(global_position, next, 1)
	query.collide_with_areas = true
	query.hit_from_inside = true
	var hit := space.intersect_ray(query)
	global_position = hit.get("position", next)
	if hit.is_empty() and not next.is_equal_approx(destination):
		return {}
	finished = true
	return {"kind": kind, "position": global_position, "collider": hit.get("collider")}

func _draw() -> void:
	if kind == &"coin":
		draw_circle(Vector2.ZERO, 5.0, Color.GOLD)
	else:
		draw_line(Vector2(-8, 6), Vector2(5, -5), Color.SADDLE_BROWN, 5.0)
		draw_circle(Vector2(5, -5), 6.0, Color.ORANGE_RED)
