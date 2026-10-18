extends Node
## Cross-scene session owner: business services, wallet transactions and story/task facts.
## No class_name: GameState is the Autoload name, not a second global class.

signal state_changed
signal event_completed(event_id: String)
signal state_reset
signal task_settled(task_id: String, result: Dictionary)
signal state_restored

const SCHEMA_VERSION: int = 5
const DAY1_MENU: TeaMenu = preload("res://src/resources/milk_tea/day1_menu.tres")
const MAX_VALUE_DEPTH: int = 32
const BUSINESS_SESSIONS = preload("res://src/gameplay/milk_tea/business_session_rules.gd")

var _business_profile := "tutorial"
var _session_menu: TeaMenu = TeaProduction.CATALOG

var current_day: int:
	get:
		return _current_day
	set(value):
		set_current_day(value)

## Empty means no story stage has been selected yet.
var story_stage: String:
	get:
		return _story_stage
	set(value):
		set_story_stage(value)

var _current_day: int = 1
var _story_stage: String = ""
var _flags: Dictionary[String, bool] = {}
var _variables: Dictionary[String, Variant] = {}
var _completed_events: Dictionary[String, bool] = {}
var _task_results: Dictionary = {}
# Static bindings survive scene disposal; reset/restore replace only session facts.
var _task_definitions: Array[Dictionary] = []
var _business_sessions: Dictionary = {}
var _economy: WalletTransactions
var _warehouse_inventory: WarehouseInventory
var _tea_production: TeaProduction
var _replacing := false
var _business_transaction := false


## Optional configuration for isolated sessions; the autoload keeps its defaults.
func _init(menu: TeaMenu = null) -> void:
	_session_menu = menu if menu != null else TeaProduction.CATALOG
	_economy = WalletTransactions.new(_session_menu)
	_economy.name = "WalletTransactions"
	add_child(_economy)
	_economy.set_session_guard(func() -> bool:
		return _replacing or _business_transaction or (_tea_production != null and _tea_production.is_submitting())
	)
	_economy.changed.connect(_on_economy_changed)


func get_transactions() -> WalletTransactions:
	return _economy


func _on_economy_changed() -> void:
	if not _replacing and not _business_transaction and (_tea_production == null or not _tea_production.is_submitting()):
		_notify_state_changed()


func get_warehouse_inventory() -> WarehouseInventory:
	_ensure_business()
	return _warehouse_inventory


func get_tea_production() -> TeaProduction:
	_ensure_business()
	return _tea_production


func _ensure_business() -> void:
	if _warehouse_inventory != null:
		return
	_warehouse_inventory = _economy.get_inventory()
	_tea_production = TeaProduction.new()
	_tea_production.name = "TeaProduction"
	add_child(_tea_production)
	_tea_production.select_menu(_profile_menu(_business_profile))
	_tea_production.configure(_warehouse_inventory, self)
	_tea_production.changed.connect(_on_business_changed)


func get_business_profile() -> String:
	return _business_profile

func select_business_profile(profile: String) -> Error:
	if profile not in ["tutorial", "day1"]:
		return ERR_INVALID_PARAMETER
	if _session_busy():
		return ERR_BUSY
	if profile == _business_profile:
		return OK
	_ensure_business()
	if _current_day != 1 or not _story_stage.is_empty() or not _flags.is_empty() or not _variables.is_empty() or not _completed_events.is_empty() or not _task_results.is_empty() or _tea_production.get_completed_count() != 0 or _economy.to_dict() != _economy.get_default_state():
		return ERR_ALREADY_IN_USE
	_business_profile = profile
	_tea_production.select_menu(_profile_menu(profile))
	_publish_profile_fact()
	return OK

func _profile_menu(profile: String) -> TeaMenu:
	return DAY1_MENU if profile == "day1" else _session_menu


## Gated recipes read the active profile from session facts instead of
## guessing it from the scene, so the formal drinks stay hidden in the tutorial.
func _publish_profile_fact() -> void:
	if _business_profile == "day1":
		_flags["business.profile.day1"] = true

