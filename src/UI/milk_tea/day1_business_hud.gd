class_name Day1BusinessHUD
extends Control

signal resume_requested

var _wallet: WalletTransactions
var _inventory: WarehouseInventory

func _ready() -> void:
	$ResumeStory.pressed.connect(func() -> void: resume_requested.emit())

func configure(wallet: WalletTransactions, inventory: WarehouseInventory) -> void:
	if is_instance_valid(_wallet) and _wallet.changed.is_connected(refresh):
		_wallet.changed.disconnect(refresh)
	_wallet = wallet
	_inventory = inventory
	_wallet.changed.connect(refresh)
	refresh()

func refresh() -> void:
	$BusinessBalance.text = "钱包 %s · 金币面额 10G" % WalletTransactions.format_money(_wallet.get_balance())

func show_resume(available: bool) -> void:
	$ResumeStory.visible = available

## Scene controllers supply temporary notices.
func show_notice(text: String) -> void:
	$Notice.text = text
	$Notice.visible = not text.is_empty()
