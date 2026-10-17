class_name UIScreen
extends Control
## Lifecycle contract for a registered UI screen.
## UIManager still works by duck typing; new screens should extend this class.

signal close_requested

func bind_ui(_manager: UIManager, _id: StringName) -> void:
	pass

func get_default_focus() -> Control:
	return null

func on_ui_closed() -> void:
	pass

func uses_native_gui_input() -> bool:
	return false

func handle_ui_input(_event: InputEvent) -> void:
	pass
