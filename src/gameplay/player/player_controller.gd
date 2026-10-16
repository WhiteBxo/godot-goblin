class_name PlayerController
extends CharacterBody2D

enum Facing { DOWN, LEFT, RIGHT, UP }

const DIRECTION_NAMES: Array[StringName] = [&"down", &"left", &"right", &"up"]

## World pixels per second; acceleration and deceleration use pixels per second squared.
@export_range(1.0, 2000.0, 1.0) var speed := 122.0
@export_range(1.0, 20000.0, 1.0) var acceleration := 1800.0
@export_range(1.0, 20000.0, 1.0) var deceleration := 2400.0
@export_range(0.1, 4.0, 0.05) var animation_speed := 1.0
@export var initial_facing: Facing = Facing.DOWN

var facing: Facing = Facing.DOWN
var movement_enabled := true

@onready var animated_sprite: AnimatedSprite2D = $Visual/AnimatedSprite2D

func _ready() -> void:
	facing = initial_facing
	_update_animation(false)

func _physics_process(delta: float) -> void:
	move_direction(Input.get_vector("move_left", "move_right", "move_up", "move_down"), delta)

func get_movement_speed() -> float:
	return speed

func set_movement_enabled(enabled: bool) -> void:
	movement_enabled = enabled
	velocity = Vector2.ZERO
	_update_animation(false)

func move_direction(direction: Vector2, delta: float) -> void:
	if not movement_enabled:
		return
	direction = direction.limit_length()
	if not direction.is_zero_approx():
		_update_facing(direction)
	var target_velocity := direction * get_movement_speed()
	var rate := deceleration if direction.is_zero_approx() else acceleration
	velocity = velocity.move_toward(target_velocity, rate * delta)
	var previous_position := global_position
	_move_velocity(delta)
	var distance := global_position.distance_to(previous_position)
	var movement_ratio := distance / maxf(delta * get_movement_speed(), 0.001)
	_update_animation(distance > 0.01, movement_ratio)

func _move_velocity(_delta: float) -> void:
	move_and_slide()

func _update_facing(direction: Vector2) -> void:
	# Keep the existing axis on exact diagonals, so holding two keys does not flicker.
	if is_equal_approx(absf(direction.x), absf(direction.y)):
		if facing == Facing.LEFT or facing == Facing.RIGHT:
			facing = Facing.LEFT if direction.x < 0.0 else Facing.RIGHT
		else:
			facing = Facing.UP if direction.y < 0.0 else Facing.DOWN
	elif absf(direction.x) > absf(direction.y):
		facing = Facing.LEFT if direction.x < 0.0 else Facing.RIGHT
	else:
		facing = Facing.UP if direction.y < 0.0 else Facing.DOWN

func _update_animation(moving: bool, movement_ratio: float = 1.0) -> void:
	var state := "walk" if moving else "idle"
	var animation := StringName("%s_%s" % [state, DIRECTION_NAMES[facing]])
	animated_sprite.speed_scale = animation_speed * clampf(movement_ratio, 0.25, 1.0) if moving else animation_speed
	# Preserve the step phase on turns; switch textures directly without crossfading.
	if moving and animated_sprite.animation != animation and String(animated_sprite.animation).begins_with("walk_"):
		var phase := animated_sprite.frame + animated_sprite.frame_progress
		animated_sprite.play(animation)
		animated_sprite.set_frame_and_progress(int(phase), fposmod(phase, 1.0))
	else:
		animated_sprite.play(animation)
