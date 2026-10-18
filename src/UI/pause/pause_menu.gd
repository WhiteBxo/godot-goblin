class_name PauseMenu
extends Control

signal resume_requested
signal title_requested

@onready var _resume: Button = $Center/Panel/Margin/Content/Resume
@onready var _title: Button = $Center/Panel/Margin/Content/ReturnTitle
@onready var _error: Label = $Center/Panel/Margin/Content/Error
var _leaving := false

func _ready() -> void:
	_resume.pressed.connect(func() -> void: resume_requested.emit())
	_title.pressed.connect(_request_title)

func _request_title() -> void:
	if _leaving:
		return
	_leaving = true
	_resume.disabled = true
	_title.disabled = true
	_error.hide()
	title_requested.emit()

func show_navigation_error(error: Error) -> void:
	_leaving = false
	_resume.disabled = false
	_title.disabled = false
	push_warning("Title navigation failed: %s" % error_string(error))
	_error.text = "暂时无法返回标题，请重试。"
	_error.show()
	_title.grab_focus()

func get_default_focus() -> Control:
	return _resume

func set_save_status(text: String) -> void:
	$Center/Panel/Margin/Content/SaveStatus.text = text
