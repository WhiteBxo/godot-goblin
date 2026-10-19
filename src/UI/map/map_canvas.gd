class_name SettlementMapCanvas
extends Control
## Schematic of known exterior footprints, using saved scene geometry.

var map_data: Dictionary = {}
var player_position := Vector2.ZERO
var target: Dictionary = {}

func _ready() -> void:
	resized.connect(queue_redraw)

func _view_rect() -> Rect2:
	var view: Rect2 = map_data.get("view", map_data.get("bounds", Rect2()))
	if not view.has_area():
		view = map_data.get("bounds", Rect2())
	return view

func world_to_map(point: Vector2) -> Vector2:
	var bounds := _view_rect()
	if not bounds.has_area():
		return Vector2.ZERO
	var available := size - Vector2(24, 24)
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
	var district := get_theme_stylebox("panel", "InsetPanel")
	# Paths first so district blocks read as places on a route, not islands.
	for link: Dictionary in map_data.get("links", []):
		draw_line(world_to_map(link.from), world_to_map(link.to), muted, 1.0)
	for region: Dictionary in map_data.regions:
		var area: Rect2 = region.bounds
		var rect := Rect2(world_to_map(area.position), world_to_map(area.end) - world_to_map(area.position))
		if rect.size.x < 2.0 or rect.size.y < 2.0:
			continue
		draw_style_box(district, rect)
		draw_rect(rect, muted, false)
		var label := "%d %s" % [int(region.get("ordinal", 0)), str(region.name)]
		if font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > rect.size.x - 6.0:
			label = str(region.name)
		if font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > rect.size.x - 6.0:
			label = str(int(region.get("ordinal", 0)))
		if rect.size.y >= font_size:
			draw_string(font, rect.position + Vector2(4, font_size + 3), label,
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 6.0, font_size, ink)
		draw_circle(world_to_map(region.position), 1.5, ink)
	if not target.is_empty():
		var pos := world_to_map(target.position)
		draw_colored_polygon(PackedVector2Array([
			pos + Vector2(0, -7), pos + Vector2(7, 0), pos + Vector2(0, 7), pos + Vector2(-7, 0)]), warning)
		draw_arc(pos, 11.0, 0, TAU, 24, warning, 1.0)
	var player := world_to_map(player_position)
	draw_circle(player, 3.0, success)
	draw_arc(player, 7.0, 0, TAU, 24, success, 1.0)
	# A north arrow keeps the schematic oriented without another legend line.
	var north := Vector2(size.x - 18, 22)
	draw_colored_polygon(PackedVector2Array([north, north + Vector2(-4, 9), north + Vector2(4, 9)]), ink)
	draw_string(font, north + Vector2(-5, -4), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
