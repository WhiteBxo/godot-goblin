extends Node
## Cross-scene session owner: business services, wallet transactions and story/task facts.
## No class_name: GameState is the Autoload name, not a second global class.

signal state_changed
signal event_completed(event_id: String)
signal state_reset
signal state_restored

const SCHEMA_VERSION: int = 4
const DAY1_MENU: TeaMenu = preload("res://src/resources/milk_tea/day1_menu.tres")
const MAX_VALUE_DEPTH: int = 32

var _business_profile := "tutorial"

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
var _economy: WalletTransactions
var _warehouse_inventory: WarehouseInventory
var _tea_production: TeaProduction
var _replacing := false
var _business_transaction := false


func _init() -> void:
	_economy = WalletTransactions.new()
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
		state_changed.emit()


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
	if _current_day != 1 or not _story_stage.is_empty() or not _flags.is_empty() or not _variables.is_empty() or not _completed_events.is_empty() or _tea_production.get_completed_count() != 0 or _economy.to_dict() != _economy.get_default_state():
		return ERR_ALREADY_IN_USE
	_business_profile = profile
	_tea_production.select_menu(_profile_menu(profile))
	_publish_profile_fact()
	return OK

func _profile_menu(profile: String) -> TeaMenu:
	return DAY1_MENU if profile == "day1" else TeaProduction.CATALOG


## Gated recipes read the active profile from session facts instead of
## guessing it from the scene, so the formal drinks stay hidden in the tutorial.
func _publish_profile_fact() -> void:
	if _business_profile == "day1":
		_flags["business.profile.day1"] = true

## All fallible validation precedes mutation; publish only the complete result.
func commit_delivery(costs: Dictionary, rewards: Dictionary, money: int, facts: Dictionary, count: int, request_id: String, notify: Callable = Callable(), drink_costs: Dictionary = {}) -> Error:
	if _session_busy():
		return ERR_BUSY
	for key: Variant in facts:
		if not key is String or not _is_namespaced_key(key) or not facts[key] is bool:
			return ERR_INVALID_DATA
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
		state_changed.emit()
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
		state_changed.emit()
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
		state_changed.emit()
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
	_variables["world.phase"] = phase
	_flags["world.phase.night"] = phase == "night"
	if phase == "day":
		_current_day += 1
	_replacing = true
	state_changed.emit()
	_replacing = false
	return true

func _on_business_changed() -> void:
	if not _replacing and not _business_transaction and _tea_production.is_submitting():
		if _business_profile == "day1":
			_variables["shop.drinks_made"] = _tea_production.get_completed_count()
		state_changed.emit()


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
	state_changed.emit()
	return true


func set_story_stage(value: String) -> bool:
	if _replacing or value == _story_stage:
		return false
	_story_stage = value
	state_changed.emit()
	return true


func has_flag(key: String) -> bool:
	return _flags.has(key)


func get_flag(key: String, default_value: bool = false) -> bool:
	return _flags.get(key, default_value)


func set_flag(key: String, value: bool = true) -> bool:
	if _replacing or not _is_namespaced_key(key) or (_flags.has(key) and _flags[key] == value):
		return false
	_flags[key] = value
	state_changed.emit()
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
	if _replacing or not _is_namespaced_key(key) or not _is_story_value(value):
		return false
	if _variables.has(key) and _same_value(_variables[key], value):
		return false
	_variables[key] = _copy_value(value)
	state_changed.emit()
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
		state_changed.emit()
	return OK


func get_variables() -> Dictionary[String, Variant]:
	return _variables.duplicate(true)


func is_event_completed(event_id: String) -> bool:
	return _completed_events.has(event_id)


func complete_event(event_id: String) -> bool:
	if _replacing or not _is_namespaced_key(event_id) or is_event_completed(event_id):
		return false
	_completed_events[event_id] = true
	state_changed.emit()
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
	var fresh := get_script().new() as Node
	fresh.select_business_profile(_business_profile)
	var defaults: Dictionary = fresh.to_dict()
	fresh.free()
	return defaults


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
	if _same_value(to_dict(), normalized):
		return OK
	_replace_session(data, false)
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
	_completed_events.clear()
	for event_id: String in data["completed_events"]:
		_completed_events[event_id] = true
	_warehouse_inventory.set_block_signals(inventory_blocked)
	_tea_production.set_block_signals(production_blocked)
	_warehouse_inventory.set_session_locked(true)
	state_changed.emit()
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
	if not data.get("schema_version") is int or data.schema_version not in [2, 3, SCHEMA_VERSION]:
		return data
	var migrated := data.duplicate(true)
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
	if not data.has_all(["schema_version", "current_day", "story_stage", "flags", "variables", "completed_events", "business", "economy"]):
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
	var candidate := WarehouseInventory.new()
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
