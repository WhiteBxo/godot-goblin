extends Node
## Only composition, data registration and debug controls. Sequence lives in JSON.

@export var autoplay := true
@onready var _game: MainGame = $MainGame
@onready var _status: Label = $DemoLayer/Panel/Content/Status
var _director: StoryDirector

func _ready() -> void:
	if not OS.has_feature("debug"):
		$DemoLayer.hide()
		return
	_director = _game.get_story_director()
	var actors := _game.get_actor_director()
	for marker: Node in $Positions.get_children():
		actors.register_position(StringName(marker.name), marker as Marker2D)
	var audio := _game.get_audio_manager()
	audio.register_sound("cinematic.bell", AudioDemoTones.tone(880.0, 0.45))
	audio.register_sound("cinematic.room", AudioDemoTones.tone(164.81, 2.0, true))
	audio.register_sound("cinematic.rumble", preload("res://src/debug/story/strange_knock.tres"))
	var error := _game.get_dialogue_manager().load_dialogues("res://src/resources/dialogue/cinematic_opening.json")
	if error == OK:
		error = _director.load_events("res://src/resources/story/cinematic_opening.json")
	if error != OK:
		_status.text = "加载失败：%s / %s" % [_director.last_error, _game.get_dialogue_manager().last_error]
		return
	_director.step_started.connect(func(_id: String, index: int, command: String) -> void: _status.text = "步骤 %d · %s" % [index + 1, command])
	_director.event_finished.connect(func(_id: String, ok: bool, reason: String) -> void: _status.text = "演出完成 · WASD 已恢复" if ok else "已停止：" + reason)
	$DemoLayer/Panel/Content/Buttons/Replay.pressed.connect(play)
	$DemoLayer/Panel/Content/Buttons/Cancel.pressed.connect(func() -> void: _director.cancel_event("Demo cancel"))
	if autoplay:
		play()

func play() -> void:
	if _director.is_busy():
		return
	# Reset demo cast for replay; these are setup operations, never sequence dispatch.
	var actors := _game.get_actor_director()
	var previous := actors.get_actor(&"customer")
	if previous != null:
		actors.actor_unregister(&"customer")
		previous.queue_free()
	_game.get_player().global_position = _game.get_active_level().get_spawn_position()
	var error := _director.request_event("cinematic.opening")
	if error != OK:
		_status.text = _director.last_error