## All fallible validation precedes mutation; publish only the complete result.
func commit_delivery(costs: Dictionary, rewards: Dictionary, money: int, facts: Dictionary, count: int, request_id: String, notify: Callable = Callable(), drink_costs: Dictionary = {}, task_id: String = "") -> Error:
	if _session_busy():
		return ERR_BUSY
	for key: Variant in facts:
		if not key is String or not _is_namespaced_key(key) or not facts[key] is bool:
			return ERR_INVALID_DATA
	if not _can_commit_task_delivery(task_id, facts):
		return ERR_UNAVAILABLE
	var draft := _economy.prepare_delivery(costs, rewards, money, request_id, drink_costs)
	if draft.is_empty():
		return ERR_INVALID_DATA
	var before := _economy.to_dict()
	_business_transaction = true
	_replacing = true
	# Internal silent replacement is called only by the owning session transaction.
	var error := _economy._replace(draft)
	if error == OK:
		for key: String in facts:
			_flags[key] = facts[key]
		_variables["shop.orders_completed"] = maxi(int(get_variable("shop.orders_completed", 0)), count)
		_warehouse_inventory.set_session_locked(true)
		_notify_state_changed()
		_economy.publish_restored(before)
		if notify.is_valid():
			notify.call()
		_warehouse_inventory.set_session_locked(false)
	_replacing = false
	_business_transaction = false
	return error

## One-shot investigation/pickup. Validate and prepare before publishing any fact.
func commit_story_interaction(receipt: String, items: Dictionary, facts: Dictionary) -> Error:
	if _session_busy():
		return ERR_BUSY
	if not _is_namespaced_key(receipt):
		return ERR_INVALID_DATA
	if get_flag(receipt):
		return ERR_ALREADY_EXISTS
	for key: Variant in facts:
		if not key is String or not _is_namespaced_key(key) or not facts[key] is bool:
			return ERR_INVALID_DATA
	_ensure_business()
	var draft := _economy.prepare_delivery({}, items, 0, "story:" + receipt)
	if draft.is_empty():
		return ERR_INVALID_DATA
	var before := _economy.to_dict()
	_business_transaction = true
	_replacing = true
	var error := _economy._replace(draft)
	if error == OK:
		for key: String in facts:
			_flags[key] = facts[key]
		_flags[receipt] = true
		_warehouse_inventory.set_session_locked(true)
		_notify_state_changed()
		_economy.publish_restored(before)
		_warehouse_inventory.set_session_locked(false)
	_replacing = false
	_business_transaction = false
	return error

## Story payment with inventory items. The receipt makes a retried request a no-op
## (ERR_ALREADY_EXISTS) instead of a second charge; shortage changes nothing.
func commit_item_payment(receipt: String, costs: Dictionary, facts: Dictionary) -> Error:
	if _session_busy():
		return ERR_BUSY
	if not _is_namespaced_key(receipt) or costs.is_empty():
		return ERR_INVALID_DATA
	if get_flag(receipt):
		return ERR_ALREADY_EXISTS
	for key: Variant in facts:
		if not key is String or not _is_namespaced_key(key) or not facts[key] is bool:
			return ERR_INVALID_DATA
	_ensure_business()
	if not _warehouse_inventory.has_materials(costs):
		return ERR_UNAVAILABLE
	var draft := _economy.prepare_delivery(costs, {}, 0, "payment:" + receipt)
	if draft.is_empty():
		return ERR_INVALID_DATA
	var before := _economy.to_dict()
	_business_transaction = true
	_replacing = true
	var error := _economy._replace(draft)
	if error == OK:
		for key: String in facts:
			_flags[key] = facts[key]
		_flags[receipt] = true
		_warehouse_inventory.set_session_locked(true)
		_notify_state_changed()
		_economy.publish_restored(before)
		_warehouse_inventory.set_session_locked(false)
	_replacing = false
	_business_transaction = false
	return error

## DayPhase owns legal transitions; publish both phase keys and the day together.
func commit_day_phase(phase: String) -> bool:
	if _session_busy() or phase not in ["day", "night"] or DayPhase.get_phase(self) == phase:
		return false
	if DayPhase.get_phase(self).is_empty():
		return false
	if phase == "day" and _current_day == 9223372036854775807:
		return false
	_variables["world.phase"] = phase
	_flags["world.phase.night"] = phase == "night"
	if phase == "day":
		_current_day += 1
	_replacing = true
	_notify_state_changed()
	_replacing = false
	return true

