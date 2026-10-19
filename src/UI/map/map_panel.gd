class_name SettlementMapPanel
extends UIScreen

@onready var _shell: ModalShell = $ModalShell
## A scene map or an exterior provider for indoor hosts; both expose get_map_data.
var _level: Object
var _player: Node2D
var _journal: TaskJournal
var _known_locations: Callable
var _canvas: SettlementMapCanvas
var _objective: Label

func _ready() -> void:
	var body := _shell.get_content()
	_canvas = body.get_node("Canvas") as SettlementMapCanvas
	_objective = body.get_node("Details/Objective") as Label
	_shell.close_requested.connect(func() -> void: close_requested.emit())
	visibility_changed.connect(_visibility_changed)
	set_process(false)

func configure(level: Object, player: Node2D, journal: TaskJournal, known: Callable) -> void:
	_level = level
	_player = player
	if is_instance_valid(_journal) and _journal.projection_changed.is_connected(refresh):
		_journal.projection_changed.disconnect(refresh)
	_journal = journal
	if is_instance_valid(_journal):
		_journal.projection_changed.connect(refresh)
	_known_locations = known

func _visibility_changed() -> void:
	set_process(is_visible_in_tree())
	if is_visible_in_tree():
		refresh()
		# Where you stand gets one ring so the two dots are told apart at a glance.
		_canvas.ping()

func _process(_delta: float) -> void:
	if is_instance_valid(_player) and _canvas.player_position != _map_player_position():
		_canvas.player_position = _map_player_position()
		_canvas.queue_redraw()

func _map_player_position() -> Vector2:
	if is_instance_valid(_level) and _level.has_method("get_map_player_position"):
		return _level.get_map_player_position(_player)
	return _player.global_position if is_instance_valid(_player) else Vector2.ZERO

func refresh() -> void:
	if not is_visible_in_tree() or not is_instance_valid(_level) or not is_instance_valid(_player) or not _known_locations.is_valid():
		return
	var data: Dictionary = _level.get_map_data(_known_locations.call())
	var target := {}
	var text := "暂无当前主目标"
	var task := _journal.get_current_main_task() if is_instance_valid(_journal) else {}
	if not task.is_empty() and task.get("revealed", false):
		var objective: Dictionary = task.get("current_objective", {})
		if not objective.is_empty() and objective.get("revealed", false):
			text = objective.text
			var location: String = objective.get("location_id", "")
			if location.is_empty():
				location = task.get("location_id", "")
			for region: Dictionary in data.regions:
				if region.location_id == location:
					target = {"position": region.position, "name": region.name}
			if not location.is_empty() and (target.is_empty() or not text.contains(str(target.name))):
				text += " · " + (str(target.name) if not target.is_empty() else "地图上未标注")
		elif not objective.is_empty():
			text = "当前目标尚未揭示"
		else:
			text = "等待后续目标"
	if _canvas.map_data != data or _canvas.player_position != _map_player_position() or _canvas.target != target:
		_canvas.map_data = data
		_canvas.player_position = _map_player_position()
		_canvas.target = target
		_canvas.queue_redraw()
	if _objective.text != text:
		_objective.text = text
		UIFlourish.settle(_objective, 0.96)
	var places: Array[String] = []
	for region: Dictionary in data.regions:
		places.append("%d  %s" % [int(region.get("ordinal", 0)), region.name])
	(_shell.get_content().get_node("Details/Places/Names") as Label).text = "\n".join(places)

func get_map_canvas() -> SettlementMapCanvas:
	return _canvas

func get_default_focus() -> Control:
	return _shell.get_close_button()

func uses_native_gui_input() -> bool:
	return true
