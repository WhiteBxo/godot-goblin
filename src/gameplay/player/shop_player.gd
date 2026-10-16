class_name ShopPlayer
extends CharacterBody2D

@export var speed := 240.0
var movement_enabled := true

func _physics_process(_delta: float) -> void:
	velocity = Input.get_vector("move_left", "move_right", "move_up", "move_down") * speed if movement_enabled else Vector2.ZERO
	move_and_slide()
	if absf(velocity.x) > 0.01:
		$Sprite.flip_h = velocity.x < 0.0

func set_movement_enabled(enabled: bool) -> void:
	movement_enabled = enabled
	velocity = Vector2.ZERO
