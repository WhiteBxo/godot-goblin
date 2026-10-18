class_name Day1StealthHUD
extends UIScreen
## Read-only presentation; buttons submit requests to the gameplay service.

var _service: Day1StealthService
var _drinks_dirty := true

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
	$Panel.visible = _service.is_mission_stage()
	if not $Panel.visible:
		return
	$Panel/Content/Status.text = "暂时无法开始潜入，请返回后重试。" if _service.status == Day1StealthService.Status.PENDING else _service.message
	$Panel/Content/Status.theme_type_variation = &"Warning" if _service.status == Day1StealthService.Status.FAILED else &"Hint"
	$Panel/Content/Actions/Coin.disabled = not _service.can_accept_input()
	$Panel/Content/Actions/Torch.disabled = not _service.can_accept_input()
	$Panel/Content/Drinks.disabled = not _service.can_accept_input()
	if _drinks_dirty:
		_refresh_drinks()
	var setup := _service.get_setup()
	if not is_instance_valid(setup):
		return
	$Panel/Content/Actions/Torch.visible = not setup.wallet_coins
	$Panel/Content/Drinks.visible = not setup.wallet_coins
	var inventory := _service.get_inventory()
	$Panel/Content/Actions/Coin.text = "古怪金币 %d%s" % [inventory.get_stock(setup.coin_item_id), " · 已选" if _service.selected_kind == &"coin" else ""]
	if setup.wallet_coins:
		$Panel/Content/Actions/Coin.text = "投掷金币 · 10G"
	$Panel/Content/Actions/Torch.text = "火把 %d%s" % [inventory.get_stock(setup.torch_item_id), " · 已选" if _service.selected_kind == &"torch" else ""]
	$Panel/Content/Actions/Retry.visible = _service.is_blocking() or (setup.wallet_coins and _service.status == Day1StealthService.Status.RUNNING)
	$Panel/Content/Actions/Retry.text = "重新潜入" if setup.wallet_coins else "从检查点重试"
	$Panel/Content/RetryHint.visible = _service.status == Day1StealthService.Status.FAILED
	$Panel/Content/RetryHint.text = "重试会恢复本次潜入前的钱包和物品。" if setup.wallet_coins else "重试返回检查点，已用物品不会补回。"
	$Panel/Content/Actions/Start.visible = _service.status == Day1StealthService.Status.IDLE
	$Panel/Content/Hint.visible = _service.status == Day1StealthService.Status.RUNNING
	var watches := PackedStringArray()
	for guard: Variant in setup.guards:
		if is_instance_valid(guard) and is_instance_valid(guard.actor):
			if guard.state not in [Day1GuardResponse.State.WATCHING, Day1GuardResponse.State.CLEARED]:
				watches.append("%s：%s" % [guard.actor.display_name, guard.get_feedback_text()])
	$Panel/Content/Guards.text = " · ".join(watches)
	$Panel/Content/Guards.visible = not watches.is_empty()
