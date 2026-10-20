class_name PlayerController
extends CharacterBody2D

enum Facing { DOWN, LEFT, RIGHT, UP }
enum Locomotion { WALK, RUN, SNEAK }

signal locomotion_changed(mode: Locomotion)
signal action_started(action: StringName, direction: Vector2)
## Animation release point. Future gameplay can spawn a projectile here.
signal action_triggered(action: StringName, direction: Vector2)
## cancelled is true when a modal lock, teleport or performance interrupts the action.
signal action_finished(action: StringName, cancelled: bool)
## A story pose reached its last frame. Looping poses never emit this.
signal performance_animation_finished(animation: StringName)
## The held slot changed. [param variant_id] carries the drink id for drink items.
signal held_changed(item: StringName, variant_id: String)
## Facing changed through movement, [method face_direction] or a story pose.
signal facing_changed(direction: Facing)

const DIRECTION_NAMES: Array[StringName] = [&"down", &"left", &"right", &"up"]
## Physics layers: 1 = world and furniture, 2 = player body, 3 = solid NPC bodies.
const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const NPC_LAYER := 3

## World pixels per second; acceleration and deceleration use pixels per second squared.
@export_range(1.0, 2000.0, 1.0) var speed := 122.0
@export_range(1.0, 20000.0, 1.0) var acceleration := 1800.0
@export_range(1.0, 20000.0, 1.0) var deceleration := 2400.0
@export_range(0.1, 4.0, 0.05) var animation_speed := 1.0
@export var initial_facing: Facing = Facing.DOWN
## NPC scenes reuse this controller without reading the player's InputMap.
@export var accepts_player_input := true
@export_range(1.0, 4.0, 0.05) var run_speed_multiplier := 1.6
@export_range(0.1, 1.0, 0.05) var sneak_speed_multiplier := 0.5
@export_range(0.05, 0.8, 0.05) var movement_deadzone := 0.25

var facing: Facing = Facing.DOWN:
	set(value):
		if facing == value:
			return
		facing = value
		facing_changed.emit(value)
var movement_enabled := true
var speed_multiplier := 1.0
## Presentation-only held slot. Stock, pricing and consumption belong to the scene that owns the item.
var held_item: StringName = &""
var held_variant_id := ""
var _performance_owner: WeakRef
var locomotion_mode: Locomotion = Locomotion.WALK
var _active_action: StringName = &""
var _action_direction := Vector2.ZERO
var _action_triggered := false
## Story pose owned by a performance; a held pose survives the release of control.
var _pose_animation: StringName = &""
var _pose_hold := false

@onready var animated_sprite: AnimatedSprite2D = $Visual/AnimatedSprite2D

