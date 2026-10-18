class_name TitleCard
extends Control
## Full-screen date / chapter card. Presentation only: it writes no story facts.
## A newer card replaces the current one, which settles as cancelled.

const FADE_SECONDS := 0.4

signal showing_changed

var _action: TitleCardAction
var _tween: Tween

@onready var _title: Label = $Center/Lines/Title
@onready var _subtitle: Label = $Center/Lines/Subtitle

func _ready() -> void:
	visible = false
	modulate.a = 0.0

## `seconds` is the readable hold time, excluding the fades on both ends.
func show_card(text: String, subtitle: String = "", seconds: float = 2.5) -> TitleCardAction:
	cancel("Replaced by a newer title card")
	var action := TitleCardAction.new()
	if text.strip_edges().is_empty() or not is_finite(seconds) or seconds <= 0.0 or not is_inside_tree():
		action.settle(false, "Title card requires text, a positive duration and a scene")
		return action
	_action = action
	_title.text = text
	_subtitle.text = subtitle
	_subtitle.visible = not subtitle.strip_edges().is_empty()
	visible = true
	modulate.a = 0.0
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "modulate:a", 1.0, FADE_SECONDS)
	_tween.tween_interval(seconds)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	_tween.finished.connect(_complete.bind(action))
	showing_changed.emit()
	return action

func is_showing() -> bool:
	return _action != null

func cancel(reason: String = "Title card cancelled") -> void:
	if _action == null:
		return
	var action := _action
	_reset()
	action.settle(false, reason)

func _complete(action: TitleCardAction) -> void:
	if action != _action:
		return
	_reset()
	action.settle(true)

func _reset() -> void:
	_action = null
	if _tween != null:
		_tween.kill()
		_tween = null
	visible = false
	modulate.a = 0.0
	showing_changed.emit()

func _exit_tree() -> void:
	cancel("Title card exited")
