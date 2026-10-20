class_name Day1BusinessHUD
extends Control

signal resume_requested

var _wallet: WalletTransactions
var _inventory: WarehouseInventory
var _state: Node
var _last_balance := 0
var _pending_delta := 0
var _shown_delta := 0
var _change_tween: Tween

func _ready() -> void:
	$ResumeStory.pressed.connect(func() -> void: resume_requested.emit())

func configure(wallet: WalletTransactions, inventory: WarehouseInventory, state: Node = null) -> void:
	if is_instance_valid(_wallet) and _wallet.changed.is_connected(refresh):
		_wallet.changed.disconnect(refresh)
	_disconnect_state()
	_wallet = wallet
	_inventory = inventory
	_state = state
	if is_instance_valid(_state):
		_state.state_reset.connect(_clear_change)
		_state.state_restored.connect(_clear_change)
	_last_balance = _wallet.get_balance()
	_clear_change()
	_wallet.changed.connect(refresh)
	refresh()

func refresh() -> void:
	var balance := _wallet.get_balance()
	var delta := balance - _last_balance
	_last_balance = balance
	if delta != 0:
		_pending_delta += delta
		_publish_change.call_deferred()
	_render_balance()

func _publish_change() -> void:
	if _pending_delta == 0 or not is_inside_tree():
		return
	_shown_delta = _pending_delta
	_pending_delta = 0
	if _change_tween != null:
		_change_tween.kill()
	_render_balance()
	_change_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_change_tween.tween_interval(2.8)
	_change_tween.tween_callback(_clear_change)

func _render_balance() -> void:
	# 余额只由右上角金币胶囊显示；这里只报这一笔的增减，避免同一个数字出现两次。
	$BusinessBalance.visible = _shown_delta != 0
	$BusinessBalance.text = "" if _shown_delta == 0 else "%s%dG" % ["+" if _shown_delta > 0 else "", _shown_delta]
	$BusinessBalance.theme_type_variation = &"Success" if _shown_delta > 0 else (&"Warning" if _shown_delta < 0 else &"")

func _clear_change() -> void:
	if _change_tween != null:
		_change_tween.kill()
		_change_tween = null
	_pending_delta = 0
	_shown_delta = 0
	if is_instance_valid(_wallet):
		_last_balance = _wallet.get_balance()
		_render_balance()

func _disconnect_state() -> void:
	if is_instance_valid(_state):
		for event: StringName in [&"state_reset", &"state_restored"]:
			if _state.is_connected(event, _clear_change):
				_state.disconnect(event, _clear_change)

func _exit_tree() -> void:
	_disconnect_state()
	if is_instance_valid(_wallet) and _wallet.changed.is_connected(refresh):
		_wallet.changed.disconnect(refresh)

func show_resume(available: bool) -> void:
	$ResumeStory.visible = available

## Scene controllers supply temporary notices.
func show_notice(text: String) -> void:
	$Notice.text = text
	$Notice.visible = not text.is_empty()
