extends SceneTree
## Day / night phase transitions, snapshot persistence and scene exit gating.

const EXIT_OPEN := &"day_phase.exit_open"

var _failures: Array[String] = []
var _state: Node

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	_state = root.get_node("GameState")
	_state.start_new_game()
	_state.state_changed.connect(func() -> void:
		if _state.has_variable(DayPhase.PHASE_VARIABLE):
			_check(DayPhase.is_night(_state) == _state.get_flag(DayPhase.NIGHT_FLAG), "Every phase notification contains matching variable and flag")
	)
	_check_initial()
	_check_transitions()
	_check_persistence()
	_check_exit_gate()
	_check_travel_gate()
	await _check_fade_gate()
	print("DAY_PHASE: ", "PASS" if _failures.is_empty() else "FAIL")
	quit(0 if _failures.is_empty() else 1)

func _check_initial() -> void:
	_check(DayPhase.get_phase(_state) == DayPhase.DAY_PHASE, "New session starts in the day phase")
	_check(not DayPhase.is_night(_state), "New session is not at night")
	_check(not _state.get_flag(DayPhase.NIGHT_FLAG), "Night flag starts false")

func _check_transitions() -> void:
	_state.state_changed.connect(func() -> void:
		_check(not DayPhase.enter_day(_state), "Synchronous observer cannot reverse a phase transaction")
	, CONNECT_ONE_SHOT)
	_check(DayPhase.enter_night(_state), "Day advances to night")
	_check(_state.get_variable(DayPhase.PHASE_VARIABLE) == DayPhase.NIGHT_PHASE, "Phase variable records night")
	_check(_state.get_flag(DayPhase.NIGHT_FLAG), "Night flag mirrors the phase")
	_check(DayPhase.is_night(_state), "is_night follows the phase")
	_check(not DayPhase.enter_night(_state), "Repeated enter_night is a no-op")
	_check(DayPhase.get_phase(_state) == DayPhase.NIGHT_PHASE and _state.get_flag(DayPhase.NIGHT_FLAG), "Repeated enter_night keeps the state")
	_check(DayPhase.enter_day(_state), "Night returns to day")
	_check(_state.current_day == 2, "Night to day advances current_day exactly once")
	_check(_state.get_variable(DayPhase.PHASE_VARIABLE) == DayPhase.DAY_PHASE, "Phase variable records day")
	_check(not _state.get_flag(DayPhase.NIGHT_FLAG), "Night flag clears with the phase")
	_check(not DayPhase.is_night(_state), "Phase variable reports day")
	_check(not DayPhase.enter_day(_state), "Repeated enter_day is a no-op")

func _check_persistence() -> void:
	DayPhase.enter_night(_state)
	var night_snapshot: Dictionary = _state.to_dict()
	_check(night_snapshot.variables.get(DayPhase.PHASE_VARIABLE) == DayPhase.NIGHT_PHASE, "Snapshot carries the phase variable")
	_check(DayPhase.enter_day(_state), "Session returns to day before restore")
	_check(_state.restore_state(night_snapshot) == OK, "Night snapshot restores")
	_check(DayPhase.is_night(_state) and _state.get_flag(DayPhase.NIGHT_FLAG), "Restored session is still at night")
	_check(DayPhase.enter_day(_state), "Restored night advances back to day")
	var day_snapshot: Dictionary = _state.to_dict()
	_check(DayPhase.enter_night(_state), "Session advances to night before the day restore")
	_check(_state.restore_state(day_snapshot) == OK, "Day snapshot restores")
	_check(not DayPhase.is_night(_state) and not _state.get_flag(DayPhase.NIGHT_FLAG), "Restored session is still in the day phase")

func _check_exit_gate() -> void:
	var exit := SceneExit.new()
	_check(exit.are_conditions_met(_state), "Exit without required flags is open")
	exit.required_flags.append(EXIT_OPEN)
	_check(not exit.are_conditions_met(_state), "Missing required flag closes the exit")
	_state.set_flag(String(EXIT_OPEN), true)
	_check(exit.are_conditions_met(_state), "Required flag opens the exit")
	_state.set_flag(String(EXIT_OPEN), false)
	_check(not exit.are_conditions_met(_state), "Cleared flag closes the exit again")
	_check(not exit.are_conditions_met(null), "Missing state fails closed")
	exit.free()

func _check_travel_gate() -> void:
	var travel := SceneTravel.new()
	var visual := ScreenTransition.new()
	travel.configure(visual, func() -> bool: return true)
	var errors: Array[int] = []
	travel.travel_failed.connect(func(_point: SceneExit, error: Error) -> void: errors.append(error))
	var exit := SceneExit.new()
	exit.destination_scene = "res://missing_gated_destination.tscn"
	exit.destination_entrance = &"shop_door"
	exit.required_flags.append(EXIT_OPEN)
	_check(travel.request_exit(exit) == ERR_UNAVAILABLE, "Gated exit refuses travel before destination checks")
	_check(errors == [ERR_UNAVAILABLE], "Gated exit reports travel_failed once")
	_check(not travel.is_busy(), "Gated exit never claims the travel lock")
	travel.free()
	visual.free()
	exit.free()

func _check_fade_gate() -> void:
	_state.set_flag(String(EXIT_OPEN), true)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var visual: ScreenTransition = load("res://src/UI/screen_transition/screen_transition.tscn").instantiate()
	layer.add_child(visual)
	var travel := SceneTravel.new()
	root.add_child(travel)
	travel.fade_seconds = 0.0
	travel.configure(visual, func() -> bool: return true)
	var point := SceneExit.new()
	point.destination_scene = "res://src/core/main.tscn"
	point.destination_entrance = &"street_door"
	point.required_flags.append(EXIT_OPEN)
	var failures: Array[int] = []
	travel.travel_failed.connect(func(_point: SceneExit, error: Error) -> void: failures.append(error))
	_check(travel.request_exit(point) == OK, "Valid gate starts travel")
	_state.set_flag(String(EXIT_OPEN), false)
	for index in range(6):
		await process_frame
	_check(not travel.is_busy() and failures == [ERR_UNAVAILABLE], "Revoking a gate during fade aborts before scene replacement")
	_check(current_scene == null, "Failed fade leaves the source scene intact")
	travel.queue_free()
	layer.queue_free()
	point.free()
	await process_frame
