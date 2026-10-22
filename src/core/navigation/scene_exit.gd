class_name SceneExit
extends InteractionPoint
## Destination and gate data only; the host routes interaction through SceneTravel.

@export_file("*.tscn") var destination_scene: String
@export var destination_entrance: StringName
## GameState flags that must all be true to use this exit. Empty means no gate.
@export var required_flags: Array[StringName] = []
## Exact chapter stages or dot-separated operation substages; empty admits all.
@export var allowed_stages: Array[String] = []
## Level-authored directions shown only when the destination gate rejects entry.
@export_multiline var unavailable_message := "暂时无法通过这扇门，请重试。"
## 胶囊上的一行短原因（"长老还没答应见你"）。留空时用通用说法。
@export var blocked_hint := ""

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

## 门后面是剧情：条件没到就把原因写在胶囊上，而不是等玩家按 E 才弹一句。
func get_blocked_reason() -> String:
	var injected := super.get_blocked_reason()
	if not injected.is_empty():
		return injected
	if are_conditions_met(get_node_or_null("/root/GameState")):
		return ""
	return blocked_hint if not blocked_hint.is_empty() else "现在还不能通过"
