class_name InteractionPoint
extends Area2D

signal availability_changed(point: InteractionPoint, available: bool)
signal interacted(point: InteractionPoint)

@export var interaction_id: StringName
@export var display_name := "交互地点"
@export_multiline var description := ""
var _bodies: Array[Node2D] = []

func _ready() -> void:
	$Label.text = display_name
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func is_available() -> bool:
	return not _bodies.is_empty()

func interact() -> void:
	if is_available():
		interacted.emit(self)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body not in _bodies:
		_bodies.append(body)
		availability_changed.emit(self, true)

func _on_body_exited(body: Node2D) -> void:
	_bodies.erase(body)
	if _bodies.is_empty():
		availability_changed.emit(self, false)
