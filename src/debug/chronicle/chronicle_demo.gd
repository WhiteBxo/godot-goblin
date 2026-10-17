extends Node
## Fixture content is opt-in and never referenced by the production host.

var _saved_state: Dictionary = {}
var _game: MainGame
var _snapshot: Dictionary = {}

func _ready() -> void:
	if not OS.has_feature("debug"):
		queue_free()
		return
	var state := get_node("/root/GameState")
	_saved_state = state.to_dict()
	state.reset_state()
	_game = preload("res://src/core/main.tscn").instantiate()
	add_child(_game)
	_game.get_story_director().load_events("res://src/debug/chronicle/demo_story.json")
	var actions := HBoxContainer.new()
	actions.position = Vector2(12, 32)
	actions.theme = preload("res://src/resources/ui/game_theme.tres")
	_game.get_node("DebugLayer").add_child(actions)
	for data: Array in [["解锁首条", "chronicle_test.discover"], ["追加记录", "chronicle_test.append"], ["解锁第二条", "chronicle_test.second"]]:
		var button := Button.new()
		button.text = data[0]
		button.pressed.connect(_request_event.bind(data[1]))
		actions.add_child(button)
	var save := Button.new()
	save.text = "快照"
	save.pressed.connect(func() -> void: _snapshot = state.to_dict())
	actions.add_child(save)
	var restore := Button.new()
	restore.text = "恢复"
	restore.pressed.connect(func() -> void:
		if not _snapshot.is_empty():
			state.restore_state(_snapshot))
	actions.add_child(restore)
	# Fixture buttons must not intercept the review panel or a paused game.
	_game.get_ui_manager().modal_changed.connect(func() -> void: actions.visible = not _game.get_ui_manager().has_modal())

func _request_event(id: String) -> void:
	var error := _game.get_story_director().request_event(id)
	if error != OK:
		push_warning("Chronicle demo event rejected (%d): %s" % [error, id])

func _exit_tree() -> void:
	if not _saved_state.is_empty():
		get_node("/root/GameState").restore_state(_saved_state)
