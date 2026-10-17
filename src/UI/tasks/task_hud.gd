class_name TaskHUD
extends PanelContainer
## Non-interactive view of the current main task; no gameplay or story commands.

@onready var _title: Label = $Margin/Content/Title
@onready var _objective: Label = $Margin/Content/Objective
var _journal: TaskJournal

func bind_journal(journal: TaskJournal) -> void:
	_disconnect_journal()
	_journal = journal
	if is_inside_tree():
		_connect_journal()
	_refresh()

func _enter_tree() -> void:
	_connect_journal()
	if not get_viewport().size_changed.is_connected(_resize_card):
		get_viewport().size_changed.connect(_resize_card)
	if is_node_ready():
		_resize_card()
		_refresh()

func _ready() -> void:
	_resize_card()
	_refresh()

func _exit_tree() -> void:
	_disconnect_journal()
	if get_viewport().size_changed.is_connected(_resize_card):
		get_viewport().size_changed.disconnect(_resize_card)

func _connect_journal() -> void:
	if is_instance_valid(_journal) and not _journal.projection_changed.is_connected(_refresh):
		_journal.projection_changed.connect(_refresh)

func _disconnect_journal() -> void:
	if is_instance_valid(_journal) and _journal.projection_changed.is_connected(_refresh):
		_journal.projection_changed.disconnect(_refresh)

func _resize_card() -> void:
	offset_left = -minf(260.0, maxf(1.0, get_viewport_rect().size.x - 32.0)) - 16.0

func _refresh() -> void:
	if not is_node_ready():
		return
	var task: Dictionary = _journal.get_current_main_task() if is_instance_valid(_journal) else {}
	visible = not task.is_empty()
	if task.is_empty():
		_title.text = ""
		_objective.text = ""
		return
	_title.text = task.title
	var objective: Dictionary = task.current_objective
	if objective.is_empty():
		_objective.text = "目标已达成，等待后续剧情。"
		return
	_objective.text = objective.text
	if objective.target != null:
		_objective.text += "  %s / %s" % [String.num(objective.progress).trim_suffix(".0"), String.num(objective.target).trim_suffix(".0")]
