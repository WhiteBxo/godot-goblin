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
	_comparison = Control.new()
	_comparison.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_comparison)
	_add_comparison_panel(_comparison, original, "原始图集", Vector2(28.0, 90.0))
	_add_comparison_panel(_comparison, processed, "预处理图集", Vector2(505.0, 90.0))

func _add_comparison_panel(parent: Control, texture: Texture2D, title: String, position: Vector2) -> void:
	var label := Label.new()
	label.position = position
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 18)
	label.text = title
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	var preview := TextureRect.new()
	preview.position = position + Vector2(0.0, 34.0)
	preview.size = Vector2(420.0, 420.0)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.texture = texture
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(preview)
