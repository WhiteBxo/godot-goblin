class_name TaskCatalog
extends RefCounted
## Static definitions only. Validate everything before replacing the live catalog.

var last_error := ""
var _tasks: Array[Dictionary] = []

func load_file(path: String, references: Dictionary = {}) -> Error:
	if not FileAccess.file_exists(path):
		last_error = "Task file does not exist: " + path
		return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "Cannot open task file: " + path
		return FileAccess.get_open_error()
	return load_json(file.get_as_text(), references)

## Several chapter files form one catalog: task and order IDs stay unique across all.
func load_files(paths: Array[String], references: Dictionary = {}) -> Error:
	var tasks: Array = []
	for path: String in paths:
		if not FileAccess.file_exists(path):
			last_error = "Task file does not exist: " + path
			return ERR_FILE_NOT_FOUND
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK:
			last_error = "%s line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()]
			return ERR_PARSE_ERROR
		if not parser.data is Dictionary or not is_number(parser.data.get("version")) or parser.data.version != 1 or not parser.data.get("tasks") is Array:
			last_error = path + ": Expected version 1 and a tasks array"
			return ERR_INVALID_DATA
		if not _keys(parser.data, ["version", "tasks"], path):
			return ERR_INVALID_DATA
		tasks.append_array(parser.data.tasks)
	return load_json(JSON.stringify({"version": 1, "tasks": tasks}), references)

func load_json(text: String, references: Dictionary = {}) -> Error:
	var parser := JSON.new()
	var error := parser.parse(text)
	if error != OK:
		last_error = "Task JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		return error
	if not _references_valid(references) or not _validate(parser.data, references):
		return ERR_INVALID_DATA
	_tasks.assign(parser.data.tasks.duplicate(true))
	last_error = ""
	return OK

func get_tasks() -> Array[Dictionary]:
	return _tasks.duplicate(true)

func _invalid(context: String, message: String) -> bool:
	last_error = context + ": " + message
	return false

func _keys(data: Dictionary, allowed: Array, context: String) -> bool:
	for key: Variant in data:
		if key not in allowed:
			return _invalid(context, "Unknown field '%s'" % key)
	return true

static func is_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(value)

## Shared by delivery requirements and item rewards: stable IDs with positive ints.
func _item_quantities(value: Variant, context: String) -> bool:
	if not value is Dictionary or value.is_empty():
		return _invalid(context, "Expected item quantities")
	for id: Variant in value:
		var amount: Variant = value[id]
		if not id is String or not id.is_valid_identifier() or not is_number(amount) or amount != floor(amount) or amount < 1 or amount > WarehouseInventory.MAX_QUANTITY:
			return _invalid(context, "Expected valid item IDs and positive integer quantities")
	return true

func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

func _references_valid(references: Dictionary) -> bool:
	if not _keys(references, ["events", "locations"], "references"):
		return false
	for field: String in references:
		if not references[field] is Array:
			return _invalid("references/" + field, "Expected an array of namespaced IDs")
		var seen := {}
		for id: Variant in references[field]:
			if not StoryLibrary.is_namespaced(id) or seen.has(id):
				return _invalid("references/" + field, "Invalid or duplicate ID '%s'" % id)
			seen[id] = true
	return true

func _condition(value: Variant, context: String, references: Dictionary, final: bool = false) -> bool:
	if not value is Dictionary:
		return _invalid(context, "Expected a condition object")
	var fields: Array = ["type"]
	match value.get("type"):
		"flag", "variable_at_least":
			fields.append("key")
			if not StoryLibrary.is_namespaced(value.get("key")):
				return _invalid(context + "/key", "Expected a namespaced fact key")
			if value.type == "variable_at_least":
				if final:
					return _invalid(context, "Final completion requires an explicit flag or completed event")
				fields.append("value")
				if not is_number(value.get("value")) or value.value <= 0:
					return _invalid(context + "/value", "Expected a finite number > 0")
		"event_completed":
			fields.append("id")
			if not StoryLibrary.is_namespaced(value.get("id")) or value.id not in references.get("events", []):
				return _invalid(context + "/id", "Unknown story event reference '%s'" % value.get("id"))
		_:
			return _invalid(context + "/type", "Unknown condition type '%s'" % value.get("type"))
	return _keys(value, fields, context)

