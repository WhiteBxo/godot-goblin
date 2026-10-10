class_name CaveDebugOverlay
extends Control

@onready var hint: Label = $Hint

var _comparison: Control

func set_hint(text: String) -> void:
	hint.text = text

func show_atlas_comparison(original: Texture2D, processed: Texture2D) -> void:
	hint.hide()
	if is_instance_valid(_comparison):
		_comparison.queue_free()
	_comparison = MarginContainer.new()
	_comparison.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_comparison)
	_comparison.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		_comparison.add_theme_constant_override("margin_" + side, 12)
	var columns := HBoxContainer.new()
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_theme_constant_override("separation", 16)
	_comparison.add_child(columns)
	_add_comparison_panel(columns, original, "原始图集")
	_add_comparison_panel(columns, processed, "预处理图集")

func _add_comparison_panel(parent: Control, texture: Texture2D, title: String) -> void:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 18)
	label.text = title
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(label)
	var preview := TextureRect.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.texture = texture
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(preview)
