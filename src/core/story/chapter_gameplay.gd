class_name ChapterGameplay
extends Node
## Scene-local business actions. Authored events decide ordering and boundaries.

const ACTIONS := "res://src/resources/story/chapter_actions.json"
var last_error := ""
var _state: Node
var _game: MainGame
var _data: Dictionary = {}
var _refresh_pending := false
var _host := ""
var _scheduler: BusinessScheduler
var _procurement: Day2Procurement
var _hud: ChapterActionsHUD
var _hud_signature := ""
var _services_ready := false
var _recap: Control
var _recap_shown := false

func configure(game: MainGame) -> Error:
	_game = game
	_state = get_node("/root/GameState")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ACTIONS))
	if not data is Dictionary or data.get("version") != 1 or not data.get("actions") is Dictionary:
		return ERR_INVALID_DATA
	_data = data
	var level := game.get_active_level()
	_host = level.get_chapter_host() if level.has_method("get_chapter_host") else ("shop" if level is MilkTeaShop else "settlement")
	_procurement = Day2Procurement.new()
	add_child(_procurement)
	_procurement.configure(_state)
	_hud = game.get_game_menu()
	_hud.action_requested.connect(perform_user_action)
	_recap = preload("res://src/UI/hud/chapter_recap.tscn").instantiate()
	game.get_ui_manager().register_screen(ScreenIds.CHAPTER_RECAP, _recap, &"popup", true)
	_recap.dismissed.connect(func() -> void:
		if _recap_shown:
			_state.set_flag("ui.two_day_recap_seen"))
	_state.state_changed.connect(_schedule_refresh)
	_game.get_tea_production().changed.connect(_schedule_refresh)
	_schedule_refresh()
	return OK

func execute(id: String) -> Dictionary:
	if not _data.actions.has(id):
		return {"ok": false, "message": "未知章节业务：" + id}
	var action: Dictionary = _data.actions[id]
	var error := ERR_INVALID_DATA
	match action.kind:
		"procurement_fund":
			error = _procurement.fund()
		"transaction":
			error = _state.commit_story_transaction(id, _counts(action.get("use_costs", {})), _counts(action.get("use_gains", {})), int(action.get("money", 0)), _counts(action.get("items", {})), action.get("flags", {}), action.get("variables", {}), _counts(action.get("item_costs", {})))
		"rest":
			var actors := _game.get_actor_director()
			var actor := actors.get_actor(StringName(action.actor))
			var marker := actors.get_position(StringName(action.actor_marker))
			var player_marker := actors.get_position(StringName(action.player_marker))
			if actor != null and marker != null and player_marker != null:
				actor.teleport_to(marker.global_position)
				_game.get_player().teleport_to(player_marker.global_position)
				error = OK
	return {"ok": error in [OK, ERR_ALREADY_EXISTS], "message": "业务已提交。" if error in [OK, ERR_ALREADY_EXISTS] else "业务未提交：" + error_string(error)}

func _counts(value: Dictionary) -> Dictionary:
	var result := {}
	for id: String in value:
		result[id] = int(value[id])
	return result

func _schedule_refresh() -> void:
	if not _refresh_pending:
		_refresh_pending = true
		_refresh.call_deferred()

func _refresh() -> void:
	_refresh_pending = false
	if not is_inside_tree():
		return
	if _state.current_day >= 2:
		if not _services_ready:
			_configure_day2()
		_procurement.refresh()
		if _state.current_day == 3 and _state.get_flag("day2.s03.festival_accepted") and not _state.get_flag("day3.festival.available"):
			_state.set_flag("day3.festival.available")
		if _host == "shop" and _state.current_day >= 3:
			for id: String in Day2Procurement.RUNNERS:
				var actor := _game.get_actor_director().get_actor(StringName(id))
				var marker := _game.get_actor_director().get_position(StringName(id))
				if actor != null and marker != null:
					actor.visible = _state.current_day == 3 and _procurement.get_status().get("status") == "funded"
					if actor.visible:
						actor.teleport_to(marker.global_position)
		for fact: Dictionary in _data.get("travel_facts", []):
			if _game.has_scene_arrival() and _host == fact.host and Day1Access.at_stage(_state, fact.stage) and not _state.get_flag(fact.flag):
				_state.set_flag(fact.flag)
		if not _state.get_flag("day2.s03.has_gathered"):
			for id: String in ["moss_green", "sugar_yam", "firefly_cap"]:
				if int(_state.get_variable("gather.total." + id, 0)) > 0:
					_state.set_flag("day2.s03.has_gathered")
		if is_instance_valid(_scheduler):
			for stage: Dictionary in _data.day2.business.stages:
				for group: Dictionary in stage.story_customers:
					var current := _scheduler.get_group(group.id)
					if current.is_empty():
						continue
					for fact: String in ["arrived", "served", "departed"]:
						var flag: String = "day2.business." + group.id + "." + fact
						var met: bool = (current.status == "waiting" if fact == "arrived" else (current.served if fact == "served" else current.status == "departed"))
						if met and not _state.get_flag(flag):
							_state.set_flag(flag)
	for fact: Dictionary in _data.get("inventory_facts", []):
		if _state.story_stage == fact.stage and not _state.get_flag(fact.flag) and _state.get_warehouse_inventory().get_stock(fact.item) > 0:
			_state.set_flag(fact.flag)
	_game.refresh_day1_access()
	var level := _game.get_active_level()
	if level.has_method("get_scene_exits"):
		for exit: SceneExit in level.get_scene_exits():
			if exit.interaction_id == &"guard_return":
				exit.visible = exit.are_conditions_met(_state)

