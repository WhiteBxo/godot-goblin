extends Node
## Demo-only data and controls; MainGame remains the production host.

@onready var _game: MainGame = $MainGame
@onready var _status: Label = $DemoLayer/Panel/Content/Status
@onready var _director: StoryDirector = _game.get_story_director()


func _ready() -> void:
	var error := _game.get_dialogue_manager().load_dialogues("res://src/resources/dialogue/day1_demo_dialogues.json")
	if error == OK:
		error = _director.load_events("res://src/resources/story/day1_demo_events.json")
	if error != OK:
		_status.text = "加载失败：%s / %s" % [_director.last_error, _game.get_dialogue_manager().last_error]
		return
	_director.event_finished.connect(_on_finished)
	_director.step_started.connect(_on_step)
	_director.choice_received.connect(func(_event: String, _dialogue: String, _line: String, choice: String) -> void: _status.text = "选择：" + choice)
	$DemoLayer/Panel/Content/Buttons/Intro.pressed.connect(_start_intro)
	$DemoLayer/Panel/Content/Buttons/Cancel.pressed.connect(func() -> void: _director.cancel_event("Demo cancel"))
	_start_intro()


func _start_intro() -> void:
	var error := _director.request_event("day1.intro")
	if error != OK:
		_status.text = "未启动（%d）：%s" % [error, _director.last_error]


func _on_step(_id: String, index: int, command: String) -> void:
	_status.text = "步骤 %d · %s" % [index + 1, command]


func _on_finished(id: String, succeeded: bool, reason: String) -> void:
	_status.text = "%s · %s" % [id, "完成" if succeeded else reason]
