class_name Day1StealthHUD
extends UIScreen
## Read-only presentation; buttons submit requests to the gameplay service.
##
## Layout rules: one card pinned to the bottom-left. Its first row is the only
## loud line (state name + objective count), everything below steps down in
## weight, and the panel height follows its content so short states never leave
## an empty gap above the buttons.

const PANEL_MARGIN := 16.0
## Guard feedback is formatted to one decimal, so 10 Hz is the natural refresh
## rate. Repainting every frame rebuilt identical strings and re-shaped the
## labels for nothing; state changes still land on the frame they happen.
const REFRESH_SECONDS := 0.1
## A refused throw reads as "the key is broken" unless the sentence stays up
## long enough to be read; the panel keeps repeating it for this long.
const REFUSAL_SECONDS := 3.0

var _service: Day1StealthService
var _drinks_dirty := true
var _last_summary := ""
var _last_status: int = -1
var _clock := 0.0
var _was_visible := false
var _refusal := ""
var _refusal_clock := 0.0
var _refresh_now := false

@onready var _panel: PanelContainer = $Panel
@onready var _status: Label = $Panel/Content/HeadRow/Status
@onready var _badge: Label = $Panel/Content/HeadRow/Objectives
@onready var _guards: Label = $Panel/Content/Guards
@onready var _objectives: Label = $Panel/Content/ObjectiveList
@onready var _hint: Label = $Panel/Content/Hint
@onready var _retry_hint: Label = $Panel/Content/RetryHint
@onready var _feedback: Label = $Panel/Content/Feedback
@onready var _coin: Button = $Panel/Content/Actions/Coin
@onready var _torch: Button = $Panel/Content/Actions/Torch
@onready var _retry: Button = $Panel/Content/Actions/Retry
@onready var _start: Button = $Panel/Content/Actions/Start
@onready var _drinks: OptionButton = $Panel/Content/Drinks
@onready var _rule: Control = $Panel/Content/Rule

func _ready() -> void:
	_coin.pressed.connect(func() -> void: _service.select_throwable(&"coin"))
	_torch.pressed.connect(func() -> void: _service.select_throwable(&"torch"))
	_retry.pressed.connect(func() -> void: _service.retry_attempt())
	_start.pressed.connect(func() -> void: _service.begin_attempt())
	_drinks.item_selected.connect(_on_drink_selected)

func configure(service: Day1StealthService) -> void:
	_service = service
	_service.changed.connect(_invalidate_drinks)
	_service.input_refused.connect(_on_input_refused)
	_service.get_inventory().changed.connect(_invalidate_drinks)
	_drinks_dirty = true

func _invalidate_drinks() -> void:
	_drinks_dirty = true

## A refused throw keeps its reason on the panel for a few seconds: the same
## sentence used to live in a tooltip nobody hovers during play.
func _on_input_refused(reason: String) -> void:
	_refusal = reason
	_refusal_clock = REFUSAL_SECONDS
	_refresh_now = true

func _on_drink_selected(index: int) -> void:
	if index > 0:
		_service.select_drink(_drinks.get_item_metadata(index))
	_drinks_dirty = true

func _refresh_drinks() -> void:
	_drinks.clear()
	_drinks.add_item("选择饮品 · 投掷消耗 1 杯")
	_drinks.set_item_disabled(0, true)
	_drinks.select(0)
	for drink: Dictionary in _service.get_inventory().get_drinks():
		# Historical cups kept for display carry no throw payload.
		if drink.get("read_only", false) or not drink.get("throw") is Dictionary or drink.throw.is_empty():
			continue
		_drinks.add_item("%s ×%d" % [drink.name, drink.quantity])
		var index := _drinks.item_count - 1
		_drinks.set_item_metadata(index, drink.id)
		_drinks.set_item_tooltip(index, drink.name)
		if _service.selected_kind == &"drink" and _service.selected_drink_id == drink.id:
			_drinks.select(index)
	_drinks_dirty = false

func _process(delta: float) -> void:
	if not is_instance_valid(_service):
		return
	if _refusal_clock > 0.0:
		_refusal_clock = maxf(0.0, _refusal_clock - delta)
		if _refusal_clock == 0.0:
			_refresh_now = true
	_panel.visible = _service.is_mission_stage()
	if not _panel.visible:
		_was_visible = false
		return
	# A status change must land immediately: the failure tint, the refused
	# flourish and the retry button all belong to the frame it happens.
	var urgent := not _was_visible or _drinks_dirty or _refresh_now or _service.status != _last_status
	_was_visible = true
	_clock -= delta
	if not urgent and _clock > 0.0:
		return
	_clock = REFRESH_SECONDS
	_refresh_now = false
	if _drinks_dirty:
		_refresh_drinks()
	var setup := _service.get_setup()
	if not is_instance_valid(setup):
		return
	_refresh_status()
	_refresh_objectives()
	_refresh_guards(setup)
	_refresh_actions(setup)
	_refresh_feedback()
	_fit_panel()

