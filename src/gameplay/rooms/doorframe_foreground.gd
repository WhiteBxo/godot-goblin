class_name DoorframeForeground
extends Node2D
## Reuses exact background texels; sorts frames or furniture against feet.

@export var baseline_y := 480.0
@export var observer_group: StringName = &"player"

var _observer: Node2D

func _ready() -> void:
	process_physics_priority = 1

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_observer):
		_observer = get_tree().get_first_node_in_group(observer_group) as Node2D
	if not is_instance_valid(_observer):
		return
	z_index = 12 if _observer.global_position.y < to_global(Vector2(0, baseline_y)).y else 8
