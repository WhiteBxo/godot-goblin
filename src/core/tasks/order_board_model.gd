class_name OrderBoardModel
extends Node
## Disposable order projection. GameState, inventory and delivery remain authoritative.

signal changed

const TRACKED_KEY := "ui.tracked_order_id"
const StateData = preload("res://src/core/game_state.gd")

var _catalog: TaskCatalog
var _journal: TaskJournal
var _state: StateData
var _inventory: WarehouseInventory
var _production: TeaProduction
var _delivery: TaskDelivery
var _entries: Array[Dictionary] = []
var _target_names: Dictionary = {}
var _delivery_targets: Dictionary = {}
var _tracked_id := ""

func configure(catalog: TaskCatalog, journal: TaskJournal, state: StateData,
		inventory: WarehouseInventory, production: TeaProduction, delivery: TaskDelivery) -> void:
	_disconnect_sources()
	_catalog = catalog
	_delivery_targets.clear()
	if _catalog != null:
		for task: Dictionary in _catalog.get_tasks():
			if task.has("delivery"):
				_delivery_targets[task.delivery.target_object_id] = true
	_journal = journal
	_state = state
	_inventory = inventory
	_production = production
	_delivery = delivery
	_connect_sources()
	refresh()

func _enter_tree() -> void:
	_connect_sources()
	refresh()

func _exit_tree() -> void:
	_disconnect_sources()

func _connect_sources() -> void:
	for source: Object in [_state, _inventory, _production, _delivery]:
		if not is_instance_valid(source):
			continue
		var event: StringName = &"availability_changed" if source == _delivery else (&"state_changed" if source == _state else &"changed")
		if not source.is_connected(event, refresh):
			source.connect(event, refresh)

func _disconnect_sources() -> void:
	for source: Object in [_state, _inventory, _production, _delivery]:
		if not is_instance_valid(source):
			continue
		var event: StringName = &"availability_changed" if source == _delivery else (&"state_changed" if source == _state else &"changed")
		if source.is_connected(event, refresh):
			source.disconnect(event, refresh)

func set_target_names(names: Dictionary) -> void:
	if _target_names != names:
		_target_names = names.duplicate(true)
		refresh()

func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)

func get_entry(order_id: String) -> Dictionary:
	for entry: Dictionary in _entries:
		if entry.order_id == order_id:
			return entry.duplicate(true)
	return {}

func get_task_entry(task_id: String) -> Dictionary:
	for entry: Dictionary in _entries:
		if entry.task_id == task_id:
			return entry.duplicate(true)
	return {}

func get_tracked_entry() -> Dictionary:
	var selected := get_entry(_tracked_id)
	if selected.get("status") == "active":
		return selected
	var fallback: Dictionary = {}
	for entry: Dictionary in _entries:
		if entry.status != "active":
			continue
		if entry.ready:
			return entry.duplicate(true)
		if fallback.is_empty():
			fallback = entry
	return fallback.duplicate(true)

func refresh() -> void:
	if _catalog == null or not is_instance_valid(_state) or not is_instance_valid(_delivery):
		return
	var next: Array[Dictionary] = []
	for task: Dictionary in _catalog.get_tasks():
		if not task.has("delivery"):
			continue
		var view := _journal.get_task(task.id)
		if not view.get("revealed", false):
			continue
		var order_id: String = task.delivery.order_id
		var done: bool = view.status == "completed" or (view.result.is_empty() and _state.get_flag("delivery." + order_id + ".completed"))
		if not done and view.status not in ["failed", "expired", "cancelled"] and not _delivery.is_order_available(order_id):
			continue
		var accepted := _delivery.is_order_accepted(order_id)
		if view.status not in ["failed", "expired", "cancelled"] and not done and not accepted and not _delivery.can_accept_order(order_id):
			continue
		next.append(_project(task, view, accepted, done))
	_project_shared_demand(next)
	var tracked := str(_state.get_variable(TRACKED_KEY, ""))
	if next != _entries or _tracked_id != tracked:
		_entries = next
		_tracked_id = tracked
		changed.emit()

## Cups remain shared inventory. Readiness means this customer can receive one;
## preparation covers the total demand of every unfinished accepted order.
func _project_shared_demand(entries: Array[Dictionary]) -> void:
	var demand: Dictionary = {}
	for entry: Dictionary in entries:
		if entry.status == "active" and not entry.product_id.is_empty():
			demand[entry.product_id] = int(demand.get(entry.product_id, 0)) + 1
	for entry: Dictionary in entries:
		entry.remaining_to_craft = 0
		entry.craft_quantity = 0
		if entry.status != "active" or entry.product_id.is_empty():
			continue
		var needed: int = demand[entry.product_id]
		var owned := _inventory.get_stock(entry.product_id)
		entry.remaining_to_craft = maxi(0, needed - owned)
		if not entry.recipe_materials.is_empty() and entry.remaining_to_craft > 0:
			var materials: Array[String] = []
			materials.assign(entry.recipe_materials)
			entry.craft_quantity = mini(entry.remaining_to_craft, _production.get_max_craftable(materials))
			var preview := _production.preview_craft(materials, entry.remaining_to_craft)
			entry.can_craft = entry.craft_quantity > 0
			entry.missing = preview.missing.duplicate(true)
			var missing_names := PackedStringArray()
			for id: String in entry.missing:
				missing_names.append("%s ×%d" % [_production.get_item_name(id), entry.missing[id]])
			entry.missing_text = "、".join(missing_names)
		if needed > 1:
			entry.hint = "同款待交 %d 杯 · 库存 %d 杯 · 还需制作 %d 杯" % [needed, owned, entry.remaining_to_craft]
			if owned > 0 and owned < needed:
				entry.status_text = "可交付一单 · 共用库存"