func _ready() -> void:
	if not accepts_player_input:
		collision_mask = 1 << (WORLD_LAYER - 1)
		_sync_npc_collision()
	facing = initial_facing
	animated_sprite.frame_changed.connect(_on_action_frame_changed)
	animated_sprite.animation_finished.connect(_on_action_animation_finished)
	_update_animation(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_npc_collision()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and accepts_player_input:
		clear_movement_input()

## Focus changes may swallow key releases. Clear global actions and residual velocity.
func clear_movement_input() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down", &"player_run", &"player_sneak", &"player_throw"]:
		Input.action_release(action)
	velocity = Vector2.ZERO
	if is_node_ready():
		cancel_action()
		_reset_locomotion()
		_update_animation(false)

## Applies to both settlement NPCs and actors spawned for story performances.
## Parent visibility also matters: an off-stage actor must never be an invisible wall.
func _sync_npc_collision() -> void:
	if not accepts_player_input:
		collision_layer = (1 << (NPC_LAYER - 1)) if is_visible_in_tree() else 0

func _physics_process(delta: float) -> void:
	if not accepts_player_input or is_performance_controlled():
		return
	if movement_enabled and animated_sprite.sprite_frames.has_animation(&"walk_down"):
		var mode := Locomotion.WALK
		if Input.is_action_pressed(&"player_sneak"):
			mode = Locomotion.SNEAK
		elif Input.is_action_pressed(&"player_run"):
			mode = Locomotion.RUN
		set_locomotion_mode(mode)
	move_direction(Input.get_vector("move_left", "move_right", "move_up", "move_down", movement_deadzone), delta)

func _unhandled_input(event: InputEvent) -> void:
	if accepts_player_input and event.is_action_pressed(&"player_throw"):
		if request_action(&"throw"):
			get_viewport().set_input_as_handled()

func get_active_action() -> StringName:
	return _active_action

func set_locomotion_mode(mode: Locomotion) -> bool:
	if not movement_enabled or is_performance_controlled() or mode < Locomotion.WALK or mode > Locomotion.SNEAK:
		return false
	if locomotion_mode != mode:
		locomotion_mode = mode
		locomotion_changed.emit(mode)
	return true

## Sets the held slot. Only [param item] with a matching variant is accepted;
## drink items require an id and every other item rejects one.
func set_held(item: StringName, variant_id: String = "") -> bool:
	if item == &"":
		return variant_id.is_empty() and clear_held()
	if (item == &"drink") != (not variant_id.is_empty()):
		return false
	if held_item == item and held_variant_id == variant_id:
		return true
	held_item = item
	held_variant_id = variant_id
	held_changed.emit(held_item, held_variant_id)
	return true

func clear_held() -> bool:
	if held_item == &"":
		return true
	held_item = &""
	held_variant_id = ""
	held_changed.emit(&"", "")
	return true

func has_held() -> bool:
	return held_item != &""

## Starts visual action playback only. No inventory, damage or projectile side effects.
func request_action(action: StringName) -> bool:
	if action != &"throw" or not movement_enabled or is_performance_controlled() or not _active_action.is_empty():
		return false
	var animation := StringName("%s_%s" % [action, DIRECTION_NAMES[facing]])
	if not animated_sprite.sprite_frames.has_animation(animation):
		return false
	_active_action = action
	_action_direction = get_facing_vector()
	_action_triggered = false
	velocity = Vector2.ZERO
	animated_sprite.speed_scale = animation_speed
	animated_sprite.play(animation)
	action_started.emit(action, _action_direction)
	return true

func cancel_action() -> void:
	_finish_action(true)

func _finish_action(cancelled: bool) -> void:
	if _active_action.is_empty():
		return
	var action := _active_action
	_active_action = &""
	_update_animation(false)
	action_finished.emit(action, cancelled)

func _on_action_frame_changed() -> void:
	if _active_action.is_empty() or _action_triggered or animated_sprite.frame < 3:
		return
	_action_triggered = true
	action_triggered.emit(_active_action, _action_direction)

func _on_action_animation_finished() -> void:
	if not _pose_animation.is_empty() and animated_sprite.animation == _pose_animation:
		var pose := _pose_animation
		if not _pose_hold:
			clear_performance_pose()
		performance_animation_finished.emit(pose)
		return
	_finish_action(false)

## Plays a named SpriteFrames animation for the performance owner. Returns false
## when the owner does not control this body or the animation does not exist.
func play_performance_animation(owner: Object, animation: StringName, hold: bool = false) -> bool:
	if _performance_owner == null or _performance_owner.get_ref() != owner:
		return false
	if not animated_sprite.sprite_frames.has_animation(animation):
		return false
	_pose_animation = animation
	_pose_hold = hold
	animated_sprite.speed_scale = animation_speed
	animated_sprite.play(animation)
	_update_animation(false)
	return true

func is_animation_looping(animation: StringName) -> bool:
	return animated_sprite.sprite_frames.has_animation(animation) and animated_sprite.sprite_frames.get_animation_loop(animation)

func clear_performance_pose() -> void:
	if _pose_animation.is_empty():
		return
	_pose_animation = &""
	_pose_hold = false
	_update_animation(false)

func _reset_locomotion() -> void:
	if locomotion_mode != Locomotion.WALK:
		locomotion_mode = Locomotion.WALK
		locomotion_changed.emit(locomotion_mode)

func is_performance_controlled() -> bool:
	return _performance_owner != null and _performance_owner.get_ref() != null

func claim_performance_control(owner: Object) -> bool:
	if owner == null or is_performance_controlled():
		return false
	_performance_owner = weakref(owner)
	clear_performance_pose()
	stop_performance_motion()
	return true

func release_performance_control(owner: Object) -> void:
	if _performance_owner != null and _performance_owner.get_ref() == owner:
		if not _pose_hold:
			clear_performance_pose()
		stop_performance_motion()
		_performance_owner = null

func stop_performance_motion() -> void:
	cancel_action()
	_reset_locomotion()
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

func face_direction(direction: Facing) -> void:
	facing = direction
	_update_animation(false)

func set_speed_multiplier(multiplier: float) -> void:
	if multiplier in [1.0, 2.0, 4.0, 8.0]:
		speed_multiplier = multiplier

func get_speed_multiplier() -> float:
	return speed_multiplier

func teleport_to(world_position: Vector2) -> void:
	clear_performance_pose()
	stop_performance_motion()
	global_position = world_position

func get_movement_speed() -> float:
	var mode_multiplier := 1.0
	if locomotion_mode == Locomotion.RUN:
		mode_multiplier = run_speed_multiplier
	elif locomotion_mode == Locomotion.SNEAK:
		mode_multiplier = sneak_speed_multiplier
	return speed * speed_multiplier * mode_multiplier

func set_movement_enabled(enabled: bool) -> void:
	movement_enabled = enabled
	if not enabled:
		cancel_action()
		_reset_locomotion()
	velocity = Vector2.ZERO
	_update_animation(false)

## [param speed_override] lets scene-owned ambient NPC movement use its own
## pace without changing the body's configured player speed.
func move_direction(direction: Vector2, delta: float, speed_override: float = 0.0) -> void:
	if not direction.is_finite() or not is_finite(delta) or delta <= 0.0:
		velocity = Vector2.ZERO
		return
	if not movement_enabled or is_performance_controlled() or not _active_action.is_empty():
		return
	direction = direction.limit_length()
	if not direction.is_zero_approx():
		_update_facing(direction)
	var move_speed := speed_override if speed_override > 0.0 else get_movement_speed()
	var target_velocity := direction * move_speed
	var rate := deceleration if direction.is_zero_approx() else acceleration
	velocity = velocity.move_toward(target_velocity, rate * delta)
	var previous_position := global_position
	_move_velocity(delta)
	var distance := global_position.distance_to(previous_position)
	var movement_ratio := distance / maxf(delta * move_speed, 0.001)
	_update_animation(distance > 0.01, movement_ratio)

## World effects displace bodies through collision without taking story control
## or changing facing (a stunned actor must keep looking in the same direction).
func displace_by(motion: Vector2) -> Vector2:
	if not movement_enabled or is_performance_controlled() or not motion.is_finite() or not is_visible_in_tree():
		return Vector2.ZERO
	var previous := global_position
	move_and_collide(motion)
	return global_position - previous

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
	if not _active_action.is_empty() or not _pose_animation.is_empty():
		return
	var state := "idle"
	if moving:
		state = ["walk", "run", "sneak"][locomotion_mode]
	elif locomotion_mode == Locomotion.SNEAK:
		state = "crouch_idle"
	var animation := StringName("%s_%s" % [state, DIRECTION_NAMES[facing]])
	var frames := animated_sprite.sprite_frames
	# NPCs reuse this controller with their existing idle/run resources.
	if not frames.has_animation(animation):
		animation = StringName("%s_%s" % ["run" if moving else "idle", DIRECTION_NAMES[facing]])
	animated_sprite.speed_scale = animation_speed * clampf(movement_ratio, 0.25, 1.0) if moving else animation_speed
	var previous := String(animated_sprite.animation)
	var was_moving := previous.begins_with("walk_") or previous.begins_with("run_") or previous.begins_with("sneak_")
	if moving and animated_sprite.animation != animation and was_moving:
		var phase := (animated_sprite.frame + animated_sprite.frame_progress) / frames.get_frame_count(animated_sprite.animation)
		animated_sprite.play(animation)
		var next_frame := phase * frames.get_frame_count(animation)
		animated_sprite.set_frame_and_progress(int(next_frame), fposmod(next_frame, 1.0))
	else:
		animated_sprite.play(animation)
