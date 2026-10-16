class_name ShopPlayer
extends PlayerController

@onready var camera: BoundedFollowCamera = $Camera2D

func configure_camera(world_bounds: Rect2) -> void:
	camera.configure(world_bounds)
