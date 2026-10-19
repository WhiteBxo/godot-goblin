class_name HandbookPanel
extends UIScreen
## Shared handbook modal: ModalShell chrome + HandbookBody tabs.

@onready var _shell: ModalShell = $ModalShell

var _body: HandbookBody
var _has_opened := false

func _ready() -> void:
	_body = _shell.get_content() as HandbookBody
	_shell.close_requested.connect(func() -> void: close_requested.emit())
	visibility_changed.connect(_on_visibility_changed)

func bind_journals(tasks: TaskJournal, chronicle: ChronicleJournal) -> void:
	_body.bind_journals(tasks, chronicle)

func bind_inventory(inventory: WarehouseInventory) -> void:
	_body.bind_inventory(inventory)

func bind_characters(journal: CharacterJournal) -> void:
	_body.bind_characters(journal)

func set_delivery_names(target_names: Dictionary, product_names: Dictionary) -> void:
	_body.set_delivery_names(target_names, product_names)

func refresh_access(tasks: bool, chronicle: bool, drinks := false, characters := false) -> void:
	_body.refresh_access(tasks, chronicle, drinks, characters)

func select_page(page: StringName) -> Error:
	var error := _body.select_page(page)
	if error == OK:
		_has_opened = true
	return error

func uses_native_gui_input() -> bool:
	return true

func get_default_focus() -> Control:
	return _shell.get_default_focus()

func get_pages() -> TabContainer:
	return _body.get_pages()

func get_tasks_page() -> TaskPanel:
	return _body.get_tasks_page()

func get_order_history_page() -> TaskPanel:
	return _body.get_order_history_page()

func get_chronicle_page() -> ChroniclePanel:
	return _body.get_chronicle_page()

func get_drinks_page() -> DrinkEncyclopediaPanel:
	return _body.get_drinks_page()

func get_characters_page() -> CharacterRecordsPanel:
	return _body.get_characters_page()

func get_close_button() -> Button:
	return _shell.get_close_button()

func get_shell() -> ModalShell:
	return _shell

func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _has_opened:
		_body.prefer_first_available()
		_has_opened = true
