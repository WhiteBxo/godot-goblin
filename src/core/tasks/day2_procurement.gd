class_name Day2Procurement
extends Node
## One fixed commission. The client's 35G is real wallet money: it lands when he
## hands it over, and the errand spends it (30G goods + 5G to whoever runs it).
## The escrow variable records how that 35G was used, not a second purse.

const KEY := "day2.procurement"
const ADVANCE := 35
const PURCHASE := 30
const RUNNERS: Array[String] = ["day2_ordinary_a", "day2_ordinary_b", "day2_ordinary_c"]
var _state: Node

func configure(state: Node) -> void:
	_state = state

func get_status() -> Dictionary:
	return _state.get_variable(KEY, {})

func fund() -> Error:
	return _state.commit_story_transaction("day2.procurement.funded", {}, {}, ADVANCE, {}, {}, {KEY: {"status": "funded", "escrow": 35, "purchase": 0, "fee": 0, "refund": 0, "runner": "", "return_day": 0, "return_phase": ""}})

## The runner carries the whole bag away: 30G for the goods, 5G as his fee.
func hire(actor_id: String) -> Error:
	var status := get_status()
	if actor_id not in RUNNERS or status.get("status") != "funded" or _state.current_day not in [2, 3]:
		return ERR_UNAVAILABLE
	status.status = "hired"
	status.runner = actor_id
	status.return_day = _state.current_day
	status.return_phase = "night"
	return _state.commit_story_transaction("day2.procurement.hired", {}, {}, -mini(ADVANCE, _state.get_transactions().get_balance()), {}, {"day2.s02.errand_runner_hired": true}, {KEY: status})

## The protagonist runs the errand: 30G leaves for the mushroom and the spare 5G
## stays in the purse as the errand fee.
func purchase_direct() -> Error:
	var status := get_status()
	if status.get("status") != "funded" or _state.current_day not in [2, 3]:
		return ERR_UNAVAILABLE
	if _state.get_transactions().get_balance() < PURCHASE:
		return ERR_UNAVAILABLE
	status.merge({"status": "returned", "escrow": 0, "purchase": 30, "fee": 0, "refund": 5, "runner": "player", "return_day": _state.current_day, "return_phase": "night" if DayPhase.is_night(_state) else "day"}, true)
	var flags := {"day3.procurement.returned": true}
	if _state.current_day == 2:
		flags["day2.procurement.purchased"] = true
	return _state.commit_story_transaction("day2.procurement.direct", {}, {}, -PURCHASE, {"insomnia_mushroom": 1}, flags, {KEY: status})

func refresh() -> void:
	var status := get_status()
	if status.is_empty() or status.status in ["delivered", "expired"]:
		return
	# Delivery only closes an errand that already returned and settled its 35G.
	# Any other state keeps its own branch so a stray flag cannot write an
	# escrow that valid_status rejects.
	if _state.get_flag("day3.procurement.delivered") and status.status == "returned":
		status.status = "delivered"
		_state.commit_story_transaction("day2.procurement.closed", {}, {}, 0, {}, {}, {KEY: status})
	elif _state.current_day > 3:
		status.status = "expired"
		status.refund = status.escrow
		status.escrow = 0
		# Hand the unspent bag back; a purse that cannot cover it gives what it has.
		_state.commit_story_transaction("day2.procurement.expired", {}, {}, -mini(int(status.refund), _state.get_transactions().get_balance()), {}, {}, {KEY: status})
	elif status.status == "hired" and (_state.current_day > status.return_day or (_state.current_day == status.return_day and (status.return_phase == "day" or DayPhase.is_night(_state)))):
		status.status = "returned"
		status.purchase = 30
		status.fee = 5
		status.refund = status.escrow - status.purchase - status.fee
		status.escrow = 0
		var flags := {"day3.procurement.returned": true}
		if _state.current_day == 2:
			flags["day2.procurement.purchased"] = true
		_state.commit_story_transaction("day2.procurement.returned", {}, {}, 0, {"insomnia_mushroom": 1}, flags, {KEY: status})

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
	if value.runner == "player":
		return value.status in ["returned", "delivered", "expired"] and value.return_day in [2, 3] and value.return_phase in ["day", "night"] and value.escrow == 0 and value.purchase == 30 and value.fee == 0 and value.refund == 5
	# Accept the old third-day return in saves, but new day-two hires return that
	# night so the Day 2 purchase dialogue can be reached that day.
	if value.runner not in RUNNERS or value.return_day not in [2, 3] or value.return_phase not in ["day", "night"]:
		return false
	if value.status == "hired":
		return value.escrow == 35 and value.purchase == 0 and value.fee == 0 and value.refund == 0
	return value.status in ["returned", "delivered", "expired"] and value.escrow == 0 and ((value.purchase == 30 and value.fee == 5 and value.refund == 0) or (value.status == "expired" and value.purchase == 0 and value.fee == 0 and value.refund == 35))
