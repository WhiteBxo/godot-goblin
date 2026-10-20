class_name InventoryPanel
extends UIScreen
## 原料图鉴：共享模态外壳包着只读的原料列表。
## It reads the single WarehouseInventory owned by GameState and keeps no stock state.

var _panel: WarehousePanel

@onready var _shell: ModalShell = $ModalShell

func _ready() -> void:
	_panel = _shell.get_content() as WarehousePanel
	if not is_instance_valid(_panel):
		push_error("InventoryPanel: content scene must be a WarehousePanel.")
		return
	_panel.set_ingredients_only(true)
	_shell.close_requested.connect(func() -> void: close_requested.emit())

func configure(inventory: WarehouseInventory) -> void:
	if not is_instance_valid(_panel) or inventory == null:
		push_error("InventoryPanel: cannot bind a missing page or inventory.")
		return
	_panel.configure(inventory)

func refresh() -> void:
	if is_instance_valid(_panel):
		_panel.refresh()

func get_warehouse_panel() -> WarehousePanel:
	return _panel

func get_shell() -> ModalShell:
	return _shell

func get_default_focus() -> Control:
	return _shell.get_default_focus()

func uses_native_gui_input() -> bool:
	# ItemList and the filter OptionButton handle their own key navigation.
	return true
