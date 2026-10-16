class_name RoomReveal
extends Area2D
## Reveals only this room's Occlusion child. Does not control movement or cameras.

signal occupancy_changed(occupied: bool)

@export var observer_group: StringName = &"player"
@export_range(0.01, 2.0, 0.01, "suffix:s") var fade_duration := 0.25

var _occupied := false
var _initialized := false
var _fade: Tween

@onready var _occlusion: Node2D = $Occlusion

func _ready() -> void:
	# Physics overlap data is not available in _ready, and MainGame places the
	# player after its children's _ready. Start transparent to avoid a roof flash
	# when spawning indoors, then resolve the initial state after physics sync.
	_occlusion.modulate.a = 0.0
	body_entered.connect(_on_body_changed)
	body_exited.connect(_on_body_changed)
	_initialize_occupancy()

func _initialize_occupancy() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	# physics_frame is emitted before the tick. Read after that tick's overlap
	# updates, including rooms instantiated by another coroutine mid-frame.
	_finish_initialization.call_deferred()

func _finish_initialization() -> void:
	_initialized = true
	_occupied = _has_observer()
	# A freshly instanced concave Area can publish its first overlap one tick
	# later than the player's transform. Resolve an indoor spawn from the
	# saved Area polygon too, so that delay never produces an opaque frame.
	if not _occupied:
		var interior: CollisionPolygon2D = $Interior
		for body in get_tree().get_nodes_in_group(observer_group):
			if body is PhysicsBody2D and Geometry2D.is_point_in_polygon(interior.to_local(body.global_position), interior.polygon):
				_occupied = true
				break
	_occlusion.modulate.a = 0.0 if _occupied else 1.0
	occupancy_changed.emit(_occupied)

func is_occupied() -> bool:
	return _occupied

func get_occlusion_alpha() -> float:
	return _occlusion.modulate.a

func _has_observer() -> bool:
	return get_overlapping_bodies().any(func(body: Node2D) -> bool: return body.is_in_group(observer_group))

func _on_body_changed(_body: Node2D) -> void:
	# Read the complete overlap set after the physics signal batch, including
	# simultaneous enter/exit and more than one observer.
	_refresh_occupancy.call_deferred()

func _refresh_occupancy() -> void:
	if not _initialized:
		return
	var occupied := _has_observer()
	if occupied == _occupied:
		return
	_occupied = occupied
	if _fade != null:
		_fade.kill()
	_fade = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Start at the current alpha when interrupted; never snap to an endpoint.
	_fade.tween_property(_occlusion, "modulate:a", 0.0 if occupied else 1.0, fade_duration)
	occupancy_changed.emit(occupied)

func _exit_tree() -> void:
	if _fade != null:
		_fade.kill()
