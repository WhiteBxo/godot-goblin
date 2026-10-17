class_name ShopPopup
extends UIScreen
## Shop modal wrapper: ModalShell chrome + ShopPage content.

signal craft_requested(materials: Array[String], quantity: int)

@onready var _shell: ModalShell = $ModalShell

var _page: ShopPage

func _ready() -> void:
	_page = _shell.get_content() as ShopPage
	_shell.close_requested.connect(func() -> void: close_requested.emit())
	_page.craft_requested.connect(
		func(materials: Array[String], quantity: int) -> void: craft_requested.emit(materials, quantity))

func present(point: InteractionPoint) -> void:
	_shell.set_title(point.display_name)
	_page.present(point)

func bind_tea_making(tea: TeaMaking) -> void:
	_page.bind_tea_making(tea)

func is_making_station() -> bool:
	return _page.is_making_station()

func configure_inventory(inventory: WarehouseInventory) -> void:
	_page.configure_inventory(inventory)

func configure_production(production: TeaProduction) -> void:
	_page.configure_production(production)

func get_crafting_panel() -> CraftingPanel:
	return _page.get_crafting_panel()

func get_warehouse_panel() -> WarehousePanel:
	return _page.get_warehouse_panel()

func get_page() -> ShopPage:
	return _page

func uses_native_gui_input() -> bool:
	return _page.uses_native_gui_input()

func get_default_focus() -> Control:
	return _shell.get_default_focus()

func get_title() -> String:
	return _shell.title

func get_shell() -> ModalShell:
	return _shell

func get_panel_rect() -> Rect2:
	return _shell.get_panel_rect()

func show_order_requirements(message: String) -> void:
	_page.show_order_requirements(message)

func show_interaction_result(message: String) -> void:
	_page.show_interaction_result(message)

func show_production_result(result: Dictionary) -> void:
	_page.show_production_result(result)
