class_name SettlementMapCanvas
extends Control
## Schematic of known exterior footprints, using saved scene geometry.

var map_data: Dictionary = {}
var player_position := Vector2.ZERO
var target: Dictionary = {}

func _ready() -> void:
	resized.connect(queue_redraw)

func world_to_map(point: Vector2) -> Vector2:
	var bounds: Rect2 = map_data.get("bounds", Rect2())
	if not bounds.has_area():
		return Vector2.ZERO
	var available := size - Vector2(32, 32)
	var ratio := maxf(0.0, minf(available.x / bounds.size.x, available.y / bounds.size.y))
	return (size - bounds.size * ratio) * 0.5 + (point - bounds.position) * ratio

func _draw() -> void:
	if map_data.is_empty():
		return
	var ink := get_theme_color("font_color", "Label")
	var muted := get_theme_color("font_color", "Muted")
	var success := get_theme_color("font_color", "Success")
	var warning := get_theme_color("font_color", "Warning")
	var font := get_theme_font("font", "Label")
	var font_size := get_theme_font_size("font_size", "Label")
	var bounds: Rect2 = map_data.bounds
	draw_rect(Rect2(world_to_map(bounds.position), world_to_map(bounds.end) - world_to_map(bounds.position)), muted, false)
	for index in range(map_data.regions.size()):
		var region: Dictionary = map_data.regions[index]
		var area: Rect2 = region.bounds
		var rect := Rect2(world_to_map(area.position), world_to_map(area.end) - world_to_map(area.position))
		draw_rect(rect, muted, false)
		var entrance := world_to_map(region.position)
		draw_circle(entrance, 2.0, ink)
		draw_string(font, rect.position + Vector2(2, font_size + 2), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
	if not target.is_empty():
		var pos := world_to_map(target.position)
		draw_arc(pos, 7.0, 0, TAU, 24, warning, 2.0)
		draw_line(pos + Vector2(-10, 0), pos + Vector2(10, 0), warning)
		draw_line(pos + Vector2(0, -10), pos + Vector2(0, 10), warning)
	draw_circle(world_to_map(player_position), 4.0, success)
