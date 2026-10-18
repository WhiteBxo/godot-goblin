extends StaticBody2D
## An authored barricade over the inherited floor. It never edits TileMap cells.

@export var size := Vector2(48, 48)

func get_blocked_bounds() -> Rect2:
	return Rect2(global_position - size * 0.5, size)

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	add_child(shape)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-size * 0.5, size), Color(0.28, 0.20, 0.13))
	for x in range(0, int(size.x), 24):
		draw_line(Vector2(x - size.x * 0.5, -size.y * 0.5), Vector2(x - size.x * 0.5, size.y * 0.5), Color(0.48, 0.36, 0.21), 4)
