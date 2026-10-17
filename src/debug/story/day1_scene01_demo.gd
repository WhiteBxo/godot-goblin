extends Node
## Trial composition only. Dialogue and presentation order live in JSON.

@export var autoplay := true
@export_file("*.json") var dialogue_file := "res://src/resources/dialogue/day1_scene01.json"
@export_file("*.json") var story_file := "res://src/resources/story/day1_scene01.json"
@onready var _game: MainGame = $MainGame
@onready var _status: Label = $DemoLayer/Panel/Content/Status

func _ready() -> void:
	if not OS.has_feature("debug"):
		$DemoLayer.hide()
		return
	var actors := _game.get_actor_director()
	$Positions.global_transform = _game.get_active_level().global_transform
	for marker: Node in $Positions.get_children():
		actors.register_position(StringName(marker.name), marker as Marker2D)
	_game.get_audio_manager().register_sound("shop.door_bell", preload("res://assets/audio/shop/door_bell.wav"))
	var director := _game.get_story_director()
	var error := _game.get_dialogue_manager().load_dialogues(dialogue_file)
	if error == OK:
		error = director.load_events(story_file)
	if error != OK:
		_status.text = "加载失败：%s / %s" % [director.last_error, _game.get_dialogue_manager().last_error]
		push_error(_status.text)
		return
	director.step_started.connect(func(_id: String, index: int, command: String) -> void:
		_status.text = "步骤 %d · %s" % [index + 1, command])
	director.event_finished.connect(func(_id: String, ok: bool, reason: String) -> void:
		_status.text = "点单结束 · WASD 移动 / E 交互已恢复" if ok else "已取消，控制已恢复：" + reason)
	$DemoLayer/Panel/Content/Cancel.pressed.connect(func() -> void: director.cancel_event("Trial cancel"))
	if autoplay:
		error = director.request_event("day1.scene01")
		if error != OK:
			_status.text = director.last_error

func get_story_authoring_game() -> MainGame:
	return _game