func _presentation(data: Dictionary, context: String, references: Dictionary) -> bool:
	if data.has("location_id") and (not StoryLibrary.is_namespaced(data.location_id) or data.location_id not in references.get("locations", [])):
		return _invalid(context + "/location_id", "Unknown location reference '%s'" % data.location_id)
	# A task objective may name the interaction point it wants the cursor to aim
	# at; scene anchors stay the authority for chapter maps.
	if data.has("target_point") and (not _text(data.target_point) or not data.target_point.is_valid_identifier()):
		return _invalid(context + "/target_point", "Expected a stable interaction identifier")
	if data.has("reveal_when") and not _condition(data.reveal_when, context + "/reveal_when", references):
		return false
	return true

func _validate(data: Variant, references: Dictionary) -> bool:
	if not data is Dictionary or not is_number(data.get("version")) or data.version != 1 or not data.get("tasks") is Array:
		return _invalid("Tasks", "Expected version 1 and a tasks array")
	if not _keys(data, ["version", "tasks"], "Tasks"):
		return false
	var used := {}
	var orders := {}
	for index in range(data.tasks.size()):
		var task: Variant = data.tasks[index]
		var context := "tasks[%d]" % index
		if not task is Dictionary:
			return _invalid(context, "Expected a task object")
		if not StoryLibrary.is_namespaced(task.get("id")) or used.has(task.id):
			return _invalid(context + "/id", "Invalid or duplicate task ID '%s'" % task.get("id"))
		used[task.id] = true
		context += "(" + task.id + ")"
		if not _keys(task, ["id", "type", "title", "description", "activate_when", "complete_when", "objectives", "location_id", "difficulty", "rewards", "reveal_when", "delivery", "fail_when", "deadline", "allow_cancel"], context):
			return false
		if task.get("type") not in ["main", "commission"]:
			return _invalid(context + "/type", "Expected main or commission")
		for field: String in ["title", "description"]:
			if not _text(task.get(field)):
				return _invalid(context + "/" + field, "Expected non-empty text")
		if not _condition(task.get("activate_when"), context + "/activate_when", references) or not _condition(task.get("complete_when"), context + "/complete_when", references, true):
			return false
		if task.has("fail_when") and not _condition(task.fail_when, context + "/fail_when", references, true):
			return false
		if task.has("deadline") and not DayPhase.is_valid_deadline(task.deadline):
			return _invalid(context + "/deadline", "Expected day >= 1, day/night phase and explicit at/after boundary")
		if task.has("allow_cancel") and not task.allow_cancel is bool:
			return _invalid(context + "/allow_cancel", "Expected bool; refunds belong to the business coordinator")
		if task.has("delivery"):
			var delivery: Variant = task.delivery
			if not delivery is Dictionary or not _keys(delivery, ["order_id", "product_id", "items", "uses", "drink", "target_object_id", "accepted_flag"], context + "/delivery"):
				return _invalid(context + "/delivery", "Expected order_id, target_object_id and one requirement")
			for field: String in ["order_id", "target_object_id"]:
				if not _text(delivery.get(field)) or not delivery[field].is_valid_identifier():
					return _invalid(context + "/delivery/" + field, "Expected a stable object/item identifier")
			if delivery.has("accepted_flag") and not StoryLibrary.is_namespaced(delivery.accepted_flag):
				return _invalid(context + "/delivery/accepted_flag", "Expected a namespaced flag")
			# A delivery carries either one finished product or a material list.
			var requirement_count := int(delivery.has("product_id")) + int(delivery.has("items")) + int(delivery.has("drink")) + int(delivery.has("uses"))
			if requirement_count != 1:
				return _invalid(context + "/delivery", "Expected exactly one of product_id, items, uses or drink")
			if delivery.has("product_id"):
				if not _text(delivery.product_id) or not delivery.product_id.is_valid_identifier():
					return _invalid(context + "/delivery/product_id", "Expected a stable object/item identifier")
			elif delivery.has("drink"):
				if not DrinkFormula.requirement_valid(delivery.drink):
					return _invalid(context + "/delivery/drink", "Invalid formula, base, tags or minimum taste")
			elif not _item_quantities(delivery.get("uses", delivery.get("items")), context + "/delivery/materials"):
				return false
			if orders.has(delivery.order_id):
				return _invalid(context + "/delivery/order_id", "Duplicate order ID")
			orders[delivery.order_id] = true
			if task.complete_when.type != "flag":
				return _invalid(context + "/complete_when", "Delivery completion requires a flag")

		if not _presentation(task, context, references):
			return false
		if task.has("difficulty") and task.difficulty not in ["low", "medium", "high"]:
			return _invalid(context + "/difficulty", "Expected low, medium or high")
		if task.has("rewards"):
			var reward: Variant = task.rewards
			if not reward is Dictionary or not _text(reward.get("text")):
				return _invalid(context + "/rewards/text", "Expected a reward object with non-empty text")
			if not _keys(reward, ["text", "reveal_when", "items", "money"], context + "/rewards"):
				return false
			if reward.has("money") and (not is_number(reward.money) or reward.money != floor(reward.money) or reward.money < 0 or reward.money > 2147483647):
				return _invalid(context + "/rewards/money", "Expected a nonnegative bounded integer")
			if reward.has("items") and not _item_quantities(reward.items, context + "/rewards/items"):
				return false

			if reward.has("reveal_when") and not _condition(reward.reveal_when, context + "/rewards/reveal_when", references):
				return false
		if not _objectives(task.get("objectives"), context + "/objectives", references):
			return false
	return true