func supply_human_ingredients() -> Dictionary:
	var items := {}
	for ingredient: IngredientDefinition in WarehouseInventory.CATALOG.ingredients:
		if ingredient.origin == "human" and ingredient.source_ids.size() == 1 and ingredient.source_ids[0].begins_with("C"):
			items[ingredient.id] = 1
	var error: Error = _state.commit_story_transaction("supply.human_%d" % Time.get_ticks_usec(), {}, {}, 0, items)
	return {"ok": error == OK, "message": "C01–C10各补充一整份（五次用量），0G。" if error == OK else "补给失败，库存保持不变。"}

func get_scheduler() -> BusinessScheduler:
	return _scheduler

func get_procurement() -> Day2Procurement:
	return _procurement

func is_save_boundary() -> bool:
	if is_instance_valid(_scheduler) and not _scheduler.get_progress().closed:
		for id: String in _data.day2.visits:
			var group := _scheduler.get_group(id)
			if group.get("status") in ["entering", "leaving"]:
				return false
	return true

func _configure_day2() -> void:
	var config: Dictionary = _data.day2
	var tavern := TavernPurchase.new()
	add_child(tavern)
	var offers := {}
	for id: String in config.tavern_offers:
		var offer: Dictionary = config.tavern_offers[id].duplicate(true)
		for key: String in ["price", "discounted_price", "stock"]:
			if offer.has(key):
				offer[key] = int(offer[key])
		offers[id] = offer
	if tavern.configure(_state.get_transactions(), offers) != OK:
		last_error = "酒馆商品与共享钱包配置不一致。"
		push_error(last_error)
		return
	_game.get_story_business().set_tavern(tavern)
	var casino := FixedStoryCasino.new()
	add_child(casino)
	var casino_config: Dictionary = config.casino.duplicate(true)
	casino_config.reward_items = _counts(casino_config.reward_items)
	if casino.configure(_state, _game.get_task_catalog(), casino_config) != OK:
		last_error = "两局赌场结算配置无效。"
		push_error(last_error)
		return
	_game.get_story_business().set_casino(casino)
	if _host == "shop":
		_scheduler = BusinessScheduler.new()
		add_child(_scheduler)
		_scheduler.set_departure_guard(_can_depart)
		var error := _scheduler.configure_session(config.business, _state, _game.get_task_delivery(), config.close_rule)
		if error != OK:
			last_error = "第二天客组营业配置无效：" + error_string(error)
			push_error(last_error)
			return
		_scheduler.changed.connect(_schedule_refresh)
		_game.get_story_business().set_business(_scheduler)
		for group: String in config.visits:
			if _state.current_day >= 3:
				continue
			var visit := CustomerVisit.new()
			add_child(visit)
			var members: Array[Dictionary] = []
			members.assign(config.visits[group])
			if visit.configure(_scheduler, _game.get_actor_director(), group, members) != OK:
				last_error = "第二天顾客路径缺少绑定：" + group
				push_error(last_error)
			visit.movement_failed.connect(func(id: String, reason: String) -> void:
				last_error = id + ": " + reason
				push_error(last_error))
	_game.get_task_delivery().set_order_availability(["day3_festival"], func(_id: String) -> bool: return _state.current_day == 3)
	_game.get_task_delivery().set_order_availability(["day2_taste"], _taste_available)
	_game.get_task_delivery().delivered.connect(_on_optional_delivered)
	_services_ready = true

func _taste_available(_id: String) -> bool:
	var actor := _game.get_actor_director().get_actor(&"day2_ordinary_c")
	return _host == "shop" and _state.current_day == 2 and is_instance_valid(_scheduler) and _scheduler.get_group("ordinary_c").get("status") == "waiting" and not _state.get_flag("day2.s02.closed") and actor != null and actor.visible

func _can_depart(group: String) -> bool:
	return group != "ordinary_c" or not _taste_pending()

