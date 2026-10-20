class_name MarketVendorPopup
extends UIScreen
## A market stall: the goods come first, the vendor's sales pitch follows the
## pick. Nothing is spoken until an item is actually chosen.

const BROWSING_HINT := "看看摊上的货，点一件听听摊主怎么说。"

## A settled sale hands the screen back to the world: the keeper says his piece
## through the normal dialogue window instead of a line inside the stall.
signal farewell_requested(lines: Array)

@onready var _shell: ModalShell = $ModalShell
var _manager: UIManager
var _screen_id: StringName = ScreenIds.MARKET_VENDOR
var _list: ItemList
var _pitch: Label
var _balance: Label
var _quote: Label
var _feedback: Label
var _quantity: SpinBox
var _buy: Button
var _view: Dictionary = {}
var _buy_call := Callable()
var _view_call := Callable()

func _ready() -> void:
	var page := _shell.get_content()
	_list = page.get_node("%Offers")
	_pitch = page.get_node("%Pitch")
	_balance = page.get_node("%Balance")
	_quote = page.get_node("%Quote")
	_feedback = page.get_node("%Feedback")
	_quantity = page.get_node("%Quantity")
	_buy = page.get_node("%Buy")
	_shell.close_requested.connect(func() -> void: close_requested.emit())
	close_requested.connect(_close)
	_list.item_selected.connect(func(_index: int) -> void: _show_pitch())
	_quantity.value_changed.connect(func(_value: float) -> void: _update_quote())
	_buy.pressed.connect(_purchase)

func bind_ui(manager: UIManager, id: StringName) -> void:
	_manager = manager
	_screen_id = id

func uses_native_gui_input() -> bool:
	return true

func get_default_focus() -> Control:
	return _list if is_instance_valid(_list) and _list.item_count > 0 else _shell.get_close_button()

## `buy(product_id, quantity) -> {ok, message}` and `refresh_view() -> Dictionary`
## stay in the chapter layer: the stall knows nothing about prices or day gates.
func present(view: Dictionary, buy: Callable, refresh_view: Callable) -> void:
	_view = view
	_buy_call = buy
	_view_call = refresh_view
	_shell.set_title(str(view.get("title", "摊主")))
	_shell.set_hint(str(view.get("hint", "点一件商品听摊主怎么说 · Enter 买下 · Esc 离开")))
	_feedback.text = ""
	_quantity.set_value_no_signal(1)
	_fill("")
	_list.deselect_all()
	_pitch.text = BROWSING_HINT
	_buy.disabled = true
	_update_quote()
	# Opening the stall orders the goods; it does not pre-pick one of them.
	if is_visible_in_tree():
		_list.grab_focus()

func get_offers() -> ItemList:
	return _list

func get_pitch_text() -> String:
	return _pitch.text

func select_product(product_id: String) -> bool:
	for index in range(_list.item_count):
		if str(_list.get_item_metadata(index)) == product_id:
			_list.select(index)
			_show_pitch()
			return true
	return false

func _close() -> void:
	if is_instance_valid(_manager):
		_manager.close_screen(_screen_id)
	else:
		hide()

func _fill(selected_id: String) -> void:
	_list.clear()
	_balance.text = "余额：%s" % WalletTransactions.format_money(int(_view.get("balance", 0)))
	var next := -1
	for index in range(_view.get("products", []).size()):
		var product: Dictionary = _view.products[index]
		_list.add_item("%s · %s / 份（%d 次用量）" % [
			str(product.get("name", product.get("id", ""))),
			WalletTransactions.format_money(int(product.get("price", 0))),
			int(product.get("portion", 1))])
		var item := _list.item_count - 1
		_list.set_item_metadata(item, str(product.get("id", "")))
		if str(product.get("id", "")) == selected_id:
			next = item
	if next >= 0:
		_list.select(next)
		_show_pitch()

func _selected_product() -> Dictionary:
	var indices := _list.get_selected_items()
	if indices.is_empty():
		return {}
	var id := str(_list.get_item_metadata(indices[0]))
	for product: Dictionary in _view.get("products", []):
		if str(product.get("id", "")) == id:
			return product
	return {}

## The pitch is the vendor's answer to a specific item, so it only appears once
## the player has pointed at one.
func _show_pitch() -> void:
	var product := _selected_product()
	_pitch.text = str(product.get("pitch", BROWSING_HINT)) if not product.is_empty() else BROWSING_HINT
	_update_quote()

func _update_quote() -> void:
	if not is_instance_valid(_buy):
		return
	var product := _selected_product()
	_buy.disabled = product.is_empty()
	if product.is_empty():
		_quote.text = "今天没有可卖的货。" if _list.item_count == 0 else "选一件商品。"
		return
	var count := int(_quantity.value)
	var total := int(product.get("price", 0)) * count
	_quote.text = "单价 %s · %d 份 · 合计 %s" % [
		WalletTransactions.format_money(int(product.get("price", 0))), count,
		WalletTransactions.format_money(total)]
	if total > int(_view.get("balance", 0)):
		_quote.text += " · 余额不足"

func _purchase() -> void:
	if not _buy_call.is_valid() or _buy.disabled:
		return
	var product := _selected_product()
	if product.is_empty():
		return
	_quantity.apply()
	var result: Dictionary = _buy_call.call(str(product.get("id", "")), int(_quantity.value))
	var succeeded := bool(result.get("ok", false))
	var farewell: Array = result.get("farewell", [])
	if succeeded and not farewell.is_empty():
		# The stall closes first so the dialogue window is not stacked on it.
		_close()
		farewell_requested.emit(farewell)
		return
	_feedback.text = str(result.get("message", ""))
	_feedback.theme_type_variation = &"Success" if succeeded else &"Warning"
	if succeeded:
		UIFlourish.settle(_feedback, 0.96)
	else:
		UIFlourish.refuse(_feedback)
	_refresh_from_host()

func _refresh_from_host() -> void:
	if not _view_call.is_valid():
		return
	var next: Variant = _view_call.call()
	if not next is Dictionary:
		return
	var keep := str(_selected_product().get("id", ""))
	_view = next
	_fill(keep)
	if keep.is_empty():
		_pitch.text = BROWSING_HINT
		_update_quote()
