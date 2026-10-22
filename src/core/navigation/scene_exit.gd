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

## 门自己带着方向：'走出奶茶店' / '进入奶茶店'。基类会给所有出口补一个
## '进入'，于是胶囊上出现'进入进入奶茶店'这种话；没写方向的门才补一个。
const _MOTION_PREFIXES := ["走出", "进入", "前往", "离开", "回到", "返回", "下到", "爬上"]

func get_action_text() -> String:
	if not action_verb.is_empty():
		return super.get_action_text()
	for prefix: String in _MOTION_PREFIXES:
		if display_name.begins_with(prefix):
			return display_name
	return "前往" + display_name

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
