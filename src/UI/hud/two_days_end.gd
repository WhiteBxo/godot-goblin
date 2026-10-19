class_name TwoDaysEnd
extends UIScreen
## Final card of the two-day build. The chapter hands the screen over here,
## so the card owns the fade, the last cue and the walk back to the title.

signal finished

var _leaving := false


func _ready() -> void:
	$Center/Content/Return.pressed.connect(_confirm)
	modulate.a = 0.0


func present(summary: String) -> void:
	$Center/Content/Summary.text = summary
	_leaving = false
	# The card rises out of the black the chapter already faded into.
	var enter := create_tween()
	enter.tween_property(self, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	enter.tween_callback(func() -> void: $Center/Content/Return.grab_focus())


func get_default_focus() -> Control:
	return $Center/Content/Return


func uses_native_gui_input() -> bool:
	return true


## Esc leaves as well: there is nothing behind the card to go back to.
func handle_ui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_confirm()


func _confirm() -> void:
	if _leaving:
		return
	_leaving = true
	var leave := create_tween()
	leave.tween_property(self, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	leave.tween_callback(func() -> void: finished.emit())
