class_name BoundedFollowCamera
extends Camera2D

@export_range(0.1, 4.0, 0.05) var preferred_zoom := 0.75

var _world_bounds := Rect2()

func _ready() -> void:
	get_viewport().size_changed.connect(_update_zoom)
	zoom = Vector2.ONE * preferred_zoom

func configure(world_bounds: Rect2) -> void:
	_world_bounds = world_bounds
	limit_left = ceili(world_bounds.position.x)
	limit_top = ceili(world_bounds.position.y)
	limit_right = floori(world_bounds.end.x)
	limit_bottom = floori(world_bounds.end.y)
	_update_zoom()
	make_current()
	reset_smoothing()
	force_update_scroll()

func _update_zoom() -> void:
	if not _world_bounds.has_area():
		return
	# A wide or tall window must never show more world than the background contains.
	var viewport_size := get_viewport_rect().size
	var minimum_zoom := maxf(viewport_size.x / _world_bounds.size.x, viewport_size.y / _world_bounds.size.y)
	zoom = Vector2.ONE * maxf(preferred_zoom, minimum_zoom)
	force_update_scroll()