## Priority only resolves competing targets inside the counter's selection group.
func get_interaction_priority(id: StringName) -> int:
	for entry: Dictionary in _entries:
		if entry.target_id == String(id) and entry.status == "active" and entry.ready:
			return 2
	# A companion without an order is still a counter-group NPC. The register
	# must outrank that neutral point as well as known, unready recipients.
	if id == &"orders":
		return 1
	return -1 if _delivery_targets.has(String(id)) else 0

func _project(task: Dictionary, view: Dictionary, accepted: bool, done: bool) -> Dictionary:
	var order_id: String = task.delivery.order_id
	var use_requirement := _delivery.get_use_requirement(order_id)
	var by_use := not use_requirement.is_empty()
	var requirement := use_requirement if by_use else _delivery.get_requirement(order_id)
	var items: Array[Dictionary] = []
	var names := PackedStringArray()
	var ready := _inventory.has_uses(requirement) if by_use else _inventory.has_materials(requirement)
	var icon: Texture2D
	for id: String in requirement:
		var definition := _inventory.get_definition(id)
		var item_name: String = definition.display_name if definition != null else "未知物品"
		items.append({"id": id, "name": item_name, "needed": int(requirement[id]), "owned": _inventory.get_uses(id) if by_use else _inventory.get_stock(id)})
		names.append("%s ×%d%s" % [item_name.trim_suffix("（成品）"), requirement[id], " 次" if by_use else ""])
		if definition != null and icon == null:
			icon = definition.icon
	var product_id: String = task.delivery.get("product_id", "")
	var status := "completed" if done else ("active" if accepted else "available")
	var stage := "ready" if ready else "collect"
	var label := "可交付" if ready else "待收集物资"
	var target_id: String = task.delivery.target_object_id
	var target_name: String = _target_names.get(target_id, "交付对象待确认")
	var hint := "交给" + target_name if ready else "收集所需物资后交付"
	var missing: Dictionary = {}
	var recipe_materials: Array[String] = []
	var can_craft := false
	if task.delivery.has("drink"):
		ready = _delivery.has_matching_drink(order_id)
		stage = "ready" if ready else "experiment"
		label = "可交付" if ready else "待自由调配"
		var ingredient_names := {}
		for ingredient: IngredientDefinition in WarehouseInventory.CATALOG.ingredients:
			ingredient_names[ingredient.id] = ingredient.display_name
		names.append(DrinkFormula.requirement_text(task.delivery.drink, ingredient_names))
		hint = "交给" + target_name if ready else "制作台 → 自由实验；选择奶茶基底与辛辣原料，确认报价后制作"
	if product_id.is_empty() and not ready:
		for item: Dictionary in items:
			if item.owned < item.needed:
				missing[item.id] = item.needed - item.owned
	if not product_id.is_empty() and not ready:
		var recipe := _production.get_recipe_by_product(product_id)
		if recipe == null or not recipe.is_available(_state):
			stage = "recipe_locked"
			label = "配方未解锁"
			hint = "已有成品也可交付；配方尚未解锁"
		else:
			recipe_materials.assign(recipe.materials)
			var preview := _production.preview_craft(recipe_materials)
			missing = preview.missing.duplicate(true)
			can_craft = accepted and preview.code == "ok"
			stage = "prepare" if preview.code == "ok" else "missing_materials"
			label = "待制作" if preview.code == "ok" else ("缺料" if not missing.is_empty() else "库存已满")
			hint = "前往制作台，配方已备好" if preview.code == "ok" else preview.message
	elif not product_id.is_empty():
		var recipe := _production.get_recipe_by_product(product_id)
		if recipe != null and recipe.is_available(_state):
			recipe_materials.assign(recipe.materials)
	if done:
		stage = "completed"
		label = "已完成"
		hint = "订单已交付并结算"
	elif view.status in ["failed", "expired", "cancelled"]:
		status = view.status
		stage = status
		label = {"failed": "已失败", "expired": "已过期", "cancelled": "已取消"}[status]
		hint = "任务已结束"
		ready = false
		can_craft = false
	elif not accepted:
		label = "可接取"
		hint = "接取后可追踪和交付"
	var missing_names := PackedStringArray()
	for id: String in missing:
		missing_names.append("%s ×%d" % [_production.get_item_name(id), missing[id]])
	var rewards: String = view.rewards.get("text", "暂无报酬")
	return {"order_id": order_id, "task_id": task.id, "title": "、".join(names), "task_title": view.title,
		"status": status, "stage": stage, "status_text": label, "accepted": accepted, "ready": ready,
		"target_id": target_id, "target_name": target_name, "items": items, "icon": icon,
		"product_id": product_id, "recipe_materials": recipe_materials, "can_craft": can_craft and not done,
		"free_formula": task.delivery.has("drink"),
		"missing": missing, "missing_text": "、".join(missing_names), "hint": hint, "rewards": rewards}
