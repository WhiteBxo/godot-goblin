class_name SceneEntrance
extends Marker2D
## Position is the player's foot position, in the level's local world pixels.

@export var entrance_id: StringName
@export var facing: PlayerController.Facing = PlayerController.Facing.DOWN

func place_player(player: PlayerController) -> void:
	player.teleport_to(global_position)
	player.face_direction(facing)
