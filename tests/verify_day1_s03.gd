extends SceneTree
## S03 authoring and compatibility checks. Real walking, return and unlock are
## verified through the formal hosts in verify_two_day_flow.gd.

const STORY := "res://src/resources/story/day1_stages_03_06.json"
const DIALOGUE := "res://src/resources/dialogue/day1_stages_03_06.json"
const PHASES := "res://src/resources/story/day1_stages_03_06_phases.json"
const SETUP := "res://src/resources/story/day1_stages_03_06_setup.json"
const MAP := "res://src/levels/settlement/settlement_map.tscn"

var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)
		push_error(message)

func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _run() -> void:
	_check(StoryLibrary.new().load_file(STORY) == OK, "Authored S03 events compile")
	_check(DialogueLibrary.new().load_file(DIALOGUE) == OK, "Authored S03 dialogue compiles")

	var story := _json(STORY)
	var events: Dictionary = story.get("events", {})
	for id: String in ["day1.s03.coin_inspect", "day1.s03.street_gone", "day1.s03.back_to_door"]:
		_check(events.has(id), "Event exists: " + id)
		_check(events.get(id, {}).get("once", false), "Event plays once: " + id)
	_check(not events.has("day1.s03.limited_exploration"), "Exploration stays player-driven, not an event")

	var dialogue: Dictionary = _json(DIALOGUE).get("dialogues", {})
	for id: String in ["day1.s03.coin_inspect", "day1.s03.street_gone", "day1.s03.limited_exploration", "day1.s03.back_to_door"]:
		_check(dialogue.has(id), "Dialogue exists: " + id)
	_check(dialogue.get("day1.s03.back_to_door", {}).get("lines", {}).get("line_1", {}).get("text", "") == "……完了，我这店不会真穿越了吧？", "Back-to-door line keeps the authored wording")

	var phases: Array = _json(PHASES).get("phases", [])
	_check(_json(PHASES).get("version", 0) == 2, "Bridge phase file uses schema version 2")
	for phase: Dictionary in phases:
		_check(events.has(phase.get("after_event", "")), "Phase follows a real event")
		_check(events.has(phase.get("next_event", "")), "Phase continues into a real event")
	var returning: Dictionary = events["day1.s03.back_to_door"].conditions.flags
	_check(returning.get("day1.s03.exploration_completed", false) and returning.get("day1.s03.returned_to_door", false), "Reflection waits until the player has observed the market and returned to the door")

	var setup := _json(SETUP)
	_check(setup.size() == 6 and setup.has_all(Day1ChapterController.SETUP_KEYS), "Chapter setup keeps exactly the six required keys")
	var auto: Array = setup.get("auto_events", [])
	for id: String in ["day1.s03.coin_inspect", "day1.s03.street_gone", "day1.s03.back_to_door"]:
		_check(auto.any(func(entry: Dictionary) -> bool: return entry.id == id), "Auto event is registered: " + id)
	var facts: Array = setup.get("derived_facts", [])
	_check(facts.size() == 1, "One derived fact closes exploration")
	var fact: Dictionary = facts[0] if not facts.is_empty() else {}
	_check(fact.get("flag", "") == "day1.s03.exploration_completed" and fact.get("stage", "") == "day1.s03.explore", "Derived fact targets the exploration substage")

	_check(fact.get("all_flags", []) == ["day1.s03.observed_yard"], "Walking through the market is the only required observation")
	var map_text := FileAccess.get_file_as_string(MAP)
	for guard: Array in [
		["day1_s03_yard", "day1.s03.observed_yard", "明亮的摊位区"],
		["day1_s03_street", "day1.s03.observed_street", "空荡荡的街道"],
		["day1_s03_path", "day1.s03.observed_path", "昏暗的洞窟岔路"],
	]:
		_check(map_text.contains("[node name=\"%s\"" % guard[0]), "Observation point exists: " + guard[0])
		_check(map_text.contains("\"%s\"" % guard[1]), "Observation point writes its own flag: " + guard[1])
		_check(map_text.contains(guard[2]), "Observation point keeps its authored title: " + guard[2])

	_check(map_text.contains("required_stages = Array[String]([\"day1.s03\"])"), "Observation points stay gated to S03")

	var packed := load(MAP) as PackedScene
	_check(packed != null, "Settlement map compiles with the new points")
	if packed != null:
		var map := packed.instantiate()
		_check(map != null, "Settlement map instantiates")
		if map != null:
			for guard: Array in [
				["day1_s03_yard", "day1.s03.observed_yard"],
				["day1_s03_street", "day1.s03.observed_street"],
				["day1_s03_path", "day1.s03.observed_path"],
			]:
				var node := map.get_node_or_null("InteractionPoints/" + guard[0])
				_check(node is StoryInteractionPoint, "Point is a story interaction: " + guard[0])
				if node is StoryInteractionPoint:
					_check(node.kind == StoryInteractionPoint.Kind.DOCUMENT, "Point reads as a document: " + guard[0])
					_check(String(node.entry_id) == guard[0], "Point entry id matches its node: " + guard[0])
					_check(String(guard[1]) in node.success_flags, "Point commits " + guard[1])
					_check(node.required_stages.has("day1.s03"), "Point requires the street stage: " + guard[0])
					_check(node.conditions_met() == false, "Point stays closed without GameState")
			map.free()

	var street := _stage_state("day1.s03.explore")
	_check(Day1Access.at_stage(street, "day1.s03"), "S03 substages still count as the street stage")
	street.free()
	var earlier := _stage_state("day1.s02")
	_check(not Day1Access.at_stage(earlier, "day1.s03"), "Earlier stages do not open the street")
	earlier.free()

	print("DAY1_S03: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _stage_state(stage: String) -> Node:
	var node := Node.new()
	node.set_script(load("res://src/core/game_state.gd"))
	node.story_stage = stage
	return node
