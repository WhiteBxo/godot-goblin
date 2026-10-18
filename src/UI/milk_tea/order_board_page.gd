class_name OrderBoardPage
extends VBoxContainer

signal accept_requested(order_id: String)
signal track_requested(order_id: String)

const FILTERS: Array[String] = ["active", "available", "completed"]
const TITLES: Array[String] = ["进行中", "可接取", "已结束"]

@onready var _tabs: TabBar = %OrderTabs
@onready var _list: OrderList = %OrderList
@onready var _ticket: OrderTicket = %Ticket
var _model: OrderBoardModel
var _ids: Array[String] = []
var _selected := ""
var _filter := "active"
var _refreshing := false

func _ready() -> void:
	_tabs.tab_changed.connect(func(index: int) -> void:
		_filter = FILTERS[index]
		refresh())
	_list.selection_requested.connect(func(id: String) -> void:
		if not _refreshing:
			_selected = id
			refresh())
	_ticket.primary_pressed.connect(_primary)
	refresh()

func configure(model: OrderBoardModel) -> void:
	if is_instance_valid(_model) and _model.changed.is_connected(refresh):
		_model.changed.disconnect(refresh)
	_model = model
	_model.changed.connect(refresh)
	refresh()

func present() -> void:
	_filter = "available"
	for entry: Dictionary in _model.get_entries():
		if entry.status == "active":
			_filter = "active"
			break
	_tabs.set_current_tab(FILTERS.find(_filter))
	refresh()

func refresh() -> void:
	if not is_node_ready() or _refreshing:
		return
	_refreshing = true
	var scroll := _list.get_v_scroll_bar().value
	var entries: Array[Dictionary] = []
	if is_instance_valid(_model):
		entries = _model.get_entries()
	var counts := {"active": 0, "available": 0, "completed": 0}
	_ids.clear()
	var filtered: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var bucket: String = entry.status if counts.has(entry.status) else "completed"
		counts[bucket] += 1
		if bucket == _filter:
			_ids.append(entry.order_id)
			filtered.append(entry)
	for index: int in range(FILTERS.size()):
		_tabs.set_tab_title(index, "%s %d" % [TITLES[index], counts[FILTERS[index]]])
	var choose_first := _selected not in _ids
	if choose_first:
		_selected = _ids[0] if not _ids.is_empty() else ""
	_list.set_entries(filtered, _selected)
	_list.get_v_scroll_bar().set_deferred("value", scroll)
	_refresh_detail()
	_refreshing = false

func _refresh_detail() -> void:
	var entry := _model.get_entry(_selected) if is_instance_valid(_model) else {}
	var action := ""
	var enabled := false
	if entry.get("status") == "available":
		action = "接取订单"
		enabled = true
	elif entry.get("status") == "active":
		var tracked := _model.get_tracked_entry()
		var current: bool = tracked.get("order_id") == _selected
		action = "正在追踪" if current else "追踪此单"
		enabled = not current
	_ticket.present(entry, action, enabled)

func _primary() -> void:
	var entry := _model.get_entry(_selected)
	if entry.get("status") == "available":
		var id := _selected
		accept_requested.emit(id)
		if _model.get_entry(id).get("status") == "active":
			_filter = "active"
			_selected = id
			_tabs.set_current_tab(0)
			refresh()
	elif entry.get("status") == "active":
		track_requested.emit(_selected)

func select_order(order_id: String) -> bool:
	var entry := _model.get_entry(order_id)
	if entry.is_empty():
		return false
	_filter = entry.status
	_selected = order_id
	_tabs.set_current_tab(FILTERS.find(_filter))
	refresh()
	return true

func get_default_focus() -> Control:
	return _list.get_default_focus() if not _ids.is_empty() else _tabs

func get_ticket() -> OrderTicket:
	return _ticket

func get_selected_id() -> String:
	return _selected
