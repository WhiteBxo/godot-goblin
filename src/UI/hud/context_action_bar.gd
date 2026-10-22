class_name ContextActionBar
extends Control
## Scene actions that used to hide behind the menu — "close the shop", "keep
## waiting", "call in a runner". Presentation only: the chapter gameplay owns
## which actions exist, when they unlock and what they do.

const REFRESH_SECONDS := 0.2
const MARGIN := 16.0
## The stealth strip lives in the same corner; keep clear of it while it is up.
const STEALTH_CLEARANCE := 40.0

const INK := Color(0.227, 0.165, 0.102, 1)
const PAPER := Color(0.961, 0.91, 0.812, 1)
const WOOD := Color(0.302, 0.204, 0.118, 1)
const CREAM := Color(0.969, 0.918, 0.824, 1)

var _game: Node
var _row: HBoxContainer
var _signature := ""
var _clock := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = $Row
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

func bind(game: Node) -> void:
	_game = game
	set_process(true)
	_clock = 0.0
	_refresh()

func _process(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = REFRESH_SECONDS
	_refresh()

func _refresh() -> void:
	var gameplay: Node = null
	if is_instance_valid(_game) and _game.has_method("get_chapter_gameplay"):
		gameplay = _game.get_chapter_gameplay()
	if not is_instance_valid(gameplay):
		_clear()
		return
	var actions: Array = [] if _blocked() else gameplay.get_user_actions()
	var signature := ""
	for action: Dictionary in actions:
		signature += "%s|%s|" % [str(action.get("id", "")), str(action.get("text", ""))]
	if signature == _signature:
		_layout()
		return
	_signature = signature
	_rebuild(actions, gameplay)
	_layout()

## Menus, dialogue and pause own the frame: the strip would be a second set of
## buttons competing with the modal the player just opened.
func _blocked() -> bool:
	if get_tree().paused:
		return true
	if not is_instance_valid(_game):
		return true
	if _game.has_method("get_ui_manager"):
		var ui = _game.get_ui_manager()
		# The chapter menu is a "popup" screen, not a modal, so both are checked.
		if ui.has_modal() or ui.is_open(ScreenIds.CHAPTER_ACTIONS):
			return true
	if _game.has_method("get_dialogue_manager") and _game.get_dialogue_manager().is_active():
		return true
	return false

func _clear() -> void:
	if _signature.is_empty() and _row.get_child_count() == 0:
		return
	_signature = ""
	for child: Node in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_layout()

func _rebuild(actions: Array, gameplay: Node) -> void:
	for child: Node in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	for index in range(actions.size()):
		var action: Dictionary = actions[index]
		_row.add_child(_make_button(action, index == 0, gameplay))

func _make_button(action: Dictionary, primary: bool, gameplay: Node) -> Button:
	var button := Button.new()
	button.text = str(action.get("text", ""))
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", CREAM if primary else INK)
	button.add_theme_color_override("font_hover_color", Color(1, 0.878, 0.6) if primary else Color(0.71, 0.275, 0.184))
	button.add_theme_color_override("font_pressed_color", Color(1, 0.82, 0.478) if primary else INK)
	button.add_theme_stylebox_override("normal", _paper(primary, 0))
	button.add_theme_stylebox_override("hover", _paper(primary, 1))
	button.add_theme_stylebox_override("pressed", _paper(primary, 2))
	button.add_theme_stylebox_override("focus", _paper(primary, 1))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var id := str(action.get("id", ""))
	button.pressed.connect(func() -> void: gameplay.perform_user_action(id))
	return button

## Cream card with an ink border and a hard offset shadow, matching the HUD.
func _paper(primary: bool, state: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = WOOD if primary else PAPER
	if state == 1:
		box.bg_color = box.bg_color.lightened(0.1)
	elif state == 2:
		box.bg_color = box.bg_color.darkened(0.08)
	box.border_color = Color(0.29, 0.216, 0.133, 1)
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 2
	box.border_width_bottom = 2
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 6
	box.corner_radius_bottom_right = 4
	box.corner_radius_bottom_left = 6
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	box.shadow_color = Color(0.227, 0.165, 0.102, 0.32)
	box.shadow_size = 0
	box.shadow_offset = Vector2(2, 2)
	return box

## The row hugs its buttons and sits above the stealth strip when that one is up.
func _layout() -> void:
	var minimum := _row.get_combined_minimum_size()
	var bottom := -MARGIN
	if is_instance_valid(_game) and _game.has_method("get_ui_manager") \
			and _game.get_ui_manager().is_open(ScreenIds.STEALTH_HUD):
		bottom -= STEALTH_CLEARANCE
	_row.offset_left = MARGIN
	_row.offset_right = MARGIN + minimum.x
	_row.offset_bottom = bottom
	_row.offset_top = bottom - minimum.y
