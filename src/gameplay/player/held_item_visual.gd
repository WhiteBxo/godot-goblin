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
## The player has no carry or throw poses yet, so the stand-in shapes are parked by
## default: the held slot keeps working for throw rules while nothing is drawn in
## the hands. Flip this on only after real held-item frames exist.
@export var draw_stand_in := false

var _player: PlayerController
var _item: StringName = &""

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

func _on_facing_changed(_direction: PlayerController.Facing) -> void:
	_place()

func _apply(item: StringName) -> void:
	_item = item
	visible = draw_stand_in and item != &""
	_place()
	queue_redraw()

## Facing order matches the enum: DOWN, LEFT, RIGHT, UP.
func _place() -> void:
	if not is_instance_valid(_player):
		return
	var facing := _player.facing
	position = [offset_down, offset_left, offset_right, offset_up][facing]
	# Facing away puts both hands behind the body, so the item must draw underneath it.
	z_index = -1 if facing == PlayerController.Facing.UP else 0

func _draw() -> void:
	if _item == &"drink":
		draw_rect(Rect2(-7, -10, 14, 20), Color.MEDIUM_PURPLE)
		draw_line(Vector2(2, -10), Vector2(5, -17), Color.WHITE, 2.0)
	elif _item == &"torch":
		draw_line(Vector2(-8, 6), Vector2(5, -5), Color.SADDLE_BROWN, 5.0)
		draw_circle(Vector2(5, -5), 6.0, Color.ORANGE_RED)
	else:
		draw_circle(Vector2.ZERO, 5.0, Color.GOLD)
