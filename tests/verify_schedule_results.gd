extends SceneTree
## Isolated configuration only: no formal deadlines, refunds or casino rules.

const StateData = preload("res://src/core/game_state.gd")
var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _task(id: String) -> Dictionary:
	return {"id": "schedule_test." + id, "type": "commission", "title": "测试委托 · " + id,
		"description": "独立配置的任务结果，不代表正式策划规则。",
		"activate_when": {"type": "flag", "key": "schedule_test.active"},
		"complete_when": {"type": "flag", "key": "schedule_test." + id + "_done"},
		"objectives": [{"id": "deliver", "text": "完成业务目标",
			"complete_when": {"type": "flag", "key": "schedule_test." + id + "_done"}}]}

func _catalog(tasks: Array) -> TaskCatalog:
	var catalog := TaskCatalog.new()
	_check(catalog.load_json(JSON.stringify({"version": 1, "tasks": tasks})) == OK, "Isolated outcome configuration loads: " + catalog.last_error)
	return catalog

func _run() -> void:
	_test_schedule()
	_test_schema()
	_test_acceptance_boundary()
	await _test_results_and_ui()
	_test_delivery()
	print("SCHEDULE_RESULTS: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_schedule() -> void:
	var state := StateData.new()
	var changes: Array[int] = []
	state.state_changed.connect(func() -> void: changes.append(state.current_day))
	_check(DayPhase.advance_to(state, 1, "day") == OK and changes.is_empty(), "Retrying current point is silent")
	_check(DayPhase.advance_to(state, 2, "day") == ERR_INVALID_PARAMETER, "Skipping a phase is rejected")
	_check(DayPhase.advance_to(state, 0, "night") == ERR_INVALID_PARAMETER, "Invalid day is rejected")
	_check(DayPhase.advance_to(state, 1, "dusk") == ERR_INVALID_PARAMETER, "Unknown phase is rejected")
	_check(DayPhase.advance_to(state, 1, "night") == OK and changes == [1], "Absolute target advances once")
	var saved := state.to_dict()
	_check(DayPhase.advance_to(state, 1, "night") == OK and changes == [1], "Repeated business request emits nothing")
	_check(DayPhase.advance_to(state, 2, "day") == OK and state.current_day == 2, "Next morning advances the date")
	_check(DayPhase.advance_to(state, 1, "night") == ERR_INVALID_PARAMETER, "Stale target never rewinds the schedule")
	_check(state.restore_state(saved) == OK and DayPhase.advance_to(state, 1, "night") == OK and state.to_dict() == saved, "Restored schedule accepts the same target without another advance")
	var at := {"day": 1, "phase": "night", "boundary": "at"}
	var after := {"day": 1, "phase": "night", "boundary": "after"}
	_check(DayPhase.is_deadline_reached(state, at) and not DayPhase.is_deadline_reached(state, after), "Deadline explicitly distinguishes at from after")
	DayPhase.advance_to(state, 2, "day")
	_check(DayPhase.is_deadline_reached(state, after), "After-night deadline is crossed the next morning")
	_check(not DayPhase.is_deadline_reached(state, {"day": 2, "phase": "night", "boundary": "at"}), "Future deadline has not been reached")
	_check(not DayPhase.is_deadline_reached(null, at), "Missing state cannot meet a deadline")
	for invalid: Variant in [null, true, 1, "", "dusk"]:
		state.set_variable("world.phase", invalid)
		_check(DayPhase.get_phase(state).is_empty() and DayPhase.advance_to(state, 2, "night") == ERR_INVALID_DATA and not DayPhase.is_deadline_reached(state, at), "Explicit malformed phase fails closed")
	state.restore_state(saved)
	state.set_current_day(9223372036854775807)
	var overflow := state.to_dict()
	_check(not DayPhase.enter_day(state) and state.to_dict() == overflow, "Date overflow is rejected before changing either phase key")
	state.free()

func _test_schema() -> void:
	var catalog := _catalog([_task("schema")])
	var baseline := catalog.get_tasks()
	for deadline: Variant in [null, {}, {"day": 0, "phase": "night", "boundary": "at"}, {"day": 1.5, "phase": "night", "boundary": "at"}, {"day": true, "phase": "night", "boundary": "at"}, {"day": 1, "phase": "night"}, {"day": 1, "phase": "dusk", "boundary": "at"}, {"day": 1, "phase": "night", "boundary": "before"}, {"day": 1, "phase": "night", "boundary": "at", "extra": true}]:
		var task := _task("schema")
		task.deadline = deadline
		_check(catalog.load_json(JSON.stringify({"version": 1, "tasks": [task]})) == ERR_INVALID_DATA and "deadline" in catalog.last_error and catalog.get_tasks() == baseline, "Malformed deadline is atomically rejected")
	var task := _task("schema")
	task.allow_cancel = "yes"
	_check(catalog.load_json(JSON.stringify({"version": 1, "tasks": [task]})) == ERR_INVALID_DATA, "Cancellation policy requires bool")
	task.erase("allow_cancel")
	task.fail_when = {"type": "variable_at_least", "key": "schedule_test.count", "value": 1}
	_check(catalog.load_json(JSON.stringify({"version": 1, "tasks": [task]})) == ERR_INVALID_DATA, "Failure requires an explicit business flag or event")

func _test_acceptance_boundary() -> void:
	var task := _task("accepted")
	task.delivery = {"order_id": "accepted_order", "target_object_id": "customer", "product_id": "pearl_milk_tea", "accepted_flag": "schedule_test.accepted"}
	task.deadline = {"day": 1, "phase": "night", "boundary": "after"}
	task.fail_when = {"type": "event_completed", "id": "schedule_test.failure_event"}
	var catalog := TaskCatalog.new()
	_check(catalog.load_json(JSON.stringify({"version": 1, "tasks": [task]}), {"events": ["schedule_test.failure_event"]}) == OK, "Explicit failure events validate through the catalog")
	var state := StateData.new()
	var journal := TaskJournal.new()
	journal.configure(catalog, state)
	state.set_flag("schedule_test.active")
	DayPhase.advance_to(state, 1, "night")
	DayPhase.advance_to(state, 2, "day")
	_check(state.get_task_result(task.id).is_empty(), "Chapter activation does not expire an unaccepted order")
	state.set_flag("schedule_test.accepted")
	_check(state.get_task_result(task.id).status == "expired", "Accepting a configured overdue task records expiry immediately")
	state.start_new_game()
	state.apply_flags({"schedule_test.active": true, "schedule_test.accepted": true})
	journal.free()
	state.complete_event("schedule_test.failure_event")
	_check(state.get_task_result(task.id).status == "failed", "Failure still settles with no scene journal present")
	state.set_flag("schedule_test.active", false)
	journal = TaskJournal.new()
	journal.configure(catalog, state)
	_check(journal.get_task(task.id).status == "failed" and journal.has_started_tasks(), "Cleared activation cannot hide the rebuilt terminal history")
	journal.free()
	state.free()

func _test_results_and_ui() -> void:
	var success := _task("success")
	var failure := _task("failure")
	failure.fail_when = {"type": "flag", "key": "schedule_test.failed"}
	var expiry := _task("expiry")
	expiry.deadline = {"day": 1, "phase": "night", "boundary": "at"}
	var cancel := _task("cancel")
	cancel.allow_cancel = true
	var pending := _task("pending")
	var conflict := _task("conflict")
	conflict.fail_when = {"type": "flag", "key": "schedule_test.conflict_failed"}
	var catalog := _catalog([success, failure, expiry, cancel, pending, conflict])
	var state := StateData.new()
	root.add_child(state)
	var journal := TaskJournal.new()
	root.add_child(journal)
	_check(journal.configure(catalog, state) == OK, "Journal binds definitions to the session")
	var settled: Array[String] = []
	state.task_settled.connect(func(id: String, result: Dictionary) -> void:
		settled.append(id)
		_check(state.get_task_result(id) == result and journal.get_task(id).status == result.status, "Settlement observers see the complete persistent projection")
		_check(state.settle_task_result(id, "cancelled") == ERR_BUSY and state.start_new_game() == ERR_BUSY and not DayPhase.enter_day(state) and not state.set_flag("schedule_test.reentry") and not state.get_warehouse_inventory().add_ingredient("syrup", 1), "Outcome notifications reject synchronous writes and schedule/new-game reentry")
		result.reason = "observer mutation"
	)
	state.set_flag("schedule_test.active")
	var changes: Array[bool] = []
	state.state_changed.connect(func() -> void:
		if state.get_flag("schedule_test.failed"):
			changes.append(state.get_task_result(failure.id).get("status") == "failed")
	)
	state.set_flag("schedule_test.success_done")
	_check(journal.get_task(success.id).status == "completed" and journal.get_task(success.id).current_objective.is_empty(), "Success locks the result and removes the current objective")
	state.set_flag("schedule_test.success_done", false)
	_check(journal.get_task(success.id).status == "completed", "Clearing a success fact cannot reopen the task")
	state.set_flag("schedule_test.failed")
	_check(changes == [true] and journal.get_task(failure.id).status == "failed", "Failure is committed before state_changed")
	state.set_flag("schedule_test.failure_done")
	_check(journal.get_task(failure.id).status == "failed", "Later success cannot replace a failed result")
	var economy_before := state.get_transactions().to_dict()
	_check(state.settle_task_result(pending.id, "cancelled") == ERR_UNAVAILABLE, "Missing cancellation rule remains pending")
	_check(state.settle_task_result(pending.id, "failed") == ERR_UNAVAILABLE, "Missing failure rule cannot be invented")
	_check(state.settle_task_result(cancel.id, "cancelled", "测试主动取消") == OK, "Explicitly allowed cancellation records caller reason")
	_check(state.get_transactions().to_dict() == economy_before, "Outcome cancellation invents no refunds or penalties")
	_check(state.settle_task_result(cancel.id, "completed") == ERR_ALREADY_EXISTS, "Opposite terminal result cannot settle twice")
	DayPhase.advance_to(state, 1, "night")
	_check(journal.get_task(expiry.id).status == "expired" and not state.can_complete_task(expiry.id), "Configured deadline locks expiry in the phase commit")
	_check(journal.get_task(pending.id).status == "active", "Task without a deadline remains active after the boundary")
	state.apply_flags({"schedule_test.conflict_done": true, "schedule_test.conflict_failed": true})
	_check(state.get_task_result(conflict.id).is_empty() and journal.get_task(conflict.id).status == "active" and not state.can_complete_task(conflict.id), "Conflicting simultaneous conditions remain pending and cannot pay out")
	_check(settled.size() == 4, "Exactly one live settlement per terminal task")
	_check(state.get_task_result(failure.id).reason == "", "Signal dictionary cannot mutate the stored result")
	var snapshot := state.to_dict()
	var snapshot_copy := state.to_dict()
	snapshot_copy.task_results[cancel.id].reason = "snapshot mutation"
	_check(state.to_dict() == snapshot, "Snapshot result containers are independent")
	journal.refresh()
	journal.refresh()
	_check(state.to_dict() == snapshot and settled.size() == 4, "Repeated projection refresh is read-only")
	journal.free()
	journal = TaskJournal.new()
	root.add_child(journal)
	journal.configure(catalog, state)
	_check(journal.has_started_tasks() and journal.get_visible_tasks().size() == 6 and journal.get_active_tasks().size() == 2 and state.to_dict() == snapshot, "Rebuilt journal retains history and only pending tasks remain active")
	var restored := StateData.new()
	_check(restored.restore_state(snapshot) == OK and restored.to_dict() == snapshot, "Fresh session restores terminal results before any scene is built")
	var restore_events: Array[String] = []
	restored.task_settled.connect(func(id: String, _result: Dictionary) -> void: restore_events.append(id))
	restored.bind_task_catalog(catalog)
	_check(restored.restore_state(snapshot) == OK and restore_events.is_empty(), "Rebinding and identical restore replay no settlement")
	var legacy := snapshot.duplicate(true)
	legacy.schema_version = 4
	legacy.erase("task_results")
	legacy.flags["schedule_test.success_done"] = true
	legacy.flags["schedule_test.failure_done"] = false
	_check(restored.restore_state(legacy) == OK and restored.get_task_result(success.id).status == "completed" and restore_events.is_empty(), "Legacy facts reconcile without live settlement events")
	var restored_changes: Array[bool] = []
	restored.state_changed.connect(func() -> void: restored_changes.append(true))
	_check(restored.restore_state(legacy) == OK and restored_changes.is_empty(), "Repeated legacy restore is also silent")
	for invalid: Variant in [null, [], {"bad": {}}, {"schedule_test.bad": {"status": "active", "day": 1, "phase": "day", "reason": ""}}, {"schedule_test.bad": {"status": "failed", "day": 1.0, "phase": "day", "reason": ""}}, {"schedule_test.bad": {"status": "failed", "day": 1, "phase": "dusk", "reason": ""}}]:
		var bad := snapshot.duplicate(true)
		bad.task_results = invalid
		var before := restored.to_dict()
		_check(restored.restore_state(bad) == ERR_INVALID_DATA and restored.to_dict() == before, "Invalid result snapshot is rejected atomically")
	var panel: TaskPopup = load("res://src/UI/tasks/task_popup.tscn").instantiate()
	panel.bind_journal(journal)
	root.add_child(panel)
	panel.show()
	for frame in range(3):
		await process_frame
	_check(panel.get_entries().item_count == 6, "Task panel lists active tasks and terminal history")
	for index in range(4):
		panel.get_entries().item_selected.emit(index)
		_check(panel.get_detail_text().text.contains(["已完成", "已失败", "已过期", "已取消"][index]) and panel.get_detail_text().text.contains("结算时间："), "Panel displays terminal result and schedule point")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for size: Vector2i in [Vector2i(640, 360), Vector2i(320, 360)]:
			root.content_scale_size = size
			root.size = size
			for frame in range(3):
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/schedule_results_%d.png" % size.x)
	panel.free()
	state.start_new_game()
	_check(state.to_dict().task_results.is_empty() and journal.get_visible_tasks().is_empty(), "New game clears terminal history with all session state")
	journal.free()
	state.free()
	restored.free()

func _test_delivery() -> void:
	for shared: bool in [true, false]:
		var task := _task("delivery")
		task.delivery = {"order_id": "schedule_delivery", "target_object_id": "customer", "product_id": "pearl_milk_tea"}
		task.deadline = {"day": 1, "phase": "night", "boundary": "at"}
		task.allow_cancel = true
		task.fail_when = {"type": "flag", "key": "schedule_test.delivery_failed"}
		task.rewards = {"text": "测试奖励", "items": {"syrup": 1}}
		var catalog := _catalog([task])
		var state := StateData.new()
		var journal := TaskJournal.new()
		journal.configure(catalog, state)
		var inventory := state.get_warehouse_inventory() if shared else WarehouseInventory.new()
		inventory.add_ingredient("pearl_milk_tea", 2)
		var delivery := TaskDelivery.new()
		_check(delivery.configure(catalog, journal, state, inventory) == OK, "Delivery binds configured lifecycle")
		state.set_flag("schedule_test.active")
		var model := OrderBoardModel.new()
		model.configure(catalog, journal, state, inventory, state.get_tea_production(), delivery)
		var active := state.to_dict()
		DayPhase.advance_to(state, 1, "night")
		var before := inventory.to_dict()
		_check(not delivery.try_submit("schedule_delivery", "customer").ok and not delivery.can_accept_order("schedule_delivery") and inventory.to_dict() == before, "Expired delivery cannot accept, consume stock or reward")
		_check(model.get_entry("schedule_delivery").status == "expired" and not model.get_entry("schedule_delivery").can_craft and model.get_tracked_entry().is_empty(), "Order projection exposes expiry and stops tracking")
		state.restore_state(active)
		state.set_flag("schedule_test.delivery_failed")
		_check(not delivery.try_submit("schedule_delivery", "customer").ok and model.get_entry("schedule_delivery").status == "failed", "Failed delivery cannot pay out and projects its result")
		if shared:
			var failed := state.to_dict()
			_check(state.commit_delivery({}, {}, 1, {task.complete_when.key: true}, 1, "bypass_failed", Callable(), {}, task.id) == ERR_UNAVAILABLE and state.to_dict() == failed, "GameState also rejects a direct payout for a failed task")
		state.restore_state(active)
		_check(state.settle_task_result(task.id, "cancelled") == OK, "Active configured delivery can be cancelled")
		_check(not delivery.try_submit("schedule_delivery", "customer").ok and delivery.accept_order("schedule_delivery") == ERR_ALREADY_EXISTS, "Cancelled delivery cannot restart or pay out")
		state.restore_state(active)
		var observations: Array[bool] = []
		state.state_changed.connect(func() -> void:
			if state.get_flag("delivery.schedule_delivery.completed"):
				observations.append(state.get_task_result(task.id).get("status") == "completed" and inventory.get_stock("pearl_milk_tea") == 1 and state.get_variable("shop.orders_completed") == 1)
		)
		var settlements: Array[String] = []
		state.task_settled.connect(func(id: String, _result: Dictionary) -> void:
			settlements.append(id)
			_check(not inventory.add_ingredient("syrup", 1), "Task settlement cannot reenter either inventory adapter")
		)
		_check(delivery.try_submit("schedule_delivery", "customer").ok and observations == [true] and settlements == [task.id], "Delivery publishes inventory, count and persistent result together exactly once")
		before = inventory.to_dict()
		DayPhase.advance_to(state, 1, "night")
		_check(state.get_task_result(task.id).status == "completed" and not delivery.try_submit("schedule_delivery", "customer").ok and inventory.to_dict() == before and settlements.size() == 1, "Later deadline never replaces successful payout")
		model.free()
		delivery.free()
		journal.free()
		if not shared:
			inventory.free()
		state.free()
