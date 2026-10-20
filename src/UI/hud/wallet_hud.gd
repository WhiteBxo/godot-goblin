class_name WalletHUD
extends PanelContainer
## Persistent gold readout: one flat chip pinned to the top-right, left of the menu
## button. Read-only — the host owns the wallet and every transaction.

## Gap between the chip and the menu button, which starts at -60.
const RIGHT_EDGE := -68.0
const ICON_BOX := 12.0
const ICON_GAP := 4.0
const TEXT_PADDING := 15.0
const MIN_WIDTH := 58.0
const ROLL_SECONDS := 0.34

var _wallet: WalletTransactions
var _shown := 0
var _target := 0
var _roll_tween: Tween

@onready var _balance: Label = $Row/Balance
@onready var _icon: TextureRect = $Row/Icon

func bind_wallet(wallet: WalletTransactions) -> void:
	if is_instance_valid(_wallet) and _wallet.changed.is_connected(_refresh):
		_wallet.changed.disconnect(_refresh)
	_wallet = wallet
	visible = is_instance_valid(_wallet)
	if not is_instance_valid(_wallet):
		return
	_wallet.changed.connect(_refresh)
	_target = _wallet.get_balance()
	_shown = _target
	_balance.text = WalletTransactions.format_money(_shown)
	_fit()

func get_balance_text() -> String:
	return _balance.text if is_instance_valid(_balance) else ""

## Global centre of the coin icon: the point incoming coins fly into.
func get_coin_target() -> Vector2:
	return _icon.get_global_rect().get_center()

## A batch of coins just landed; the chip takes the hit and the number rolls.
func pop(count_hint := 1) -> void:
	UIFlourish.settle(self, 1.0 + minf(0.02 * count_hint, 0.10))

func _refresh() -> void:
	if not is_instance_valid(_wallet):
		return
	var next := _wallet.get_balance()
	if next == _target:
		return
	_target = next
	_fit()
	_roll()

func _roll() -> void:
	if _roll_tween != null and _roll_tween.is_valid():
		_roll_tween.kill()
	_roll_tween = create_tween()
	_roll_tween.tween_method(_apply_value, float(_shown), float(_target), ROLL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _apply_value(value: float) -> void:
	_shown = int(roundf(value))
	_balance.text = WalletTransactions.format_money(_shown)

## The chip grows leftward from a fixed right edge, and is measured against the
## final value so a rolling number never makes it twitch mid-count.
func _fit() -> void:
	if not is_node_ready():
		return
	var font := _balance.get_theme_font("font")
	var font_size := _balance.get_theme_font_size("font_size")
	var text_width := font.get_string_size(WalletTransactions.format_money(_target), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var width := maxf(text_width + ICON_BOX + ICON_GAP + TEXT_PADDING, MIN_WIDTH)
	offset_left = RIGHT_EDGE - width
	offset_right = RIGHT_EDGE