## The status line is the only loud element: state name, danger tint, and the
## service's own sentence parked in a tooltip instead of a second paragraph.
func _refresh_status() -> void:
	var status := _service.status
	_status.text = _service.get_headline()
	_status.theme_type_variation = &"Danger" if status in [Day1StealthService.Status.FAILED, Day1StealthService.Status.INTERCEPTED] else &""
	_status.tooltip_text = _service.message
	if status != _last_status:
		_last_status = status
		if status in [Day1StealthService.Status.FAILED, Day1StealthService.Status.INTERCEPTED]:
			UIFlourish.refuse(_status)

func _refresh_objectives() -> void:
	var summary := _service.get_objective_summary()
	_badge.visible = not summary.is_empty()
	_badge.text = summary
	if summary != _last_summary:
		_last_summary = summary
		if not summary.is_empty():
			UIFlourish.stamp(_badge)
	var progress := _service.get_objective_progress()
	_objectives.visible = not progress.is_empty() and _service.status != Day1StealthService.Status.ESCAPED
	_objectives.text = progress

func _refresh_guards(setup: Day1StealthSetup) -> void:
	var watches := PackedStringArray()
	var cleared := 0
	for guard: Variant in setup.guards:
		if is_instance_valid(guard) and is_instance_valid(guard.actor):
			if guard.state == Day1GuardResponse.State.CLEARED:
				cleared += 1
			elif guard.state != Day1GuardResponse.State.WATCHING:
				watches.append("%s：%s" % [guard.actor.display_name, guard.get_feedback_text()])
	if cleared > 0:
		watches.append("已放行 %d 名" % cleared)
	_guards.text = " · ".join(watches)
	_guards.visible = not watches.is_empty()

func _refresh_actions(setup: Day1StealthSetup) -> void:
	var idle := not _service.can_accept_input()
	_coin.disabled = idle
	_torch.disabled = idle
	_drinks.disabled = idle
	var running := _service.status == Day1StealthService.Status.RUNNING
	_coin.visible = not setup.interior_only and running
	_torch.visible = not setup.wallet_coins and running
	_drinks.visible = not setup.wallet_coins and running
	var inventory := _service.get_inventory()
	_coin.text = "古怪金币 %d%s" % [inventory.get_stock(setup.coin_item_id), " · 已选" if _service.selected_kind == &"coin" else ""]
	if setup.wallet_coins:
		# The wallet price is the only cost the player can be short of. An
		# enabled-looking button that silently refuses is what "the button does
		# nothing" looked like, so the balance owns the label and the state.
		var balance := _service.get_coin_balance()
		if balance >= WalletTransactions.COIN_FACE_VALUE:
			_coin.text = "投掷金币 · %dG%s" % [WalletTransactions.COIN_FACE_VALUE, " · 已选" if _service.selected_kind == &"coin" else ""]
		else:
			_coin.text = "金币不足 · 当前 %dG" % balance
			_coin.disabled = true
	_torch.text = "火把 %d%s" % [inventory.get_stock(setup.torch_item_id), " · 已选" if _service.selected_kind == &"torch" else ""]
	_retry.visible = _service.is_blocking()
	_retry.text = "重新潜入" if setup.wallet_coins else "从检查点重试"
	_start.visible = _service.status == Day1StealthService.Status.IDLE
	_retry_hint.visible = _retry.visible
	_retry_hint.text = "重试会恢复本次潜入前的钱包和物品。" if setup.wallet_coins else "重试返回检查点，已用物品不会补回。"
	_rule.visible = _coin.visible or _retry.visible or _start.visible or _drinks.visible
	_hint.text = setup.controls_hint if not setup.controls_hint.is_empty() else "鼠标瞄准落点 · F 投掷 · Ctrl 潜行"

## One line for "why nothing happened": a fresh refusal wins over the standing
## block reason so the panel never explains a state the player already left.
func _refresh_feedback() -> void:
	var text := _refusal if _refusal_clock > 0.0 else _service.get_block_reason()
	_feedback.visible = not text.is_empty()
	_feedback.text = text

## Anchored to the bottom edge: the card grows upward into empty map instead of
## hanging off the screen when a wrapped hint adds a line.
func _fit_panel() -> void:
	var height := _panel.get_combined_minimum_size().y
	if is_equal_approx(_panel.offset_top, -PANEL_MARGIN - height):
		return
	_panel.offset_top = -PANEL_MARGIN - height
