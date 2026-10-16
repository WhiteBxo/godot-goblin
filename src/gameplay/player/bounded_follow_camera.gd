class_name BoundedFollowCamera
extends Camera2D

@export_range(0.1, 4.0, 0.05) var preferred_zoom := 0.5

var _world_bounds := Rect2()
var _follow_offset := Vector2.ZERO
var _settled := false

@onready var _follow_target := get_parent() as Node2D

func _ready() -> void:
	_follow_offset = position
	top_level = true
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	process_physics_priority = 1
	get_viewport().size_changed.connect(_update_zoom)
	zoom = Vector2.ONE * preferred_zoom

func _physics_process(_delta: float) -> void:
	_update_follow_target()
	# End the smoothing tail exactly; pixel snapping can expose floating-point drift.
	if not _settled and get_screen_center_position().distance_squared_to(global_position) < 0.0001:
		reset_smoothing()
		_settled = true

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
	_update_follow_target()
	force_update_scroll()

func _update_follow_target() -> void:
	if not _world_bounds.has_area():
		return
	var half_view := get_viewport_rect().size / zoom * 0.5
	var minimum := Vector2(limit_left, limit_top) + half_view
	var maximum := Vector2(limit_right, limit_bottom) - half_view
	# Clamp before smoothing so pushing a wall cannot keep pulling the camera outside.
	var target := (_follow_target.global_position + _follow_offset).clamp(minimum, maximum.max(minimum))
	if global_position.distance_squared_to(target) > 0.000001:
		global_position = target
		_settled = false
