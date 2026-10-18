class_name InteractionPoint
extends Area2D

signal availability_changed(point: InteractionPoint, available: bool)
signal interacted(point: InteractionPoint)

@export var interaction_id: StringName
@export var display_name := "交互地点"
@export_multiline var description := ""
## Local artwork bounds, independent of the reach/collision shape.
@export var feedback_rect := Rect2(-18, -18, 36, 36)
@export var success_sound: String = ""
@export_enum("UI", "SFX") var sound_bus: String = "UI"
## Scene-authored links stay valid when the host reparents actors.
@export var required_actors: Array[Node2D] = []
## Related overlapping targets may use business priority after spatial selection.
@export var selection_group: StringName
@export var interaction_enabled := true:
	set(value):
		interaction_enabled = value
		if is_inside_tree():
			availability_changed.emit(self, is_available())
var _bodies: Array[Node2D] = []

func _ready() -> void:
	$Label.text = display_name
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func hide_development_markers() -> void:
	$Marker.hide()
	$Label.hide()

func is_available() -> bool:
	_bodies = _bodies.filter(func(body: Node2D) -> bool:
		return is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion())
	return (interaction_enabled and is_visible_in_tree() and is_inside_tree()
		and not is_queued_for_deletion() and not _bodies.is_empty()
		and required_actors.all(func(actor: Node2D) -> bool:
			return is_instance_valid(actor) and actor.is_visible_in_tree() and not actor.is_queued_for_deletion()))

func interact() -> void:
	if is_available():
		interacted.emit(self)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body not in _bodies:
		_bodies.append(body)
		availability_changed.emit(self, is_available())

func _on_body_exited(body: Node2D) -> void:
	_bodies.erase(body)
	if _bodies.is_empty():
		availability_changed.emit(self, false)
