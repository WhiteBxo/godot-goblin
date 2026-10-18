class_name OrderList
extends ScrollContainer
## Stable two-line rows; refreshing stock never replaces the focused button.

signal selection_requested(order_id: String)

@onready var _rows: VBoxContainer = $Rows
var _buttons: Dictionary[String, Button] = {}

func set_entries(entries: Array[Dictionary], selected_id: String) -> void:
	var ids: Array[String] = []
	for entry: Dictionary in entries:
		ids.append(entry.order_id)
	for id: String in _buttons.keys():
		if id not in ids:
			var button := _buttons[id]
			_rows.remove_child(button)
			button.queue_free()
			_buttons.erase(id)
	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index]
		var id: String = entry.order_id
		if not _buttons.has(id):
			_buttons[id] = _make_row(id)
		var button := _buttons[id]
		_rows.move_child(button, index)
		button.theme_type_variation = &"OrderRowSelected" if id == selected_id else &"OrderRow"
		button.tooltip_text = "%s · %s · %s" % [entry.title, entry.target_name, entry.status_text]
		(button.get_node("Content/Icon") as TextureRect).texture = entry.icon
		(button.get_node("Content/Labels/Title") as Label).text = entry.title
		(button.get_node("Content/Labels/Meta") as Label).text = "%s · %s" % [entry.target_name, entry.status_text]
	for index: int in range(ids.size()):
		var button := _buttons[ids[index]]
		button.focus_neighbor_top = button.get_path_to(_buttons[ids[maxi(0, index - 1)]])
		button.focus_neighbor_bottom = button.get_path_to(_buttons[ids[mini(ids.size() - 1, index + 1)]])

func _make_row(id: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_child(button)
	button.pressed.connect(func() -> void: selection_requested.emit(id))
	button.focus_entered.connect(func() -> void:
		selection_requested.emit(id)
		ensure_control_visible.call_deferred(button))
	var content := HBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 8
	content.offset_right = -8
	content.offset_top = 4
	content.offset_bottom = -4
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(icon)
	var labels := VBoxContainer.new()
	labels.name = "Labels"
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	labels.add_theme_constant_override("separation", 4)
	content.add_child(labels)
	for field: String in ["Title", "Meta"]:
		var label := Label.new()
		label.name = field
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.theme_type_variation = &"Hint" if field == "Meta" else &""
		labels.add_child(label)
	return button

func get_default_focus() -> Control:
	return _rows.get_child(0) as Control if _rows.get_child_count() > 0 else null

func focus_order(id: String) -> void:
	if _buttons.has(id):
		_buttons[id].grab_focus()
