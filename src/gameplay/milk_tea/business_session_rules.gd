extends RefCounted
## Pure configuration, snapshot and transition validation. No live session state.

const PREFIX := "business.session."
const STATUSES := ["entering", "waiting", "leaving", "departed"]

static func empty_snapshot() -> Dictionary:
	return {"version": 1, "published_stages": [], "groups": {}, "closed": false}

static func valid_session_id(value: Variant) -> bool:
	if not value is String or value.is_empty():
		return false
	for part: String in value.split("."):
		if not part.is_valid_identifier():
			return false
	return true

static func parse_plan(plan: Dictionary, orders: Array[Dictionary]) -> Dictionary:
	if not valid_session_id(plan.get("session_id")) or not plan.get("stages") is Array or plan.stages.is_empty():
		return {}
	var known_orders := {}
	for order: Dictionary in orders:
		known_orders[order.order_id] = order
	var result := {"stages": {}, "groups": {}, "orders": {}}
	var actors := {}
	for stage: Variant in plan.stages:
		if not stage is Dictionary or not _valid_id(stage.get("id")) or result.stages.has(stage.id):
			return {}
		result.stages[stage.id] = []
		for kind: String in ["ordinary", "story"]:
			var customers: Variant = stage.get(kind + "_customers", [])
			if not customers is Array:
				return {}
			for customer: Variant in customers:
				if not customer is Dictionary or not _valid_id(customer.get("id")) or result.groups.has(customer.id) or not _unique_ids(customer.get("actor_ids")) or not _unique_ids(customer.get("order_ids")):
					return {}
				for actor: String in customer.actor_ids:
					if actors.has(actor):
						return {}
					actors[actor] = true
				for id: String in customer.order_ids:
					if not known_orders.has(id) or result.orders.has(id) or known_orders[id].target_object_id not in customer.actor_ids:
						return {}
					result.orders[id] = customer.id
				var group: Dictionary = customer.duplicate(true)
				group.stage_id = stage.id
				group.kind = kind
				result.groups[customer.id] = group
				result.stages[stage.id].append(customer.id)
	return result

static func valid_snapshot(value: Variant, definition: Dictionary = {}) -> bool:
	if not value is Dictionary or value.size() != 4 or not value.has_all(["version", "published_stages", "groups", "closed"]):
		return false
	if not value.version is int or value.version != 1 or not value.published_stages is Array or not value.groups is Dictionary or not value.closed is bool:
		return false
	if not _unique_ids(value.published_stages, true):
		return false
	for stage: String in value.published_stages:
		if not definition.is_empty() and not definition.stages.has(stage):
			return false
	for id: Variant in value.groups:
		if not _valid_id(id) or not value.groups[id] is String or value.groups[id] not in STATUSES:
			return false
		if not definition.is_empty() and (not definition.groups.has(id) or definition.groups[id].stage_id not in value.published_stages):
			return false
	if not definition.is_empty():
		for id: String in definition.groups:
			var group: Dictionary = definition.groups[id]
			if group.kind == "ordinary" and group.stage_id in value.published_stages and not value.groups.has(id):
				return false
	return true

static func group_served(group: Dictionary, flags: Dictionary, cancelled_orders: Dictionary = {}) -> bool:
	for id: String in group.order_ids:
		if not flags.get("delivery." + id + ".completed", false) and not (group.kind == "ordinary" and cancelled_orders.get(id, false)):
			return false
	return true