func _objectives(value: Variant, context: String, references: Dictionary) -> bool:
	if not value is Array or value.is_empty():
		return _invalid(context, "Expected a non-empty objectives array")
	var used := {}
	var has_required := false
	for index in range(value.size()):
		var objective: Variant = value[index]
		var path := context + "[%d]" % index
		if not objective is Dictionary:
			return _invalid(path, "Expected an objective object")
		if not objective.get("id") is String or not objective.id.is_valid_identifier() or used.has(objective.id):
			return _invalid(path + "/id", "Invalid or duplicate objective ID")
		used[objective.id] = true
		if not _keys(objective, ["id", "text", "hint", "complete_when", "required", "location_id", "reveal_when", "target_point"], path):
			return false
		if not _text(objective.get("text")) or not objective.get("required", true) is bool:
			return _invalid(path, "Expected non-empty text and bool required")
		# 任务指引是可选的界面提示（怎么操作），和任务项目（做什么）分开存。
		if objective.has("hint") and not _text(objective.get("hint")):
			return _invalid(path + "/hint", "Expected a non-empty hint when present")
		has_required = has_required or objective.get("required", true)
		if not _condition(objective.get("complete_when"), path + "/complete_when", references) or not _presentation(objective, path, references):
			return false
	return true if has_required else _invalid(context, "At least one required objective is needed")

static func matches_condition(condition: Dictionary, state: Node) -> bool:
	match condition.type:
		"flag":
			return state.get_flag(condition.key)
		"event_completed":
			return state.is_event_completed(condition.id)
		"variable_at_least":
			var value: Variant = state.get_variable(condition.key)
			return is_number(value) and value >= condition.value
	return false

static func matches_facts(condition: Dictionary, flags: Dictionary, variables: Dictionary, events: Array) -> bool:
	match condition.type:
		"flag":
			return flags.get(condition.key, false)
		"event_completed":
			return condition.id in events
		"variable_at_least":
			var value: Variant = variables.get(condition.key)
			return is_number(value) and value >= condition.value
	return false
