class_name MilkTeaShop
extends Node2D

func get_spawn_position() -> Vector2:
	return $Spawn.global_position

func get_interaction_points() -> Array[InteractionPoint]:
	var points: Array[InteractionPoint] = []
	for child in $InteractionPoints.get_children():
		if child is InteractionPoint:
			points.append(child)
	return points
