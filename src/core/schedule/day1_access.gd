class_name Day1Access
extends RefCounted
## Reads the published Day 1 stage and business facts; never advances story.

static func at_stage(state: Node, stage: String) -> bool:
	var current: String = state.story_stage
	return current == stage or current.begins_with(stage + ".")

static func is_later_stage(state: Node) -> bool:
	for stage: String in ["day1.s03", "day1.s04", "day1.s05", "day1.s06"]:
		if at_stage(state, stage):
			return true
	return false

static func can_leave_shop(state: Node) -> bool:
	if state.get_business_profile() != "day1":
		return true
	if at_stage(state, "day1.s05"):
		return DayPhase.is_night(state) and state.get_flag("day1.s04.commission_accepted")
	return at_stage(state, "day1.s03") or state.story_stage == "day1.investigate_coins"

static func can_enter_elder(state: Node) -> bool:
	return (at_stage(state, "day1.s05") and DayPhase.is_night(state)
		and state.get_flag("day1.s04.commission_accepted"))

static func can_make_blood_drink(state: Node) -> bool:
	return (at_stage(state, "day1.s06") and state.get_flag("day1.s05.blood_acquired")
		and state.get_flag("day1.s05.returned_shop"))
