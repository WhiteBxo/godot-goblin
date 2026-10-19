class_name ChapterActionsHUD
extends UIScreen
## A disposable view of actions supplied by the scene's gameplay service.
signal action_requested(id: String)

var _expanded := false
var _notice := ""
var _summary := ""
var _context_details := false

func _ready() -> void:
	$Scroll/Content/Details.pressed.connect(func() -> void:
		_expanded = not _expanded
		_refresh_notice())

func _refresh_notice() -> void:
	$Scroll/Content/NoticePanel/Notice.text = _notice if _expanded else _summary
	$Scroll/Content/Details.text = "收起支线" if _expanded else "支线详情"
	$Scroll/Content/OptionalButtons.visible = _expanded

func show_actions(actions: Array[Dictionary], notice: String, enabled: bool, summary: String = "", context_details: bool = false) -> void:
	if context_details != _context_details:
		_expanded = context_details
		_context_details = context_details
	_notice = notice
	_summary = summary if not summary.is_empty() else notice
	_refresh_notice()
	$Scroll/Content/NoticePanel.visible = not notice.is_empty()
	var has_optional := actions.any(func(action: Dictionary) -> bool: return action.get("kind") == "hire")
	$Scroll/Content/Details.visible = has_optional or (not notice.is_empty() and _summary != _notice)
	$Scroll/Content/Details.disabled = not enabled
	var buttons: VBoxContainer = $Scroll/Content/Buttons
	var optional: VBoxContainer = $Scroll/Content/OptionalButtons
	for container: VBoxContainer in [buttons, optional]:
		for child: Node in container.get_children():
			container.remove_child(child)
			child.queue_free()
	for action: Dictionary in actions:
		var button := Button.new()
		button.text = action.text
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.disabled = not enabled
		button.pressed.connect(func() -> void: action_requested.emit(action.id))
		(optional if action.get("kind") == "hire" else buttons).add_child(button)
