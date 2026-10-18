class_name Day1ChapterController
extends Node
## S03-S06 and the Day 2 placeholder: composition only, in both the shop and the
## settlement. Event order, gameplay waits and actor placement are data in SETUP;
## this node loads them, starts eligible automatic events and derives declared facts.

const SETUP := "res://src/resources/story/day1_stages_03_06_setup.json"
## The Day 1 task catalog is the union of both chapter files; IDs stay unique.
const TASK_FILES: Array[String] = [
	"res://src/resources/tasks/day1_stages_01_02.json",
	"res://src/resources/tasks/day1_stages_03_06.json",
	"res://src/resources/tasks/day1_daily_orders.json",
	"res://src/resources/tasks/day2_stages_01_05.json",
]
const SOUND_LIBRARY := "res://src/resources/audio/sound_library.tres"
const SETUP_KEYS := ["story", "dialogue", "phases", "auto_events", "derived_facts", "scene_setups"]
const DAY2_SETUP := "res://src/resources/story/day2_stages_01_05_setup.json"

var last_error := ""
var _game: MainGame
var _state: Node
var _setup: Dictionary = {}
var _host := ""
var _loaded := false
var _auto_pending := false
var _refresh_pending := false
var _staged_for := "__unstaged__"
var _failed_auto_events: Dictionary = {}
var _recovery_blocked := false

## The settlement has no other story host, so it owns every Day 1 stage there
## (including the S02 -> S03 hand-off). In the shop it owns only S03 onward.
static func owns_stage(state: Node, host: String) -> bool:
	return host != "shop" or state.story_stage == "day1.investigate_coins" or Day1Access.is_later_stage(state) or Day1Access.is_day2_placeholder(state) or Day1Access.at_stage(state, "day3")

func configure(game: MainGame, host: String) -> Error:
	_game = game
	_host = host
	_state = get_node("/root/GameState")
	var error := _load_setup(SETUP)
	if error != OK:
		push_error(last_error)
		return error
	if host == "settlement":
		# The shop registers the library in Day1ShopController; each host has its own AudioManager.
		var errors: PackedStringArray = load(SOUND_LIBRARY).register_all(game.get_audio_manager())
		if not errors.is_empty():
			push_warning("Settlement audio: " + "; ".join(errors))
	_state.state_changed.connect(_schedule_refresh)
	_state.state_reset.connect(_on_session_replaced)
	_state.state_restored.connect(_on_session_replaced)
	game.get_story_director().event_finished.connect(_on_event_finished)
	_activate.call_deferred()
	return OK

## Validates the whole setup before use. Empty lists are legal: the skeleton runs.
func _load_setup(path: String) -> Error:
	var parser := JSON.new()
	if not FileAccess.file_exists(path) or parser.parse(FileAccess.get_file_as_string(path)) != OK:
		last_error = "Chapter setup missing or not JSON: " + path
		return ERR_PARSE_ERROR
	var data: Variant = parser.data
	if not data is Dictionary or not data.has_all(SETUP_KEYS) or data.size() != SETUP_KEYS.size():
		last_error = "Chapter setup requires exactly: " + ", ".join(SETUP_KEYS)
		return ERR_INVALID_DATA
	for key: String in ["story", "dialogue", "phases"]:
		if not data[key] is String or not (data[key].begins_with("res://") or data[key].begins_with("user://")):
			last_error = "Chapter setup %s must be a res:// or user:// path" % key
			return ERR_INVALID_DATA
	for key: String in ["auto_events", "derived_facts", "scene_setups"]:
		if not data[key] is Array:
			last_error = "Chapter setup %s must be an array" % key
			return ERR_INVALID_DATA
	for entry: Variant in data.auto_events:
		var id: Variant = entry.get("id") if entry is Dictionary else entry
		if not StoryLibrary.is_namespaced(id):
			last_error = "auto_events requires namespaced event IDs"
			return ERR_INVALID_DATA
	for fact: Variant in data.derived_facts:
		if not fact is Dictionary or not fact.has_all(["flag", "stage", "all_flags"]) or fact.size() != 3:
			last_error = "derived_facts entries require flag, stage and all_flags"
			return ERR_INVALID_DATA
		if not StoryLibrary.is_namespaced(fact.flag) or not fact.stage is String or not fact.all_flags is Array or fact.all_flags.is_empty():
			last_error = "derived_facts requires a namespaced flag, a stage and a non-empty all_flags"
			return ERR_INVALID_DATA
		for key: Variant in fact.all_flags:
			if not StoryLibrary.is_namespaced(key) or key == fact.flag:
				last_error = "derived_facts all_flags must be namespaced and differ from the output"
				return ERR_INVALID_DATA
	for scene_setup: Variant in data.scene_setups:
		if not scene_setup is Dictionary or not scene_setup.has_all(["host", "stage", "actors"]) or scene_setup.size() != 3:
			last_error = "scene_setups entries require host, stage and actors"
			return ERR_INVALID_DATA
		if scene_setup.host not in ["shop", "settlement", "tavern", "casino", "elder_house"] or not scene_setup.stage is String or not scene_setup.actors is Dictionary:
			last_error = "scene_setups host must be shop or settlement; actors an object"
			return ERR_INVALID_DATA
		for actor: Variant in scene_setup.actors:
			var marker: Variant = scene_setup.actors[actor]
			if not actor is String or not (marker == null or (marker is String and not marker.is_empty())):
				last_error = "scene_setups actors map actor IDs to a Marker name or null (hidden)"
				return ERR_INVALID_DATA
	_setup = data
	return OK

