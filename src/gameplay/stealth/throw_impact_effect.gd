class_name ThrowImpactEffect
extends Node2D
## Short pixel burst at the landing point. It reports nothing to gameplay.

@export_range(0.05, 1.0, 0.01) var lifetime := 0.24
@export_range(1.0, 24.0, 1.0) var spread := 10.0

var kind: StringName = &"coin"
var _elapsed := 0.0

func configure(throw_kind: StringName) -> void:
	kind = throw_kind
	z_index = 26

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress := clampf(_elapsed / maxf(lifetime, 0.001), 0.0, 1.0)
	var color := _color()
	var fade := 1.0 - progress
	if _elapsed < 0.06:
		# One bright frame sells the hit before the ring expands.
		draw_rect(Rect2(Vector2(-1, -1), Vector2(2, 2)), Color(1.0, 0.98, 0.9, 0.95))
	var radius := 2.0 + spread * progress
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 20, Color(color, 0.75 * fade), 1.0, false)
	for direction: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var point := (direction * (3.0 + spread * 0.6 * progress)).round()
		draw_rect(Rect2(point, Vector2.ONE), Color(color, 0.85 * fade))

func _color() -> Color:
	if kind == &"drink":
		return Color(0.62, 0.85, 0.72)
	if kind == &"torch":
		return Color(1.0, 0.62, 0.28)
	return Color(1.0, 0.84, 0.38)
