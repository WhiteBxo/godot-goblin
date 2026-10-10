class_name CavePlayer
extends CharacterBody2D

@export var speed := 122.0
@export var body_half_size := Vector2(7.0, 6.0)

@onready var camera: Camera2D = $Camera2D

var walkability_query: Callable
var overview_enabled := false

func configure(query: Callable) -> void:
	walkability_query = query

func _physics_process(delta: float) -> void:
	move_direction(Input.get_vector("move_left", "move_right", "move_up", "move_down"), delta)

func move_direction(direction: Vector2, delta: float) -> void:
	if direction == Vector2.ZERO or not walkability_query.is_valid():
		return
	var motion := direction.normalized() * speed * delta
	var target := global_position + Vector2(motion.x, 0.0)
	if can_stand_at(target):
		global_position.x = target.x
	target = global_position + Vector2(0.0, motion.y)
	if can_stand_at(target):
		global_position.y = target.y

func can_stand_at(world_position: Vector2) -> bool:
	return walkability_query.is_valid() and bool(walkability_query.call(world_position, body_half_size))

func follow_player() -> void:
	overview_enabled = false
	camera.top_level = false
	camera.position = Vector2.ZERO
	camera.zoom = Vector2.ONE
	camera.make_current()

func show_overview(bounds: Rect2, viewport_size: Vector2) -> void:
	center_camera_on(bounds.get_center())
	var available_size := viewport_size - Vector2(40.0, 80.0)
	camera.zoom = Vector2.ONE * minf(available_size.x / bounds.size.x, available_size.y / bounds.size.y)

func center_camera_on(world_position: Vector2) -> void:
	overview_enabled = true
	camera.top_level = true
	camera.global_position = world_position
	camera.zoom = Vector2.ONE
