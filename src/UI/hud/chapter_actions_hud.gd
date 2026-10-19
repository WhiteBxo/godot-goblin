class_name ChapterActionsHUD
extends UIScreen
## A disposable view of actions supplied by the scene's gameplay service.
signal action_requested(id: String)

var _expanded := false
var _notice := ""
var _summary := ""

func _ready() -> void:
	$Content/Details.pressed.connect(func() -> void:
		_expanded = not _expanded
		_refresh_notice())

func _refresh_notice() -> void:
	$Content/NoticePanel/Notice.text = _notice if _expanded else _summary
	$Content/Details.text = "收起支线" if _expanded else "支线详情"

func show_actions(actions: Array[Dictionary], notice: String, enabled: bool, summary: String = "") -> void:
	_notice = notice
	_summary = summary if not summary.is_empty() else notice
	_refresh_notice()
	$Content/NoticePanel.visible = not notice.is_empty()
	$Content/Details.visible = not notice.is_empty() and _summary != _notice
	$Content/Details.disabled = not enabled
	var buttons: VBoxContainer = $Content/Buttons
	for child: Node in buttons.get_children():
		buttons.remove_child(child)
		child.queue_free()
	for action: Dictionary in actions:
		var button := Button.new()
		button.text = action.text
		button.disabled = not enabled
		button.pressed.connect(func() -> void: action_requested.emit(action.id))
		buttons.add_child(button)