func _on_business_changed() -> void:
	if not _replacing and not _business_transaction and _tea_production.is_submitting():
		if _business_profile == "day1":
			_variables["shop.drinks_made"] = _tea_production.get_completed_count()
		_notify_state_changed()


## Bind authored rules, never UI progress. The full task catalog must be bound first.
## Scene reconstruction repeats the same binding; rules are not saved as live state.
func bind_business_session(plan: Dictionary, close_rule: Dictionary = {}) -> Error:
	if _session_busy():
		return ERR_BUSY
	var orders: Array[Dictionary] = []
	for task: Dictionary in _task_definitions:
		if task.has("delivery"):
			orders.append(task.delivery)
	var definition := BUSINESS_SESSIONS.parse_plan(plan, orders)
	if definition.is_empty():
		return ERR_INVALID_DATA
	var rule := BUSINESS_SESSIONS.parse_close_rule(close_rule, definition) if not close_rule.is_empty() else {}
	if not close_rule.is_empty() and rule.is_empty():
		return ERR_INVALID_DATA
	var binding := {"definition": definition, "close_rule": rule}
	var id: String = plan.session_id
	var key: String = BUSINESS_SESSIONS.PREFIX + id
	if _variables.has(key):
		if not _valid_business_snapshot(_variables[key], binding, _flags, _current_day, DayPhase.get_phase(self)):
			return ERR_INVALID_DATA
		if _business_sessions.has(id) and not _same_value(_business_sessions[id], binding):
			return ERR_ALREADY_EXISTS
	_business_sessions[id] = binding.duplicate(true)
	return OK

func load_business_session(session_id: String) -> Dictionary:
	if not BUSINESS_SESSIONS.valid_session_id(session_id):
		return {}
	return get_variable(BUSINESS_SESSIONS.PREFIX + session_id, {})

## Compare/replace under the same guard as deliveries, wallet and restoration.
func commit_business_session(session_id: String, expected: Dictionary, next: Dictionary) -> Error:
	var error := _check_business_write(session_id, expected, next)
	if error != OK:
		return error
	if _same_value(expected, next):
		return OK
	if not BUSINESS_SESSIONS.valid_transition(expected, next, _business_sessions[session_id].definition, _flags):
		return ERR_UNAVAILABLE
	_publish_business_session(session_id, next)
	return OK

## Close, completion fact, phase mirrors and deadline outcomes publish together.
## No close rule means pending, including when every configured order was served.
func close_business_session(session_id: String, expected: Dictionary, next: Dictionary) -> Error:
	var error := _check_business_write(session_id, expected, next)
	if error != OK:
		return error
	var binding: Dictionary = _business_sessions[session_id]
	var rule: Dictionary = binding.close_rule
	if rule.is_empty():
		return ERR_UNCONFIGURED
	if expected.closed:
		return OK if _same_value(expected, next) else ERR_UNAVAILABLE
	var closed := expected.duplicate(true)
	closed.closed = true
	if not _same_value(closed, next) or _current_day != rule.from.day or DayPhase.get_phase(self) != rule.from.phase:
		return ERR_UNAVAILABLE
	if not BUSINESS_SESSIONS.can_close(expected, binding.definition, rule, _flags):
		return ERR_UNAVAILABLE
	_publish_business_session(session_id, next, rule)
	return OK

func _check_business_write(session_id: String, expected: Dictionary, next: Dictionary) -> Error:
	if _session_busy() or (is_inside_tree() and get_tree().paused):
		return ERR_BUSY
	if not _business_sessions.has(session_id):
		return ERR_UNCONFIGURED
	var definition: Dictionary = _business_sessions[session_id].definition
	if not BUSINESS_SESSIONS.valid_snapshot(expected, definition) or not BUSINESS_SESSIONS.valid_snapshot(next, definition):
		return ERR_INVALID_DATA
	var current := load_business_session(session_id)
	if current.is_empty():
		current = BUSINESS_SESSIONS.empty_snapshot()
	return OK if _same_value(current, expected) else ERR_BUSY

