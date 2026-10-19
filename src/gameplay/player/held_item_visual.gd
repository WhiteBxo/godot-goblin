class_name HeldItemVisual
extends Node2D
## Pixel stand-in for whatever the player is holding. Purely visual: stock,
## pricing and throw resolution stay with the scene that owns the item.
## Replace the drawing calls with real sprites once item art exists.

@export var owner_path: NodePath = NodePath("..")
## Hand anchor per facing, in shop_player world units: the 128x160 frame puts the
## feet at y=0 and the head at y=-114, so the hands hang around y=-52.
## The player uses four separate sprite sets instead of mirroring, so the anchor
## cannot be derived from a single offset.
@export var offset_down := Vector2(24.0, -52.0)
@export var offset_up := Vector2(-24.0, -52.0)
@export var offset_left := Vector2(-24.0, -52.0)
@export var offset_right := Vector2(24.0, -52.0)

## How far the carried item lifts on each step. One pixel of bob is enough to
## read as "held in a hand" instead of "pasted on the sprite".
const BOB_HEIGHT := 1.5
const BOB_SPEED := 9.0
const MOVING_SPEED := 6.0
## Used when a drink has no product art (a free-formula cup).
const DRINK_FALLBACK: Texture2D = preload("res://assets/ui/milk_tea/products/custom_drink.svg")

var _player: PlayerController
var _item: StringName = &""
## Authoritative hand position for the current facing, before the walk bob.
var _anchor := Vector2.ZERO
var _bob := 0.0
## Real art for the held item; the drawn cup below is the fallback stand-in.
var _texture: Texture2D

func _ready() -> void:
	_player = get_node_or_null(owner_path) as PlayerController
	if _player == null:
		push_warning("HeldItemVisual: owner_path does not resolve to a PlayerController.")
		queue_free()
		return
	_player.held_changed.connect(_on_held_changed)
	_player.facing_changed.connect(_on_facing_changed)
	_apply(_player.held_item)

func _on_held_changed(item: StringName, _variant_id: String) -> void:
	_apply(item)

## The scene that owns the item knows its art; this node only draws it.
func set_item_texture(texture: Texture2D) -> void:
	_texture = texture
	queue_redraw()

func _on_facing_changed(_direction: PlayerController.Facing) -> void:
	_place()

## A carried cup rides the walk cycle. Presentation only: the hand anchor stays
## the same, so nothing gameplay-facing depends on this offset.
func _process(delta: float) -> void:
	if _item == &"":
		return
	var moving := is_instance_valid(_player) and _player.velocity.length() > MOVING_SPEED
	if not moving:
		_bob = 0.0
		position = _anchor
		return
	_bob = fmod(_bob + delta * BOB_SPEED, TAU)
	position = _anchor + Vector2(0.0, -absf(sin(_bob * 2.0)) * BOB_HEIGHT)

func _apply(item: StringName) -> void:
	_item = item
	visible = item != &""
	_place()
	queue_redraw()

## Facing order matches the enum: DOWN, LEFT, RIGHT, UP.
func _place() -> void:
	if not is_instance_valid(_player):
		return
	var facing := _player.facing
	_anchor = [offset_down, offset_left, offset_right, offset_up][facing]
	_bob = 0.0
	position = _anchor
	# Facing away puts both hands behind the body, so the item must draw underneath it.
	z_index = -1 if facing == PlayerController.Facing.UP else 0

func _draw() -> void:
	if _item == &"drink":
		# Product art when the menu has it, the neutral cup otherwise. Either way
		# the player sees the drink they are about to hand over.
		var art: Texture2D = _texture if _texture != null else DRINK_FALLBACK
		draw_texture_rect(art, Rect2(Vector2(-9.0, -11.0), Vector2(18.0, 22.0)), false)
		return
	if _texture != null:
		draw_texture_rect(_texture, Rect2(Vector2(-9.0, -11.0), Vector2(18.0, 22.0)), false)
		return
	if _item == &"torch":
		draw_line(Vector2(-8, 6), Vector2(5, -5), Color.SADDLE_BROWN, 5.0)
		draw_circle(Vector2(5, -5), 6.0, Color.ORANGE_RED)
	else:
		draw_circle(Vector2.ZERO, 5.0, Color.GOLD)