func _on_session_replaced() -> void:
	_recovery_blocked = false
	_loaded = false
	_auto_pending = false
	_failed_auto_events.clear()
	_staged_for = "__unstaged__"
	_activate.call_deferred()

func _on_event_finished(id: String, ok: bool, _reason: String) -> void:
	_recovery_blocked = not ok
	if id in _automatic_ids():
		if ok:
			_failed_auto_events.erase(id)
		else:
			_failed_auto_events[id] = true
	_schedule_refresh()

## Loads the chapter data once this host owns the stage, then places actors.
func _activate() -> void:
	if not is_instance_valid(_game) or not is_inside_tree() or not owns_stage(_state, _host):
		return
	var selected := DAY2_SETUP if _state.story_stage.begins_with("day2") or _state.story_stage.begins_with("day3") else SETUP
	if _setup.get("story", "") != ("res://src/resources/story/day2_stages_01_05.json" if selected == DAY2_SETUP else "res://src/resources/story/day1_stages_03_06.json"):
		if _game.get_story_director().is_busy():
			return
		_loaded = false
		if _load_setup(selected) != OK:
			return
	if not _loaded:
		var director := _game.get_story_director()
		if director.is_busy():
			# event_finished schedules the next attempt. Repeated deferred calls
			# would drain forever in this idle frame and prevent the event advancing.
			return
		var error := _game.get_dialogue_manager().load_dialogues(_setup.dialogue)
		if error == OK:
			error = director.load_events(_setup.story)
		if error == OK:
			error = _game.get_gameplay_bridge().load_phases(_setup.phases)
		if error != OK:
			last_error = "Day 1 chapter load failed (%s): %s %s" % [error_string(error), director.last_error, _game.get_gameplay_bridge().last_error]
			push_error(last_error)
			return
		_loaded = true
		last_error = ""
	apply_scene_setup()
	_mark_shop_exit()
	_schedule_refresh()

## Real travel only: the shop door must actually lead here, not a stage switch.
func _mark_shop_exit() -> void:
	if _host != "settlement" or not _game.has_scene_arrival():
		return
	if not Day1Access.at_stage(_state, "day1.s03") or _state.get_flag("day1.s03.exited_shop"):
		return
	_state.set_flag("day1.s03.exited_shop")

func is_loaded() -> bool:
	return _loaded

## Unpublished stages need an authored actor setup as well as a save declaration.
## The published S02 ending has no actors and deliberately uses an empty setup.
func preflight_recovery(stage: String, host: String) -> Error:
	var error := _load_setup(DAY2_SETUP if stage.begins_with("day2") or stage.begins_with("day3") else SETUP)
	if error != OK:
		return error
	if stage != "day1.investigate_coins":
		var found := false
		for entry: Dictionary in _setup.scene_setups:
			found = found or (entry.stage == stage and entry.host == host)
		if not found:
			return ERR_UNCONFIGURED
	error = StoryLibrary.new().load_file(_setup.story)
	return DialogueLibrary.new().load_file(_setup.dialogue) if error == OK else error

