class_name HandbookBody
extends VBoxContainer
## Shared handbook content: tabs and the two browser pages. No modal chrome here.

@onready var _pages: TabContainer = %Pages
@onready var _tasks: TaskPanel = $Pages/Tasks
@onready var _chronicle: ChroniclePanel = $Pages/Chronicle
@onready var _drinks: DrinkEncyclopediaPanel = $Pages/Drinks

var _tasks_available := false
var _chronicle_available := false
var _drinks_available := false

func _ready() -> void:
	_pages.set_tab_title(0, "委托")
	_pages.set_tab_title(1, "异闻录")
	_pages.set_tab_title(2, "饮品图鉴")

func bind_inventory(inventory: WarehouseInventory) -> void:
	_drinks.configure(inventory)

func bind_journals(tasks: TaskJournal, chronicle: ChronicleJournal) -> void:
	_tasks.bind_journal(tasks)
	_chronicle.bind_journal(chronicle)

func set_delivery_names(target_names: Dictionary, product_names: Dictionary) -> void:
	_tasks.set_delivery_names(target_names, product_names)

func refresh_access(tasks: bool, chronicle: bool, drinks := false) -> void:
	_tasks_available = tasks
	_chronicle_available = chronicle
	_drinks_available = drinks
	_pages.set_tab_hidden(0, not tasks)
	_pages.set_tab_hidden(1, not chronicle)
	_pages.set_tab_hidden(2, not drinks)
	if _pages.current_tab < 0 or not [tasks, chronicle, drinks][_pages.current_tab]:
		prefer_first_available()

func prefer_first_available() -> void:
	_pages.current_tab = 0 if _tasks_available else 1 if _chronicle_available else 2 if _drinks_available else -1

func select_page(page: StringName) -> Error:
	if (page == &"tasks" and not _tasks_available) or (page == &"chronicle" and not _chronicle_available) or (page == &"drinks" and not _drinks_available):
		return ERR_UNAVAILABLE
	if page not in [&"tasks", &"chronicle", &"drinks"]:
		return ERR_INVALID_PARAMETER
	_pages.current_tab = {&"tasks": 0, &"chronicle": 1, &"drinks": 2}[page]
	return OK

func get_default_focus() -> Control:
	var page := _pages.get_current_tab_control()
	return page.get_default_focus() if page != null else null

func get_pages() -> TabContainer:
	return _pages

func get_tasks_page() -> TaskPanel:
	return _tasks

func get_chronicle_page() -> ChroniclePanel:
	return _chronicle

func get_drinks_page() -> DrinkEncyclopediaPanel:
	return _drinks
