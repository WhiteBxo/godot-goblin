class_name ControlHint
extends Control
## L0: one line at the bottom of the world that teaches exactly two things —
## how to walk and how to interact. It never blocks input, never opens a modal
## and never asks for a save; it shows once per input device, then folds away
## the moment the player actually walks.

const SHOW_SECONDS := 9.0
const WALK_DISTANCE := 24.0
const FADE_SECONDS := 0.4

const KEYBOARD_TEXT := "[WASD] 移动        [E] 互动"
const TOUCH_TEXT := "左侧拖动 移动        靠近后点 [交互]"

var _bar: PanelContainer
var _label: Label
var _state: Node
var _player: Node2D
var _origin := Vector2.ZERO
var _clock := 0.0
var _running := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar = $Bar
	_label = $Bar/Label
	_label.text = TOUCH_TEXT if MobileSupport.is_touch_ui() else KEYBOARD_TEXT
	visible = false
	modulate.a = 0.0
	set_process(false)
	_fit()

## The bar hugs its sentence: a fixed 380px plate left empty paper on both sides.
func _fit() -> void:
	var minimum := _bar.get_combined_minimum_size()
	_bar.offset_left = -minimum.x * 0.5
	_bar.offset_right = minimum.x * 0.5

func bind(game: Node) -> void:
	_state = game.get_node_or_null("/root/GameState")
	_player = game.get_player() if game.has_method("get_player") else null
	if _state == null or _state.get_flag(_record_key()):
		return
	visible = true
	_running = true
	_clock = SHOW_SECONDS
	_origin = _player.global_position if is_instance_valid(_player) else Vector2.ZERO
	set_process(true)
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)

## One record per device: a phone player is not taught the keyboard layout and
## a keyboard player is not taught touch, even on the same save.
func _record_key() -> String:
	return "ui.hint.l0.touch" if MobileSupport.is_touch_ui() else "ui.hint.l0.keyboard"

func _process(delta: float) -> void:
	if not _running:
		return
	_clock -= delta
	var walked: bool = is_instance_valid(_player) and _player.global_position.distance_to(_origin) >= WALK_DISTANCE
	if walked or _clock <= 0.0:
		_finish()

func _finish() -> void:
	_running = false
	set_process(false)
	if _state != null:
		_state.set_flag(_record_key())
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(func() -> void: visible = false)
