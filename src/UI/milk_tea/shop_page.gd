class_name ShopPage
extends VBoxContainer
## Shop content page: description, tea-making ingredients, crafting and warehouse.
## The page owns no modal chrome; ShopPopup puts it in the shared ModalShell.

signal craft_requested(materials: Array[String], quantity: int)
signal accept_requested(order_id: String)
signal track_requested(order_id: String)

var _production: TeaProduction
var _crafting_panel: CraftingPanel
var _warehouse_panel: WarehousePanel
var _point_id: StringName
var _order_requirements := "制作后成品进入库存，携带到指定 NPC 按 E 交付。"
var _tea: TeaMaking
var _station := false
var _orders: OrderBoardModel

@onready var _description_scroll: ScrollContainer = %DescriptionScroll
@onready var _description: Label = %Description
@onready var _recipe_status: Label = %RecipeStatus
@onready var _ingredients: HBoxContainer = %Ingredients
@onready var _body: VBoxContainer = %Body
@onready var _board: OrderBoardPage = $OrderBoard
@onready var _craft_modes: TabBar = $CraftModes
@onready var _order_crafting: OrderCraftingPage = $Body/OrderCrafting

func _ready() -> void:
	move_child(_craft_modes, 0)
	_board.accept_requested.connect(func(id: String) -> void: accept_requested.emit(id))
	_board.track_requested.connect(func(id: String) -> void: track_requested.emit(id))
	_order_crafting.track_requested.connect(func(id: String) -> void: track_requested.emit(id))
	_order_crafting.craft_requested.connect(func(materials: Array[String], quantity: int) -> void: craft_requested.emit(materials, quantity))
	_craft_modes.tab_changed.connect(func(_index: int) -> void: _refresh_recipe())

func configure_orders(model: OrderBoardModel) -> void:
	_orders = model
	_board.configure(model)
	_order_crafting.configure(model)

func get_order_board_page() -> OrderBoardPage:
	return _board

func get_order_crafting_page() -> OrderCraftingPage:
	return _order_crafting

func select_crafting_mode(free: bool) -> void:
	_craft_modes.current_tab = 1 if free else 0
	_refresh_recipe()
	if free and is_instance_valid(_crafting_panel) and is_visible_in_tree():
		_crafting_panel.grab_default_focus()

func get_default_focus() -> Control:
	if _board.visible:
		return _board.get_default_focus()
	if _order_crafting.visible:
		return _order_crafting.get_default_focus()
	if is_instance_valid(_crafting_panel) and _crafting_panel.visible:
		return _crafting_panel.get_default_focus()
	return null

func bind_tea_making(tea: TeaMaking) -> void:
	_tea = tea
	_tea.changed.connect(_refresh_recipe)
	for ingredient: String in TeaMaking.LABELS:
		var button := Button.new()
		button.text = "加入" + TeaMaking.LABELS[ingredient]
		button.theme_type_variation = &"GhostButton"
		button.pressed.connect(func() -> void:
			if _tea.add_ingredient(ingredient) == ERR_INVALID_DATA:
				_recipe_status.text = "顺序错误，请从红茶重新开始。"
			)
		_ingredients.add_child(button)
	_refresh_recipe()

func is_making_station() -> bool:
	return _station

func _refresh_recipe() -> void:
	var demo_recipe := is_instance_valid(_tea) and _tea.has_session()
	var crafting := _station and not demo_recipe
	var order_mode := crafting and is_instance_valid(_orders) and _craft_modes.current_tab == 0
	_board.visible = _point_id == &"orders" and is_instance_valid(_orders)
	_craft_modes.visible = crafting and is_instance_valid(_orders)
	_order_crafting.visible = order_mode
	_ingredients.visible = _station and demo_recipe
	_recipe_status.visible = _station and demo_recipe
	_body.visible = crafting or _point_id == &"storage"
	if is_instance_valid(_crafting_panel):
		_crafting_panel.visible = crafting and not order_mode
	if is_instance_valid(_warehouse_panel):
		_warehouse_panel.visible = _point_id == &"storage"
	_description_scroll.visible = (not _station or demo_recipe) and _point_id != &"storage" and not _board.visible
	_recipe_status.text = _tea.get_instruction() if is_instance_valid(_tea) else "当前没有制作目标。"
	for button: Button in _ingredients.get_children():
		button.disabled = not is_instance_valid(_tea) or not _tea.is_active()

func present(point: InteractionPoint) -> void:
	_point_id = point.interaction_id
	_station = point.interaction_id == &"tea_station"
	_description.text = (
		"固定配方：珍珠奶茶一杯\n按红茶 → 牛奶 → 珍珠依次投料。\n顺序错误会清空本杯进度；关窗可保留进度。\n仅当前玩法目标可制作，不消耗库存。"
		if _station and is_instance_valid(_tea) else point.description
	)
	_description_scroll.scroll_vertical = 0
	_refresh_recipe()
	if not is_instance_valid(_production):
		return
	if _station and not (is_instance_valid(_tea) and _tea.has_session()):
		_craft_modes.current_tab = 0
		_refresh_recipe()
		if is_instance_valid(_orders):
			_order_crafting.present()
		_crafting_panel.refresh(true)
		if _crafting_panel.visible:
			_crafting_panel.grab_default_focus()
	elif _point_id == &"orders":
		if is_instance_valid(_orders):
			_board.present()
		_refresh_order_board()
	elif _point_id == &"storage":
		_warehouse_panel.refresh()

func configure_inventory(inventory: WarehouseInventory) -> void:
	if not is_instance_valid(_warehouse_panel):
		_warehouse_panel = WarehousePanel.new()
		_warehouse_panel.name = "WarehousePanel"
		_warehouse_panel.visible = false
		_body.add_child(_warehouse_panel)
	_warehouse_panel.configure(inventory)

func configure_production(production: TeaProduction) -> void:
	if is_instance_valid(_production) and _production.changed.is_connected(_refresh_order_board):
		_production.changed.disconnect(_refresh_order_board)
	_production = production
	_production.changed.connect(_refresh_order_board)
	if not is_instance_valid(_crafting_panel):
		_crafting_panel = preload("res://src/UI/milk_tea/crafting_panel.tscn").instantiate()
		_crafting_panel.name = "CraftingPanel"
		_crafting_panel.visible = false
		_body.add_child(_crafting_panel)
		_crafting_panel.craft_requested.connect(
			func(materials: Array[String], quantity: int) -> void: craft_requested.emit(materials, quantity))
	_crafting_panel.configure(production)

func get_crafting_panel() -> CraftingPanel:
	return _crafting_panel

func get_warehouse_panel() -> WarehousePanel:
	return _warehouse_panel

func get_ingredients() -> HBoxContainer:
	return _ingredients

func get_description_text() -> String:
	return _description.text

func get_description_label() -> Label:
	return _description

func uses_native_gui_input() -> bool:
	return _board.visible or _order_crafting.visible or (is_instance_valid(_crafting_panel) and _crafting_panel.visible and _crafting_panel.uses_native_gui_input())

func _refresh_order_board() -> void:
	if _point_id == &"orders":
		_description.text = _production.get_order_text() + "\n\n" + _order_requirements

func show_order_requirements(message: String) -> void:
	_order_requirements = message
	_refresh_order_board()

func show_interaction_result(message: String) -> void:
	_description.text = message

func show_production_result(result: Dictionary) -> void:
	_order_crafting.show_result(result)
	if is_instance_valid(_crafting_panel):
		_crafting_panel.show_result(result)
