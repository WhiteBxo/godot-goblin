class_name DoorframeForeground
extends Node2D
## Reuses exact background texels. The level sorts this baseline against all actors.

@export var baseline_y := 480.0

func get_baseline_position() -> Vector2:
	return to_global(Vector2(0, baseline_y))
