class_name PlayerBodyFeel
extends Node2D
## Presentation only: the body answers a change of speed, and the walk cycle
## lands on whole pixels.
##
## Nothing here touches movement, collision or the animation state machine. The
## node owns [Visual.scale] (a stretch when the body pushes off, a squash when it
## brakes) and [Visual.position.y], which only ever moves by whole pixels so
## nearest-filtered pixel art never shimmers. Every reaction ends on the identity
## transform, so a settled player is exactly its authored size.

@export var owner_path: NodePath = NodePath("..")
@export var shadow_path: NodePath = NodePath("../Shadow")
## Vertical stretch while the body pushes off, as a fraction of its height.
@export_range(0.0, 0.10, 0.005) var stretch := 0.04
## Horizontal squash while the body brakes, as a fraction of its width.
@export_range(0.0, 0.10, 0.005) var squash := 0.05
@export_range(0.02, 0.30, 0.005) var start_seconds := 0.10
@export_range(0.02, 0.30, 0.005) var stop_seconds := 0.09
## Whole pixels the body lifts on alternating walk frames.
@export var step_bob := 1.0
## How much the shadow narrows while the body is lifted.
@export_range(0.0, 0.10, 0.005) var shadow_shrink := 0.04

## Below this the body counts as standing, so a slow drift cannot start a squash.
const MOVE_EPSILON := 2.0
## Speed gained or lost in one frame that counts as really pushing off or
## braking, instead of the tiny drift of a turn.
const SPEED_STEP := 8.0

var _player: PlayerController
var _shadow: Node2D
var _shadow_base := Vector2.ONE
## Authored visual scale. Inherited players shrink the whole rig (rooms use 0.5),
## so every reaction is relative to this and never to 1.
var _base_scale := Vector2.ONE
var _tween: Tween
var _moving := false
var _braking := false
var _last_speed := 0.0
## Whole-pixel drop under a brake, eased back to zero so the feet stay planted.
var _dip := 0.0
var _offset := 0.0

func _ready() -> void:
	_player = get_node_or_null(owner_path) as PlayerController
	_shadow = get_node_or_null(shadow_path) as Node2D
	if _shadow != null:
		_shadow_base = _shadow.scale
	_base_scale = scale
	scale = _base_scale

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	# A story pose or a locked body is not the player's own movement: return to
	# the authored size without pretending they braked.
	if not _player.movement_enabled or _player.is_performance_controlled():
		if _moving:
			_moving = false
			_braking = false
			_settle()
		_last_speed = 0.0
		_apply(0.0, delta)
		return
	var speed := _player.velocity.length()
	var moving := speed > MOVE_EPSILON
	if moving and not _moving:
		_braking = false
		_react(true)
	elif _braking and speed > _last_speed + SPEED_STEP:
		# Pushing again out of a brake: no second push-off, the squash just ends.
		_braking = false
	elif not _braking and speed < _last_speed - SPEED_STEP:
		# Key already released: react on the first braking frame instead of
		# waiting for the deceleration to finish. A body that stops dead in one
		# frame brakes too.
		_braking = true
		_react(false)
	_moving = moving
	_last_speed = speed
	_apply(_step_lift() if moving else 0.0, delta)

## Alternating walk frames put the body one pixel up, which reads as a step
## without touching the sprite itself.
func _step_lift() -> float:
	var sprite := _player.animated_sprite
	if sprite == null or sprite.animation.is_empty():
		return 0.0
	return -step_bob if sprite.frame % 2 == 1 else 0.0

func _apply(bob: float, delta: float) -> void:
	_dip = move_toward(_dip, 0.0, delta / maxf(stop_seconds, 0.001))
	var wanted := roundf(bob + _dip)
	if is_equal_approx(_offset, wanted):
		return
	_offset = wanted
	position.y = wanted

func _react(moving: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var shadow_relative := Vector2.ONE
	if moving:
		scale = _base_scale * Vector2(1.0 - stretch * 0.5, 1.0 + stretch)
		shadow_relative = Vector2(1.0 - shadow_shrink, 1.0)
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(self, "scale", _base_scale, start_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		scale = _base_scale * Vector2(1.0 + squash, 1.0 - squash * 0.8)
		shadow_relative = Vector2(1.0 + shadow_shrink * 0.6, 1.0)
		_dip = 1.0
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(self, "scale", _base_scale, stop_seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _shadow != null:
		_shadow.scale = _shadow_base * shadow_relative
		_tween.tween_property(_shadow, "scale", _shadow_base, 0.10)

func _settle() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_tween = null
	scale = _base_scale
	_dip = 0.0
	if _shadow != null:
		_shadow.scale = _shadow_base
