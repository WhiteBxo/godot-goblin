class_name TitleCard
extends Control
## Full-screen date / chapter card. Presentation only: it writes no story facts.
## A newer card replaces the current one, which settles as cancelled.

const FADE_SECONDS := 0.4

signal showing_changed

var _action: TitleCardAction
var _tween: Tween
var _content_tween: Tween

@onready var _title: Label = $Center/Lines/Title
@onready var _subtitle: Label = $Center/Lines/Subtitle
@onready var _lines: VBoxContainer = $Center/Lines
@onready var _rule: ColorRect = $Center/Lines/Rule

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
	_play_content()
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "modulate:a", 1.0, FADE_SECONDS)
	_tween.tween_interval(seconds)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	_tween.finished.connect(_complete.bind(action))
	showing_changed.emit()
	return action

func is_showing() -> bool:
	return _action != null

## The card itself is one fader; inside it the day lands first, the gold rule
## draws out under it, then the place arrives. Everything finishes inside the
## same fade, so a skip or a cancel never leaves half a card on screen.
func _play_content() -> void:
	if _content_tween != null:
		_content_tween.kill()
	var box := _lines.size
	if box == Vector2.ZERO:
		box = _lines.get_combined_minimum_size()
	_lines.pivot_offset = box * 0.5
	_lines.scale = Vector2(1.03, 0.94)
	_title.modulate.a = 0.0
	_subtitle.modulate.a = 0.0
	_rule.pivot_offset = _rule.size * 0.5
	_rule.scale.x = 0.0
	_content_tween = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_content_tween.tween_property(_lines, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_content_tween.tween_property(_title, "modulate:a", 1.0, 0.22).set_delay(0.06)
	_content_tween.tween_property(_rule, "scale:x", 1.0, 0.30).set_delay(0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_content_tween.tween_property(_subtitle, "modulate:a", 1.0, 0.24).set_delay(0.20)

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
	if _content_tween != null:
		_content_tween.kill()
		_content_tween = null
	_lines.scale = Vector2.ONE
	_lines.modulate.a = 1.0
	_title.modulate.a = 1.0
	_subtitle.modulate.a = 1.0
	_rule.scale.x = 1.0
	visible = false
	modulate.a = 0.0
	showing_changed.emit()

func _exit_tree() -> void:
	cancel("Title card exited")
