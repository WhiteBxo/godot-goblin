class_name DrinkEncyclopediaPanel
extends VBoxContainer

signal remake_requested(materials: Array[String], iced: bool)

const Artwork = preload("res://src/UI/milk_tea/item_artwork.gd")

var _image: TextureRect
var _materials: HBoxContainer
var _inventory: WarehouseInventory
var _list: ItemList
var _details: Label
var _detail: Control
var _remake: Button
var _feedback: Label
var _selected_id := ""
## The pane only turns when a different drink is opened; a stock refresh of the
## drink already on screen must leave the words still.
var _shown_id := ""

func _ready() -> void:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(row)
	_list = ItemList.new()
	_list.custom_minimum_size.x = 164
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(32, 32)
	_list.item_selected.connect(_select)
	row.add_child(_list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var details_column := VBoxContainer.new()
	details_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(details_column)
	_image = Artwork.preview()
	_image.name = "DrinkImage"
	_image.texture = Artwork.DRINK_ICON
	details_column.add_child(_image)
	_materials = HBoxContainer.new()
	details_column.add_child(_materials)
	_details = Label.new()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_column.add_child(_details)
	_detail = details_column
	_feedback = Label.new()
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_feedback)
	_remake = Button.new()
	_remake.text = "放入制作台"
	_remake.theme_type_variation = &"GhostButton"
	_remake.pressed.connect(func() -> void:
		var record := _inventory.get_drink_record(_selected_id)
		if record.is_empty():
			return
		var materials: Array[String] = []
		materials.assign(record.ingredients)
		remake_requested.emit(materials, record.iced))
	add_child(_remake)

func configure(inventory: WarehouseInventory) -> void:
	if is_instance_valid(_inventory) and _inventory.changed.is_connected(refresh):
		_inventory.changed.disconnect(refresh)
	_inventory = inventory
	_inventory.changed.connect(refresh)
	refresh()

func refresh() -> void:
	_list.clear()
	var selected := -1
	for drink: Dictionary in _inventory.get_drinks(true):
		var index := _list.add_item("%s · %d 杯" % [drink.name, drink.quantity], Artwork.DRINK_ICON)
		_list.set_item_metadata(index, drink.id)
		_list.set_item_tooltip(index, drink.name)
		if drink.id == _selected_id:
			selected = index
	_remake.disabled = _list.item_count == 0
	if _list.item_count == 0:
		_image.visible = false
		Artwork.show_materials(_materials, _inventory, [])
		_selected_id = ""
		_details.text = "尚未发现自由饮品。到制作台选择基底和辅料，制作后会自动记入图鉴。"
		_open_detail()
		return
	selected = maxi(selected, 0)
	_list.select(selected)
	_select(selected)

func _select(index: int) -> void:
	_selected_id = str(_list.get_item_metadata(index))
	var record := _inventory.get_drink_record(_selected_id)
	_image.visible = true
	Artwork.show_materials(_materials, _inventory, record.ingredients)
	_details.text = DrinkFormula.describe(record) + "\n首次发现：第 %d 天 · 库存 %d 杯" % [record.discovered_day, record.quantity]
	var historical_ice: bool = DrinkFormula.ICE_ID in record.ingredients
	_remake.disabled = historical_ice or record.ingredients.size() > _inventory.get_recipe_slots()
	_feedback.text = "冰块现为独立选项，此历史原料配方仅供查看。" if historical_ice else "当前槽位不足以重做此历史配方。" if _remake.disabled else ""
	_open_detail()

## The pane opens on the new drink instead of swapping the words in place.
## Alpha and scale only, so the split layout never reflows.
func _open_detail() -> void:
	var changed := _selected_id != _shown_id
	_shown_id = _selected_id
	if changed and _detail != null:
		UIFlourish.reveal(_detail, 0.99)

func show_remake_result(ok: bool) -> void:
	_feedback.text = "配方已放入制作台，前往制作台即可制作。" if ok else "当前无法重做此配方。"

func get_default_focus() -> Control:
	return _list if _list.item_count > 0 else _remake

func get_list() -> ItemList:
	return _list

func get_details() -> Label:
	return _details

func get_remake_button() -> Button:
	return _remake