func _taste_pending() -> bool:
	return _state.get_flag("task.day2_taste.accepted") and _state.get_task_result("day2.orders.taste").is_empty() and not _state.get_flag("delivery.day2_taste.completed")

func _on_optional_delivered(id: String) -> void:
	if id == "day2_taste":
		_scheduler.request_departure.call_deferred("ordinary_c")
		_game.get_shop_ui().show_feedback.call_deferred("试饮评价 · 奶香里带着辛辣，正合口味！配方已留在饮品图鉴。", true)

func _quiet(allow_menu := false) -> bool:
	var travel := _game.get_scene_travel()
	var ui := _game.get_ui_manager()
	var clear := not ui.has_modal() or (allow_menu and ui.get_top_screen_id() == ScreenIds.CHAPTER_ACTIONS)
	return not get_tree().paused and not _game.is_session_initializing() and clear and not _game.get_story_director().is_busy() and not _game.get_dialogue_manager().is_active() and (not is_instance_valid(travel) or not travel.is_busy())

func get_user_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if _state.current_day == 2 and _host == "settlement" and _near_point(&"day1_s03_yard"):
		var quote: Dictionary = _state.get_transactions().get_product_quote("market_insomnia_mushroom")
		if quote.get("ok", false):
			actions.append({"id": "signature_buy_mushroom", "text": "市场购买醒神菇 · %dG / 份（5次）" % int(quote.unit_price), "kind": "signature_buy_mushroom"})
	if _state.current_day == 2 and _host == "shop" and not _state.get_flag("signature.S06.rescued_in_time"):
		var patient := _game.get_actor_director().get_actor(&"fat_goblin")
		if patient != null and patient.visible and patient.global_position.distance_to(_game.get_player().global_position) <= 112.0:
			actions.append({"id": "signature_rescue", "text": "救治胖哥布林 · 醒神菇1次用量", "kind": "signature_rescue"})
	if _host == "shop" and _taste_pending():
		actions.append({"id": "cancel_taste", "text": "取消可选试饮", "kind": "cancel_taste"})
	for action: Dictionary in _data.get("user_actions", []):
		if action.host != _host or action.stage != _state.story_stage:
			continue
		if action.get("kind") in ["evening", "next_day"] and _state.current_day != 3:
			continue
		if action.get("kind") == "evening" and DayPhase.is_night(_state):
			continue
		if action.get("kind") == "next_day" and not DayPhase.is_night(_state):
			continue
		actions.append(action.duplicate(true))
	if _state.get_flag("features.hiring_available") and _host == "shop" and _state.current_day in [2, 3] and _procurement.get_status().get("status") == "funded":
		for id: String in Day2Procurement.RUNNERS:
			if id == "day2_ordinary_c" and _taste_pending():
				continue
			var actor := _game.get_actor_director().get_actor(StringName(id))
			if actor != null and actor.visible:
				actions.append({"id": "hire:" + id, "text": "雇佣 " + actor.display_name + " · 专款支付30G货款＋5G跑腿费", "kind": "hire", "actor": id})
	return actions

func _near_point(id: StringName) -> bool:
	var level := _game.get_active_level()
	if not level.has_method("get_interaction_points"):
		return false
	for point: InteractionPoint in level.get_interaction_points():
		if point.interaction_id == id:
			return point.global_position.distance_to(_game.get_player().global_position) <= 112.0
	return false

func perform_user_action(id: String) -> void:
	if not _quiet(true):
		return
	for action: Dictionary in get_user_actions():
		if action.id != id:
			continue
		_game.get_ui_manager().close_screen(ScreenIds.CHAPTER_ACTIONS)
		var error := ERR_UNAVAILABLE
		if action.has("trigger"):
			error = _game.get_story_director().request_interaction(action.trigger)
		else:
			match action.get("kind"):
				"signature_buy_mushroom":
					var result: Dictionary = _state.get_transactions().purchase("market_insomnia_mushroom", 1, "signature-market-%d" % Time.get_ticks_usec())
					error = OK if result.get("ok", false) else ERR_UNAVAILABLE
				"signature_rescue":
					error = _state.rescue_signature_patient()
				"cancel_taste":
					error = _state.settle_task_result("day2.orders.taste", "cancelled", "主动取消试饮")
					if error == OK and is_instance_valid(_scheduler):
						_scheduler.request_departure("ordinary_c")
				"close":
					error = close_business()
				"hire":
					error = _procurement.hire(action.actor)
				"evening":
					error = DayPhase.advance_to(_state, 3, "night")
				"next_day":
					error = DayPhase.advance_to(_state, 4, "day")
		_game.get_shop_ui().show_feedback("操作已完成。" if error == OK else "暂时无法完成，请先交付已接订单。", error == OK)
		_schedule_refresh()
		return

