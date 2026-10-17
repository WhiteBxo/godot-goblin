class_name Day1ShopController
extends Node
## Composition and checkpoint projection only. Event sequence and gameplay links are data.

const SETUP := "res://src/resources/story/day1_stages_01_02_setup.json"
const STORY := "res://src/resources/story/day1_stages_01_02.json"
const DIALOGUE := "res://src/resources/dialogue/day1_stages_01_02.json"
const PHASES := "res://src/resources/story/day1_stages_01_02_phases.json"

var _game: MainGame
var _state: Node
var _setup: Dictionary
var _opening_pending := false
var last_error := ""

func configure(game: MainGame) -> Error:
	_game = game
	_state = get_node("/root/GameState")
	_setup = JSON.parse_string(FileAccess.get_file_as_string(SETUP))
	var actors := game.get_actor_director()
	for marker: Marker2D in game.get_active_level().get_story_positions():
		actors.register_position(StringName(marker.name), marker)
	var errors: PackedStringArray = preload("res://src/resources/audio/sound_library.tres").register_all(game.get_audio_manager())
	if not errors.is_empty():
		last_error = "; ".join(errors)
		return ERR_INVALID_DATA
	var batches: Array[Dictionary] = []
	for batch: Dictionary in _setup.batches:
		batches.append(batch)
	game.get_task_delivery().configure_batches(batches)
	var legacy := actors.get_actor(&"fat_goblin")
	if is_instance_valid(legacy):
		legacy.hide()
	_game.get_business_hud().resume_requested.connect(_schedule_resume)
	_state.state_reset.connect(_schedule_resume)
	_state.state_restored.connect(_schedule_resume)
	_state.state_changed.connect(_refresh)
	game.get_tea_production().changed.connect(_refresh)
	game.get_story_director().event_finished.connect(_event_finished)
	game.get_gameplay_bridge().continuation_failed.connect(func(_id: String, _error: Error) -> void: _show_resume())
	_resume_boundary.call_deferred(game.has_scene_arrival())
	return OK

func _schedule_resume() -> void:
	_opening_pending = false
	_resume_boundary.call_deferred()

func _resume_boundary(preserve_player_position: bool = false) -> void:
	if not is_instance_valid(_game) or not is_inside_tree():
		return
	last_error = ""
	var director := _game.get_story_director()
	var bridge := _game.get_gameplay_bridge()
	bridge.stop(true)
	director.cancel_event("Resume checkpoint")
	var ui := _game.get_ui_manager()
	for id: StringName in [&"shop", &"chronicle"]:
		ui.close_screen(id)
	_game.get_camera_director().cancel_all("Resume checkpoint")
	var error := _game.get_dialogue_manager().load_dialogues(DIALOGUE)
	if error == OK:
		error = director.load_events(STORY)
	if error != OK:
		last_error = "Day 1 story load failed: %d" % error
		push_error(last_error)
		_show_resume()
		return
	var checkpoint: Dictionary = {}
	for candidate: Dictionary in _setup.checkpoints:
		if candidate.event.is_empty() or _state.is_event_completed(candidate.event):
			checkpoint = candidate
			break
	var positions := {}
	for marker: Marker2D in _game.get_active_level().get_story_positions():
		positions[String(marker.name)] = marker.global_position
	if not preserve_player_position:
		_game.get_player().teleport_to(positions.day1_player)
	var actors := _game.get_actor_director()
	for id: String in _setup.actors:
		var actor := actors.get_actor(StringName(id))
		actor.teleport_to(positions[checkpoint.actors.get(id, "day1_door")])
		actor.visible = checkpoint.actors.has(id)
	_state.set_story_stage(checkpoint.stage)
	# A recreated scene needs the current scene music, without replaying an event.
	if not checkpoint.event.is_empty() and _game.get_audio_manager().get_bgm_state().id.is_empty():
		_game.get_audio_manager().play_bgm("music.daily_milk_tea", 1.0, -12.0)
	error = bridge.load_phases(PHASES)
	if error != OK:
		last_error = bridge.last_error
		push_error(last_error)
		_show_resume()
		return
	_game.get_business_hud().show_resume(false)
	_opening_pending = checkpoint.event.is_empty()
	_refresh()

func _process(_delta: float) -> void:
	if _opening_pending and (not is_instance_valid(_game.get_scene_travel()) or not _game.get_scene_travel().is_busy()) and not get_tree().paused and not _game.get_ui_manager().has_modal() and not _game.get_story_director().is_busy():
		_opening_pending = false
		var error := _game.get_story_director().request_event(_setup.opening_event)
		if error != OK:
			last_error = _game.get_story_director().last_error
			_show_resume()

func _event_finished(_id: String, ok: bool, _reason: String) -> void:
	if not ok:
		_show_resume()
	_refresh()

func _show_resume() -> void:
	if is_instance_valid(_game.get_business_hud()):
		_game.get_business_hud().show_resume(true)

func _refresh() -> void:
	if is_inside_tree() and is_instance_valid(_game) and _game.is_inside_tree():
		_game.refresh_day1_access()
