class_name TaskPopup
extends UIScreen
## Standalone task window used by tests and F6 previews.
## The shipped game opens TaskPanel inside the shared handbook.

@onready var _shell: ModalShell = $ModalShell

var _page: TaskPanel
var _pending_journal: TaskJournal
var _pending_targets: Dictionary = {}
var _pending_products: Dictionary = {}

func _ready() -> void:
	_page = _shell.get_content() as TaskPanel
	_shell.close_requested.connect(func() -> void: close_requested.emit())
	if is_instance_valid(_pending_journal):
		_page.bind_journal(_pending_journal)
		_pending_journal = null
	if not _pending_targets.is_empty() or not _pending_products.is_empty():
		_page.set_delivery_names(_pending_targets, _pending_products)

func bind_journal(journal: TaskJournal) -> void:
	if is_instance_valid(_page):
		_page.bind_journal(journal)
	else:
		_pending_journal = journal

func set_delivery_names(target_names: Dictionary, product_names: Dictionary) -> void:
	if is_instance_valid(_page):
		_page.set_delivery_names(target_names, product_names)
	else:
		_pending_targets = target_names.duplicate(true)
		_pending_products = product_names.duplicate(true)

func uses_native_gui_input() -> bool:
	return true

func get_default_focus() -> Control:
	return _shell.get_default_focus()

func get_entries() -> TaskList:
	return _page.get_entries()

func get_detail_title() -> Label:
	return _page.get_detail_title()

func get_detail_text() -> RichTextLabel:
	return _page.get_detail_text()

func get_body() -> BoxContainer:
	return _page.get_body()

func get_panel_rect() -> Rect2:
	return _shell.get_panel_rect()

func get_close_button() -> Button:
	return _shell.get_close_button()
