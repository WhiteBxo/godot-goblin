class_name FixedStoryCasino
extends Node
## Two authored outcomes, with durable receipts in the existing shared session.
## No stakes, odds, random outcomes, reward choice policy or deadline defaults.

const StateData = preload("res://src/core/game_state.gd")

var _state: StateData
var _task: Dictionary = {}
var _config: Dictionary = {}
var _busy := false

## config requires debt_task_id, loss_receipt, win_receipt, reward_items.
## Pass the full merged catalog: binding follows TaskJournal's existing contract.
func configure(state: StateData, catalog: TaskCatalog, config: Dictionary) -> Error:
	if _busy or not is_instance_valid(state) or catalog == null:
		return ERR_UNAVAILABLE
	if not config.has_all(["debt_task_id", "loss_receipt", "win_receipt", "reward_items"]):
		return ERR_UNCONFIGURED
	for key: String in ["debt_task_id", "loss_receipt", "win_receipt"]:
		if not config[key] is String or not StoryLibrary.is_namespaced(config[key]):
			return ERR_INVALID_DATA
	if config.loss_receipt == config.win_receipt or not config.reward_items is Dictionary or config.reward_items.is_empty():
		return ERR_INVALID_DATA
	for id: Variant in config.reward_items:
		if not id is String or state.get_warehouse_inventory().get_definition(id) == null or not config.reward_items[id] is int or config.reward_items[id] <= 0 or config.reward_items[id] > WalletTransactions.LIMIT:
			return ERR_INVALID_DATA
	var debt := {}
	for task: Dictionary in catalog.get_tasks():
		if task.id == config.debt_task_id:
			debt = task
	if debt.is_empty() or debt.activate_when.type != "flag":
		return ERR_INVALID_DATA
	var reserved: Array = [config.loss_receipt, config.win_receipt]
	if debt.activate_when.key in reserved or debt.get("delivery", {}).get("accepted_flag", "") in reserved:
		return ERR_INVALID_DATA
	var activation_keys: Array = [debt.activate_when.key, debt.get("delivery", {}).get("accepted_flag", "")]
	for key: String in ["complete_when", "fail_when"]:
		if debt.has(key) and debt[key].type == "flag" and (debt[key].key in reserved or debt[key].key in activation_keys):
			return ERR_INVALID_DATA
	_busy = true
	var error := state.bind_task_catalog(catalog)
	_busy = false
	if error != OK:
		return error
	_state = state
	_task = debt.duplicate(true)
	_config = config.duplicate(true)
	return OK

## Establish the debt through A's configured activation/acceptance facts.
## The loss receipt and activation commit together, without issuing a cash charge.
func settle_first_loss() -> Dictionary:
	if not _ready_for_request():
		return _result(false, "unavailable", "赌场结算尚未就绪或正在提交。")
	if _state.get_flag(_config.loss_receipt):
		return _result(false, "duplicate_transaction", "第一局已经结算。")
	if not _state.get_task_result(_task.id).is_empty() or _state.has_conflicting_task_result(_task.id):
		return _result(false, "task_unavailable", "债务任务已有终态或条件冲突。")
	if _task.has("deadline") and DayPhase.is_deadline_reached(_state, _task.deadline):
		return _result(false, "task_unavailable", "债务任务已超过配置期限。")
	if TaskCatalog.matches_condition(_task.complete_when, _state) or (_task.has("fail_when") and TaskCatalog.matches_condition(_task.fail_when, _state)):
		return _result(false, "task_unavailable", "债务结束条件已满足。")
	var facts := {_task.activate_when.key: true}
	var delivery: Dictionary = _task.get("delivery", {})
	if delivery.has("accepted_flag"):
		facts[delivery.accepted_flag] = true
	_busy = true
	var error := _state.commit_story_interaction(_config.loss_receipt, {}, facts)
	_busy = false
	return _commit_result(error, "第一局结算完成，债务任务已建立。")

## Resolved reward bundle is mandatory; the host must finish any future picker first.
## Existing GameState -> WalletTransactions draft commits items, fact and receipt once.
func settle_second_win() -> Dictionary:
	if not _ready_for_request():
		return _result(false, "unavailable", "赌场结算尚未就绪或正在提交。")
	if _state.get_flag(_config.win_receipt):
		return _result(false, "duplicate_transaction", "第二局已经结算。")
	if not _state.get_flag(_config.loss_receipt) or not _state.can_complete_task(_task.id):
		return _result(false, "task_unavailable", "第一局尚未结算，或债务任务不可继续。")
	for id: String in _config.reward_items:
		if _state.get_warehouse_inventory().get_stock(id) > WalletTransactions.LIMIT - _config.reward_items[id]:
			return _result(false, "inventory_full", "奖励库存已满，请腾出空间后重试。")
	_busy = true
	var error := _state.commit_story_interaction(_config.win_receipt, _config.reward_items, {})
	_busy = false
	var result := _commit_result(error, "第二局结算完成，奖励已入库。")
	if result.ok:
		result.items = _config.reward_items.duplicate(true)
	return result

## Waiver is a separate authored action after the win; A owns its durable result.
func waive_debt(reason: String) -> Dictionary:
	if not _ready_for_request():
		return _result(false, "unavailable", "赌场结算尚未就绪或正在提交。")
	if not _state.get_flag(_config.win_receipt):
		return _result(false, "task_unavailable", "第二局尚未结算。")
	if not _state.get_task_result(_task.id).is_empty():
		return _result(false, "already_settled", "债务任务已有终态。")
	_busy = true
	var error := _state.settle_task_result(_task.id, "cancelled", reason)
	_busy = false
	return _commit_result(error, "奶茶债务已免除。")

## Query after restore/reconstruction; never infer a waiver from a transient signal.
func get_status() -> Dictionary:
	if not is_instance_valid(_state) or _config.is_empty():
		return {}
	return {"first_settled": _state.get_flag(_config.loss_receipt),
		"second_settled": _state.get_flag(_config.win_receipt),
		"debt_result": _state.get_task_result(_task.id)}

func _ready_for_request() -> bool:
	return not _busy and is_instance_valid(_state) and not _config.is_empty() and _state.can_take_snapshot()

func _commit_result(error: Error, success: String) -> Dictionary:
	if error == OK:
		return _result(true, "ok", success)
	return _result(false, "commit_failed", "结算被拒绝，请检查任务绑定、取消规则或会话状态。")

func _result(ok: bool, code: String, message: String) -> Dictionary:
	return {"ok": ok, "code": code, "message": message, "money_delta": 0, "items": {}}
