class_name StoryBusinessAdapter
extends RefCounted
## Projects authored steps onto real business services. Owns no rules, prices,
## stock, balances or receipts; every write still goes through the service.

const StateData = preload("res://src/core/game_state.gd")

var _state: StateData
var _unlock_map: Callable
var _known_location: Callable
var _tavern: TavernPurchase
var _casino: FixedStoryCasino
var _business: BusinessScheduler
var _chapter_actions: Callable

## Scene-local gameplay adapter. IDs are authored data; unbound actions fail closed.
func set_chapter_actions(actions: Callable) -> void:
	_chapter_actions = actions

func chapter_action(id: String) -> Dictionary:
	if not _chapter_actions.is_valid():
		return _failure("unconfigured", "章节业务尚未接入。")
	return _chapter_actions.call(id)

## known_location(id) -> bool lets the host reject unknown map regions.
## Map knowledge is additive: a rejected unlock never removes authored facts.
func configure(state: StateData, unlock_map: Callable, known_location: Callable = Callable()) -> void:
	_state = state
	_unlock_map = unlock_map
	_known_location = known_location

func set_tavern(service: TavernPurchase) -> void:
	_tavern = service

func set_casino(service: FixedStoryCasino) -> void:
	_casino = service

func set_business(service: BusinessScheduler) -> void:
	_business = service

## Story-authored payment. The receipt is both the wallet request ID and the
## durable step fact, so a replayed event never credits twice. The wallet owns
## the balance; this adapter only projects the real result.
func grant_money(amount: int, receipt: String) -> Dictionary:
	if not is_instance_valid(_state):
		return _failure("unconfigured", "钱包尚未接入。")
	var result: Dictionary = _state.get_transactions().add_money(amount, receipt)
	var replayed: bool = result.get("code", "") == "duplicate_transaction"
	if not result.get("ok", false) and not replayed:
		return _failure(String(result.get("code", "failed")), String(result.get("message", "报酬发放失败。")))
	if not _project(receipt):
		return _failure("unavailable", "报酬已发放，但步骤事实写入被拒绝。")
	var message := "该笔报酬已结算。" if replayed else "报酬已发放。"
	return {"ok": true, "code": "ok", "message": message,
		"money_delta": int(result.get("money_delta", 0))}

## Map unlocking and region knowledge publish together; the panel only opens
## after the host reports a real assembly.
func unlock_map(locations: Array) -> Dictionary:
	if not is_instance_valid(_state) or not _unlock_map.is_valid():
		return _failure("unconfigured", "地图服务尚未接入。")
	if not _state.can_take_snapshot():
		return _failure("unavailable", "当前状态正在替换，无法解锁地图。")
	for location: Variant in locations:
		if not location is String:
			return _failure("invalid_parameter", "地图地点必须是字符串。")
		if _known_location.is_valid() and not bool(_known_location.call(location)):
			return _failure("unknown_location", "地图地点不存在：" + location)
	for location: String in locations:
		_state.set_flag("ui.map.known." + location)
		if not _state.get_flag("ui.map.known." + location):
			return _failure("unavailable", "地图知识写入被拒绝。")
	var error: Variant = _unlock_map.call()
	if error is int and error != OK and error != ERR_ALREADY_EXISTS:
		return _failure("unavailable", "地图装配失败：%s" % error_string(error))
	return _success("地图已解锁。")

## The receipt is both the wallet request ID and the durable story fact.
## A settled receipt is replayed as success and never charges twice.
func purchase(product_id: String, quantity: int, receipt: String) -> Dictionary:
	if not is_instance_valid(_tavern):
		return _failure("unconfigured", "酒馆购买尚未接入。")
	var result: Dictionary = _tavern.purchase(product_id, quantity, receipt)
	var replayed: bool = result.get("code", "") == "duplicate_transaction"
	if not result.get("ok", false) and not replayed:
		return _failure(String(result.get("code", "failed")), String(result.get("message", "购买失败。")))
	if not _project(receipt):
		return _failure("unavailable", "购买已结算，但步骤事实写入被拒绝。")
	var message := "购买完成。" if not replayed else "该笔购买已结算。"
	return {"ok": true, "code": "ok", "message": message,
		"money_delta": int(result.get("money_delta", 0)), "items": result.get("items", {}).duplicate(true)}

## Two authored outcomes plus a separate waiver. Duplicate or already-settled
## receipts mean the authored boundary already happened.
func casino(step: String, reason: String) -> Dictionary:
	if not is_instance_valid(_casino):
		return _failure("unconfigured", "赌场结算尚未接入。")
	var result: Dictionary
	match step:
		"first_loss":
			result = _casino.settle_first_loss()
		"second_win":
			result = _casino.settle_second_win()
		_:
			result = _casino.waive_debt(reason)
	if result.get("ok", false):
		return _success(String(result.get("message", "赌场结算完成。")))
	if String(result.get("code", "")) in ["duplicate_transaction", "already_settled"]:
		return _success("该赌场结算已成立。")
	return _failure(String(result.get("code", "failed")), String(result.get("message", "赌场结算失败。")))

## One action per scheduler entry point; no stage order is invented here.
func business(action: String, stage_id: String, group_id: String) -> Dictionary:
	if not is_instance_valid(_business):
		return _failure("unconfigured", "营业调度尚未接入。")
	var error: Error
	match action:
		"publish":
			error = _business.publish_stage(stage_id)
		"request_arrival":
			error = _business.request_arrival(group_id)
		"confirm_arrival":
			error = _business.confirm_arrival(group_id)
		"request_departure":
			error = _business.request_departure(group_id)
		"confirm_departure":
			error = _business.confirm_departure(group_id)
		_:
			error = _business.request_close()
	if error == OK:
		return _success("营业状态已更新。")
	# Re-requesting an applied transition (or republishing a stage) is a replay.
	if error == ERR_ALREADY_EXISTS:
		return _success("该营业状态已成立。")
	if error == ERR_UNCONFIGURED:
		return _failure("unconfigured", "关店规则尚未配置，营业保持进行中。")
	if error == ERR_DOES_NOT_EXIST:
		return _failure("unknown", "营业阶段或顾客组不存在。")
	return _failure("unavailable", "营业状态更新被拒绝：%s" % error_string(error))

func _project(receipt: String) -> bool:
	if not StoryLibrary.is_namespaced(receipt):
		return false
	_state.set_flag(receipt)
	return _state.get_flag(receipt)

func _success(message: String) -> Dictionary:
	return {"ok": true, "code": "ok", "message": message}

func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