func is_recovery_ready() -> bool:
	return _loaded and not _recovery_blocked and last_error.is_empty() and _staged_for == _state.story_stage and (_state.story_stage == "day1.investigate_coins" or not get_scene_setup().is_empty())

## The first matching entry for this host and the exact current stage, or {}.
func get_scene_setup() -> Dictionary:
	for scene_setup: Dictionary in _setup.get("scene_setups", []):
		if scene_setup.host == _host and scene_setup.stage == _state.story_stage:
			return scene_setup
	return {}

## Visibility override for Day1WorldController: true/false when the current
## stage's setup names this actor, null otherwise.
func get_staged_visibility(actor_id: StringName) -> Variant:
	if not _loaded:
		return null
	if actor_id == &"drunken_guard" and Day1Access.at_stage(_state, "day1.s05") and _state.get_flag("day1.s05.drunken_paid"):
		return false
	var actors: Dictionary = get_scene_setup().get("actors", {})
	if not actors.has(String(actor_id)):
		return null
	return actors[String(actor_id)] != null

## Rebuilt scenes recover their staging from data instead of replaying events.
func apply_scene_setup() -> void:
	_staged_for = _state.story_stage
	var scene_setup := get_scene_setup()
	if scene_setup.is_empty():
		return
	var actors := _game.get_actor_director()
	for id: String in scene_setup.actors:
		var actor := actors.get_actor(StringName(id))
		if actor == null:
			push_warning("Chapter scene setup: unknown actor " + id)
			continue
		var marker_id: Variant = scene_setup.actors[id]
		if marker_id == null:
			actor.visible = false
			continue
		var marker := actors.get_position(StringName(marker_id))
		if marker == null:
			push_warning("Chapter scene setup: unknown Marker " + str(marker_id))
			continue
		actor.teleport_to(marker.global_position)
		actor.visible = not (id == "drunken_guard" and Day1Access.at_stage(_state, "day1.s05") and _state.get_flag("day1.s05.drunken_paid"))

func _automatic_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry: Variant in _setup.get("auto_events", []):
		if entry is String:
			ids.append(entry)
		elif entry.get("host") == _host:
			ids.append(entry.id)
	return ids

func _schedule_refresh() -> void:
	if not _refresh_pending:
		_refresh_pending = true
		_refresh.call_deferred()

func _refresh() -> void:
	_refresh_pending = false
	if not is_instance_valid(_game) or not is_inside_tree():
		return
	var hud := _game.get_business_hud()
	if is_instance_valid(hud):
		hud.show_notice("")
	if not owns_stage(_state, _host):
		_loaded = false
		_auto_pending = false
		return
	if _state.story_stage.begins_with("day2") and not _setup.get("story", "").contains("day2"):
		_activate()
		return
	if not _loaded:
		if owns_stage(_state, _host):
			_activate()
		return
	_derive_facts()
	# Restage only when the stage changes; events moving actors mid-stage keep control.
	if _state.story_stage != _staged_for and not _game.get_story_director().is_busy():
		apply_scene_setup()
	_auto_pending = true

func _derive_facts() -> void:
	for fact: Dictionary in _setup.derived_facts:
		if _state.get_flag(fact.flag) or not Day1Access.at_stage(_state, fact.stage):
			continue
		if fact.all_flags.all(func(key: String) -> bool: return _state.get_flag(key)):
			_state.set_flag(fact.flag)

## Waits for the same quiet moment as the shop opening: no travel, pause, modal or story.
func _process(_delta: float) -> void:
	if not _auto_pending or not _loaded or _game.is_session_initializing():
		return
	var travel := _game.get_scene_travel()
	if (is_instance_valid(travel) and travel.is_busy()) or get_tree().paused or _game.get_ui_manager().has_modal():
		return
	var director := _game.get_story_director()
	if director.is_busy() or _game.get_dialogue_manager().is_active():
		return
	_auto_pending = false
	for id: String in _automatic_ids():
		if _failed_auto_events.has(id):
			continue
		if not director.get_event_summary(id).get("conditions_met", false) or _state.is_event_completed(id):
			continue
		var error := director.request_event(id)
		if error == OK:
			return
		# Bridge waits and host guards reject quietly; retry on the next state change.
		if error != ERR_BUSY and error != ERR_UNAUTHORIZED:
			last_error = director.last_error
			push_warning("Auto event %s: %s" % [id, last_error])
