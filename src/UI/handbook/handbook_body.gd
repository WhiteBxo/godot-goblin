class_name HandbookBody
extends VBoxContainer
## Shared handbook content: tabs and browser pages. No modal chrome here.

@onready var _pages: TabContainer = %Pages
@onready var _tasks: TaskPanel = $Pages/Tasks
@onready var _chronicle: ChroniclePanel = $Pages/Chronicle
@onready var _drinks: DrinkEncyclopediaPanel = $Pages/Drinks
@onready var _characters: CharacterRecordsPanel = $Pages/Characters
@onready var _order_history: TaskPanel = $Pages/Orders

var _tasks_available := false
var _chronicle_available := false
var _drinks_available := false
var _characters_available := false

func _ready() -> void:
	_pages.set_tab_title(0, "任务日志")
	_pages.set_tab_title(1, "异闻录")
	_pages.set_tab_title(2, "哥布林饮品图鉴")
	_pages.set_tab_title(3, "人物记录")
	_pages.set_tab_title(4, "奶茶订单")
	_pages.tab_changed.connect(_reveal_page)

## Flipping a tab opens that page instead of swapping the words underneath the
## eye. Only alpha and scale move, so nothing reflows.
func _reveal_page(_index: int) -> void:
	var page := _pages.get_current_tab_control()
	if page != null:
		UIFlourish.reveal(page, 0.99)

func bind_characters(journal: CharacterJournal) -> void:
	_characters.bind_journal(journal)

func bind_inventory(inventory: WarehouseInventory) -> void:
	_drinks.configure(inventory)

func bind_journals(tasks: TaskJournal, chronicle: ChronicleJournal) -> void:
	_tasks.bind_journal(tasks)
	_order_history.bind_journal(tasks)
	_chronicle.bind_journal(chronicle)

func set_delivery_names(target_names: Dictionary, product_names: Dictionary) -> void:
	_tasks.set_delivery_names(target_names, product_names)
	_order_history.set_delivery_names(target_names, product_names)

func refresh_access(tasks: bool, chronicle: bool, drinks := false, characters := false) -> void:
	_tasks_available = tasks
	_chronicle_available = chronicle
	_drinks_available = drinks
	_characters_available = characters
	_pages.set_tab_hidden(0, not tasks)
	_pages.set_tab_hidden(1, not chronicle)
	_pages.set_tab_hidden(2, not drinks)
	_pages.set_tab_hidden(3, not characters)
	if _pages.current_tab < 0 or not [tasks, chronicle, drinks, characters, true][_pages.current_tab]:
		prefer_first_available()

func prefer_first_available() -> void:
	_pages.current_tab = 0 if _tasks_available else 1 if _chronicle_available else 2 if _drinks_available else 3 if _characters_available else -1

func select_page(page: StringName) -> Error:
	if (page == ScreenIds.TASKS and not _tasks_available) or (page == ScreenIds.CHRONICLE and not _chronicle_available) or (page == ScreenIds.DRINKS and not _drinks_available) or (page == ScreenIds.CHARACTERS and not _characters_available):
		return ERR_UNAVAILABLE
	if page not in [ScreenIds.TASKS, ScreenIds.CHRONICLE, ScreenIds.DRINKS, ScreenIds.CHARACTERS, ScreenIds.ORDER_HISTORY]:
		return ERR_INVALID_PARAMETER
	_pages.current_tab = {ScreenIds.TASKS: 0, ScreenIds.CHRONICLE: 1, ScreenIds.DRINKS: 2, ScreenIds.CHARACTERS: 3, ScreenIds.ORDER_HISTORY: 4}[page]
	return OK

func get_default_focus() -> Control:
	var page := _pages.get_current_tab_control()
	return page.get_default_focus() if page != null else null

func get_pages() -> TabContainer:
	return _pages

func get_tasks_page() -> TaskPanel:
	return _tasks

func get_order_history_page() -> TaskPanel:
	return _order_history

func get_chronicle_page() -> ChroniclePanel:
	return _chronicle

func get_drinks_page() -> DrinkEncyclopediaPanel:
	return _drinks

func get_characters_page() -> CharacterRecordsPanel:
	return _characters
