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
## NPC scenes reuse this controller without reading the player's InputMap.
@export var accepts_player_input := true

var facing: Facing = Facing.DOWN
var movement_enabled := true
var speed_multiplier := 1.0
var _performance_owner: WeakRef

@onready var animated_sprite: AnimatedSprite2D = $Visual/AnimatedSprite2D

func _ready() -> void:
	facing = initial_facing
	_update_animation(false)

func _physics_process(delta: float) -> void:
	if not accepts_player_input or is_performance_controlled():
		return
	move_direction(Input.get_vector("move_left", "move_right", "move_up", "move_down"), delta)

func is_performance_controlled() -> bool:
	return _performance_owner != null and _performance_owner.get_ref() != null

func claim_performance_control(owner: Object) -> bool:
	if owner == null or is_performance_controlled():
		return false
	_performance_owner = weakref(owner)
	stop_performance_motion()
	return true

func release_performance_control(owner: Object) -> void:
	if _performance_owner != null and _performance_owner.get_ref() == owner:
		stop_performance_motion()
		_performance_owner = null

func stop_performance_motion() -> void:
	velocity = Vector2.ZERO
	_update_animation(false)

func set_performance_facing(owner: Object, direction: Facing) -> void:
	if _performance_owner == null or _performance_owner.get_ref() != owner:
		return
	facing = direction
	_update_animation(false)

## Called only from ActorDirector's physics tick. Uses each subclass's collision rules.
func move_performance(owner: Object, target: Vector2, move_speed: float, delta: float) -> void:
	if _performance_owner == null or _performance_owner.get_ref() != owner:
		return
	var offset := target - global_position
	_update_facing(offset)
	velocity = offset.normalized() * minf(move_speed, offset.length() / delta)
	var previous_position := global_position
	_move_velocity(delta)
	var distance := global_position.distance_to(previous_position)
	_update_animation(distance > 0.01, distance / maxf(delta * move_speed, 0.001))

func get_emote_offset() -> Vector2:
	var texture := animated_sprite.sprite_frames.get_frame_texture(animated_sprite.animation, animated_sprite.frame)
	if texture == null:
		return Vector2(0, -48)
	return to_local(animated_sprite.to_global(Vector2(0, animated_sprite.offset.y - texture.get_height() * 0.5))) + Vector2(0, -8)

func get_facing_vector() -> Vector2:
	return [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP][facing]

func set_speed_multiplier(multiplier: float) -> void:
	if multiplier in [1.0, 2.0, 4.0, 8.0]:
		speed_multiplier = multiplier

func get_speed_multiplier() -> float:
	return speed_multiplier

func teleport_to(world_position: Vector2) -> void:
	stop_performance_motion()
	global_position = world_position

func get_movement_speed() -> float:
	return speed * speed_multiplier

func set_movement_enabled(enabled: bool) -> void:
	movement_enabled = enabled
	velocity = Vector2.ZERO
	_update_animation(false)

func move_direction(direction: Vector2, delta: float) -> void:
	if not movement_enabled or is_performance_controlled():
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
	var state := "run" if moving else "idle"
	var animation := StringName("%s_%s" % [state, DIRECTION_NAMES[facing]])
	animated_sprite.speed_scale = animation_speed * clampf(movement_ratio, 0.25, 1.0) if moving else animation_speed
	# Preserve the step phase on turns; switch textures directly without crossfading.
	if moving and animated_sprite.animation != animation and String(animated_sprite.animation).begins_with("run_"):
		var phase := animated_sprite.frame + animated_sprite.frame_progress
		animated_sprite.play(animation)
		animated_sprite.set_frame_and_progress(int(phase), fposmod(phase, 1.0))
	else:
		animated_sprite.play(animation)
