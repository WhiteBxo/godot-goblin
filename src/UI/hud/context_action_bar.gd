class_name ContextActionBar
extends Control
## Scene actions that used to hide behind the menu — "close the shop", "keep
## waiting", "call in a runner". Presentation only: the chapter gameplay owns
## which actions exist, when they unlock and what they do.

const REFRESH_SECONDS := 0.2
const MARGIN := 16.0
## The stealth strip lives in the same corner; keep clear of it while it is up.
const STEALTH_CLEARANCE := 40.0

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
	# ChipButton is the paper tag; the primary action uses the gold primary.
	button.theme_type_variation = &"PrimaryButton" if primary else &"ChipButton"
	button.add_theme_font_size_override("font_size", 12)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var id := str(action.get("id", ""))
	button.pressed.connect(func() -> void: gameplay.perform_user_action(id))
	return button

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
