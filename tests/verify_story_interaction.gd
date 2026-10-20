extends SceneTree
## Exercise the actual story component and the shared, atomic session transaction.

const POINT := preload("res://src/gameplay/story_interaction/story_interaction_point.tscn")
var _failures: Array[String] = []
var _state: Node
var _reentered := false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
		push_error(message)

func _point(kind: StoryInteractionPoint.Kind, id: StringName) -> StoryInteractionPoint:
	var point: StoryInteractionPoint = POINT.instantiate()
	point.kind = kind
	point.entry_id = id
	point.interaction_id = id
	point.item_id = "day1_griffin_blood"
	point.required_flags.assign([&"world.phase.night", &"day1.s04.commission_accepted"])
	point.required_stages.assign(["day1.s05"])
	point.success_flags.assign([&"day1.s05.blood_acquired"] if kind == StoryInteractionPoint.Kind.PICKUP else [&"day1.s05.document_read"])
	root.add_child(point)
	return point

func _run() -> void:
	_state = root.get_node("GameState")
	_state.start_new_game()
	_check(_state.select_business_profile("day1") == OK, "Use the real Day 1 inventory")
	var point := _point(StoryInteractionPoint.Kind.PICKUP, &"day1_blood_storage")
	_check(not point.resolve().ok, "Night/stage/acceptance gates reject an early pickup")
	DayPhase.enter_night(_state)
	_state.set_story_stage("day1.s05.search")
	_check(not point.resolve().ok, "Night and stage alone cannot bypass acceptance")
	_state.set_flag("day1.s04.commission_accepted")
	var inventory: WarehouseInventory = _state.get_warehouse_inventory()
	# An inventory observer attempts the same operation synchronously.
	inventory.changed.connect(func() -> void:
		_check(_state.get_flag("day1.s05.blood_acquired") and point.is_resolved(), "Observers see inventory, business fact and receipt together")
		if not _reentered:
			_reentered = true
			_check(not point.resolve().ok, "Synchronous reentry cannot grant a second item")
	, CONNECT_ONE_SHOT)
	var first_result := point.resolve()
	_check(first_result.ok, "Pickup commits: " + first_result.message)
	_check(inventory.get_stock("day1_griffin_blood") == 1, "Exactly one blood item enters the shared inventory")
	_check(not point.resolve().ok, "Repeated pickup rejects")
	var snapshot: Dictionary = _state.to_dict()
	point.queue_free()
	await process_frame
	point = _point(StoryInteractionPoint.Kind.PICKUP, &"day1_blood_storage")
	_check(not point.resolve().ok, "Recreated point reads the durable receipt")
	_check(_state.restore_state(snapshot) == OK, "Pickup snapshot restores")
	_check(not point.resolve().ok and inventory.get_stock("day1_griffin_blood") == 1, "Restore does not duplicate blood")
	var document := _point(StoryInteractionPoint.Kind.DOCUMENT, &"day1_elder_document")
	var notifications: Array[bool] = []
	document.resolved.connect(func(_id: StringName) -> void: notifications.append(true))
	_check(not _state.get_flag("day1.s05.document_read"), "Entering a document area does not count as reading")
	_check(document.resolve().ok and document.resolve().ok, "Document can be read again")
	_check(notifications.size() == 1 and _state.get_flag("day1.s05.document_read"), "Reading publishes one business fact and one notification")
	var bad := _point(StoryInteractionPoint.Kind.PICKUP, &"bad_pickup")
	bad.item_id = "missing_item"
	var before: Dictionary = _state.to_dict()
	_check(not bad.resolve().ok and _state.to_dict() == before, "Invalid item fails atomically with no receipt")
	bad.item_id = "day1_griffin_blood"
	_check(bad.resolve().ok, "Failed pickup can be retried after configuration is repaired")
	var full := _point(StoryInteractionPoint.Kind.PICKUP, &"full_pickup")
	# Earlier pickups already raised the stock, so fill by the remaining room
	# instead of a fixed amount: the entry must sit exactly at capacity.
	var room: int = WarehouseInventory.MAX_QUANTITY - inventory.get_stock("day1_griffin_blood")
	_check(inventory.add_ingredient("day1_griffin_blood", room), "Prepare a full inventory entry")
	before = _state.to_dict()
	_check(not full.resolve().ok and _state.to_dict() == before, "Capacity failure grants nothing and records no receipt")
	full.queue_free()
	point.queue_free()
	document.queue_free()
	bad.queue_free()
	await process_frame
	print("STORY_INTERACTION: ", "PASS" if _failures.is_empty() else "FAIL")
	quit(0 if _failures.is_empty() else 1)
