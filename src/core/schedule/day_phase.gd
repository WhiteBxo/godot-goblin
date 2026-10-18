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
	if state.has_variable(PHASE_VARIABLE):
		var stored: Variant = state.get_variable(PHASE_VARIABLE)
		return stored if stored is String and stored in [DAY_PHASE, NIGHT_PHASE] else ""
	return NIGHT_PHASE if state.get_flag(NIGHT_FLAG) else DAY_PHASE

static func phase_from_facts(variables: Dictionary, flags: Dictionary) -> String:
	if variables.has(PHASE_VARIABLE):
		var stored: Variant = variables[PHASE_VARIABLE]
		return stored if stored is String and stored in [DAY_PHASE, NIGHT_PHASE] else ""
	return NIGHT_PHASE if flags.get(NIGHT_FLAG, false) else DAY_PHASE

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

## Absolute adjacent target: safe to retry even after rebuilding the caller.
## The caller supplies its business/story rule; this module does not close shops.
static func advance_to(state: Node, day: int, phase: String) -> Error:
	if not is_instance_valid(state) or not is_valid_point(day, phase):
		return ERR_INVALID_PARAMETER
	var current := get_phase(state)
	if current.is_empty():
		return ERR_INVALID_DATA
	if state.current_day == day and current == phase:
		return OK
	if not is_adjacent_point(state.current_day, current, day, phase):
		return ERR_INVALID_PARAMETER
	return OK if _write_phase(state, phase) else ERR_BUSY

## Shared by compound business commits; validation must not publish a partial phase.
static func is_adjacent_point(from_day: int, from_phase: String, day: int, phase: String) -> bool:
	if not is_valid_point(from_day, from_phase) or not is_valid_point(day, phase):
		return false
	return (from_phase == DAY_PHASE and phase == NIGHT_PHASE and day == from_day) or (from_phase == NIGHT_PHASE and phase == DAY_PHASE and day > from_day and day - from_day == 1)

static func is_valid_point(day: Variant, phase: Variant) -> bool:
	return day is int and day >= 1 and phase is String and phase in [DAY_PHASE, NIGHT_PHASE]

## boundary is deliberately required: no implicit deadline policy.
static func is_valid_deadline(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3 or not value.has_all(["day", "phase", "boundary"]):
		return false
	var day: Variant = value.day
	return typeof(day) in [TYPE_INT, TYPE_FLOAT] and is_finite(day) and day == floor(day) and day >= 1 and day < 9223372036854775807 and value.phase in [DAY_PHASE, NIGHT_PHASE] and value.boundary in ["at", "after"]

static func is_deadline_reached(state: Node, deadline: Dictionary) -> bool:
	if not is_instance_valid(state) or not is_valid_deadline(deadline):
		return false
	return is_deadline_reached_at(state.current_day, get_phase(state), deadline)

static func is_deadline_reached_at(current_day: int, phase: String, deadline: Dictionary) -> bool:
	if not is_valid_point(current_day, phase) or not is_valid_deadline(deadline):
		return false
	var day: int = int(deadline.day)
	if current_day != day:
		return current_day > day
	if phase == deadline.phase:
		return deadline.boundary == "at"
	return phase == NIGHT_PHASE
