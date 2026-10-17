extends Node
## Editor-only acceptance host. Fixtures never load through MainGame.

var _saved_state: Dictionary = {}

func _ready() -> void:
	if not OS.has_feature("debug"):
		queue_free()
		return
	var state := get_node("/root/GameState")
	_saved_state = state.to_dict()
	state.reset_state()
	var game: MainGame = preload("res://src/core/main.tscn").instantiate()
	game.name = "Game"
	add_child(game)
	var director := game.get_story_director()
	var error := director.load_events("res://tests/fixtures/task_story.json")
	if error == OK:
		error = game.get_gameplay_bridge().load_phases("res://tests/fixtures/task_phases.json")
	if error == OK:
		error = director.request_event("task_test.accept")
	if error != OK:
		push_error("Task acceptance fixture could not start (%d): %s" % [error, director.last_error])
	var hint := Label.new()
	hint.text = "任务 P0 测试 · 查看订单板 → 制作交付 → 关闭弹窗"
	hint.position = Vector2(16, 30)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.theme = preload("res://src/resources/ui/game_theme.tres")
	game.get_node("DebugLayer").add_child(hint)

func _exit_tree() -> void:
	if not _saved_state.is_empty():
		get_node("/root/GameState").restore_state(_saved_state)
