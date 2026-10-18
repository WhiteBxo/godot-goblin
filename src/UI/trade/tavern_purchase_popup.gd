class_name TavernPurchasePopup
extends UIScreen

@onready var _shell: ModalShell = $ModalShell
var _service: TavernPurchase
var _manager: UIManager
var _screen_id: StringName = ScreenIds.TAVERN_PURCHASE
var _list: ItemList
var _quantity: SpinBox
var _balance: Label
var _quote: Label
var _feedback: Label
var _buy: Button
var _again: Button
var _offers: Array[Dictionary] = []
var _request_id := ""
var _submitted := false
var _submitting := false

func _ready() -> void:
	var page := _shell.get_content()
	_list = page.get_node("%Offers")
	_quantity = page.get_node("%Quantity")
	_balance = page.get_node("%Balance")
	_quote = page.get_node("%Quote")
	_feedback = page.get_node("%Feedback")
	_buy = page.get_node("%Buy")
	_again = page.get_node("%Again")
	_shell.close_requested.connect(func() -> void: close_requested.emit())
	close_requested.connect(_close)
	_list.item_selected.connect(func(_index: int) -> void: _new_request())
	_quantity.value_changed.connect(func(_value: float) -> void: _new_request())
	_buy.pressed.connect(_purchase)
	_again.pressed.connect(_new_request)
	visibility_changed.connect(_on_visibility_changed)
	_refresh()
	_new_request()

func configure(service: TavernPurchase) -> void:
	_disconnect_service()
	_service = service
	_connect_service()
	if is_node_ready():
		_refresh()
		_new_request()

func _enter_tree() -> void:
	_connect_service()

func _exit_tree() -> void:
	_disconnect_service()

func _connect_service() -> void:
	if is_instance_valid(_service) and not _service.changed.is_connected(_refresh):
		_service.changed.connect(_refresh)

func _disconnect_service() -> void:
	if is_instance_valid(_service) and _service.changed.is_connected(_refresh):
		_service.changed.disconnect(_refresh)

func bind_ui(manager: UIManager, id: StringName) -> void:
	_manager = manager
	_screen_id = id

func uses_native_gui_input() -> bool:
	return true

func get_default_focus() -> Control:
	return _list if is_instance_valid(_list) and _list.item_count > 0 else _shell.get_close_button()

func on_ui_closed() -> void:
	# Closing cancels only the local confirmation, never business facts or input locks.
	_request_id = ""

func _close() -> void:
	if is_instance_valid(_manager):
		_manager.close_screen(_screen_id)
	else:
		hide()
		on_ui_closed()

func _on_visibility_changed() -> void:
	if visible and is_node_ready():
		_refresh()
		_new_request()

func _new_request() -> void:
	if _submitting:
		return
	_request_id = "tavern:" + Crypto.new().generate_random_bytes(16).hex_encode()
	_submitted = false
	if is_instance_valid(_feedback):
		_feedback.text = ""
		_feedback.theme_type_variation = &"Hint"
	_update_quote()

func _refresh() -> void:
	if not is_instance_valid(_list):
		return
	var selected := ""
	var indices := _list.get_selected_items()
	if not indices.is_empty() and indices[0] < _offers.size():
		selected = _offers[indices[0]].product_id
	_offers = _service.get_offers() if is_instance_valid(_service) else []
	_list.clear()
	var next_index := 0
	for offer: Dictionary in _offers:
		var stock_text := "不限量" if offer.remaining < 0 else "余量 %d" % offer.remaining
		_list.add_item("%s · %s · %s" % [offer.display_name, WalletTransactions.format_money(offer.unit_price), stock_text])
		if offer.product_id == selected:
			next_index = _list.item_count - 1
	if _list.item_count > 0:
		_list.select(next_index)
	_balance.text = "余额：%s" % WalletTransactions.format_money(_service.get_balance() if is_instance_valid(_service) else 0)
	_update_quote()

func _update_quote() -> void:
	if not is_instance_valid(_buy):
		return
	_again.visible = _submitted
	var indices := _list.get_selected_items()
	_buy.disabled = _submitted or _submitting or indices.is_empty()
	if indices.is_empty():
		_quote.text = "商品与价格尚未配置。"
		return
	var offer: Dictionary = _offers[indices[0]]
	var quantity := int(_quantity.value)
	var total: int = offer.unit_price * quantity
	var price_text := "单价 %s" % WalletTransactions.format_money(offer.unit_price)
	if offer.has("discounted_price"):
		price_text = "原价 %s → 折后 %s" % [WalletTransactions.format_money(offer.price), WalletTransactions.format_money(offer.unit_price)]
	_quote.text = "%s · %d 份 · 合计 %s" % [price_text, quantity, WalletTransactions.format_money(total)]
	if _submitted:
		_quote.text += " · 已完成"
	elif offer.remaining == 0:
		_quote.text += " · 已售罄"
	elif offer.remaining > 0 and quantity > offer.remaining:
		_quote.text += " · 库存不足"
	elif total > _service.get_balance():
		_quote.text += " · 余额不足"

func _purchase() -> void:
	if _submitting or _submitted or _request_id.is_empty() or not is_instance_valid(_service):
		return
	_quantity.apply()
	var indices := _list.get_selected_items()
	if indices.is_empty():
		return
	_submitting = true
	var result := _service.purchase(_offers[indices[0]].product_id, int(_quantity.value), _request_id)
	_submitting = false
	_submitted = result.ok or result.code == "duplicate_transaction"
	_feedback.text = result.message
	_feedback.theme_type_variation = &"Success" if result.ok else &"Warning"
	_refresh()
