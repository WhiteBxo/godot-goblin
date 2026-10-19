class_name Day1StealthHUD
extends UIScreen
## Read-only presentation; buttons submit requests to the gameplay service.
##
## Layout rules: one card pinned to the bottom-left. Its first row is the only
## loud line (state name + objective count), everything below steps down in
## weight, and the panel height follows its content so short states never leave
## an empty gap above the buttons.

const PANEL_MARGIN := 16.0

var _service: Day1StealthService
var _drinks_dirty := true
var _last_summary := ""
var _last_status: int = -1

@onready var _panel: PanelContainer = $Panel
@onready var _status: Label = $Panel/Content/HeadRow/Status
@onready var _badge: Label = $Panel/Content/HeadRow/Objectives
@onready var _guards: Label = $Panel/Content/Guards
@onready var _objectives: Label = $Panel/Content/ObjectiveList
@onready var _hint: Label = $Panel/Content/Hint
@onready var _retry_hint: Label = $Panel/Content/RetryHint

func _ready() -> void:
	$Panel/Content/Actions/Coin.pressed.connect(func() -> void: _service.select_throwable(&"coin"))
	$Panel/Content/Actions/Torch.pressed.connect(func() -> void: _service.select_throwable(&"torch"))
	$Panel/Content/Actions/Retry.pressed.connect(func() -> void: _service.retry_attempt())
	$Panel/Content/Actions/Start.pressed.connect(func() -> void: _service.begin_attempt())
	$Panel/Content/Drinks.item_selected.connect(_on_drink_selected)

func configure(service: Day1StealthService) -> void:
	_service = service
	_service.changed.connect(_invalidate_drinks)
	_service.get_inventory().changed.connect(_invalidate_drinks)
	_drinks_dirty = true

func _invalidate_drinks() -> void:
	_drinks_dirty = true

func _on_drink_selected(index: int) -> void:
	if index > 0:
		_service.select_drink($Panel/Content/Drinks.get_item_metadata(index))
	_drinks_dirty = true

func _refresh_drinks() -> void:
	var choices: OptionButton = $Panel/Content/Drinks
	choices.clear()
	choices.add_item("选择饮品 · 投掷消耗 1 杯")
	choices.set_item_disabled(0, true)
	choices.select(0)
	for drink: Dictionary in _service.get_inventory().get_drinks():
		# Historical cups kept for display carry no throw payload.
		if drink.get("read_only", false) or not drink.get("throw") is Dictionary or drink.throw.is_empty():
			continue
		choices.add_item("%s ×%d" % [drink.name, drink.quantity])
		var index := choices.item_count - 1
		choices.set_item_metadata(index, drink.id)
		choices.set_item_tooltip(index, drink.name)
		if _service.selected_kind == &"drink" and _service.selected_drink_id == drink.id:
			choices.select(index)
	_drinks_dirty = false

func _process(_delta: float) -> void:
	if not is_instance_valid(_service):
		return
	_panel.visible = _service.is_mission_stage()
	if not _panel.visible:
		return
	if _drinks_dirty:
		_refresh_drinks()
	var setup := _service.get_setup()
	if not is_instance_valid(setup):
		return
	_refresh_status()
	_refresh_objectives()
	_refresh_guards(setup)
	_refresh_actions(setup)
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
	var coin: Button = $Panel/Content/Actions/Coin
	var torch: Button = $Panel/Content/Actions/Torch
	var retry: Button = $Panel/Content/Actions/Retry
	var start: Button = $Panel/Content/Actions/Start
	var drinks: OptionButton = $Panel/Content/Drinks
	var idle := not _service.can_accept_input()
	coin.disabled = idle
	torch.disabled = idle
	drinks.disabled = idle
	var running := _service.status == Day1StealthService.Status.RUNNING
	coin.visible = not setup.interior_only and running
	torch.visible = not setup.wallet_coins and running
	drinks.visible = not setup.wallet_coins and running
	var inventory := _service.get_inventory()
	coin.text = "古怪金币 %d%s" % [inventory.get_stock(setup.coin_item_id), " · 已选" if _service.selected_kind == &"coin" else ""]
	if setup.wallet_coins:
		coin.text = "投掷金币 · 10G"
	torch.text = "火把 %d%s" % [inventory.get_stock(setup.torch_item_id), " · 已选" if _service.selected_kind == &"torch" else ""]
	retry.visible = _service.is_blocking()
	retry.text = "重新潜入" if setup.wallet_coins else "从检查点重试"
	start.visible = _service.status == Day1StealthService.Status.IDLE
	_retry_hint.visible = retry.visible
	_retry_hint.text = "重试会恢复本次潜入前的钱包和物品。" if setup.wallet_coins else "重试返回检查点，已用物品不会补回。"
	$Panel/Content/Rule.visible = coin.visible or retry.visible or start.visible or drinks.visible
	_hint.text = setup.controls_hint if not setup.controls_hint.is_empty() else "F 投币 · Ctrl 潜行 · R 重试"

## Anchored to the bottom edge: the card grows upward into empty map instead of
## hanging off the screen when a wrapped hint adds a line.
func _fit_panel() -> void:
	var height := _panel.get_combined_minimum_size().y
	if is_equal_approx(_panel.offset_top, -PANEL_MARGIN - height):
		return
	_panel.offset_top = -PANEL_MARGIN - height
