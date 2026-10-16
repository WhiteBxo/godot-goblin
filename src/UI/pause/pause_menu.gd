class_name PauseMenu
extends Control

signal resume_requested

func _ready() -> void:
	$Center/Panel/Margin/Content/Resume.pressed.connect(func() -> void: resume_requested.emit())

func get_default_focus() -> Control:
	return $Center/Panel/Margin/Content/Resume
