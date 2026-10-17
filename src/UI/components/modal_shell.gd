class_name ModalShell
extends Control
## Shared modal chrome: shade, outer margin, bordered panel, header, body and footer.
## Screens compose it with a content scene; content pages never draw their own chrome.

signal close_requested

@export var title := "标题"
@export var hint := ""
@export var content_scene: PackedScene

@onready var _title: Label = %Title
@onready var _close: Button = %Close
@onready var _body: VBoxContainer = %Body
@onready var _footer: Label = %Footer
@onready var _panel: PanelContainer = %Panel

var _content: Control

func _ready() -> void:
	_title.text = title
	_close.pressed.connect(func() -> void: close_requested.emit())
	set_hint(hint)
	if content_scene != null:
		_content = content_scene.instantiate() as Control
		if _content != null:
			_body.add_child(_content)

func set_title(text: String) -> void:
	title = text
	if is_node_ready():
		_title.text = text

func set_hint(text: String) -> void:
	hint = text
	if is_node_ready():
		_footer.text = text
		_footer.visible = not text.is_empty()

func get_content() -> Control:
	return _content

func get_close_button() -> Button:
	return _close

func get_panel_rect() -> Rect2:
	return _panel.get_global_rect()

func get_default_focus() -> Control:
	if is_instance_valid(_content) and _content.has_method("get_default_focus"):
		var target: Control = _content.get_default_focus()
		if is_instance_valid(target):
			return target
	return _close
