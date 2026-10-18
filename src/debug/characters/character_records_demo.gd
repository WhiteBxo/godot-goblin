extends Node
## Explicit preview only. Never load these events from the production host.

var _saved_state: Dictionary = {}
var _snapshot: Dictionary = {}
var _game: MainGame

func _ready() -> void:
	if not OS.has_feature("debug"):
		queue_free()
		return
	var state := get_node("/root/GameState")
	_saved_state = state.to_dict()
	state.reset_state()
	_game = preload("res://src/debug/story/legacy_shop.tscn").instantiate()
	add_child(_game)
	_game.get_story_director().load_events("res://src/debug/characters/demo_story.json")
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var actions := HBoxContainer.new()
	actions.position = Vector2(12, 32)
	actions.theme = preload("res://src/resources/ui/game_theme.tres")
	layer.add_child(actions)
	for data: Array in [["解锁守卫", "character_test.discover"], ["追加判断", "character_test.append"]]:
		var button := Button.new()
		button.text = data[0]
		button.pressed.connect(_request_event.bind(data[1]))
		actions.add_child(button)
	for data: Array in [["查看", func() -> void: _game.open_characters()],
		["快照", func() -> void: _snapshot = state.to_dict()],
		["恢复", func() -> void:
			if not _snapshot.is_empty():
				state.restore_state(_snapshot)],
		["重置", func() -> void: state.reset_state()]]:
		var button := Button.new()
		button.text = data[0]
		button.pressed.connect(data[1])
		actions.add_child(button)
	_game.get_ui_manager().modal_changed.connect(func() -> void: actions.visible = not _game.get_ui_manager().has_modal())

func get_preview_game() -> MainGame:
	return _game

func _request_event(id: String) -> void:
	var error := _game.get_story_director().request_event(id)
	if error != OK:
		push_warning("Character demo event rejected (%d): %s" % [error, id])

func _exit_tree() -> void:
	if not _saved_state.is_empty():
		get_node("/root/GameState").restore_state(_saved_state)
