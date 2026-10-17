class_name SceneExit
extends InteractionPoint
## Destination data only; the host routes interaction through SceneTravel.

@export_file("*.tscn") var destination_scene: String
@export var destination_entrance: StringName
