class_name SceneExit
extends InteractionPoint
## Destination and gate data only; the host routes interaction through SceneTravel.

@export_file("*.tscn") var destination_scene: String
@export var destination_entrance: StringName
## GameState flags that must all be true to use this exit. Empty means no gate.
@export var required_flags: Array[StringName] = []
## Exact chapter stages or dot-separated operation substages; empty admits all.
@export var allowed_stages: Array[String] = []

## Empty conditions always pass; a missing state fails closed.
func are_conditions_met(state: Node) -> bool:
	if required_flags.is_empty() and allowed_stages.is_empty():
		return true
	if state == null or not is_instance_valid(state):
		return false
	for flag: StringName in required_flags:
		if not state.get_flag(String(flag)):
			return false
	if not allowed_stages.is_empty():
		for stage: String in allowed_stages:
			if Day1Access.at_stage(state, stage):
				return true
		return false
	return true