func close_business() -> Error:
	if not is_instance_valid(_scheduler):
		return ERR_UNCONFIGURED
	if _taste_pending():
		return ERR_UNAVAILABLE
	# Unaccepted optional orders never prevent closing; accepted ones must settle.
	for id: String in Day2Procurement.RUNNERS:
		if _state.get_flag("task." + id + ".accepted") and not _state.get_flag("delivery." + id + ".completed"):
			return ERR_UNAVAILABLE
	return _scheduler.request_close()

func get_gathering_notice() -> String:
	if not _state.get_flag("day2.s03.festival_accepted") or _state.get_flag("day3.festival.delivered") or _state.current_day not in [2, 3]:
		return ""
	var inventory: WarehouseInventory = _state.get_warehouse_inventory()
	var requirement := _game.get_task_delivery().get_requirement("day3_festival")
	var lines := PackedStringArray(["七日祭食材 · 可顺路采集"])
	for id: String in requirement:
		var owned: int = inventory.get_stock(id)
		var needed: int = requirement[id]
		lines.append("%s %d/%d · 缺%d" % [inventory.get_definition(id).display_name, owned, needed, maxi(0, needed - owned)])
	lines.append("已齐备，第三天到酒馆交付。" if inventory.has_materials(requirement) else "集市往商业街途中，寻找路边材料。")
	return "\n".join(lines)

func _process(_delta: float) -> void:
	if not is_instance_valid(_hud) or not is_instance_valid(_game.get_story_director()):
		return
	var actions := get_user_actions()
	if _host == "shop" and _state.story_stage == "day3.handoff" and _state.get_flag("day2.completed") and not _state.get_flag("ui.two_day_recap_seen") and not _recap_shown and _quiet():
		_recap.present(get_recap_text())
		_recap_shown = _game.get_ui_manager().open_screen(ScreenIds.CHAPTER_RECAP) == OK
	var notice := ""
	if _state.current_day in [2, 3]:
		var status := _procurement.get_status()
		if not status.is_empty() and status.status not in ["delivered", "expired"]:
			notice = "代购专款 %dG · %s" % [int(status.escrow), {"funded": "尚未雇人", "hired": "跑腿途中", "returned": "醒神菇已带回，请交给胖哥布林", "delivered": "已向胖哥布林交付", "expired": "已超时"}.get(status.status, "")]
	var gathering_notice := get_gathering_notice()
	if not gathering_notice.is_empty():
		notice += ("\n\n" if not notice.is_empty() else "") + gathering_notice
	var enabled := _quiet(true)
	var signature := JSON.stringify([actions, notice, enabled])
	if signature != _hud_signature:
		_hud_signature = signature
		_hud.show_actions(actions, notice, enabled)

func get_optional_summary() -> String:
	var lines := PackedStringArray()
	if _state.current_day in [2, 3]:
		var status := _procurement.get_status()
		if not status.is_empty() and status.status not in ["delivered", "expired"]:
			lines.append("代购 · " + {"funded": "可雇人", "hired": "跑腿途中", "returned": "待交付"}.get(status.status, ""))
	if not get_gathering_notice().is_empty():
		var requirement := _game.get_task_delivery().get_requirement("day3_festival")
		var ready: bool = _state.get_warehouse_inventory().has_materials(requirement)
		lines.append("七日祭 · " + ("已齐备，第三天交付" if ready else "材料待采集"))
	return "\n".join(lines)

func get_recap_text() -> String:
	var orders := 0
	for task: Dictionary in _game.get_task_catalog().get_tasks():
		var delivery: Dictionary = task.get("delivery", {})
		var id: String = delivery.get("order_id", "")
		if (id.begins_with("day1") or id.begins_with("day2")) and (delivery.has("product_id") or delivery.has("drink")) and _state.get_flag("delivery." + id + ".completed"):
			orders += 1
	var recipes: int = _state.get_warehouse_inventory().get_drinks(true).size()
	var records: Dictionary = _state.get_variable("characters.entries", {})
	var discoveries := PackedStringArray()
	for fact: Array in [["day1.s05.document_read", "取得文书"], ["day1.s05.blood_acquired", "取得血液"], ["day2.s05.special_drink_delivered", "完成守卫招待"]]:
		if _state.get_flag(fact[0]):
			discoveries.append(fact[1])
	return "营业成果\n交付 %d 张饮品订单 · 当前余额 %s\n\n探索与发现\n记录了 %d 种自创饮品 · %d 位人物\n%s\n\n未解之谜\n黄金乡、变量，以及格里芬之血的秘密……" % [orders, WalletTransactions.format_money(_state.get_transactions().get_balance()), recipes, records.size(), " · ".join(discoveries)]
