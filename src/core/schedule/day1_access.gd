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

## Later chapter ownership; travel permission follows the real schedule below.
static func is_day2_placeholder(state: Node) -> bool:
	return at_stage(state, "day2")

static func can_leave_shop(state: Node) -> bool:
	if state.get_business_profile() != "day1":
		return true
	if is_day2_placeholder(state) or at_stage(state, "day3"):
		return state.current_day == 3 or (state.current_day == 2 and DayPhase.is_night(state))
	if at_stage(state, "day1.s05"):
		return DayPhase.is_night(state) and state.get_flag("day1.s04.commission_accepted")
	return at_stage(state, "day1.s03") or state.story_stage == "day1.investigate_coins"

static func can_enter_elder(state: Node) -> bool:
	return (at_stage(state, "day1.s05") and DayPhase.is_night(state)
		and state.get_flag("day1.s04.commission_accepted"))

static func is_market_only(state: Node) -> bool:
	return (state.get_business_profile() == "day1" and state.current_day == 1
		and is_later_stage(state) and not state.get_flag("day1.s04.commission_accepted"))

static func can_make_blood_drink(state: Node) -> bool:
	return (at_stage(state, "day1.s06") and state.get_flag("day1.s05.blood_acquired")
		and state.get_flag("day1.s05.returned_shop"))

## The S05 night infiltration is an unsafe phase: confirming a new formula price
## there would let the player re-roll money mid-mission. Previews stay read-only.
static func pricing_blocked(state: Node) -> bool:
	return state.get_business_profile() == "day1" and at_stage(state, "day1.s05") and DayPhase.is_night(state)
