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
## Whole pixels the body leans into a turn. Sprites have no turn frames, so this
## is what makes a direction change read as a step instead of a swap.
@export var turn_nudge := 1.0
@export_range(0.02, 0.30, 0.005) var turn_seconds := 0.09
## One speck of floor dust at each footfall. Sneaking never raises any.
@export var dust_enabled := true

## Below this the body counts as standing, so a slow drift cannot start a squash.
const MOVE_EPSILON := 2.0
## Speed gained or lost in one frame that counts as really pushing off or
## braking, instead of the tiny drift of a turn.
const SPEED_STEP := 8.0
const DUST_NAME := "StepDust"

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
## Whole-pixel lean into the last turn, eased back to zero.
var _lurch := 0.0
var _offset := Vector2.ZERO
var _last_frame := -1
var _last_animation: StringName = &""
static var _dust_art: Texture2D

func _ready() -> void:
	_player = get_node_or_null(owner_path) as PlayerController
	_shadow = get_node_or_null(shadow_path) as Node2D
	if _shadow != null:
		_shadow_base = _shadow.scale
	_base_scale = scale
	scale = _base_scale
	if _player != null and not _player.facing_changed.is_connected(_on_facing_changed):
		_player.facing_changed.connect(_on_facing_changed)

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
	if moving:
		_maybe_step_dust()

## Alternating walk frames put the body one pixel up, which reads as a step
## without touching the sprite itself.
func _step_lift() -> float:
	var sprite := _player.animated_sprite
	if sprite == null or sprite.animation.is_empty():
		return 0.0
	return -step_bob if sprite.frame % 2 == 1 else 0.0

func _apply(bob: float, delta: float) -> void:
	_dip = move_toward(_dip, 0.0, delta / maxf(stop_seconds, 0.001))
	_lurch = move_toward(_lurch, 0.0, delta / maxf(turn_seconds, 0.001))
	var wanted := Vector2(roundf(_lurch), roundf(bob + _dip))
	if _offset.is_equal_approx(wanted):
		return
	_offset = wanted
	position = wanted

## A direction change leans the body one pixel into the turn, then settles. The
## sprites have no turn frames, so this is the whole "I just turned" beat.
func _on_facing_changed(direction: PlayerController.Facing) -> void:
	if _player == null or not _player.movement_enabled or _player.is_performance_controlled():
		return
	if direction == PlayerController.Facing.LEFT:
		_lurch = -turn_nudge
	elif direction == PlayerController.Facing.RIGHT:
		_lurch = turn_nudge
	else:
		# A vertical turn has no sideways lean: drop the previous one instead of
		# letting it decay while the body already faces the camera.
		_lurch = 0.0

## One puff per two frames of the walk cycle, so the dust keeps the sprite's own
## rhythm instead of a timer of its own. Sneaking raises nothing.
func _maybe_step_dust() -> void:
	if not dust_enabled or _player.locomotion_mode == PlayerController.Locomotion.SNEAK:
		return
	var sprite := _player.animated_sprite
	if sprite == null or sprite.animation.is_empty():
		return
	var frame := sprite.frame
	var same_animation := sprite.animation == _last_animation
	if same_animation and frame == _last_frame:
		return
	_last_animation = sprite.animation
	_last_frame = frame
	# A changed animation is not a footfall; wait one frame for the next one.
	if not same_animation or frame % 2 != 0:
		return
	_emit_dust(2 if _player.locomotion_mode == PlayerController.Locomotion.RUN else 1)

func _emit_dust(count: int) -> void:
	var art := _dust_texture()
	for index in range(count):
		var puff := Sprite2D.new()
		puff.name = DUST_NAME
		puff.texture = art
		puff.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		puff.z_index = -1
		puff.scale = _base_scale * 1.25
		puff.position = Vector2(randf_range(-2.5, 2.5), randf_range(-1.0, 0.5))
		puff.modulate = Color(0.86, 0.80, 0.70, 0.55)
		_player.add_child(puff)
		var drift := Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, -1.5))
		var tween := puff.create_tween().set_parallel(true)
		tween.tween_property(puff, "position", puff.position + drift, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(puff, "modulate:a", 0.0, 0.26)
		tween.tween_property(puff, "scale", _base_scale * 1.6, 0.26)
		tween.chain().tween_callback(puff.queue_free)

## A four-pixel speck with soft corners; generated once so the dust needs no art.
static func _dust_texture() -> Texture2D:
	if _dust_art != null:
		return _dust_art
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var solid := [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]
	for point: Vector2i in solid:
		image.set_pixelv(point, Color(1, 1, 1, 1))
	var soft := [Vector2i(0, 1), Vector2i(3, 1), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 3), Vector2i(2, 3)]
	for point: Vector2i in soft:
		image.set_pixelv(point, Color(1, 1, 1, 0.55))
	_dust_art = ImageTexture.create_from_image(image)
	return _dust_art

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
	_lurch = 0.0
	_offset = Vector2.ZERO
	position = Vector2.ZERO
	if _shadow != null:
		_shadow.scale = _shadow_base
