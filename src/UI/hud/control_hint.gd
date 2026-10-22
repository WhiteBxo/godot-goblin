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
## Which fact marks this lesson as taught. L0 has one per device; later tips
## (map, throwing) pass their own key.
var _flag_key := ""
## L0 waits for the first frame the player can actually act: an opening
## performance or a locked intro would otherwise teach keys nobody can press yet.
var _waiting_for_control := false
## L0 folds away as soon as the player walks. A tip about a key he is already
## pressing must not vanish the moment he moves.
var _dismiss_on_walk := true

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
	_waiting_for_control = true
	set_process(true)

## One lesson, shown once per save. The map and the throw controls are not
## permanent HUD furniture: they are taught here, then they live in the menu or
## on a key, and the corner stays free for the game.
func show_tip(text: String, key: String, seconds: float = 7.0, dismiss_on_walk: bool = false) -> void:
	if is_instance_valid(_state) and _state.get_flag(key):
		return
	if _running:
		# A newer lesson replaces the one on screen rather than stacking.
		_running = false
	_start(text, key, seconds, dismiss_on_walk)

func _start(text: String, key: String, seconds: float, dismiss_on_walk: bool) -> void:
	_waiting_for_control = false
	_flag_key = key
	_dismiss_on_walk = dismiss_on_walk
	_label.text = text
	_label.visible = true
	_fit()
	visible = true
	_running = true
	_clock = seconds
	_origin = _player.global_position if is_instance_valid(_player) else Vector2.ZERO
	modulate.a = 1.0
	set_process(true)

## One record per device: a phone player is not taught the keyboard layout and
## a keyboard player is not taught touch, even on the same save.
func _record_key() -> String:
	return "ui.hint.l0.touch" if MobileSupport.is_touch_ui() else "ui.hint.l0.keyboard"

## Free control means the player can walk and is not being puppeteered; the L0
## sentence is only true once that holds, so the timer starts then, not at load.
func _can_act() -> bool:
	if not is_instance_valid(_player):
		return false
	if not bool(_player.get("movement_enabled")):
		return false
	if _player.has_method("is_performance_controlled") and _player.is_performance_controlled():
		return false
	return true

func _process(delta: float) -> void:
	if _waiting_for_control:
		if not _can_act():
			return
		_start(KEYBOARD_TEXT if not MobileSupport.is_touch_ui() else TOUCH_TEXT, _record_key(), SHOW_SECONDS, true)
	if not _running:
		return
	_clock -= delta
	var walked: bool = _dismiss_on_walk and is_instance_valid(_player) and _player.global_position.distance_to(_origin) >= WALK_DISTANCE
	if walked or _clock <= 0.0:
		_finish()

func _finish() -> void:
	_running = false
	set_process(false)
	if _state != null and not _flag_key.is_empty():
		_state.set_flag(_flag_key)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(func() -> void: visible = false)
