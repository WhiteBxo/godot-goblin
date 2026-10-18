class_name StoryInteractionPoint
extends InteractionPoint
## Static investigation configuration. The host dispatches; GameState commits.

signal resolved(entry_id: StringName)
signal rejected(entry_id: StringName, reason: String)

enum Kind { PICKUP, DOCUMENT }

@export var kind: Kind = Kind.PICKUP
@export var entry_id: StringName
@export var item_id: String = ""
@export_range(1, 99) var amount := 1
@export var amount_is_uses := false
@export var required_flags: Array[StringName] = []
## Each entry permits that stage and its dot-separated operation substages.
@export var required_stages: Array[String] = []
@export var success_flags: Array[StringName] = []

var _state: Node
var _resolving := false

func _ready() -> void:
	super._ready()
	_state = get_node_or_null("/root/GameState")
	if entry_id == &"" or (kind == Kind.PICKUP and item_id.is_empty()):
		push_error("StoryInteractionPoint %s has invalid configuration" % get_path())
		interaction_enabled = false

func conditions_met() -> bool:
	if not is_instance_valid(_state):
		return false
	for flag: StringName in required_flags:
		if not _state.get_flag(String(flag)):
			return false
	if not required_stages.is_empty():
		var matches := false
		for stage: String in required_stages:
			matches = matches or Day1Access.at_stage(_state, stage)
		if not matches:
			return false
	return true

func is_available() -> bool:
	return (super.is_available() and conditions_met()
		and (kind == Kind.DOCUMENT or not is_resolved()))

func receipt_flag() -> String:
	return "story." + str(entry_id) + ".resolved"

func is_resolved() -> bool:
	return is_instance_valid(_state) and _state.get_flag(receipt_flag())

## Documents call this after their content closes; pickups call it from dispatch.
func resolve() -> Dictionary:
	if _resolving or not conditions_met():
		return _failure("当前无法调查。")
	if is_resolved():
		if kind == Kind.DOCUMENT:
			return {"ok": true, "message": description}
		return _failure("已经取走了。")
	var facts := {}
	for flag: StringName in success_flags:
		facts[String(flag)] = true
	var items := {item_id: amount} if not item_id.is_empty() else {}
	_resolving = true
	var error: Error
	if amount_is_uses:
		error = _state.commit_story_transaction(receipt_flag(), {}, items, 0, {}, facts)
	else:
		error = _state.commit_story_interaction(receipt_flag(), items, facts)
	if error != OK:
		_resolving = false
		return _failure("调查未完成或无法放入库存，请重试。（%s）" % error_string(error))
	resolved.emit(entry_id)
	_resolving = false
	availability_changed.emit(self, is_available())
	return {"ok": true, "message": "已取得：%s × %d" % [display_name, amount] if kind == Kind.PICKUP else description}

func _failure(message: String) -> Dictionary:
	rejected.emit(entry_id, message)
	return {"ok": false, "message": message}