## One stage publication or one real arrival/departure per commit. Never rewind.
static func valid_transition(before: Dictionary, next: Dictionary, definition: Dictionary, flags: Dictionary, cancelled_orders: Dictionary = {}) -> bool:
	if before.closed or next.closed or not valid_snapshot(next, definition):
		return false
	if next.published_stages != before.published_stages:
		if next.published_stages.size() != before.published_stages.size() + 1 or next.published_stages.slice(0, -1) != before.published_stages:
			return false
		var groups: Dictionary = before.groups.duplicate()
		for id: String in definition.stages[next.published_stages.back()]:
			if definition.groups[id].kind == "ordinary":
				groups[id] = "entering"
		return groups == next.groups
	var changes := 0
	for id: String in before.groups:
		if not next.groups.has(id):
			return false
	for id: String in next.groups:
		var old: String = before.groups.get(id, "dormant")
		var status: String = next.groups[id]
		if old == status:
			continue
		changes += 1
		var group: Dictionary = definition.groups[id]
		match old:
			"dormant":
				if status != "entering":
					return false
			"entering":
				if status != "waiting":
					return false
			"waiting":
				if not group_served(group, flags, cancelled_orders) or (status != "leaving" and not (status == "departed" and group.kind == "ordinary")):
					return false
			"leaving":
				if status != "departed" or not group_served(group, flags, cancelled_orders):
					return false
			_:
				return false
	return changes == 1

## Every gate is explicit; empty lists permit an explicitly configured manual close.
static func parse_close_rule(value: Dictionary, definition: Dictionary) -> Dictionary:
	var keys := ["from", "to", "required_stages", "served_groups", "departed_groups", "required_flags", "completed_flag"]
	if value.size() != keys.size() or not value.has_all(keys):
		return {}
	var rule := value.duplicate(true)
	for key: String in ["from", "to"]:
		var point: Variant = rule[key]
		if not point is Dictionary or point.size() != 2 or not point.has_all(["day", "phase"]):
			return {}
		if typeof(point.day) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(point.day) or point.day != floor(point.day) or point.day < 1 or point.day >= 9223372036854775807:
			return {}
		point.day = int(point.day)
		if not DayPhase.is_valid_point(point.day, point.phase):
			return {}
	if not DayPhase.is_adjacent_point(rule.from.day, rule.from.phase, rule.to.day, rule.to.phase):
		return {}
	for key: String in ["required_stages", "served_groups", "departed_groups", "required_flags"]:
		if not _unique_ids(rule[key], true):
			return {}
		for id: String in rule[key]:
			if key == "required_stages" and not definition.stages.has(id):
				return {}
			if key in ["served_groups", "departed_groups"] and not definition.groups.has(id):
				return {}
			if key == "required_flags" and not _valid_flag(id):
				return {}
	if not _valid_flag(rule.completed_flag) or rule.completed_flag in [DayPhase.NIGHT_FLAG, "business.profile.day1"] or rule.completed_flag in rule.required_flags:
		return {}
	return rule

static func can_close(snapshot: Dictionary, definition: Dictionary, rule: Dictionary, flags: Dictionary, cancelled_orders: Dictionary = {}) -> bool:
	return close_requirements_met(snapshot, definition, rule, flags, true, cancelled_orders) and not flags.get(rule.completed_flag, false)

static func close_requirements_met(snapshot: Dictionary, definition: Dictionary, rule: Dictionary, flags: Dictionary, check_flags := true, cancelled_orders: Dictionary = {}) -> bool:
	for stage: String in rule.required_stages:
		if stage not in snapshot.published_stages:
			return false
	for id: String in rule.served_groups:
		if not snapshot.groups.has(id) or not group_served(definition.groups[id], flags, cancelled_orders):
			return false
	for id: String in rule.departed_groups:
		if snapshot.groups.get(id) != "departed" or not group_served(definition.groups[id], flags, cancelled_orders):
			return false
	if check_flags:
		for flag: String in rule.required_flags:
			if not flags.get(flag, false):
				return false
	return true

static func _valid_flag(value: Variant) -> bool:
	return valid_session_id(value) and "." in value

static func _valid_id(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _unique_ids(value: Variant, allow_empty := false) -> bool:
	if not value is Array or (value.is_empty() and not allow_empty):
		return false
	var seen := {}
	for id: Variant in value:
		if not _valid_id(id) or seen.has(id):
			return false
		seen[id] = true
	return true
