class_name PromptBar
extends CenterContainer
## Bottom-centre interaction prompt with a themed keycap.

@onready var _key: Label = %Key
@onready var _text: Label = %Text

func show_prompt(text: String, key: String = "E") -> void:
	_key.text = key
	_text.text = text
	visible = not text.is_empty()

func clear() -> void:
	_text.text = ""
	visible = false

func get_text() -> String:
	return _text.text

func get_key_text() -> String:
	return _key.text

func get_text_label() -> Label:
	return _text
