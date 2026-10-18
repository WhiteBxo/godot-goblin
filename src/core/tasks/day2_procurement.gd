class_name Day2Procurement
extends Node
## One fixed commission. Escrow is a durable task variable, never wallet income.

const KEY := "day2.procurement"
const RUNNERS: Array[String] = ["day2_ordinary_a", "day2_ordinary_b", "day2_ordinary_c"]
var _state: Node

func configure(state: Node) -> void:
	_state = state

func get_status() -> Dictionary:
	return _state.get_variable(KEY, {})

func fund() -> Error:
	return _state.commit_story_transaction("day2.procurement.funded", {}, {}, 0, {}, {}, {KEY: {"status": "funded", "escrow": 35, "purchase": 0, "fee": 0, "refund": 0, "runner": "", "return_day": 0, "return_phase": ""}})

func hire(actor_id: String) -> Error:
	var status := get_status()
	if actor_id not in RUNNERS or status.get("status") != "funded" or _state.current_day not in [2, 3]:
		return ERR_UNAVAILABLE
	status.status = "hired"
	status.runner = actor_id
	status.return_day = 3
	status.return_phase = "day" if _state.current_day == 2 else "night"
	return _state.commit_story_transaction("day2.procurement.hired", {}, {}, 0, {}, {"day2.s02.errand_runner_hired": true}, {KEY: status})

func refresh() -> void:
	var status := get_status()
	if status.is_empty() or status.status in ["delivered", "expired"]:
		return
	if _state.get_flag("day3.procurement.delivered"):
		status.status = "delivered"
		_state.commit_story_transaction("day2.procurement.closed", {}, {}, 0, {}, {}, {KEY: status})
	elif _state.current_day > 3:
		status.status = "expired"
		status.refund = status.escrow
		status.escrow = 0
		_state.commit_story_transaction("day2.procurement.expired", {}, {}, 0, {}, {}, {KEY: status})
	elif status.status == "hired" and (_state.current_day > status.return_day or (_state.current_day == status.return_day and (status.return_phase == "day" or DayPhase.is_night(_state)))):
		status.status = "returned"
		status.purchase = 30
		status.fee = 5
		status.refund = status.escrow - status.purchase - status.fee
		status.escrow = 0
		_state.commit_story_transaction("day2.procurement.returned", {}, {}, 0, {"insomnia_mushroom": 1}, {"day3.procurement.returned": true}, {KEY: status})

static func valid_status(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 8 or not value.has_all(["status", "escrow", "purchase", "fee", "refund", "runner", "return_day", "return_phase"]):
		return false
	for key: String in ["escrow", "purchase", "fee", "refund", "return_day"]:
		var amount: Variant = value[key]
		if typeof(amount) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(amount) or amount != floor(amount) or amount < 0:
			return false
	if value.status not in ["funded", "hired", "returned", "delivered", "expired"]:
		return false
	if value.escrow + value.purchase + value.fee + value.refund != 35:
		return false
	if value.runner == "":
		return value.status in ["funded", "expired"] and value.purchase == 0 and value.fee == 0 and value.return_day == 0 and value.return_phase == "" and value.escrow == (35 if value.status == "funded" else 0)
	if value.runner not in RUNNERS or value.return_day != 3 or value.return_phase not in ["day", "night"]:
		return false
	if value.status == "hired":
		return value.escrow == 35 and value.purchase == 0 and value.fee == 0 and value.refund == 0
	return value.status in ["returned", "delivered", "expired"] and value.escrow == 0 and ((value.purchase == 30 and value.fee == 5 and value.refund == 0) or (value.status == "expired" and value.purchase == 0 and value.fee == 0 and value.refund == 35))
