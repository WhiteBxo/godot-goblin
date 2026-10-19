class_name SettlementMapCanvas
extends Control
## Exterior overview and local floor map, using native world coordinates.

var map_data: Dictionary = {}
var player_position := Vector2.ZERO
var target: Dictionary = {}
@export var compact := false
const OVERVIEW: Texture2D = preload("res://assets/map/cartography/cavern_floor_overview.png")

func _art_rect() -> Rect2:
	var extent := OVERVIEW.get_size()
	var scale_factor := minf((size.x - 8.0) / extent.x, (size.y - 8.0) / extent.y)
	return Rect2((size - extent * scale_factor) * 0.5, extent * scale_factor)

## The supplied image is the full 2400 x 2640 exterior at half resolution.
func _art_point(world: Vector2) -> Vector2:
	var bounds: Rect2 = map_data.get("bounds", Rect2(0, 0, 2400, 2640))
	var normalized := (world - bounds.position) / bounds.size
	var rect := _art_rect()
	return rect.position + normalized.clamp(Vector2.ZERO, Vector2.ONE) * rect.size

func _draw_illustration() -> void:
	draw_texture_rect(OVERVIEW, _art_rect(), false)
	var font := get_theme_font("font", "Label")
	var font_size := get_theme_font_size("font_size", "Label")
	var occupied: Array[Rect2] = []
	for region: Dictionary in map_data.regions:
		var point := _art_point((region.bounds as Rect2).get_center())
		var label: String = String(region.name).get_slice(" · ", 0).replace("东侧居民区", "东居民区")
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var origin := Vector2.ZERO
		var box := Rect2()
		for offset: Vector2 in [Vector2(0, 22), Vector2(24, -10), Vector2(-24, -10), Vector2(48, 22), Vector2(-48, 22), Vector2(0, -22)]:
			origin = (point + Vector2(-width * 0.5, 0) + offset).clamp(Vector2(6, font_size), size - Vector2(width + 6, 6))
			box = Rect2(origin + Vector2(-3, -font_size), Vector2(width + 6, font_size + 4))
			if not occupied.any(func(other: Rect2) -> bool: return other.grow(2).intersects(box)):
				break
		occupied.append(box)
		draw_line(point, box.get_center(), get_theme_color("font_color", "Muted"), 1.0)
		draw_style_box(get_theme_stylebox("panel", "InsetPanel"), box)
		draw_string(font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, get_theme_color("font_color", "Label"))
	if target.has("position"):
		var point := _art_point(target.position)
		draw_arc(point, 8.0, 0, TAU, 24, get_theme_color("font_color", "Warning"), 2.0)
	var player := _art_point(player_position)
	draw_circle(player, 3.0, get_theme_color("font_color", "Success"))
	draw_arc(player, 5.0, 0, TAU, 24, get_theme_color("font_color", "Label"), 1.0)

func _draw_local_map() -> void:
	var floor_color := get_theme_color("font_color", "Muted")
	for area: Rect2 in map_data.get("floor_cells", []):
		var rect := Rect2(world_to_map(area.position), world_to_map(area.end) - world_to_map(area.position))
		draw_rect(rect, floor_color)
	var edge := Rect2(Vector2(4, 4), size - Vector2(8, 8))
	if target.has("position"):
		var point := world_to_map(target.position).clamp(edge.position, edge.end)
		draw_colored_polygon(PackedVector2Array([point + Vector2(0, -3), point + Vector2(3, 0), point + Vector2(0, 3), point + Vector2(-3, 0)]), get_theme_color("font_color", "Warning"))
	var player := world_to_map(player_position)
	draw_circle(player, 2.0, get_theme_color("font_color", "Success"))
	draw_arc(player, 3.5, 0, TAU, 16, get_theme_color("font_color", "Label"), 1.0)
	var font := get_theme_font("font", "Label")
	draw_string(font, Vector2(size.x - 14, 12), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size", "Label"), get_theme_color("font_color", "Label"))

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
	var available := size - (Vector2(8, 8) if compact else Vector2(24, 24))
	var ratio := maxf(0.0, minf(available.x / bounds.size.x, available.y / bounds.size.y))
	return (size - bounds.size * ratio) * 0.5 + (point - bounds.position) * ratio

func _draw() -> void:
	if map_data.is_empty():
		return
	if compact and map_data.has("floor_cells"):
		_draw_local_map()
		return
	if map_data.get("illustrated", false) and not compact:
		_draw_illustration()
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
		if not compact and rect.size.y >= font_size:
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