func _publish_business_session(session_id: String, next: Dictionary, close_rule: Dictionary = {}) -> void:
	_ensure_business()
	_replacing = true
	var locked := _warehouse_inventory.is_session_locked()
	_warehouse_inventory.set_session_locked(true)
	_variables[BUSINESS_SESSIONS.PREFIX + session_id] = next.duplicate(true)
	if not close_rule.is_empty():
		_current_day = close_rule.to.day
		_variables[DayPhase.PHASE_VARIABLE] = close_rule.to.phase
		_flags[DayPhase.NIGHT_FLAG] = close_rule.to.phase == DayPhase.NIGHT_PHASE
		_flags[close_rule.completed_flag] = true
	_notify_state_changed()
	_warehouse_inventory.set_session_locked(locked)
	_replacing = false

func _valid_business_snapshot(value: Variant, binding: Dictionary, flags: Dictionary, day: int, phase: String) -> bool:
	var definition: Dictionary = binding.get("definition", {})
	if not BUSINESS_SESSIONS.valid_snapshot(value, definition):
		return false
	if definition.is_empty():
		return true
	for id: String in value.groups:
		if value.groups[id] in ["leaving", "departed"] and not BUSINESS_SESSIONS.group_served(definition.groups[id], flags):
			return false
	var rule: Dictionary = binding.get("close_rule", {})
	if rule.is_empty():
		return true
	if value.closed != flags.get(rule.completed_flag, false):
		return false
	if not value.closed:
		return true
	var boundary := {"day": rule.to.day, "phase": rule.to.phase, "boundary": "at"}
	# Story permission can be revoked later; the committed closure remains final.
	return BUSINESS_SESSIONS.close_requirements_met(value, definition, rule, flags, false) and DayPhase.is_deadline_reached_at(day, phase, boundary)


## Delivery holds this through all synchronous notifications, including receipts.
func begin_business_transaction() -> bool:
	if _session_busy():
		return false
	_business_transaction = true
	return true


func end_business_transaction() -> void:
	_business_transaction = false


func _session_busy() -> bool:
	return _economy.is_busy()


## Setters return true only when data changed. Invalid input is left untouched.
func set_current_day(value: int) -> bool:
	if _replacing or value < 1 or value == _current_day:
		return false
	_current_day = value
	_notify_state_changed()
	return true


func set_story_stage(value: String) -> bool:
	if _replacing or value == _story_stage:
		return false
	_story_stage = value
	_notify_state_changed()
	return true


func has_flag(key: String) -> bool:
	return _flags.has(key)


func get_flag(key: String, default_value: bool = false) -> bool:
	return _flags.get(key, default_value)


func set_flag(key: String, value: bool = true) -> bool:
	if _replacing or not _is_namespaced_key(key) or (_flags.has(key) and _flags[key] == value):
		return false
	_flags[key] = value
	_notify_state_changed()
	return true


func get_flags() -> Dictionary[String, bool]:
	return _flags.duplicate()


func has_variable(key: String) -> bool:
	return _variables.has(key)


func get_variable(key: String, default_value: Variant = null) -> Variant:
	return _copy_value(_variables.get(key, default_value))


## Values: null, bool, int, finite float, String, Array, string-keyed Dictionary.
## Containers may nest up to MAX_VALUE_DEPTH; Objects and cycles are rejected.
func set_variable(key: String, value: Variant) -> bool:
	if _replacing or key.begins_with(BUSINESS_SESSIONS.PREFIX) or not _is_namespaced_key(key) or not _is_story_value(value):
		return false
	if _variables.has(key) and _same_value(_variables[key], value):
		return false
	_variables[key] = _copy_value(value)
	_notify_state_changed()
	return true


## Commit related gameplay facts before notifying synchronous observers.
func apply_flags(flags: Dictionary) -> Error:
	if _replacing:
		return ERR_BUSY
	for key: Variant in flags:
		if not key is String or not _is_namespaced_key(key) or not flags[key] is bool:
			return ERR_INVALID_DATA
	var changed := false
	for key: String in flags:
		changed = changed or not _flags.has(key) or _flags[key] != flags[key]
		_flags[key] = flags[key]
	if changed:
		_notify_state_changed()
	return OK


func get_variables() -> Dictionary[String, Variant]:
	return _variables.duplicate(true)


