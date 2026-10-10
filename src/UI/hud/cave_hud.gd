class_name CaveHud
extends CanvasLayer

@onready var hint: Label = $Hint

func set_hint(text: String) -> void:
	hint.text = text
