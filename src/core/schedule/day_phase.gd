class_name DayPhase
extends RefCounted
## Day / night phase machine. GameState owns the phase fact; this class owns the
## legal transitions and the mirrored nights flag, and nothing else.

const PHASE_VARIABLE := "world.phase"
const NIGHT_FLAG := "world.phase.night"
const DAY_PHASE := "day"
const NIGHT_PHASE := "night"

## Reads the stored phase. A missing variable falls back to the nights flag so
## debug or story writes that only touched the fact still resolve. Unknown
## stored values return "" and reject every transition instead of being guessed.
static func get_phase(state: Node) -> String:
	if state == null or not is_instance_valid(state):
		return DAY_PHASE
	var stored: Variant = state.get_variable(PHASE_VARIABLE, "")
	if stored is String:
		var phase: String = stored
		if phase == DAY_PHASE or phase == NIGHT_PHASE:
			return phase
		if not phase.is_empty():
			return ""
	if state.get_flag(NIGHT_FLAG):
		return NIGHT_PHASE
	return DAY_PHASE

static func is_night(state: Node) -> bool:
	return get_phase(state) == NIGHT_PHASE

## Only day -> night and night -> day are legal. Repeating a completed
## transition keeps the state untouched and returns false.
static func enter_night(state: Node) -> bool:
	if get_phase(state) != DAY_PHASE:
		return false
	return _write_phase(state, NIGHT_PHASE)

static func enter_day(state: Node) -> bool:
	if get_phase(state) != NIGHT_PHASE:
		return false
	return _write_phase(state, DAY_PHASE)

## The variable is the persistent truth; the flag mirrors it for existing
## gathering gates and debug tools, so both keys always change together.
static func _write_phase(state: Node, phase: String) -> bool:
	return is_instance_valid(state) and state.has_method("commit_day_phase") and state.commit_day_phase(phase)
