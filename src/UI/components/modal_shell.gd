class_name ModalShell
extends Control
## Shared modal chrome: shade, outer margin, bordered panel, header, body and footer.
## Screens compose it with a content scene; content pages never draw their own chrome.

signal close_requested

@export var title := "标题"
@export var hint := ""
@export var content_scene: PackedScene
@export_range(0.0, 0.5, 0.01) var open_seconds := 0.10

@onready var _title: Label = %Title
@onready var _close: Button = %Close
@onready var _body: VBoxContainer = %Body
@onready var _footer: Label = %Footer
@onready var _panel: PanelContainer = %Panel
@onready var _dim: Panel = %Dim

var _content: Control
var _open_tween: Tween

func _ready() -> void:
	_title.text = title
	_close.pressed.connect(func() -> void: close_requested.emit())
	set_hint(hint)
	if content_scene != null:
		_content = content_scene.instantiate() as Control
		if _content != null:
			_body.add_child(_content)
	_panel.resized.connect(_center_pivot)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready():
		if is_visible_in_tree():
			_play_open()
		else:
			_finish_open()

## The panel is the only animated node: the root stays laid out so focus and
## hit-testing are valid from the first frame of the open animation.
func _play_open() -> void:
	_center_pivot()
	if _open_tween != null:
		_open_tween.kill()
	if open_seconds <= 0.0:
		_finish_open()
		return
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.94, 0.94)
	_dim.modulate.a = 0.0
	_open_tween = create_tween().set_parallel(true)
	_open_tween.tween_property(_panel, "modulate:a", 1.0, open_seconds)
	_open_tween.tween_property(_panel, "scale", Vector2.ONE, open_seconds * 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(_dim, "modulate:a", 1.0, open_seconds)

func _finish_open() -> void:
	if _open_tween != null:
		_open_tween.kill()
		_open_tween = null
	_panel.modulate.a = 1.0
	_panel.scale = Vector2.ONE
	_dim.modulate.a = 1.0

func _center_pivot() -> void:
	_panel.pivot_offset = _panel.size * 0.5

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
