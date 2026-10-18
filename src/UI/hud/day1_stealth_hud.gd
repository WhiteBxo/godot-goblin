class_name Day1StealthHUD
extends UIScreen
## Read-only presentation; buttons submit requests to the gameplay service.

var _service: Day1StealthService

func _ready() -> void:
	$Panel/Content/Actions/Coin.pressed.connect(func() -> void: _service.select_throwable(&"coin"))
	$Panel/Content/Actions/Torch.pressed.connect(func() -> void: _service.select_throwable(&"torch"))
	$Panel/Content/Actions/Retry.pressed.connect(func() -> void: _service.retry_attempt())
	$Panel/Content/Actions/Start.pressed.connect(func() -> void: _service.begin_attempt())

func configure(service: Day1StealthService) -> void:
	_service = service

func _process(_delta: float) -> void:
	if not is_instance_valid(_service):
		return
	$Panel.visible = _service.is_mission_stage()
	if not $Panel.visible:
		return
	$Panel/Content/Status.text = "夜间潜入暂不可用：火把来源、守卫和撤离规则尚未确定。" if _service.status == Day1StealthService.Status.PENDING else _service.message
	$Panel/Content/Actions/Coin.disabled = not _service.can_accept_input()
	$Panel/Content/Actions/Torch.disabled = not _service.can_accept_input()
	var setup := _service.get_setup()
	if not is_instance_valid(setup):
		return
	var inventory := _service.get_inventory()
	$Panel/Content/Actions/Coin.text = "金币 %d%s" % [inventory.get_stock(setup.coin_item_id), " · 已选" if _service.selected_kind == &"coin" else ""]
	$Panel/Content/Actions/Torch.text = "火把 %d%s" % [inventory.get_stock(setup.torch_item_id), " · 已选" if _service.selected_kind == &"torch" else ""]
	$Panel/Content/Actions/Retry.visible = _service.is_blocking()
	$Panel/Content/Actions/Start.visible = _service.status == Day1StealthService.Status.IDLE
	$Panel/Content/Hint.visible = _service.status == Day1StealthService.Status.RUNNING
	var watches := PackedStringArray()
	for guard: Variant in setup.guards:
		if is_instance_valid(guard) and is_instance_valid(guard.actor):
			var states := ["观察", "警戒", "分心", "混乱", "已放行"]
			watches.append("%s：%s" % [guard.actor.display_name, states[guard.state]])
	$Panel/Content/Guards.text = " · ".join(watches)
