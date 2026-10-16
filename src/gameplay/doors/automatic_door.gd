@tool
class_name AutomaticDoor
extends Node2D

## Positions and dimensions use the reference image's 1376 × 768 pixel space.
@export var door_width := 72.0
@export var door_height := 76.0
@export var vertical := false
@export var door_color := Color("855944")
@export var glass := false
@export var open_angle := -70.0
@export var animation_duration := 0.28
@export var close_delay := 0.65

var is_open := false
var _openness := 0.0
var _occupants: Array[Node2D] = []
var _tween: Tween

@onready var _blocker: CollisionShape2D = $Body/CollisionShape2D
@onready var _sensor: Area2D = $Proximity
@onready var _timer: Timer = $CloseTimer

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var axis := Vector2.DOWN if vertical else Vector2.RIGHT
	var blocker_shape := RectangleShape2D.new()
	blocker_shape.size = Vector2(12, door_width) if vertical else Vector2(door_width, 12)
	_blocker.shape = blocker_shape
	_blocker.position = axis * door_width * 0.5
	var sensor_shape := RectangleShape2D.new()
	sensor_shape.size = blocker_shape.size + Vector2(112, 112)
	$Proximity/CollisionShape2D.shape = sensor_shape
	$Proximity/CollisionShape2D.position = _blocker.position
	_sensor.body_entered.connect(_on_body_entered)
	_sensor.body_exited.connect(_on_body_exited)
	_timer.timeout.connect(_try_close)
	queue_redraw()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	# Match the player's existing z = 10 without depending on its node hierarchy.
	z_index = 9
	for body in _occupants:
		if is_instance_valid(body) and body.global_position.y < global_position.y + 8:
			z_index = 11
	# Also handles an occupant freed while standing in the doorway.
	if is_open and _timer.is_stopped() and not _has_player():
		_timer.start(close_delay)

func _has_player() -> bool:
	return _sensor.get_overlapping_bodies().any(func(body: Node2D) -> bool: return body.is_in_group("player"))

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if body not in _occupants:
		_occupants.append(body)
	_timer.stop()
	_set_open(true)

func _on_body_exited(body: Node2D) -> void:
	_occupants.erase(body)
	if body.is_in_group("player") and not _has_player():
		_timer.start(close_delay)

func _try_close() -> void:
	if not _has_player():
		_set_open(false)

func _set_open(value: bool) -> void:
	if value == is_open:
		return
	is_open = value
	# Physics signals run during a query flush; defer changes as Godot requires.
	_blocker.set_deferred("disabled", value)
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_animate, _openness, 1.0 if value else 0.0, animation_duration)

func _animate(value: float) -> void:
	_openness = value
	queue_redraw()

func _draw() -> void:
	var axis := Vector2.DOWN if vertical else Vector2.RIGHT
	var end := axis.rotated(deg_to_rad(open_angle) * _openness) * door_width
	# Side-facing doors are drawn as a narrow panel, matching the reference art.
	var lift := Vector2(-22, 0).lerp(Vector2(0, -door_height), _openness) if vertical else Vector2(0, -door_height)
	var panel := PackedVector2Array([Vector2.ZERO, end, end + lift, lift])
	draw_colored_polygon(panel, door_color)
	var outline := PackedVector2Array([panel[0], panel[1], panel[2], panel[3], panel[0]])
	draw_polyline(outline, Color("2a2029"), 4, false)
	var inset := PackedVector2Array([end * 0.12 + lift * 0.12, end * 0.88 + lift * 0.12, end * 0.88 + lift * 0.88, end * 0.12 + lift * 0.88])
	draw_colored_polygon(inset, Color("a2b9ba") if glass else door_color.lightened(0.12))
	draw_polyline(PackedVector2Array([inset[0], inset[1], inset[2], inset[3], inset[0]]), door_color.darkened(0.35), 2, false)
	var handle := end * 0.84 + lift * 0.45
	draw_circle(handle, 4, Color("2a2029"))
	draw_circle(handle + Vector2(-1, -1), 2, Color("c4c4b8"))
