class_name HandbookPanel
extends Control

signal close_requested

@onready var _pages: TabContainer = $Margin/Panel/Content/Pages
@onready var _close: Button = $Margin/Panel/Content/Header/Close
@onready var _tasks: TaskPanel = $Margin/Panel/Content/Pages/Tasks
@onready var _chronicle: ChroniclePanel = $Margin/Panel/Content/Pages/Chronicle
var _has_opened := false
var _tasks_available := false
var _chronicle_available := false

func _ready() -> void:
	_tasks.set_embedded(_close)
	_chronicle.set_embedded(_close)
	_pages.set_tab_title(0, "委托")
	_pages.set_tab_title(1, "异闻录")
	_close.pressed.connect(func() -> void: close_requested.emit())
	_pages.tab_changed.connect(_on_tab_changed)
	visibility_changed.connect(_on_visibility_changed)

func bind_journals(tasks: TaskJournal, chronicle: ChronicleJournal) -> void:
	_tasks.bind_journal(tasks)
	_chronicle.bind_journal(chronicle)

func set_delivery_names(target_names: Dictionary, product_names: Dictionary) -> void:
	_tasks.set_delivery_names(target_names, product_names)

func refresh_access(tasks: bool, chronicle: bool) -> void:
	_tasks_available = tasks
	_chronicle_available = chronicle
	_pages.set_tab_hidden(0, not tasks)
	_pages.set_tab_hidden(1, not chronicle)
	if tasks and (_pages.current_tab < 0 or (_pages.current_tab == 1 and not chronicle)):
		_pages.current_tab = 0
	elif chronicle and (_pages.current_tab < 0 or (_pages.current_tab == 0 and not tasks)):
		_pages.current_tab = 1

func select_page(page: StringName) -> Error:
	if (page == &"tasks" and not _tasks_available) or (page == &"chronicle" and not _chronicle_available):
		return ERR_UNAVAILABLE
	if page not in [&"tasks", &"chronicle"]:
		return ERR_INVALID_PARAMETER
	_has_opened = true
	_pages.current_tab = 0 if page == &"tasks" else 1
	return OK

func uses_native_gui_input() -> bool:
	return true

func get_default_focus() -> Control:
	var page := _pages.get_current_tab_control()
	return page.get_default_focus() if page != null else _close

func _on_tab_changed(_index: int) -> void:
	if is_visible_in_tree() and can_process():
		get_default_focus().grab_focus()

func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _has_opened:
		_pages.current_tab = 0 if _tasks_available else 1
		_has_opened = true
