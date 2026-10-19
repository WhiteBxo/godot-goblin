class_name ChapterActionsHUD
extends UIScreen
## A disposable view of actions supplied by the scene's gameplay service.
signal action_requested(id: String)

func show_actions(actions: Array[Dictionary], notice: String, enabled: bool) -> void:
	$Content/NoticePanel/Notice.text = notice
	$Content/NoticePanel.visible = not notice.is_empty()
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