func is_event_completed(event_id: String) -> bool:
	return _completed_events.has(event_id)


func complete_event(event_id: String) -> bool:
	if _replacing or not _is_namespaced_key(event_id) or is_event_completed(event_id):
		return false
	_completed_events[event_id] = true
	_notify_state_changed()
	event_completed.emit(event_id)
	return true


func get_completed_events() -> Array[String]:
	var events: Array[String] = []
	events.assign(_completed_events.keys())
	events.sort()
	return events


func reset_state() -> bool:
	if _session_busy():
		return false
	var defaults := _new_game_snapshot()
	if _same_value(to_dict(), defaults):
		return false
	_replace_session(defaults, true)
	return true


## Explicit new game, including cancellation of scene-local story/recipe work.
## Scene switching/reloading must never call this. No disk save is implied.
func start_new_game() -> Error:
	if _session_busy():
		return ERR_BUSY
	_replace_session(_new_game_snapshot(), true)
	return OK


func _new_game_snapshot() -> Dictionary:
	var fresh := get_script().new(_session_menu) as Node
	fresh.select_business_profile(_business_profile)
	var defaults: Dictionary = fresh.to_dict()
	fresh.free()
	return defaults


## File coordinators must sample after synchronous transactions/notifications end.
func can_take_snapshot() -> bool:
	return not _session_busy()


## Check migrations and the complete schema without replacing live facts/signals.
func validate_snapshot(data: Dictionary) -> Error:
	return OK if _is_valid_snapshot(_migrate_snapshot(data)) else ERR_INVALID_DATA


## Native Variant snapshot, with independent containers; no file I/O.
func to_dict() -> Dictionary:
	_ensure_business()
	return {
		"schema_version": SCHEMA_VERSION,
		"current_day": _current_day,
		"story_stage": _story_stage,
		"flags": get_flags(),
		"variables": get_variables(),
		"completed_events": get_completed_events(),
		"task_results": _task_results.duplicate(true),
		"business": {"profile_id": _business_profile, "inventory": _warehouse_inventory.to_dict(), "production": _tea_production.to_dict()},
		"economy": _economy.to_dict(),
	}


## Complete replacement, not a merge. Validate before touching live state.
## Valid identical snapshots return OK without signals. Restoring events does
## not emit event_completed, so loading cannot replay one-shot story effects.
func restore_state(data: Dictionary) -> Error:
	data = _migrate_snapshot(data)
	if _session_busy():
		return ERR_BUSY
	if not _is_valid_snapshot(data):
		return ERR_INVALID_DATA
	var normalized := to_dict()
	for key: String in normalized:
		normalized[key] = _copy_value(data[key])
	normalized.completed_events.sort()
	_resolve_snapshot_task_results(normalized)
	if _same_value(to_dict(), normalized):
		return OK
	_replace_session(normalized, false)
	return OK


## All components are validated first; publish only after the whole session commits.
## Keep service identities so existing UI subscriptions survive new game/restore.
func _replace_session(data: Dictionary, new_game: bool) -> void:
	_ensure_business()
	var economy_before := _economy.to_dict()
	var profile_changed: bool = _business_profile != data.business.profile_id
	_business_profile = data.business.profile_id
	_tea_production.select_menu(_profile_menu(_business_profile))
	_publish_profile_fact()
	_economy.restore_state(data.economy, false)
	_replacing = true
	var inventory_changed: bool = economy_before.inventory != data.business.inventory
	var production_changed: bool = profile_changed or _tea_production.to_dict() != data.business.production
	var inventory_blocked := _warehouse_inventory.is_blocking_signals()
	var production_blocked := _tea_production.is_blocking_signals()
	_warehouse_inventory.set_block_signals(true)
	_tea_production.set_block_signals(true)
	_tea_production.restore_state(data.business.production)
	_current_day = data["current_day"]
	_story_stage = data["story_stage"]
	_flags.assign(data["flags"])
	_variables.assign(data["variables"].duplicate(true))
	_task_results = data.task_results.duplicate(true)
	_completed_events.clear()
	for event_id: String in data["completed_events"]:
		_completed_events[event_id] = true
	_warehouse_inventory.set_block_signals(inventory_blocked)
	_tea_production.set_block_signals(production_blocked)
	_warehouse_inventory.set_session_locked(true)
	_notify_state_changed(false)
	_economy.publish_restored(economy_before)
	if production_changed and not inventory_changed:
		_tea_production.changed.emit()
	if new_game:
		state_reset.emit()
	else:
		state_restored.emit()
	_warehouse_inventory.set_session_locked(false)
	_replacing = false


