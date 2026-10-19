class_name PromptBar
extends CenterContainer
## Bottom-centre interaction prompt with a themed keycap.

@export_range(0.0, 0.5, 0.01) var appear_seconds := 0.08

@onready var _key: Label = %Key
@onready var _text: Label = %Text
var _fade: Tween

func show_prompt(text: String, key: String = "E") -> void:
	var changed := _text.text != text or _key.text != key
	_key.text = key
	_text.text = text
	if text.is_empty():
		clear()
		return
	if not visible:
		visible = true
		modulate.a = 0.0
		_start_fade(1.0)
	elif changed:
		# Only the text changed: keep the prompt stable and avoid a second fade.
		modulate.a = 1.0

func clear() -> void:
	_text.text = ""
	if _fade != null:
		_fade.kill()
		_fade = null
	modulate.a = 1.0
	visible = false

func _start_fade(target: float) -> void:
	if _fade != null:
		_fade.kill()
	if appear_seconds <= 0.0:
		modulate.a = target
		return
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", target, appear_seconds)

func get_text() -> String:
	return _text.text

func get_key_text() -> String:
	return _key.text

func get_text_label() -> Label:
	return _text
