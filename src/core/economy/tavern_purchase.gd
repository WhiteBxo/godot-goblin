class_name TavernPurchase
extends Node
## A view/controller over the injected session wallet; owns no balance or stock.
## Compile offers BEFORE constructing the wallet. Runtime repricing needs a wallet API.

signal changed

var _wallet: WalletTransactions
var _offers: Dictionary = {}

## Offers: product_id -> {item_id, price, discounted_price?, stock?}.
## An explicit final integer price avoids inventing a discount rounding policy.
static func compile_products(offers: Dictionary) -> Dictionary:
	var products := {}
	for id: Variant in offers:
		var offer: Variant = offers[id]
		if not id is String or id.strip_edges().is_empty() or not offer is Dictionary:
			return {"ok": false, "products": {}}
		for key: Variant in offer:
			if key not in ["item_id", "price", "discounted_price", "stock"]:
				return {"ok": false, "products": {}}
		if not offer.get("item_id") is String or not _amount(offer.get("price")):
			return {"ok": false, "products": {}}
		var price: Variant = offer.get("discounted_price", offer.price)
		if not _amount(price) or price > offer.price or (offer.has("stock") and not _amount(offer.stock)):
			return {"ok": false, "products": {}}
		var product := {"item_id": offer.item_id, "price": price}
		if offer.has("stock"):
			product.stock = offer.stock
		products[id] = product
	return {"ok": true, "products": products}

## The host supplies the same immutable offers used to compile TeaMenu.products.
## WalletTransactions has no public configuration getter; see the integration contract.
func configure(wallet: WalletTransactions, offers: Dictionary) -> Error:
	if not is_instance_valid(wallet) or wallet.is_busy():
		return ERR_UNAVAILABLE
	var compiled := compile_products(offers)
	if not compiled.ok:
		return ERR_INVALID_DATA
	var defaults := wallet.get_default_state()
	for id: String in compiled.products:
		var product: Dictionary = compiled.products[id]
		if wallet.get_inventory().get_definition(product.item_id) == null:
			return ERR_INVALID_DATA
		if product.has("stock") != defaults.merchant_stock.has(id):
			return ERR_INVALID_DATA
		if product.has("stock") and product.stock != defaults.merchant_stock[id]:
			return ERR_INVALID_DATA
	_disconnect_wallet()
	_wallet = wallet
	_offers = offers.duplicate(true)
	_connect_wallet()
	changed.emit()
	return OK

func _enter_tree() -> void:
	_connect_wallet()

func _exit_tree() -> void:
	_disconnect_wallet()

func _connect_wallet() -> void:
	if is_instance_valid(_wallet) and not _wallet.changed.is_connected(_on_wallet_changed):
		_wallet.changed.connect(_on_wallet_changed)

func _disconnect_wallet() -> void:
	if is_instance_valid(_wallet) and _wallet.changed.is_connected(_on_wallet_changed):
		_wallet.changed.disconnect(_on_wallet_changed)

func _on_wallet_changed() -> void:
	changed.emit()

func get_balance() -> int:
	return _wallet.get_balance() if is_instance_valid(_wallet) else 0

func get_offers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(_wallet):
		return result
	var stock: Dictionary = _wallet.to_dict().merchant_stock
	for id: String in _offers:
		var offer: Dictionary = _offers[id].duplicate(true)
		offer.product_id = id
		offer.unit_price = offer.get("discounted_price", offer.price)
		offer.remaining = stock.get(id, -1)
		offer.display_name = _wallet.get_inventory().get_definition(offer.item_id).display_name
		result.append(offer)
	return result

func purchase(product_id: String, quantity: Variant, request_id: String) -> Dictionary:
	if not is_instance_valid(_wallet) or not _offers.has(product_id):
		return {"ok": false, "code": "unavailable", "message": "商品尚未配置。", "request_id": request_id,
			"balance": get_balance(), "money_delta": 0, "items": {}}
	# Never split debit, inventory addition, merchant stock or receipts into calls.
	return _wallet.purchase(product_id, quantity, request_id)

static func _amount(value: Variant) -> bool:
	return value is int and value >= 0 and value <= WalletTransactions.LIMIT