func _migrate_snapshot(data: Dictionary) -> Dictionary:
	if not data.get("schema_version") is int or data.schema_version not in [2, 3, 4, SCHEMA_VERSION]:
		return data
	var migrated := data.duplicate(true)
	if data.schema_version in [2, 3, 4]:
		migrated["task_results"] = {}
	if not migrated.get("business") is Dictionary or not migrated.get("economy") is Dictionary or not migrated.business.get("inventory") is Dictionary or not migrated.economy.get("inventory") is Dictionary:
		return data
	if not _same_value(migrated.business.inventory, migrated.economy.inventory):
		return data
	if data.schema_version == 2:
		for inventory: Dictionary in [migrated.business.inventory, migrated.economy.inventory]:
			if not inventory.get("ingredients") is Dictionary:
				return data
			if not inventory.ingredients.has("strange_coin"):
				inventory.ingredients["strange_coin"] = {"quantity": 0, "discovered": false, "known_properties": []}
				if inventory.get("schema_version") in [2, WarehouseInventory.SCHEMA_VERSION]:
					inventory.ingredients.strange_coin["used"] = 0
		migrated.schema_version = SCHEMA_VERSION
		migrated.business["profile_id"] = "tutorial"
	# v4 adds formula products and the encyclopedia to the shared inventory. Old
	# sessions keep their fixed products; no recipe/discovery is invented for them.
	migrated.schema_version = SCHEMA_VERSION
	migrated.business.inventory = WarehouseInventory.migrate_snapshot(migrated.business.inventory)
	migrated.economy.inventory = WarehouseInventory.migrate_snapshot(migrated.economy.inventory)
	if data.schema_version in [2, 3] and migrated.business.get("production") is Dictionary and not migrated.business.production.has("formula_requests"):
		migrated.business.production["formula_requests"] = {}
	return migrated

func _is_valid_snapshot(data: Dictionary) -> bool:
	if not data.has_all(["schema_version", "current_day", "story_stage", "flags", "variables", "completed_events", "task_results", "business", "economy"]):
		return false
	if not data["schema_version"] is int or data["schema_version"] != SCHEMA_VERSION:
		return false
	if not data["current_day"] is int or data["current_day"] < 1 or not data["story_stage"] is String:
		return false
	if not data["flags"] is Dictionary or not data["variables"] is Dictionary or not data["completed_events"] is Array:
		return false
	for key: Variant in data["flags"]:
		if not key is String or not _is_namespaced_key(key) or not data["flags"][key] is bool:
			return false
	for key: Variant in data["variables"]:
		if not key is String or not _is_namespaced_key(key) or not _is_story_value(data["variables"][key]):
			return false
		if key.begins_with(BUSINESS_SESSIONS.PREFIX):
			var id: String = key.trim_prefix(BUSINESS_SESSIONS.PREFIX)
			if not BUSINESS_SESSIONS.valid_session_id(id) or not _valid_business_snapshot(data.variables[key], _business_sessions.get(id, {}), data.flags, data.current_day, DayPhase.phase_from_facts(data.variables, data.flags)):
				return false
	if not _valid_task_results(data.task_results):
		return false
	var seen_events: Dictionary[String, bool] = {}
	for event_id: Variant in data["completed_events"]:
		if not event_id is String or not _is_namespaced_key(event_id) or seen_events.has(event_id):
			return false
		seen_events[event_id] = true
	if _economy.validate_state(data.economy) != OK:
		return false
	if not data.business is Dictionary or not data.business.has_all(["profile_id", "inventory", "production"]) or data.business.profile_id not in ["tutorial", "day1"]:
		return false
	if not _same_value(data.economy.inventory, data.business.inventory):
		return false
	if not data.business.production is Dictionary or not data.business.production.has_all(["completed_order_ids", "formula_requests"]):
		return false
	_ensure_business()
	var production_candidate := TeaProduction.new()
	production_candidate.select_menu(_profile_menu(data.business.profile_id))
	var production_valid := production_candidate.is_valid_snapshot(data.business.production)
	production_candidate.free()
	if not production_valid:
		return false
	var candidate := WarehouseInventory.new(_session_menu)
	var valid := candidate.restore_state(data.business.inventory) == OK
	candidate.free()
	return valid


