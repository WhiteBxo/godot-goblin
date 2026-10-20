class_name TaskList
extends ScrollContainer
## Task rows that grow with their title: a long name wraps onto a second line
## instead of being cut inside a fixed-height ItemList row.
##
## Keeps the item API the task pages and their tests already speak
## (add_item / item_count / get_item_text / select / item_selected).

signal item_selected(index: int)
signal item_activated(index: int)

const ROW_MIN_HEIGHT := 26
## 主线、支线与已结束的行各有自己的底样式，列表本身就是一张优先级表。
const ROW_VARIATIONS: Dictionary = {
	"main": &"TaskRowMain",
	"side": &"TaskRowSide",
	"done": &"TaskRowDone",
}

var _selected := -1
var _silent_focus := false

var item_count: int:
	get:
		return _rows().get_child_count()

func clear() -> void:
	for child: Node in _rows().get_children():
		_rows().remove_child(child)
		child.queue_free()
	_selected = -1

func add_item(text: String, kind := "side") -> int:
	var button := Button.new()
	# Stable name so focus paths survive a refresh that rebuilds every row.
	button.name = "Row%d" % _rows().get_child_count()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0, ROW_MIN_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.set_meta(&"row_variation", ROW_VARIATIONS.get(kind, ROW_VARIATIONS.side))
	button.theme_type_variation = _variation(button, false)
	button.set_meta(&"task_row", true)
	button.pressed.connect(func() -> void:
		item_selected.emit(button.get_index()))
	button.focus_entered.connect(func() -> void:
		if not _silent_focus:
			item_selected.emit(button.get_index()))
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.double_click:
			item_activated.emit(button.get_index()))
	_rows().add_child(button)
	_relink()
	return button.get_index()

## Rows are buttons now, so the arrow keys need explicit neighbours; otherwise
## focus would leave the list instead of stepping to the next task.
func _relink() -> void:
	var count := item_count
	for index: int in range(count):
		var button := _row(index)
		if button == null:
			continue
		var above := _row(maxi(0, index - 1))
		var below := _row(mini(count - 1, index + 1))
		button.focus_neighbor_top = button.get_path_to(above)
		button.focus_neighbor_bottom = button.get_path_to(below)
	if count > 0:
		focus_next = get_path_to(_row(0))
		focus_previous = get_path_to(_row(count - 1))

## Tab leaves the container for its own first row instead of dropping focus on
## the floor; the viewport's focus walk cannot see rows inside a scroll clip.
func _input(event: InputEvent) -> void:
	if not has_focus() or not event.is_action_pressed("ui_focus_next"):
		return
	var first := _row(0)
	if first == null:
		return
	get_viewport().set_input_as_handled()
	first.grab_focus()

## Arrow keys step the selection even while the container itself holds focus.
func _gui_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	var step := 0
	if event.is_action_pressed("ui_down"):
		step = 1
	elif event.is_action_pressed("ui_up"):
		step = -1
	if step == 0:
		# Tab enters the rows instead of cycling on the container itself.
		if event.is_action_pressed("ui_focus_next"):
			var first := _row(0)
			if first != null:
				first.grab_focus()
				accept_event()
		return
	var target := clampi(_selected_index() + step, 0, item_count - 1)
	select(target)
	item_selected.emit(target)
	accept_event()

func get_item_text(index: int) -> String:
	var button := _row(index)
	return button.text if button != null else ""

func set_item_tooltip(index: int, text: String) -> void:
	var button := _row(index)
	if button != null:
		button.tooltip_text = text

func get_item_tooltip(index: int) -> String:
	var button := _row(index)
	return button.tooltip_text if button != null else ""

func set_item_disabled(index: int, disabled: bool) -> void:
	var button := _row(index)
	if button != null:
		button.disabled = disabled

## Selection is only styling here; like ItemList.select it emits nothing.
func select(index: int) -> void:
	_selected = index
	for position: int in range(item_count):
		var button := _row(position)
		if button != null:
			button.theme_type_variation = _variation(button, position == index)

func _variation(button: Button, selected: bool) -> StringName:
	var base: StringName = button.get_meta(&"row_variation", ROW_VARIATIONS.side)
	return StringName(String(base) + "Selected") if selected else base

func is_selected(index: int) -> bool:
	return index == _selected and index >= 0 and index < item_count

## Index of the row that currently owns focus, or -1 when the list has none.
func focused_row() -> int:
	for index: int in range(item_count):
		var button := _row(index)
		if button != null and button.has_focus():
			return index
	return -1

## Moves focus onto a row without reporting it as a user selection.
func focus_row(index: int) -> void:
	var button := _row(index)
	if button == null:
		return
	_silent_focus = true
	button.grab_focus()
	_silent_focus = false

func ensure_current_is_visible() -> void:
	var button := _row(_selected_index())
	if button != null:
		ensure_control_visible(button)

func _selected_index() -> int:
	return maxi(_selected, 0)

func _row(index: int) -> Button:
	if index < 0 or index >= item_count:
		return null
	return _rows().get_child(index) as Button

func _rows() -> VBoxContainer:
	return $Rows
