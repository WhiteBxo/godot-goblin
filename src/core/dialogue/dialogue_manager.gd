class_name DialogueManager
extends Node
## Scene-local flow. The host owns gameplay locks and story-state changes.

signal dialogue_started(dialogue_id: String)
signal dialogue_ended(dialogue_id: String, cancelled: bool)
signal choice_selected(dialogue_id: String, line_id: String, choice_id: String)
signal line_changed(line_id: String)

@export_file("*.json") var dialogue_file: String = "res://src/resources/dialogue/example_dialogues.json"
## Exact speaker names; per-line portrait paths override these defaults.
@export var speaker_portraits: Dictionary[String, Texture2D] = {
	"主角": preload("res://assets/characters/apron_man/apron_man_full_body.jpg"),
	"主角·内心": preload("res://assets/characters/apron_man/apron_man_full_body.jpg"),
	"玩家": preload("res://assets/characters/apron_man/apron_man_full_body.jpg"),
	"胖哥布林": preload("res://assets/characters/goblin/goblin_smiling.png"),
	"哥布林": preload("res://assets/characters/goblin/goblin_smiling.png"),
}

var last_error: String = ""
var _library := DialogueLibrary.new()
var _ui: DialogueUI
var _can_start: Callable
var _dialogue_id: String = ""
var _line_id: String = ""
var _dialogue: Dictionary = {}
var _loaded: bool = false
var _selecting: bool = false


func configure(ui: DialogueUI, can_start: Callable = Callable()) -> void:
	end_dialogue(true)
	if is_instance_valid(_ui):
		_ui.advance_requested.disconnect(advance)
		_ui.choice_requested.disconnect(select_choice)
		_ui.cancel_requested.disconnect(_cancel)
		_ui.tree_exiting.disconnect(_cancel)
	_ui = ui
	_can_start = can_start
	_ui.advance_requested.connect(advance)
	_ui.choice_requested.connect(select_choice)
	_ui.cancel_requested.connect(_cancel)
	_ui.tree_exiting.connect(_cancel)


## Explicit reload is allowed only while idle. Failed loads preserve the library.
func load_dialogues(path: String = "") -> Error:
	if is_active():
		return ERR_BUSY
	var error := _library.load_file(dialogue_file if path.is_empty() else path)
	last_error = _library.last_error
	if error == OK:
		_loaded = true
	return error


func start_dialogue(id: String) -> Error:
	last_error = ""
	if is_active() or _selecting or (_can_start.is_valid() and not _can_start.call()):
		return ERR_BUSY
	if not is_instance_valid(_ui) or not _ui.is_inside_tree():
		return ERR_UNCONFIGURED
	if not _loaded:
		var error := load_dialogues()
		if error != OK:
			return error
	if not _library.has_dialogue(id):
		last_error = "Unknown dialogue ID: " + id
		return ERR_DOES_NOT_EXIST
	_dialogue = _library.get_dialogue(id)
	_dialogue_id = id
	_line_id = _dialogue["start"]
	dialogue_started.emit(id)
	if is_active():
		_present_line()
	return OK


func is_active() -> bool:
	return not _dialogue_id.is_empty()


func get_current_line_id() -> String:
	return _line_id


func advance() -> void:
	if not is_active() or _selecting:
		return
	if _ui.is_revealing():
		_ui.reveal_all()
		return
	var line: Dictionary = _dialogue["lines"][_line_id]
	if not line.get("choices", []).is_empty():
		return
	_go_to(line.get("next", ""))


func select_choice(index: int) -> void:
	if not is_active() or _selecting or _ui.is_revealing():
		return
	var choices: Array = _dialogue["lines"][_line_id].get("choices", [])
	if index < 0 or index >= choices.size():
		return
	var choice: Dictionary = choices[index]
	var selected_dialogue := _dialogue_id
	var selected_line := _line_id
	_selecting = true
	choice_selected.emit(selected_dialogue, selected_line, choice["id"])
	_selecting = false
	# A listener may cancel the session. Never advance an already-ended dialogue.
	if is_active():
		_go_to(choice.get("next", ""))


func end_dialogue(cancelled: bool = false) -> void:
	if not is_active():
		return
	var id := _dialogue_id
	_dialogue_id = ""
	_line_id = ""
	_dialogue = {}
	if is_instance_valid(_ui):
		_ui.close_dialogue()
	dialogue_ended.emit(id, cancelled)


func _go_to(line_id: String) -> void:
	if line_id.is_empty():
		end_dialogue()
	else:
		_line_id = line_id
		_present_line()


func _present_line() -> void:
	var line: Dictionary = _dialogue["lines"][_line_id]
	var portrait: Texture2D = speaker_portraits.get(line["speaker"])
	if line.has("portrait"):
		# An explicit empty path suppresses even a configured speaker portrait.
		portrait = null
	if not line.get("portrait", "").is_empty():
		portrait = load(line["portrait"]) as Texture2D
	var choices: Array[String] = []
	for choice: Dictionary in line.get("choices", []):
		choices.append(choice["text"])
	_ui.present_line(line["speaker"], line["text"], portrait, choices)
	line_changed.emit(_line_id)


func _cancel() -> void:
	end_dialogue(true)


func _exit_tree() -> void:
	end_dialogue(true)