func _is_namespaced_key(key: String) -> bool:
	var parts := key.split(".")
	if parts.size() < 2:
		return false
	for part: String in parts:
		if not part.is_valid_identifier():
			return false
	return true


func _is_story_value(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_VALUE_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item: Variant in value:
				if not _is_story_value(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not _is_story_value(value[key], depth + 1):
					return false
			return true
	return false


func _copy_value(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value


## Numeric type changes (including nested int -> float) are meaningful.
func _same_value(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is Array:
		if left.size() != right.size():
			return false
		for index in range(left.size()):
			if not _same_value(left[index], right[index]):
				return false
		return true
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _same_value(left[key], right[key]):
				return false
		return true
	return left == right


## Binding configuration is separate from projection refresh. No live settlement
## signal is replayed when a catalog first encounters legacy completion facts.
func bind_task_catalog(catalog: TaskCatalog) -> Error:
	if _session_busy():
		return ERR_BUSY
	if catalog == null:
		return ERR_INVALID_PARAMETER
	_task_definitions = catalog.get_tasks()
	var settled := _resolve_task_results()
	if not settled.is_empty():
		var blocked := _replacing
		_replacing = true
		_notify_state_changed(false)
		_replacing = blocked
	return OK

## Delivery must check this before any inventory/wallet mutation.
func can_complete_task(task_id: String) -> bool:
	if _task_results.has(task_id) or DayPhase.get_phase(self).is_empty():
		return false
	for task: Dictionary in _task_definitions:
		if task.id == task_id:
			return _task_is_started(task) and not (task.has("fail_when") and TaskCatalog.matches_condition(task.fail_when, self)) and not (task.has("deadline") and DayPhase.is_deadline_reached(self, task.deadline))
	return false

func _can_commit_task_delivery(task_id: String, facts: Dictionary) -> bool:
	if task_id.is_empty():
		return true # Legacy raw business transaction, without a bound task.
	if not can_complete_task(task_id):
		return false
	for task: Dictionary in _task_definitions:
		if task.id == task_id:
			return task.complete_when.type == "flag" and facts.get(task.complete_when.key, false)
	return false

func has_conflicting_task_result(task_id: String) -> bool:
	for task: Dictionary in _task_definitions:
		if task.id == task_id:
			return _task_is_started(task) and _task_result_candidates(task).size() > 1
	return false

## Standalone inventory adapter: TaskDelivery holds the business lock and has
## already exchanged inventory silently. Publish all facts/count/results once.
func commit_delivery_facts(facts: Dictionary, count: int, task_id: String = "") -> Error:
	if _replacing or not _business_transaction:
		return ERR_BUSY
	for key: Variant in facts:
		if not key is String or not _is_namespaced_key(key) or not facts[key] is bool:
			return ERR_INVALID_DATA
	if not _can_commit_task_delivery(task_id, facts):
		return ERR_UNAVAILABLE
	for key: String in facts:
		_flags[key] = facts[key]
	_variables["shop.orders_completed"] = maxi(int(get_variable("shop.orders_completed", 0)), count)
	_replacing = true
	_notify_state_changed()
	_replacing = false
	return OK

func get_task_result(task_id: String) -> Dictionary:
	return _task_results.get(task_id, {}).duplicate(true)

## Business coordinators explicitly request cancellation. No money/items change.
## Success/failure/expiry still require their configured condition to be true.
func settle_task_result(task_id: String, status: String, reason: String = "") -> Error:
	if _session_busy():
		return ERR_BUSY
	if _task_results.has(task_id):
		return ERR_ALREADY_EXISTS
	for task: Dictionary in _task_definitions:
		if task.id != task_id:
			continue
		if not _task_is_started(task) or DayPhase.get_phase(self).is_empty():
			return ERR_UNAVAILABLE
		var candidates := _task_result_candidates(task)
		if status == "cancelled":
			if not task.get("allow_cancel", false) or not candidates.is_empty():
				return ERR_UNAVAILABLE
		elif candidates.size() != 1 or candidates[0] != status:
			return ERR_UNAVAILABLE
		_task_results[task_id] = _new_task_result(status, reason)
		var settled: Array[String] = [task_id]
		_notify_state_changed(true, settled)
		return OK
	return ERR_DOES_NOT_EXIST

func _task_is_started(task: Dictionary) -> bool:
	if not TaskCatalog.matches_condition(task.activate_when, self):
		return false
	var delivery: Dictionary = task.get("delivery", {})
	return not delivery.has("accepted_flag") or get_flag(delivery.accepted_flag)

func _task_result_candidates(task: Dictionary) -> Array[String]:
	var candidates: Array[String] = []
	if TaskCatalog.matches_condition(task.complete_when, self):
		candidates.append("completed")
	if task.has("fail_when") and TaskCatalog.matches_condition(task.fail_when, self):
		candidates.append("failed")
	if task.has("deadline") and DayPhase.is_deadline_reached(self, task.deadline):
		candidates.append("expired")
	return candidates

func _new_task_result(status: String, reason: String) -> Dictionary:
	return {"status": status, "day": _current_day, "phase": DayPhase.get_phase(self), "reason": reason}

func _resolve_task_results() -> Array[String]:
	var context := {"current_day": _current_day, "flags": _flags, "variables": _variables,
		"completed_events": get_completed_events(), "task_results": _task_results}
	return _resolve_snapshot_task_results(context)

## Reconcile legacy snapshots before comparison/replacement, silently. Repeating
## the same legacy restore therefore compares against the same normalized result.
func _resolve_snapshot_task_results(data: Dictionary) -> Array[String]:
	var settled: Array[String] = []
	var phase := DayPhase.phase_from_facts(data.variables, data.flags)
	if phase.is_empty():
		return settled
	for task: Dictionary in _task_definitions:
		if data.task_results.has(task.id) or not TaskCatalog.matches_facts(task.activate_when, data.flags, data.variables, data.completed_events):
			continue
		var delivery: Dictionary = task.get("delivery", {})
		if delivery.has("accepted_flag") and not data.flags.get(delivery.accepted_flag, false):
			continue
		var candidates: Array[String] = []
		if TaskCatalog.matches_facts(task.complete_when, data.flags, data.variables, data.completed_events):
			candidates.append("completed")
		if task.has("fail_when") and TaskCatalog.matches_facts(task.fail_when, data.flags, data.variables, data.completed_events):
			candidates.append("failed")
		if task.has("deadline") and DayPhase.is_deadline_reached_at(data.current_day, phase, task.deadline):
			candidates.append("expired")
		# Conflicting simultaneous conditions require an explicit design decision.
		if candidates.size() == 1:
			data.task_results[task.id] = {"status": candidates[0], "day": data.current_day, "phase": phase, "reason": ""}
			settled.append(task.id)
	return settled

func _notify_state_changed(resolve_tasks: bool = true, explicit_results: Array[String] = []) -> void:
	var settled: Array[String] = []
	if resolve_tasks:
		settled = _resolve_task_results()
	settled.append_array(explicit_results)
	var blocked := _replacing
	var inventory_locked := false
	if not settled.is_empty():
		_replacing = true
		_ensure_business()
		inventory_locked = _warehouse_inventory.is_session_locked()
		_warehouse_inventory.set_session_locked(true)
	state_changed.emit()
	for task_id: String in settled:
		task_settled.emit(task_id, get_task_result(task_id))
	if not settled.is_empty():
		_warehouse_inventory.set_session_locked(inventory_locked)
	_replacing = blocked

func _valid_task_results(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for id: Variant in value:
		if not id is String or not _is_namespaced_key(id):
			return false
		var result: Variant = value[id]
		if not result is Dictionary or result.size() != 4 or not result.has_all(["status", "day", "phase", "reason"]):
			return false
		if not result.status is String or result.status not in ["completed", "failed", "expired", "cancelled"] or not result.reason is String or not DayPhase.is_valid_point(result.day, result.phase):
			return false
	return true
