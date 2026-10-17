extends SceneTree

const StateScript = preload("res://src/core/game_state.gd")

var _state: StateScript
var _checks: int = 0
var _failures: Array[String] = []
var _changes: Array[Dictionary] = []
var _events: Array[String] = []
var _resets: int = 0
var _restores: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)


func _run() -> void:
	_state = StateScript.new()
	root.add_child(_state)
	_state.state_changed.connect(func() -> void: _changes.append(_state.to_dict()))
	_state.event_completed.connect(func(event_id: String) -> void: _events.append(event_id))
	_state.state_reset.connect(func() -> void: _resets += 1)
	_state.state_restored.connect(func() -> void: _restores += 1)
	_test_defaults()
	_test_writes_and_signals()
	_test_container_isolation()
	_test_restore()
	_test_invalid_input()
	_test_reset()
	await _test_autoload_lifetime()
	_state.free()
	print("GAME_STATE: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _test_defaults() -> void:
	_check(_state.current_day == 1, "New game starts on day 1")
	_check(_state.story_stage.is_empty(), "New game has no selected story stage")
	_check(_state.get_flags().is_empty() and _state.get_variables().is_empty() and _state.get_completed_events().is_empty(), "Story collections start empty")
	_check(not _state.get_flag("day1.unknown") and _state.get_flag("day1.unknown", true), "Missing flag respects the default")
	_check(not _state.has_flag("day1.unknown"), "Flag reads do not create keys")
	_check(_state.get_variable("day1.unknown", 7) == 7 and _state.get_variable("day1.unknown") == null, "Missing variable respects the default")
	_check(not _state.has_variable("day1.unknown") and not _state.is_event_completed("day1.arrival"), "Unknown variables and events do not exist")
	_check(not _state.reset_state() and _changes.is_empty() and _resets == 0, "Resetting default state is silent")


func _test_writes_and_signals() -> void:
	_check(_state.set_current_day(2), "Day setter accepts a positive day")
	_check(_changes.size() == 1 and _changes.back()["current_day"] == 2, "Change signal observes the committed day")
	_check(not _state.set_current_day(2) and not _state.set_current_day(0) and not _state.set_current_day(-1), "Duplicate and invalid days are rejected")
	_state.current_day = 3
	_check(_state.current_day == 3 and _changes.size() == 2, "Property assignment uses the day setter")
	_check(_state.set_story_stage("day1.opening") and not _state.set_story_stage("day1.opening"), "Stage writes suppress duplicates")
	_state.story_stage = "day1.orders"
	_check(_state.story_stage == "day1.orders" and _changes.size() == 4, "Stage property assignment emits one change")
	_check(_state.set_flag("day1.order_checked") and _state.get_flag("day1.order_checked"), "Namespaced flag can be set and read")
	_check(not _state.set_flag("day1.order_checked") and _changes.size() == 5, "Duplicate flag is silent")
	_check(_state.set_flag("day1.order_checked", false) and _state.has_flag("day1.order_checked") and not _state.get_flag("day1.order_checked"), "Flag can change to explicit false")
	_check(_state.set_flag("day2.order_checked") and not _state.get_flag("day1.order_checked"), "Namespaces keep similar flag names independent")
	_check(_state.set_variable("day1.orders", 1) and not _state.set_variable("day1.orders", 1), "Variable writes suppress duplicate values")
	_check(_state.set_variable("day1.orders", 1.0) and typeof(_state.get_variable("day1.orders")) == TYPE_FLOAT, "Changing a number's type is a real change")
	_check(_state.set_variable("day1.optional", null) and _state.has_variable("day1.optional"), "Explicit null differs from an absent variable")
	_check(not _state.set_variable("day1.optional", null), "Duplicate null is silent")
	var before := _changes.size()
	_check(_state.complete_event("day1.arrival") and _state.is_event_completed("day1.arrival"), "One-shot event can be completed")
	_check(not _state.complete_event("day1.arrival"), "One-shot event cannot complete twice")
	_check(_events == ["day1.arrival"] and _changes.size() == before + 1, "Event completion emits exactly one event and state notification")


func _test_container_isolation() -> void:
	var source := {"orders": [{"tea": "oolong", "count": 2}], "paid": false}
	_check(_state.set_variable("day1.order_data", source), "Nested story data is supported")
	source["orders"][0]["count"] = 99
	var value: Dictionary = _state.get_variable("day1.order_data")
	_check(value["orders"][0]["count"] == 2, "Mutating the setter input cannot change stored state")
	value["orders"][0]["count"] = 88
	_check(_state.get_variable("day1.order_data")["orders"][0]["count"] == 2, "Variable reads return deep copies")
	var variables := _state.get_variables()
	variables["day1.order_data"]["orders"].clear()
	var flags := _state.get_flags()
	flags["day1.order_checked"] = true
	var events := _state.get_completed_events()
	events.clear()
	_check(_state.get_variable("day1.order_data")["orders"].size() == 1 and not _state.get_flag("day1.order_checked") and _state.is_event_completed("day1.arrival"), "Collection getters cannot expose mutable state")
	var before := _changes.size()
	_check(not _state.set_variable("day1.order_data", {"paid": false, "orders": [{"tea": "oolong", "count": 2}]}), "Equal dictionaries with different insertion order are silent")
	_check(_state.set_variable("day1.order_data", {"paid": false, "orders": [{"tea": "oolong", "count": 2.0}]}), "Nested numeric type changes are preserved")
	_check(_changes.size() == before + 1, "Only the nested type change emits a notification")
	_changes.back()["variables"]["day1.order_data"]["orders"].clear()
	_check(_state.get_variable("day1.order_data")["orders"].size() == 1, "Notification observer snapshots cannot mutate live state")


func _test_restore() -> void:
	var snapshot := _state.to_dict()
	_check(snapshot["schema_version"] == 2, "Snapshots include their schema version")
	var fresh := StateScript.new()
	_check(fresh.restore_state(snapshot) == OK and fresh.to_dict() == snapshot, "Snapshot round trip restores all story and economy fields")
	snapshot["variables"]["day1.order_data"]["orders"][0]["count"] = 55
	_check(fresh.get_variable("day1.order_data")["orders"][0]["count"] == 2.0, "Restore input is deep copied")
	_check(_state.get_variable("day1.order_data")["orders"][0]["count"] == 2.0, "Serialized output is deep copied")
	fresh.free()
	var replacement := StateScript.new()
	replacement.set_current_day(7)
	replacement.set_story_stage("day7.closing")
	replacement.set_flag("day7.closed")
	replacement.set_variable("day7.total", [3, true, "tea", null, 0.5])
	replacement.complete_event("day7.goodbye")
	replacement.complete_event("day7.closing")
	var data := replacement.to_dict()
	replacement.free()
	var before := _changes.size()
	_check(_state.restore_state(data) == OK, "Valid replacement snapshot is accepted")
	_check(_changes.size() == before + 1 and _restores == 1 and _changes.back() == data, "Restore emits one notification after the entire state is replaced")
	_check(not _state.has_flag("day1.order_checked") and not _state.has_variable("day1.orders") and not _state.is_event_completed("day1.arrival"), "Restoring replaces rather than merges old data")
	_check(_events == ["day1.arrival"], "Restoring completed events does not replay event_completed")
	data["completed_events"].reverse()
	_check(_state.restore_state(data) == OK and _changes.size() == before + 1 and _restores == 1, "Identical restore is silent regardless of event order")
	data["variables"]["day7.total"][0] = 3.0
	_check(_state.restore_state(data) == OK and typeof(_state.get_variable("day7.total")[0]) == TYPE_FLOAT, "Restore preserves a nested numeric type change")
	_check(_restores == 2, "Changed restore emits state_restored once")


func _test_invalid_input() -> void:
	var baseline := _state.to_dict()
	var before := _changes.size()
	for key: String in ["", "order_checked", ".flag", "day1.", "day1..flag", "day 1.flag", "day1.bad-key"]:
		_check(not _state.set_flag(key) and not _state.set_variable(key, 1) and not _state.complete_event(key), "Reject malformed namespace: " + key)
	var object := RefCounted.new()
	for value: Variant in [object, Vector2.ONE, INF, NAN, {1: "non-string key"}, [object]]:
		_check(not _state.set_variable("day1.invalid", value), "Reject unsupported variable data")
	var cycle: Array = []
	cycle.append(cycle)
	_check(not _state.set_variable("day1.cycle", cycle), "Reject cyclic containers without recursing forever")
	cycle.clear()
	var invalid: Array[Dictionary] = [{}]
	for entry: Array in [
		["schema_version", 99], ["schema_version", 1.0],
		["current_day", 0], ["current_day", 2.5], ["current_day", true],
		["story_stage", 1], ["flags", []], ["flags", {"plain": true}],
		["flags", {"day1.flag": 1}], ["flags", {1: true}],
		["variables", []], ["variables", {"plain": 1}],
		["variables", {"day1.bad": object}], ["variables", {"day1.bad": INF}],
		["completed_events", {}], ["completed_events", ["plain"]],
		["completed_events", [3]], ["completed_events", ["day1.once", "day1.once"]],
	]:
		var data := baseline.duplicate(true)
		data[entry[0]] = entry[1]
		invalid.append(data)
	for field: String in baseline:
		var missing := baseline.duplicate(true)
		missing.erase(field)
		invalid.append(missing)
	for data: Dictionary in invalid:
		_check(_state.restore_state(data) == ERR_INVALID_DATA, "Malformed snapshot is rejected")
		_check(_state.to_dict() == baseline, "Invalid restore leaves all previous state intact")
	_check(_changes.size() == before and _restores == 2, "All invalid writes and restores are silent")


func _test_reset() -> void:
	var before := _changes.size()
	var fresh := StateScript.new()
	var defaults := fresh.to_dict()
	fresh.free()
	_check(_state.reset_state() and _state.to_dict() == defaults, "Reset restores all fields and clears events")
	_check(_changes.size() == before + 1 and _changes.back() == defaults and _resets == 1, "Reset emits one coherent state notification and one reset signal")
	_check(not _state.reset_state() and _changes.size() == before + 1 and _resets == 1, "Repeated reset is silent")


func _test_autoload_lifetime() -> void:
	var global_state := root.get_node_or_null("GameState") as StateScript
	_check(global_state != null, "Project registers GameState as an Autoload")
	if global_state == null:
		return
	_check(global_state.to_dict() == _state.to_dict(), "Autoload initializes to the same defaults as an isolated instance")
	global_state.set_flag("test.scene_persisted")
	var scene := PackedScene.new()
	var scene_root := Node.new()
	_check(scene.pack(scene_root) == OK, "Build a minimal scene for the lifecycle test")
	scene_root.free()
	for index in range(2):
		_check(change_scene_to_packed(scene) == OK, "Switch test scene")
		await scene_changed
		_check(root.get_node("GameState") == global_state and global_state.get_flag("test.scene_persisted"), "Autoload identity and data survive scene changes")
	paused = true
	_check(global_state.set_variable("test.paused", 1), "Data API is available while the game is paused")
	paused = false
	global_state.reset_state()
