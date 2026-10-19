class_name ThrowAimIndicator
extends Node2D
## Day 1 throw reticle and range ring. Presentation only: the service owns aim
## validity, cost and resolution. Drawn in whole pixels so it stays crisp.

@export var valid_color := Color(1.0, 0.86, 0.56, 0.95)
@export var invalid_color := Color(1.0, 0.38, 0.32, 0.95)
@export var range_color := Color(1.0, 0.88, 0.68, 0.16)
@export var guide_color := Color(1.0, 0.92, 0.78, 0.22)
@export_range(4.0, 32.0, 1.0) var reticle_gap := 3.0
@export_range(2.0, 32.0, 1.0) var reticle_arm := 5.0

var _player: PlayerController
var _range := 0.0
var _target := Vector2.ZERO
var _valid := true
var _active := false
var _shown := false

func configure(player: PlayerController, throw_range: float) -> void:
	_player = player
	_range = maxf(0.0, throw_range)
	z_index = 25
	visible = false

func present(target: Vector2, valid: bool, active: bool) -> void:
	var next_target := target.round()
	if next_target == _target and valid == _valid and active == _active:
		return
	_target = next_target
	_valid = valid
	_active = active and is_instance_valid(_player) and _player.is_visible_in_tree()
	_shown = _active
	visible = _active
	queue_redraw()

func is_showing() -> bool:
	return _shown

func _draw() -> void:
	if not _active or not is_instance_valid(_player) or get_tree().paused:
		return
	var color := valid_color if _valid else invalid_color
	var player_point := to_local(_player.global_position).round()
	if _range > 0.0:
		draw_arc(player_point, _range, 0.0, TAU, 72, range_color, 1.0, false)
	_draw_guide(player_point, to_local(_target).round())
	var origin := to_local(_target).round()
	for axis in range(2):
		var along := Vector2.RIGHT if axis == 0 else Vector2.DOWN
		draw_line(origin + along * reticle_gap, origin + along * (reticle_gap + reticle_arm), color, 1.0, false)
		draw_line(origin - along * reticle_gap, origin - along * (reticle_gap + reticle_arm), color, 1.0, false)
	# A one-pixel centre keeps the exact landing point readable on the tile grid.
	draw_rect(Rect2(origin, Vector2.ONE), color)

func _draw_guide(from: Vector2, to: Vector2) -> void:
	var offset := to - from
	var distance := offset.length()
	if distance < 8.0:
		return
	var step := 16.0
	var direction := offset / distance
	var travelled := step
	while travelled < distance - 6.0:
		var point := (from + direction * travelled).round()
		draw_rect(Rect2(point, Vector2.ONE), guide_color)
		travelled += step
