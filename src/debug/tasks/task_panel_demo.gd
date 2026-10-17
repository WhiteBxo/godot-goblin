extends Node
## Opt-in UI fixtures only; the production catalog and delivery service stay intact.

var _saved_state: Dictionary = {}
var _game: MainGame

func _ready() -> void:
	if not OS.has_feature("debug"):
		queue_free()
		return
	var state := get_node("/root/GameState")
	_saved_state = state.to_dict()
	state.reset_state()
	_game = preload("res://src/core/main.tscn").instantiate()
	add_child(_game)
	var catalog := TaskCatalog.new()
	if catalog.load_file("res://tests/fixtures/task_panel_tasks.json") != OK:
		push_error(catalog.last_error)
		return
	_game.get_task_journal().configure(catalog, state)
	state.set_flag("task.panel.active")
	state.set_variable("task.panel.count", 1)
	var actions := HFlowContainer.new()
	actions.position = Vector2(12, 12)
	actions.size.x = 430
	actions.theme = preload("res://src/resources/ui/game_theme.tres")
	_game.get_node("DebugLayer").add_child(actions)
	for data: Array in [["推进目标", "task.panel.board"], ["完成主线", "task.panel.main_done"], ["揭示委托", "task.panel.revealed"], ["揭示奖励", "task.panel.reward_revealed"]]:
		var button := Button.new()
		button.text = data[0]
		button.pressed.connect(state.set_flag.bind(data[1], true))
		actions.add_child(button)
	var counter := Button.new()
	counter.text = "计数 +1"
	counter.pressed.connect(func() -> void: state.set_variable("task.panel.count", int(state.get_variable("task.panel.count", 0)) + 1))
	actions.add_child(counter)
	var reset := Button.new()
	reset.text = "清空活动任务"
	reset.pressed.connect(state.reset_state)
	actions.add_child(reset)
	_game.get_ui_manager().modal_changed.connect(func() -> void: actions.visible = not _game.get_ui_manager().has_modal())
	_game.open_tasks()

func _exit_tree() -> void:
	if not _saved_state.is_empty():
		get_node("/root/GameState").restore_state(_saved_state)
