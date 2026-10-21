extends SceneTree
## Day 1 closing systems: payment, item condition, phase, title card, animation,
## walk-in triggers, the S03-S06 chapter host, chapter stage isolation and delivery fallback.

var _failures: Array[String] = []
var _state: Node
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)

func _frames(count: int = 4) -> void:
	for index in range(count):
		await physics_frame
	await process_frame

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	_state = root.get_node("GameState")
	_check_schema()
	_check_payment()
	await _check_shop_handoff()
	await _check_shop_host()
	await _check_settlement_host()
	_check_catalog_and_fallback()
	print("DAY1_CHAPTER_SYSTEMS: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _new_day1(stage: String) -> void:
	_check(_state.start_new_game() == OK, "New game")
	_check(_state.select_business_profile("day1") == OK, "Select Day 1")
	_state.set_story_stage(stage)

func _story(events: Dictionary) -> String:
	return JSON.stringify({"version": 1, "events": events})

func _check_schema() -> void:
	var library := StoryLibrary.new()
	var accepted := {
		"t.pay": {"steps": [{"command": "pay_items", "items": {"strange_coin": 2}, "receipt": "t.paid", "set_flags": {"t.cleared": true}}]},
		"t.when": {"conditions": {"items": {"strange_coin": 1}}, "steps": [{"command": "wait", "seconds": 0, "when": {"items": {"strange_coin": 3}}}]},
		"t.phase": {"steps": [{"command": "set_phase", "phase": "day"}]},
		"t.card": {"steps": [{"command": "title_card", "text": "第一天结束", "subtitle": "", "seconds": 1, "wait": false}]},
		"t.anim": {"steps": [{"command": "actor_animate", "actor": "fat_goblin", "animation": "emote_laugh", "hold": true}]},
	}
	_check(library.load_json(_story(accepted)) == OK, "New commands and items condition validate: " + library.last_error)
	var rejected := [
		{"command": "pay_items", "items": {}, "receipt": "t.paid"},
		{"command": "pay_items", "items": {"strange_coin": 0}, "receipt": "t.paid"},
		{"command": "pay_items", "items": {"strange_coin": 1.5}, "receipt": "t.paid"},
		{"command": "pay_items", "items": {"strange_coin": 1}, "receipt": "paid"},
		{"command": "pay_items", "items": {"strange_coin": 1}, "receipt": "t.paid", "set_flags": {"t.paid": true}},
		{"command": "set_phase", "phase": "dusk"},
		{"command": "title_card", "text": " "},
		{"command": "title_card", "text": "x", "seconds": 0},
		{"command": "actor_animate", "actor": "fat_goblin"},
		{"command": "actor_animate", "actor": "fat_goblin", "animation": "x", "hold": 1},
		{"command": "wait", "seconds": 0, "when": {"items": {"strange_coin": -1}}},
	]
	for step: Dictionary in rejected:
		_check(library.load_json(_story({"t.bad": {"steps": [step]}})) != OK, "Schema rejects " + JSON.stringify(step))

func _check_payment() -> void:
	_new_day1("day1.s05")
	var inventory: WarehouseInventory = _state.get_warehouse_inventory()
	var costs := {"strange_coin": 2}
	_check(_state.commit_item_payment("t.bribe", costs, {}) == ERR_UNAVAILABLE, "Undiscovered or missing coins cannot pay")
	_check(not _state.get_flag("t.bribe"), "Failed payment writes no receipt")
	_check(_state.commit_story_interaction("t.coins", {"strange_coin": 3}, {}) == OK, "Seed three real coins")
	_check(_state.commit_item_payment("bribe", costs, {}) == ERR_INVALID_DATA, "Receipt must be namespaced")
	_check(_state.commit_item_payment("t.bribe", costs, {"t.cleared": true}) == OK, "Payment commits")
	_check(inventory.get_stock("strange_coin") == 1, "Payment deducts exactly the cost")
	_check(_state.get_flag("t.bribe") and _state.get_flag("t.cleared"), "Payment writes receipt and facts together")
	_check(_state.commit_item_payment("t.bribe", costs, {}) == ERR_ALREADY_EXISTS, "Same receipt never charges twice")
	_check(inventory.get_stock("strange_coin") == 1, "Retry keeps the balance")
	_check(_state.commit_item_payment("t.second", costs, {}) == ERR_UNAVAILABLE and inventory.get_stock("strange_coin") == 1, "Shortage changes nothing")
	_check(_state.begin_business_transaction(), "Hold the session")
	_check(_state.commit_item_payment("t.third", {"strange_coin": 1}, {}) == ERR_BUSY, "Busy session rejects payment")
	_state.end_business_transaction()
	var snapshot: Dictionary = _state.to_dict()
	_check(_state.restore_state(snapshot) == OK, "Snapshot with payment receipt restores")
	_check(_state.commit_item_payment("t.bribe", costs, {}) == ERR_ALREADY_EXISTS, "Restored payment receipt prevents another charge")
	var observed := {"atomic": false, "reentry": OK, "consume": true}
	var on_changed := func() -> void:
		observed.atomic = inventory.get_stock("strange_coin") == 0 and _state.get_flag("t.last") and _state.get_flag("t.last_clear")
		observed.reentry = _state.commit_item_payment("t.reentry", {"strange_coin": 1}, {})
		observed.consume = inventory.try_consume({"strange_coin": 1})
	_state.state_changed.connect(on_changed, CONNECT_ONE_SHOT)
	_check(_state.commit_item_payment("t.last", {"strange_coin": 1}, {"t.last_clear": true}) == OK, "Final coin payment commits")
	_check(observed.atomic and observed.reentry == ERR_BUSY and not observed.consume, "Payment subscribers see the complete transaction and cannot reenter")

func _check_shop_handoff() -> void:
	_new_day1("day1.investigate_coins")
	var game: MainGame = load("res://src/core/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames()
	_check(game.get_chapter_controller().is_loaded(), "S02 coin-investigation boundary loads the chapter without rewinding")
	_state.set_story_stage("day1.wait_group")
	await _frames()
	_check(not game.get_chapter_controller().is_loaded(), "Earlier stage releases chapter ownership")
	_load_test_story(game, {"t.handoff": {"steps": [
		{"command": "set_stage", "value": "day1.investigate_coins"},
		{"command": "wait", "seconds": 0.05},
	]}})
	var result := await _run_event(game, "t.handoff")
	await _frames()
	_check(result.ok and game.get_chapter_controller().is_loaded(), "Busy S02-to-S03 handoff finishes before chapter activation")
	_check(_state.story_stage == "day1.investigate_coins", "Handoff keeps the coin-investigation stage")
	_check(game.get_player().collision_mask == 5, "Shop player collides with world and visible NPCs")
	var exit: SceneExit = game.get_active_level().get_scene_exits()[0]
	_check(not exit.get_node("Marker").visible and not exit.get_node("Label").visible, "Shop door keeps development markers hidden")
	current_scene = null
	game.queue_free()
	await _frames()

func _load_test_story(game: MainGame, events: Dictionary) -> void:
	var path := "user://day1_chapter_systems_story.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_story(events))
	file.close()
	_check(game.get_story_director().load_events(path) == OK, "Test story loads: " + game.get_story_director().last_error)

func _run_event(game: MainGame, id: String, timeout_ms: int = 8000) -> Dictionary:
	var director := game.get_story_director()
	var result := {"done": false, "ok": false, "reason": ""}
	var on_finish := func(event_id: String, ok: bool, reason: String) -> void:
		if event_id == id:
			result.done = true
			result.ok = ok
			result.reason = reason
	director.event_finished.connect(on_finish)
	var error := director.request_event(id)
	if error != OK:
		director.event_finished.disconnect(on_finish)
		return {"done": true, "ok": false, "reason": "request %s: %s" % [error_string(error), director.last_error]}
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not result.done and Time.get_ticks_msec() < deadline:
		if game.get_dialogue_manager().is_active():
			game.get_dialogue_manager().advance()
		await process_frame
	director.event_finished.disconnect(on_finish)
	return result

func _check_shop_host() -> void:
	_new_day1("day1.s06")
	_state.commit_story_interaction("t.shop_coins", {"strange_coin": 2}, {})
	var game: MainGame = load("res://src/core/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames()
	var chapter := game.get_chapter_controller()
	_check(chapter != null and chapter.is_loaded(), "Shop chapter controller loads the skeleton at S06: " + (chapter.last_error if chapter else "missing"))
	_check(_state.story_stage == "day1.s06", "Day1ShopController does not pull S06 back to a checkpoint")
	var card := game.get_title_card()
	_check(card != null, "Host creates a TitleCard")
	_check(card.get_parent() == game.get_node("TransitionLayer"), "Title card uses the existing transition layer")
	var shown := card.show_card("可见性检查", "", 5)
	_check(card.is_visible_in_tree(), "Showing a card reveals its host layer")
	card.cancel()
	_check(shown.completed and not game.get_node("TransitionLayer").visible, "Cancelling the last visual hides the transition layer")
	_load_test_story(game, {
		"t.pay_branch": {"once": false, "steps": [
			{"command": "pay_items", "items": {"strange_coin": 1}, "receipt": "t.toll", "set_flags": {"t.toll_ok": true}, "when": {"items": {"strange_coin": 1}}},
			{"command": "set_flag", "key": "t.too_poor", "when": {"items": {"strange_coin": 9}}},
		]},
		"t.pay_short": {"steps": [{"command": "pay_items", "items": {"strange_coin": 9}, "receipt": "t.big"}]},
		"t.card": {"once": false, "steps": [{"command": "title_card", "text": "第一天结束", "seconds": 0.05}]},
		"t.card_detached": {"steps": [{"command": "title_card", "text": "x", "seconds": 5, "wait": false}, {"command": "wait", "seconds": 0.05}]},
		"t.night": {"steps": [{"command": "set_phase", "phase": "night"}, {"command": "set_phase", "phase": "night"}]},
		"t.day": {"steps": [{"command": "set_phase", "phase": "day"}]},
		"t.anim_missing": {"steps": [{"command": "actor_animate", "actor": "fat_goblin", "animation": "collapse_down"}]},
		"t.anim_hold": {"steps": [{"command": "actor_animate", "actor": "fat_goblin", "animation": "emote_laugh", "hold": true}]},
		"t.ending": {"steps": [
			{"command": "set_flag", "key": "day1.s06.completed"},
			{"command": "title_card", "text": "第一天结束", "seconds": 0.05},
			{"command": "set_phase", "phase": "day"},
			{"command": "set_stage", "value": "day2.unpublished"},
			{"command": "title_card", "text": "第二天", "subtitle": "白天 · 奶茶店", "seconds": 0.05},
		]},
	})
	var inventory: WarehouseInventory = _state.get_warehouse_inventory()
	var result := await _run_event(game, "t.pay_branch")
	_check(result.ok, "Payment event succeeds: " + result.reason)
	_check(inventory.get_stock("strange_coin") == 1 and _state.get_flag("t.toll_ok"), "Event pays once and writes facts")
	_check(not _state.get_flag("t.too_poor"), "items condition skips the unaffordable branch")
	result = await _run_event(game, "t.pay_branch")
	_check(result.ok and inventory.get_stock("strange_coin") == 1, "Replayed event treats the settled receipt as paid")
	result = await _run_event(game, "t.pay_short")
	_check(not result.ok and inventory.get_stock("strange_coin") == 1, "Shortage fails the event without charging")
	result = await _run_event(game, "t.card")
	_check(result.ok and not card.is_showing(), "Title card completes and hides")
	result = await _run_event(game, "t.card_detached")
	_check(result.ok, "Non-blocking title card is drained or cancelled at the end: " + result.reason)
	await _frames()
	_check(not card.is_showing(), "Event end leaves no title card on screen")
	var day := int(_state.current_day)
	# Run the animation checks before advancing the day: past day 1 the world
	# projection puts this actor in his resting pose, whose sheet has no
	# `emote_laugh`, and a held expression would immediately be replaced by it.
	result = await _run_event(game, "t.anim_missing")
	_check(not result.ok, "Missing animation fails instead of skipping")
	var goblin := game.get_actor_director().get_actor(&"fat_goblin")
	result = await _run_event(game, "t.anim_hold")
	_check(result.ok, "Finite animation completes: " + result.reason)
	_check(goblin.animated_sprite.animation == &"emote_laugh", "Held pose stays after the event")
	goblin.teleport_to(goblin.global_position)
	_check(goblin.animated_sprite.animation != &"emote_laugh", "Teleport clears a held pose")
	result = await _run_event(game, "t.night")
	_check(result.ok and DayPhase.is_night(_state), "set_phase enters night and repeating it is a no-op")
	result = await _run_event(game, "t.day")
	_check(result.ok and not DayPhase.is_night(_state) and _state.current_day == day + 1, "set_phase day advances the day")
	# Ending recipe: chapter end card, morning, chapter stage isolation.
	_state.set_story_stage("day1.s06")
	_state.commit_day_phase("night")
	result = await _run_event(game, "t.ending")
	_check(result.ok and _state.story_stage == "day2.unpublished", "Ending moves to the chapter stage isolation: " + result.reason)
	await _frames()
	_check(game.get_chapter_gameplay() != null, "Rebuilt chapter retains its scene-local gameplay service")
	_check(not game.get_business_hud().get_node("Notice").visible, "Published chapter removes the obsolete Day2 unavailable notice")
	current_scene = null
	game.queue_free()
	await _frames()
	# A rebuilt shop must not drag the placeholder back to an S02 checkpoint.
	game = load("res://src/core/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames()
	_check(_state.story_stage == "day2.unpublished", "Rebuilt shop keeps the chapter stage isolation")
	current_scene = null
	game.queue_free()
	await _frames()

func _check_settlement_host() -> void:
	_new_day1("day1.investigate_coins")
	var game: MainGame = load("res://src/core/settlement.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames()
	var chapter := game.get_chapter_controller()
	_check(chapter != null and chapter.is_loaded(), "Settlement chapter controller loads the skeleton")
	_check(game.get_audio_manager().sounds.has("music.daily_milk_tea"), "Settlement registers the sound library")
	# Data-driven host features, exercised with an in-memory setup.
	var setup := {
		"story": "user://day1_chapter_systems_story.json", "dialogue": "res://src/resources/dialogue/day1_stages_03_06.json",
		"phases": "res://src/resources/story/day1_stages_03_06_phases.json",
		"auto_events": ["t.auto"],
		"derived_facts": [{"flag": "t.explored", "stage": "day1.s03", "all_flags": ["t.look_a", "t.look_b"]}],
		"scene_setups": [{"host": "settlement", "stage": "day1.s04", "actors": {"entrance_guard": "drunken_guard", "mansion_gate": null}}],
	}
	var path := "user://day1_chapter_systems_setup.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(setup))
	file.close()
	var bad := Day1ChapterController.new()
	var bad_path := "user://day1_chapter_systems_bad.json"
	file = FileAccess.open(bad_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"story": "x"}))
	file.close()
	_check(bad._load_setup(bad_path) != OK, "Incomplete setup is rejected")
	bad.free()
	_check(chapter._load_setup(path) == OK, "Test setup validates: " + chapter.last_error)
	_load_test_story(game, {
		"t.auto": {"conditions": {"stage": "day1.s03", "flags": {"t.explored": true}}, "steps": [{"command": "set_stage", "value": "day1.s04"}]},
		"t.zone": {"trigger": "t_zone", "steps": [{"command": "set_flag", "key": "t.zone_fired"}]},
	})
	chapter.set("_loaded", true)
	_state.set_story_stage("day1.s03")
	_state.set_flag("t.look_a")
	await _frames()
	_check(not _state.get_flag("t.explored"), "Derived fact waits for every source flag")
	_state.set_flag("t.look_b")
	await _frames(8)
	_check(_state.get_flag("t.explored"), "Derived fact is written once all flags hold")
	_check(_state.story_stage == "day1.s04" and _state.is_event_completed("t.auto"), "Auto event starts once its conditions hold")
	await _frames()
	var marker := game.get_actor_director().get_position(&"drunken_guard")
	var goblin := game.get_actor_director().get_actor(&"entrance_guard")
	var guard := game.get_actor_director().get_actor(&"mansion_gate")
	_check(goblin.visible and goblin.global_position.distance_to(marker.global_position) < 1.0, "Stage setup places the actor at its Marker")
	_check(guard == null or not guard.visible, "Stage setup hides actors mapped to null")
	await _frames()
	_check(goblin.visible, "World projection keeps staged visibility")
	# A failed automatic event must wait for explicit retry, even if state changes.
	setup.auto_events = ["t.fail_auto"]
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(setup))
	file.close()
	_check(chapter._load_setup(path) == OK, "Failure scenario setup validates")
	_load_test_story(game, {"t.fail_auto": {"steps": [
		{"command": "pay_items", "items": {"strange_coin": 99}, "receipt": "t.unaffordable"},
	]}})
	var attempts: Array[String] = []
	game.get_story_director().event_started.connect(func(id: String) -> void: attempts.append(id))
	_state.set_flag("t.refresh")
	await _frames(12)
	_state.set_flag("t.refresh_again")
	await _frames(12)
	_check(attempts == ["t.fail_auto"], "Failed automatic event is attempted once across state changes")
	var hud := game.get_business_hud()
	_check(hud == null or not hud.get_node("ResumeStory").visible, "Chapter failure does not expose the S01-S02 resume button")
	_load_test_story(game, {"t.zone": {"trigger": "t_zone", "steps": [{"command": "set_flag", "key": "t.zone_fired"}]}})
	# Walk-in trigger: routes through StoryDirector and retries after a rejection.
	var zone: StoryTriggerZone = load("res://src/gameplay/story_interaction/story_trigger_zone.tscn").instantiate()
	zone.trigger_id = &"t_zone"
	zone.required_stages = ["day1.s04"]
	game.get_active_level().add_child(zone)
	var player := game.get_player() as PlayerController
	# Place the zone on a real walkable spot. The old (-5000,-5000) sat outside the
	# map, and the host snaps a player teleported out of bounds back to the spawn,
	# so the walk-in never actually happened.
	var entry: Vector2 = game.get_active_level().get_spawn_position()
	zone.global_position = entry
	player.teleport_to(entry + Vector2(160, 0))
	game.call("_create_trigger_zones", zone)
	_check(game.get_trigger_zones().has(zone), "Host registers trigger zones")
	game.get_ui_manager().open_screen(ScreenIds.DIALOGUE)
	player.teleport_to(entry)
	# Area detection only updates on physics ticks; render frames left `_inside` false.
	for i in range(12):
		await physics_frame
	_check(zone.is_player_inside() and not _state.get_flag("t.zone_fired"), "Busy host rejects the walk-in without consuming it")
	game.get_ui_manager().close_screen(ScreenIds.DIALOGUE)
	for i in range(30):
		await physics_frame
	_check(_state.get_flag("t.zone_fired"), "Zone retries and starts the event once the host is free")
	current_scene = null
	game.queue_free()
	await _frames()

func _check_catalog_and_fallback() -> void:
	var catalog := TaskCatalog.new()
	# The real host injects the authored map regions (main.gd `_create_task_system`);
	# loading without them makes every `settlement.*` location look unknown.
	var references := {"locations": RpgWorldMapData.location_ids()}
	_check(catalog.load_files(Day1ChapterController.TASK_FILES, references) == OK, "Day 1 task files merge: " + catalog.last_error)
	var total := 0
	for path: String in Day1ChapterController.TASK_FILES:
		var single := TaskCatalog.new()
		_check(single.load_file(path, references) == OK, "Chapter file loads alone: " + path)
		total += single.get_tasks().size()
	_check(catalog.get_tasks().size() == total, "Chapter files merge without losing or duplicating tasks")
	var duplicate_path := "user://day1_chapter_systems_dup.json"
	var file := FileAccess.open(duplicate_path, FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(Day1ChapterController.TASK_FILES[0]))
	file.close()
	_check(catalog.load_files([Day1ChapterController.TASK_FILES[0], duplicate_path], references) != OK, "Duplicate IDs across files are rejected")
	# Two orders for one NPC: the active one is reported, not the later inactive one.
	var tasks := {"version": 1, "tasks": [
		_task("t.s04_order", "t.s04_open", "t.s04_done", "t_s04_order", "plain_milk_tea"),
		_task("t.s06_order", "t.s06_open", "t.s06_done", "t_s06_order", "day1_blood_milk_tea"),
	]}
	_new_day1("day1.s04")
	var test_catalog := TaskCatalog.new()
	_check(test_catalog.load_json(JSON.stringify(tasks)) == OK, "Fallback catalog loads: " + test_catalog.last_error)
	var journal := TaskJournal.new()
	root.add_child(journal)
	journal.configure(test_catalog, _state)
	var delivery := TaskDelivery.new()
	root.add_child(delivery)
	delivery.configure(test_catalog, journal, _state, _state.get_warehouse_inventory())
	_state.set_flag("t.s04_open")
	_check(delivery.is_order_accepted("t_s04_order") and delivery.accept_order("t_s04_order") == ERR_ALREADY_EXISTS, "Story-accepted order is already active and cannot be accepted twice")
	var reported: Array[String] = []
	delivery.delivery_failed.connect(func(order_id: String, _message: String) -> void: reported.append(order_id))
	var result := delivery.deliver_to("fat_goblin")
	_check(not result.ok and reported == ["t_s04_order"], "Missing materials report the active order, not the later one: %s" % [reported])
	delivery.queue_free()
	journal.queue_free()

func _task(id: String, open: String, done: String, order: String, product: String) -> Dictionary:
	return {"id": id, "type": "main", "title": id, "description": id,
		"activate_when": {"type": "flag", "key": open}, "reveal_when": {"type": "flag", "key": open},
		"complete_when": {"type": "flag", "key": done},
		"objectives": [{"id": "deliver", "text": "交付", "complete_when": {"type": "flag", "key": done}}],
		"delivery": {"order_id": order, "product_id": product, "target_object_id": "fat_goblin"}}
