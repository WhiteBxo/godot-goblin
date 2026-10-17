class_name ShopPopup
extends Control

signal close_requested
signal craft_requested(materials: Array[String])

const LAYOUT_NORMAL: Dictionary = {"center": 40, "margin_x": 24, "margin_y": 20, "gap": 12, "title": 24, "close": 32}
const LAYOUT_CRAFTING: Dictionary = {"center": 16, "margin_x": 12, "margin_y": 10, "gap": 8, "title": 18, "close": 26}

var _production: TeaProduction
var _crafting_panel: CraftingPanel
var _warehouse_panel: WarehousePanel
var _point_id: StringName
var _order_requirements := "制作后成品进入库存，携带到指定 NPC 按 E 交付。"

var _tea: TeaMaking
var _station := false

func _ready() -> void:
	$Center/Panel/Margin/Content/Close.pressed.connect(func() -> void: close_requested.emit())

func bind_tea_making(tea: TeaMaking) -> void:
	_tea = tea
	_tea.changed.connect(_refresh_recipe)
	for ingredient: String in TeaMaking.LABELS:
		var button := Button.new()
		button.text = "加入" + TeaMaking.LABELS[ingredient]
		button.pressed.connect(func() -> void:
			if _tea.add_ingredient(ingredient) == ERR_INVALID_DATA:
				$Center/Panel/Margin/Content/RecipeStatus.text = "顺序错误，请从红茶重新开始。"
			)
		$Center/Panel/Margin/Content/Ingredients.add_child(button)
	_refresh_recipe()

func is_making_station() -> bool:
	return _station

func _refresh_recipe() -> void:
	var demo_recipe := is_instance_valid(_tea) and _tea.has_session()
	$Center/Panel/Margin/Content/Ingredients.visible = _station and demo_recipe
	$Center/Panel/Margin/Content/RecipeStatus.visible = _station and demo_recipe
	if is_instance_valid(_crafting_panel):
		_crafting_panel.visible = _station and not demo_recipe
		$Center/Panel/Margin/Content/DescriptionScroll.visible = (not _station or demo_recipe) and _point_id != &"storage"
	$Center/Panel/Margin/Content/RecipeStatus.text = _tea.get_instruction() if is_instance_valid(_tea) else "当前没有制作目标。"
	for button: Button in $Center/Panel/Margin/Content/Ingredients.get_children():
		button.disabled = not is_instance_valid(_tea) or not _tea.is_active()
	_apply_layout(_station and not demo_recipe)

## The crafting view needs the extra width; other panels keep the roomier default margins.
func _apply_layout(crafting: bool) -> void:
	var preset: Dictionary = LAYOUT_CRAFTING if crafting else LAYOUT_NORMAL
	var center := $Center as MarginContainer
	for side: String in ["left", "right", "top", "bottom"]:
		center.add_theme_constant_override("margin_" + side, int(preset.center))
	var margin := $Center/Panel/Margin as MarginContainer
	margin.add_theme_constant_override("margin_left", int(preset.margin_x))
	margin.add_theme_constant_override("margin_right", int(preset.margin_x))
	margin.add_theme_constant_override("margin_top", int(preset.margin_y))
	margin.add_theme_constant_override("margin_bottom", int(preset.margin_y))
	($Center/Panel/Margin/Content as VBoxContainer).add_theme_constant_override("separation", int(preset.gap))
	($Center/Panel/Margin/Content/Title as Label).add_theme_font_size_override("font_size", int(preset.title))
	($Center/Panel/Margin/Content/Close as Button).custom_minimum_size.y = preset.close

func present(point: InteractionPoint) -> void:
	_point_id = point.interaction_id
	_station = point.interaction_id == &"tea_station"
	if is_instance_valid(_warehouse_panel):
		_warehouse_panel.visible = _point_id == &"storage"
	_refresh_recipe()
	var demo_recipe := is_instance_valid(_tea) and _tea.has_session()
	var crafting := _station and not demo_recipe
	$Center/Panel/Margin/Content/Title.text = point.display_name
	$Center/Panel/Margin/Content/DescriptionScroll/Description.text = (
		"固定配方：珍珠奶茶一杯\n按红茶 → 牛奶 → 珍珠依次投料。\n顺序错误会清空本杯进度；关窗可保留进度。\n仅当前玩法目标可制作，不消耗库存。"
		if _station and is_instance_valid(_tea) else point.description
	)
	$Center/Panel/Margin/Content/DescriptionScroll.scroll_vertical = 0
	if not is_instance_valid(_production):
		return
	if crafting:
		_crafting_panel.refresh(true)
		_crafting_panel.grab_default_focus()
	elif _point_id == &"orders":
		_refresh_order_board()
	elif _point_id == &"storage":
		_warehouse_panel.refresh()

func configure_inventory(inventory: WarehouseInventory) -> void:
	if not is_instance_valid(_warehouse_panel):
		_warehouse_panel = WarehousePanel.new()
		_warehouse_panel.name = "WarehousePanel"
		var content := $Center/Panel/Margin/Content
		content.add_child(_warehouse_panel)
		content.move_child(_warehouse_panel, $Center/Panel/Margin/Content/Close.get_index())
		_warehouse_panel.hide()
	_warehouse_panel.configure(inventory)

func configure_production(production: TeaProduction) -> void:
	if is_instance_valid(_production) and _production.changed.is_connected(_refresh_order_board):
		_production.changed.disconnect(_refresh_order_board)
	_production = production
	_production.changed.connect(_refresh_order_board)
	if not is_instance_valid(_crafting_panel):
		_crafting_panel = preload("res://src/UI/milk_tea/crafting_panel.tscn").instantiate()
		_crafting_panel.name = "ProductionPanel"
		var content := $Center/Panel/Margin/Content
		content.add_child(_crafting_panel)
		content.move_child(_crafting_panel, $Center/Panel/Margin/Content/Close.get_index())
		_crafting_panel.craft_requested.connect(
			func(materials: Array[String]) -> void: craft_requested.emit(materials))
	_crafting_panel.configure(production)
	_crafting_panel.hide()

func get_crafting_panel() -> CraftingPanel:
	return _crafting_panel

func uses_native_gui_input() -> bool:
	return is_instance_valid(_crafting_panel) and _crafting_panel.visible and _crafting_panel.uses_native_gui_input()

func _refresh_order_board() -> void:
	if _point_id == &"orders":
		$Center/Panel/Margin/Content/DescriptionScroll/Description.text = _production.get_order_text() + "\n\n" + _order_requirements

func show_order_requirements(message: String) -> void:
	_order_requirements = message
	_refresh_order_board()

func show_interaction_result(message: String) -> void:
	$Center/Panel/Margin/Content/DescriptionScroll/Description.text = message

func show_production_result(result: Dictionary) -> void:
	if is_instance_valid(_crafting_panel):
		_crafting_panel.show_result(result)

func get_default_focus() -> Control:
	return $Center/Panel/Margin/Content/Close
