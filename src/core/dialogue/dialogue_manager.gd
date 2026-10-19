class_name DialogueManager
extends Node
## Scene-local flow. The host owns gameplay locks and story-state changes.

signal dialogue_started(dialogue_id: String)
signal dialogue_ended(dialogue_id: String, cancelled: bool)
signal choice_selected(dialogue_id: String, line_id: String, choice_id: String)
signal line_changed(line_id: String)

@export_file("*.json") var dialogue_file: String = "res://src/resources/dialogue/example_dialogues.json"
## Player names use the left portrait slot; all other speakers use the right.
@export var left_portrait_speakers: PackedStringArray = ["主角", "主角·内心", "玩家"]
## Exact speaker names; per-line portrait paths override these defaults.
@export var speaker_portraits: Dictionary[String, Texture2D] = {
	"主角": preload("res://assets/characters/apron_man/player_talking_portrait.png"),
	"主角·内心": preload("res://assets/characters/apron_man/player_neutral_portrait.png"),
	"玩家": preload("res://assets/characters/apron_man/player_talking_portrait.png"),
	"胖哥布林": preload("res://assets/characters/goblin/goblin_smiling_portrait.png"),
	"哥布林": preload("res://assets/characters/goblin/goblin_smiling_portrait.png"),
	# The authored scenes name the same townsfolk by role; they share the one
	# finished goblin portrait instead of blinking to an empty frame.
	"哥布林甲": preload("res://assets/characters/goblin/goblin_smiling_portrait.png"),
	"哥布林乙": preload("res://assets/characters/goblin/goblin_smiling_portrait.png"),
	"哥布林丙": preload("res://assets/characters/goblin/goblin_smiling_portrait.png"),
	"哥布林顾客": preload("res://assets/characters/goblin/goblin_smiling_portrait.png"),
	"哥布林顾客甲": preload("res://assets/characters/goblin/goblin_smiling_portrait.png"),
	"哥布林顾客乙": preload("res://assets/characters/goblin/goblin_smiling_portrait.png"),
	"另一名哥布林": preload("res://assets/characters/goblin/goblin_smiling_portrait.png"),
	"酒馆老板": preload("res://assets/characters/goblin/goblin_smiling_portrait.png"),
	"赌场老板": preload("res://assets/characters/goblin/goblin_smiling_portrait.png"),
}

var last_error: String = ""
var _library := DialogueLibrary.new()
var _ui: DialogueUI
var _can_start: Callable
var _dialogue_id: String = ""
var _line_id: String = ""
var _dialogue: Dictionary = {}
var _loaded: bool = false
var _loaded_path: String = ""
var _selecting: bool = false
var _cancel_protected: bool = false


func configure(ui: DialogueUI, can_start: Callable = Callable()) -> void:
	end_dialogue(true)
	if is_instance_valid(_ui):
		_ui.advance_requested.disconnect(advance)
		_ui.choice_requested.disconnect(select_choice)
		_ui.cancel_requested.disconnect(_cancel)
		_ui.skip_requested.disconnect(skip_to_end)
		_ui.tree_exiting.disconnect(_cancel)
	_ui = ui
	_can_start = can_start
	_ui.advance_requested.connect(advance)
	_ui.choice_requested.connect(select_choice)
	_ui.cancel_requested.connect(_cancel)
	_ui.skip_requested.connect(skip_to_end)
	_ui.tree_exiting.connect(_cancel)


## Explicit reload is allowed only while idle. Failed loads preserve the library.
func load_dialogues(path: String = "") -> Error:
	if is_active():
		return ERR_BUSY
	var source := dialogue_file if path.is_empty() else path
	var error := _library.load_file(source)
	last_error = _library.last_error
	if error == OK:
		_loaded = true
		_loaded_path = source
	return error


## Path of the last successful load; empty until a catalogue is loaded, so tools
## can tell "never loaded" from the exported default.
func get_dialogue_source_path() -> String:
	return _loaded_path


func start_dialogue(id: String, cancel_protected: bool = false) -> Error:
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
	_cancel_protected = cancel_protected
	_ui.set_cancel_protected(cancel_protected)
	dialogue_started.emit(id)
	if is_active():
		return _present_line()
	return OK


func is_active() -> bool:
	return not _dialogue_id.is_empty()


func get_current_line_id() -> String:
	return _line_id


## Override the displayed image for this line only, including an explicit null to hide.
## Does not restart the line or emit line_changed. The next line resolves normally.
func set_current_portrait(portrait: Texture2D) -> Error:
	if not is_active() or not is_instance_valid(_ui) or not _ui.is_inside_tree():
		return ERR_UNCONFIGURED
	_ui.set_portrait(portrait)
	return OK


## Update a speaker default for future lines; refresh the current line unless it
## declares an explicit portrait. Null removes the default for this speaker.
func set_speaker_portrait(speaker: String, portrait: Texture2D) -> void:
	if portrait == null:
		speaker_portraits.erase(speaker)
	else:
		speaker_portraits[speaker] = portrait
	if is_active() and is_instance_valid(_ui):
		var line: Dictionary = _dialogue["lines"][_line_id]
		if line["speaker"] == speaker and not line.has("portrait"):
			_ui.set_portrait(portrait)


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


## Finish the current dialogue's remaining linear lines in one step. Choices stop
## the skip so a branch still needs a deliberate decision.
func skip_to_end() -> void:
	if not is_active() or _selecting:
		return
	var visited := {_line_id: true}
	var moved := false
	while true:
		var line: Dictionary = _dialogue["lines"][_line_id]
		if not line.get("choices", []).is_empty():
			break
		var next := String(line.get("next", ""))
		if next.is_empty():
			end_dialogue()
			return
		if visited.has(next):
			break
		visited[next] = true
		_line_id = next
		moved = true
	if not is_instance_valid(_ui):
		return
	if moved and _present_line() != OK:
		return
	_ui.reveal_all()


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
	# A listener may cancel this dialogue, or end it and start another one. The
	# old choice must never advance the replacement session.
	if _dialogue_id == selected_dialogue and _line_id == selected_line:
		_go_to(choice.get("next", ""))


func end_dialogue(cancelled: bool = false) -> void:
	if not is_active():
		return
	var id := _dialogue_id
	_dialogue_id = ""
	_line_id = ""
	_dialogue = {}
	_cancel_protected = false
	if is_instance_valid(_ui):
		_ui.set_cancel_protected(false)
		_ui.close_dialogue()
	dialogue_ended.emit(id, cancelled)


func _go_to(line_id: String) -> void:
	if line_id.is_empty():
		end_dialogue()
	else:
		_line_id = line_id
		_present_line()


func _present_line() -> Error:
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
	var error := _ui.present_line(line["speaker"], line["text"], portrait, choices, line["speaker"] in left_portrait_speakers)
	if error != OK:
		# Dropping the line would leave the host's input lock on with no visible
		# dialogue, so the session ends instead.
		last_error = "Dialogue UI could not present a line: %s" % error_string(error)
		end_dialogue(true)
		return error
	line_changed.emit(_line_id)
	return OK


func _cancel() -> void:
	end_dialogue(true)


func _exit_tree() -> void:
	end_dialogue(true)
