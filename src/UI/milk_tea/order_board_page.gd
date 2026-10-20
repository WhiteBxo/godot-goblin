class_name OrderBoardPage
extends VBoxContainer

signal accept_requested(order_id: String)
signal track_requested(order_id: String)
## An accepted optional order can be given up: a job the player cannot finish
## must never block the counter (关店) without a way out.
signal cancel_requested(order_id: String)

const FILTERS: Array[String] = ["active", "available"]
const TITLES: Array[String] = ["进行中", "可接取"]
## One slip at a time: the queue is walked instead of collapsed, so the player
## sees five orders become five jobs rather than one frame where nothing is left.
const ACCEPT_BEAT := 0.14

@onready var _tabs: TabBar = %OrderTabs
@onready var _list: OrderList = %OrderList
@onready var _ticket: OrderTicket = %Ticket
var _model: OrderBoardModel
var _ids: Array[String] = []
var _selected := ""
var _filter := "active"
var _refreshing := false
## Set while an accept request is in flight. The model projection, not the
## signal return, decides whether the page moves to 进行中.
var _pending_accept := ""
## Set while 一键接单 walks the queue. The board keeps 可接取 on screen for the
## duration so the list visibly empties, then lands on 进行中 once.
var _accepting_all := false

func _ready() -> void:
	_tabs.tab_changed.connect(func(index: int) -> void:
		if _refreshing or index < 0 or index >= FILTERS.size():
			return
		_filter = FILTERS[index]
		refresh())
	_list.selection_requested.connect(func(id: String) -> void:
		if not _refreshing:
			_selected = id
			refresh())
	_ticket.primary_pressed.connect(_primary)
	_ticket.secondary_pressed.connect(_secondary)
	%AcceptAll.pressed.connect(_accept_all)
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
		if entry.status == "active" and _is_milk_order(entry):
			_filter = "active"
			break
	_sync_tab()
	refresh()

func refresh() -> void:
	if not is_node_ready() or _refreshing:
		return
	_refreshing = true
	var scroll := _list.get_v_scroll_bar().value
	var entries: Array[Dictionary] = []
	if is_instance_valid(_model):
		entries = _model.get_entries()
	_resolve_pending_accept()
	var counts := {"active": 0, "available": 0}
	_ids.clear()
	var filtered: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if not counts.has(entry.status) or not _is_milk_order(entry):
			continue
		var bucket: String = entry.status
		counts[bucket] += 1
		if bucket == _filter:
			_ids.append(entry.order_id)
			filtered.append(entry)
	for index: int in range(FILTERS.size()):
		_tabs.set_tab_title(index, "%s %d" % [TITLES[index], counts[FILTERS[index]]])
	%AcceptAll.text = "一键接单（%d）" % counts.available
	%AcceptAll.disabled = counts.available == 0 or _accepting_all
	var choose_first := _selected not in _ids
	if choose_first:
		_selected = _ids[0] if not _ids.is_empty() else ""
	_sync_tab()
	_list.set_entries(filtered, _selected)
	_list.get_v_scroll_bar().set_deferred("value", scroll)
	_refresh_detail()
	_refreshing = false

func _accept_all() -> void:
	if _accepting_all or not is_instance_valid(_model):
		return
	var pending: Array[String] = []
	for entry: Dictionary in _model.get_entries():
		if entry.status == "available" and _is_milk_order(entry):
			pending.append(entry.order_id)
	if pending.is_empty():
		return
	_accepting_all = true
	var start_filter := _filter
	%AcceptAll.disabled = true
	var accepted := ""
	for id: String in pending:
		if not is_inside_tree() or _model.get_entry(id).get("status") != "available":
			continue
		_selected = id
		accept_requested.emit(id)
		if _model.get_entry(id).get("status") != "active":
			continue
		accepted = id
		# The slip leaves the list, the ticket turns to the next customer and the
		# button count drops: one order's worth of beat before the next one.
		await get_tree().create_timer(ACCEPT_BEAT).timeout
	_accepting_all = false
	if not is_inside_tree():
		return
	# The queue has drained: the player is looking at the work, not the offers.
	if _filter == start_filter and _filter == "available":
		_filter = "active"
		if not accepted.is_empty():
			_selected = accepted
	refresh()

func _is_milk_order(entry: Dictionary) -> bool:
	return not str(entry.get("product_id", "")).is_empty() or entry.get("free_formula", false)

## A successful accept moves the board to 进行中 exactly once, even when the
## project refresh arrives from a model change rather than this call stack.
func _resolve_pending_accept() -> void:
	if _pending_accept.is_empty():
		return
	var pending := _model.get_entry(_pending_accept) if is_instance_valid(_model) else {}
	if pending.get("status") == "active":
		_filter = "active"
		_selected = _pending_accept
	_pending_accept = ""

## Programmatic tab changes stay silent so the filter has one owner: this page.
func _sync_tab() -> void:
	var index := FILTERS.find(_filter)
	if index < 0 or _tabs.current_tab == index:
		return
	_tabs.set_block_signals(true)
	_tabs.set_current_tab(index)
	_tabs.set_block_signals(false)

func _refresh_detail() -> void:
	var entry := _model.get_entry(_selected) if is_instance_valid(_model) else {}
	var action := ""
	var enabled := false
	var secondary := ""
	if entry.get("status") == "available":
		action = "接取订单"
		enabled = true
	elif entry.get("status") == "active":
		var tracked := _model.get_tracked_entry()
		var current: bool = tracked.get("order_id") == _selected
		# Done cups are handed over at the counter, so this page only points at
		# the order; it never settles one from the menu.
		action = "正在追踪" if current else "追踪此单"
		enabled = not current
		# The customer waits on this optional order: offer the way out on the
		# slip instead of hiding it in the chapter menu.
		if entry.get("allow_cancel", false):
			secondary = "取消订单"
	_ticket.present(entry, action, enabled, secondary)

func _secondary() -> void:
	if _selected.is_empty():
		return
	cancel_requested.emit(_selected)

func _primary() -> void:
	var entry := _model.get_entry(_selected)
	if entry.get("status") == "available":
		_pending_accept = _selected
		accept_requested.emit(_selected)
		# A rejected accept leaves the order available; the note below then
		# stays on 可接取 instead of pretending the order moved.
		refresh()
	elif entry.get("status") == "active":
		track_requested.emit(_selected)

func select_order(order_id: String) -> bool:
	var entry := _model.get_entry(order_id)
	if entry.is_empty() or entry.status not in FILTERS or not _is_milk_order(entry):
		return false
	_filter = entry.status
	_selected = order_id
	_sync_tab()
	refresh()
	return true

func get_default_focus() -> Control:
	return _list.get_default_focus() if not _ids.is_empty() else _tabs

func get_ticket() -> OrderTicket:
	return _ticket

func get_selected_id() -> String:
	return _selected

func get_active_filter() -> String:
	return _filter

func get_tabs() -> TabBar:
	return _tabs
