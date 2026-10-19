class_name ChapterServicePoint
extends InteractionPoint
## Authored stage prompts; the existing StoryDirector route owns every event.

@export var stage_prompts: Dictionary[String, String] = {}
var _state: Node
var _default_name := ""

func _ready() -> void:
	super._ready()
	_state = get_node("/root/GameState")
	_default_name = display_name
	_state.state_changed.connect(_refresh_prompt)
	_refresh_prompt()

func _refresh_prompt() -> void:
	display_name = stage_prompts.get(_state.story_stage, _default_name)
	availability_changed.emit(self, is_available())

func is_available() -> bool:
	return super.is_available() and is_instance_valid(_state) and stage_prompts.has(_state.story_stage)
