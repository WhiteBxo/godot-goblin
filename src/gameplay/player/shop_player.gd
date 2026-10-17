class_name ShopPlayer
extends PlayerController

@onready var camera: BoundedFollowCamera = $Camera2D

func configure_camera(world_bounds: Rect2) -> void:
	camera.configure(world_bounds)

func teleport_to(world_position: Vector2) -> void:
	super.teleport_to(world_position)
	camera.reset_smoothing()
	camera.force_update_scroll()
