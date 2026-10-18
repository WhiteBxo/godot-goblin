class_name Day1ThrowProjectile
extends Node2D
## Swept world-layer collision, advanced by the service in physics time.

var kind: StringName
var destination := Vector2.ZERO
var speed := 520.0
var finished := false
var payload: Dictionary = {}

func advance(delta: float, space: PhysicsDirectSpaceState2D) -> Dictionary:
	if finished:
		return {}
	var next := global_position.move_toward(destination, speed * delta)
	var query := PhysicsRayQueryParameters2D.create(global_position, next, 1)
	query.collide_with_areas = true
	query.hit_from_inside = true
	var phantom: Dictionary = payload.get("modifiers", {}).get("phantom", {})
	var hit := {} if phantom.get("ignore_walls", false) else space.intersect_ray(query)
	global_position = hit.get("position", next)
	if hit.is_empty() and not next.is_equal_approx(destination):
		return {}
	finished = true
	# Keep the impact on the near side of a solid wall for subsequent area rays.
	var origin: Vector2 = global_position + hit.get("normal", Vector2.ZERO) * 0.5
	return {"kind": kind, "position": origin, "collider": hit.get("collider"), "payload": payload}

func _draw() -> void:
	if kind == &"coin":
		draw_circle(Vector2.ZERO, 5.0, Color.GOLD)
	elif kind == &"drink":
		draw_rect(Rect2(-7, -10, 14, 20), Color.MEDIUM_PURPLE)
		draw_line(Vector2(2, -10), Vector2(5, -17), Color.WHITE, 2.0)
	else:
		draw_line(Vector2(-8, 6), Vector2(5, -5), Color.SADDLE_BROWN, 5.0)
		draw_circle(Vector2(5, -5), 6.0, Color.ORANGE_RED)
