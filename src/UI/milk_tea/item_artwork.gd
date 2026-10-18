extends RefCounted
## Presentation helpers. Custom drinks use a neutral cup, not another recipe's art.

const DRINK_ICON: Texture2D = preload("res://assets/ui/milk_tea/products/custom_drink.svg")

static func preview(size: int = 64) -> TextureRect:
	var image := TextureRect.new()
	image.custom_minimum_size = Vector2(size, size)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return image

static func show_materials(row: HBoxContainer, inventory: WarehouseInventory, materials: Array) -> void:
	for child: Node in row.get_children():
		child.free()
	for id: String in materials:
		var view := inventory.get_ingredient_view(id)
		if view.is_empty():
			continue
		var image := preview(32)
		image.texture = view.icon
		image.tooltip_text = view.name
		row.add_child(image)
