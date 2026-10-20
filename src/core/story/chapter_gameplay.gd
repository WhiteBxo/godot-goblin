class_name ChapterGameplay
extends Node
## Scene-local business actions. Authored events decide ordering and boundaries.

## 结算页的分节标题；界面据此上色，文案里不再重复一份。
const RECAP_SECTIONS := ["营业成果", "探索与发现", "未解之谜", "待续"]

const ACTIONS := "res://src/resources/story/chapter_actions.json"
## Optional commissions served beside a group's planned order. They stay outside
## the business plan, so the story beat still turns on the planned drink; while one
## is accepted its host group waits instead of leaving, which is what makes a
## greedy experiment safe to accept.
const OPTIONAL_ORDERS := {
	"day2_taste": {"task": "day2.orders.taste", "group": "ordinary_c", "actor": &"day2_ordinary_c",
		"feedback": "试饮评价 · 奶香里带着辛辣，正合口味！配方已留在饮品图鉴。"},
	"day2_special_sour": {"task": "day2.orders.special_sour", "group": "festival", "actor": &"day2_festival_1",
		"feedback": "围观者甲吮了一口就皱眉又笑：这酸味够劲。售价已按确认配方结算。"},
	"day2_special_herbal": {"task": "day2.orders.special_herbal", "group": "elder", "actor": &"day2_elder_1",
		"feedback": "草木味在舌根停了一会儿，顾客乙点头收下。售价已按确认配方结算。"},
	"day2_special_wine": {"task": "day2.orders.special_wine", "group": "emissary", "actor": &"day2_emissary_0",
		"feedback": "使者闻了闻杯口：这才像招待。售价已按确认配方结算。"},
	"day2_special_smoky": {"task": "day2.orders.special_smoky", "group": "rumor", "actor": &"day2_rumor_1",
		"feedback": "烟熏味让顾客乙眯起眼，说像火塘边的味道。售价已按确认配方结算。"},
	"day2_special_spicy": {"task": "day2.orders.special_spicy", "group": "ordinary_b", "actor": &"day2_ordinary_b",
		"feedback": "散客被辣得直吸气，还是把杯子推了回来要续。售价已按确认配方结算。"},
}
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
var _ending: Control
var _ending_shown := false
var _vendor_popup: MarketVendorPopup
var _vendor_actor: StringName

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
	_ending = preload("res://src/UI/hud/two_days_end.tscn").instantiate()
	game.get_ui_manager().register_screen(ScreenIds.TWO_DAYS_END, _ending, &"popup", true)
	_ending.finished.connect(_finish_two_days)
	_vendor_popup = preload("res://src/UI/trade/market_vendor_popup.tscn").instantiate()
	game.get_ui_manager().register_screen(ScreenIds.MARKET_VENDOR, _vendor_popup, &"popup", true)
	_vendor_popup.farewell_requested.connect(_play_vendor_farewell)
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
		"signature_discovery":
			var result: Dictionary = _state.discover_signature(action.signature_id)
			error = OK if result.get("ok", false) else ERR_UNAVAILABLE
		"transaction":
			error = _state.commit_story_transaction(id, _counts(action.get("use_costs", {})), _counts(action.get("use_gains", {})), int(action.get("money", 0)), _counts(action.get("items", {})), action.get("flags", {}), action.get("variables", {}), _counts(action.get("item_costs", {})))
			if error == OK:
				_announce_gains(action)
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

## Ingredients arrive in "uses", not portions, so a silent grant reads as a bug:
## the warehouse shows one partially consumed portion. Say the amount out loud.
func _announce_gains(action: Dictionary) -> void:
	var gains: Dictionary = _counts(action.get("use_gains", {}))
	if gains.is_empty():
		return
	var inventory = _state.get_warehouse_inventory()
	var parts := PackedStringArray()
	for id: String in gains:
		var definition = inventory.get_definition(id)
		parts.append("%s ×%d 次用量" % [definition.display_name if definition != null else id, int(gains[id])])
	var ui := _game.get_shop_ui()
	if is_instance_valid(ui) and ui.has_method("show_feedback"):
		ui.show_feedback("获得 " + "、".join(parts), true)

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
	var optional_ids: Array[String] = []
	optional_ids.assign(OPTIONAL_ORDERS.keys())
	_game.get_task_delivery().set_order_availability(optional_ids, _optional_available)
	_game.get_task_delivery().delivered.connect(_on_optional_delivered)
	_services_ready = true

## Optional slips only answer while their customer actually stands in the shop, so
## a customer who already left cannot leave a dead order on the board.
func _optional_available(order_id: String) -> bool:
	var info: Dictionary = OPTIONAL_ORDERS.get(order_id, {})
	if info.is_empty() or _host != "shop" or _state.current_day != 2 or _state.get_flag("day2.s02.closed"):
		return false
	var actor := _game.get_actor_director().get_actor(info.actor)
	return actor != null and actor.visible

func _can_depart(group: String) -> bool:
	for order_id: String in OPTIONAL_ORDERS:
		if OPTIONAL_ORDERS[order_id].group == group and _optional_pending(order_id):
			return false
	return true

func _optional_pending(order_id: String) -> bool:
	var info: Dictionary = OPTIONAL_ORDERS.get(order_id, {})
	return (not info.is_empty()
		and _state.get_flag("task.%s.accepted" % order_id)
		and _state.get_task_result(info.task).is_empty()
		and not _state.get_flag("delivery.%s.completed" % order_id))

func _taste_pending() -> bool:
	return _optional_pending("day2_taste")

func _on_optional_delivered(id: String) -> void:
	var info: Dictionary = OPTIONAL_ORDERS.get(id, {})
	if info.is_empty() or not is_instance_valid(_scheduler):
		return
	# Only releases a group that is otherwise served; the planned drink still owns
	# the story beat when it has not been delivered yet.
	_release_group(info.group)
	_game.get_shop_ui().show_feedback.call_deferred(info.feedback, true)

## An ordinary group has no authored beat, so its release happens here. A story
## group is released by its own *_after departure step instead: departing it now
## would make that step fail on a group that is already walking out.
func _release_group(group_id: String) -> void:
	if is_instance_valid(_scheduler) and _scheduler.get_group(group_id).get("kind") == "ordinary":
		_scheduler.request_departure.call_deferred(group_id)

func _quiet(allow_menu := false) -> bool:
	var travel := _game.get_scene_travel()
	var ui := _game.get_ui_manager()
	var clear := not ui.has_modal() or (allow_menu and ui.get_top_screen_id() == ScreenIds.CHAPTER_ACTIONS)
	return not get_tree().paused and not _game.is_session_initializing() and clear and not _game.get_story_director().is_busy() and not _game.get_dialogue_manager().is_active() and (not is_instance_valid(travel) or not travel.is_busy())

func get_user_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if _state.story_stage == "day1.s04.wait_taste" and _host == "shop":
		var inventory: WarehouseInventory = _state.get_warehouse_inventory()
		# The trial is mixed freely, so the shortfall is the missing ingredient,
		# not a missing finished cup.
		var mixed: bool = is_instance_valid(_game.get_task_delivery()) and _game.get_task_delivery().has_matching_drink("day1_s04_taste")
		if not mixed and not inventory.has_uses({"firefly_cap": 1, "goblin_firebrew": 1}):
			actions.append({"id": "taste_resupply", "text": "向胖哥布林补领缺少的试饮用料", "kind": "taste_resupply"})
	if _state.current_day in [2, 3] and _host == "settlement" and _near_point(&"day1_s03_yard") and _procurement.get_status().get("status") == "funded":
		actions.append({"id": "procurement_direct", "text": "用代购款买醒神菇 · 30G，剩下的5G算你的跑腿费", "kind": "procurement_direct"})
	elif _state.current_day == 2 and _host == "settlement" and _near_point(&"day1_s03_yard"):
		var quote: Dictionary = _state.get_transactions().get_product_quote("market_insomnia_mushroom")
		if quote.get("ok", false):
			actions.append({"id": "signature_buy_mushroom", "text": "市场购买醒神菇 · %dG / 份（5次）" % int(quote.unit_price), "kind": "signature_buy_mushroom"})
	if _state.current_day in [2, 3] and _host == "shop" and not _state.get_flag("signature.S06.rescued_in_time") and not _state.get_flag("day3.procurement.delivered"):
		var patient := _game.get_actor_director().get_actor(&"fat_goblin")
		if patient != null and patient.visible and patient.global_position.distance_to(_game.get_player().global_position) <= 112.0:
			actions.append({"id": "signature_rescue", "text": "救治胖哥布林 · 醒神菇1次用量", "kind": "signature_rescue"})
	if _host == "shop" and _taste_pending():
		actions.append({"id": "cancel_taste", "text": "取消可选试饮", "kind": "cancel_taste"})
		# 自由实验只能显示「缺货」时这单就没法做，关店也会被它挡住：
		# 和第一天一样给一次补领，别让可选订单变成死路。
		if not _has_spicy_uses():
			actions.append({"id": "taste_supply", "text": "向胖哥布林补领辛辣试饮用料 · 老火烧1份", "kind": "taste_supply"})
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
	if _host == "shop" and _state.current_day in [2, 3] and _procurement.get_status().get("status") == "funded":
		for id: String in Day2Procurement.RUNNERS:
			if id == "day2_ordinary_c" and _taste_pending():
				continue
			var actor := _game.get_actor_director().get_actor(StringName(id))
			if actor != null and actor.visible:
				actions.append({"id": "hire:" + id, "text": "临时委托 " + actor.display_name + " · 代购款付30G货款＋5G跑腿费", "kind": "hire", "actor": id})
	return actions

## 已发现、还有余量的哥布林辛辣原料。缺了它自由实验只能显示「缺货」。
func _has_spicy_uses() -> bool:
	var inventory: WarehouseInventory = _state.get_warehouse_inventory()
	for choice: Dictionary in inventory.get_formula_choices(false):
		var definition: IngredientDefinition = inventory.get_definition(choice.id)
		if definition == null or definition.origin != "otherworld":
			continue
		if "辛辣" in definition.recipe_flavors and inventory.get_uses(choice.id) > 0:
			return true
	return false

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
				"taste_resupply":
					var gains := {}
					for item: String in ["firefly_cap", "goblin_firebrew"]:
						if _state.get_warehouse_inventory().get_uses(item) == 0:
							gains[item] = 1
					error = _state.commit_story_transaction("day1.taste.resupply_%d" % Time.get_ticks_usec(), {}, gains)
				"taste_supply":
					error = _state.commit_story_transaction(
						"day2.taste.supply_%d" % Time.get_ticks_usec(), {}, {}, 0, {"goblin_firebrew": 1})
				"procurement_direct":
					error = _procurement.purchase_direct()
				"signature_buy_mushroom":
					error = _buy_market_product("market_insomnia_mushroom")
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
		_game.get_shop_ui().show_feedback(
			("操作已完成。" if error == OK else get_close_block_reason() if action.get("kind") == "close"
				else "暂时无法完成，请先交付已接订单。"), error == OK)
		_schedule_refresh()
		return

## Market stalls are a conversation, not a menu entry: talking to a vendor opens
## that vendor's goods. Day one is spent earning the commission, so the grocers
## wave the newcomer off until the second day.
func _vendor_config(actor_id: StringName) -> Dictionary:
	for vendor: Dictionary in _data.get("market_vendors", []):
		if String(vendor.get("actor", "")) == String(actor_id):
			return vendor
	return {}

func is_market_vendor(actor_id: StringName) -> bool:
	return not _vendor_config(actor_id).is_empty()

func get_vendor_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for vendor: Dictionary in _data.get("market_vendors", []):
		ids.append(StringName(vendor.get("actor", "")))
	return ids

func can_trade_with_vendors() -> bool:
	return _host == "settlement" and _state.current_day >= 2 and _state.get_flag("day1.s04.commission_accepted")

func open_market_vendor(actor_id: StringName) -> Error:
	if not is_market_vendor(actor_id):
		return ERR_DOES_NOT_EXIST
	if not can_trade_with_vendors():
		return ERR_UNAVAILABLE
	var error: Error = _game.get_ui_manager().open_screen(ScreenIds.MARKET_VENDOR)
	if error != OK:
		return error
	_vendor_actor = actor_id
	_vendor_popup.present(get_vendor_view(actor_id), buy_from_vendor,
		func() -> Dictionary: return get_vendor_view(_vendor_actor))
	return OK

## Only goods the shared wallet can quote are listed; each one carries the line
## that vendor says about that very item, so the goods come before the speech.
func get_vendor_view(actor_id: StringName) -> Dictionary:
	var vendor := _vendor_config(actor_id)
	var inventory: WarehouseInventory = _state.get_warehouse_inventory()
	var products: Array[Dictionary] = []
	for entry: Dictionary in vendor.get("products", []):
		var product := String(entry.get("id", ""))
		var quote: Dictionary = _state.get_transactions().get_product_quote(product)
		if not quote.get("ok", false):
			continue
		var definition := inventory.get_definition(quote.item_id)
		products.append({
			"id": product,
			"name": definition.display_name if definition != null else String(quote.item_id),
			"price": int(quote.unit_price),
			"portion": definition.uses_per_portion if definition != null else 1,
			"pitch": String(entry.get("pitch", "")),
		})
	return {
		"title": String(vendor.get("title", "摊主")),
		"hint": "点一件商品听摊主怎么说 · Enter 买下 · Esc 离开",
		"balance": _state.get_transactions().get_balance(),
		"products": products,
	}

## Settled from the stall's own button; the result is the sentence read there.
## A sale also carries what the keeper says once the coins change hands, so the
## stall can close and let the normal dialogue window take over.
func buy_from_vendor(product: String, quantity: int) -> Dictionary:
	var count: int = maxi(1, quantity)
	var quote: Dictionary = _state.get_transactions().get_product_quote(product)
	if not quote.get("ok", false):
		return {"ok": false, "message": "这件货今天没有。"}
	var cost := int(quote.unit_price) * count
	if _state.get_transactions().get_balance() < cost:
		return {"ok": false, "message": "金币不够：这些要 %dG。" % cost}
	if _buy_market_product(product, count) != OK:
		return {"ok": false, "message": "没能买成，金币还在你手里。"}
	var definition = _state.get_warehouse_inventory().get_definition(quote.item_id)
	return {"ok": true, "message": "买下 %s ×%d 份（%dG）。" % [
		definition.display_name if definition != null else String(quote.item_id), count, cost],
		"farewell": _vendor_farewell(product)}

## The pitch sells the good; this is the same keeper a beat later, so the two
## lines are authored side by side in the stall's own entry.
func _vendor_farewell(product: String) -> Array:
	for vendor: Dictionary in _data.get("market_vendors", []):
		if not _vendor_actor.is_empty() and String(vendor.get("actor", "")) != String(_vendor_actor):
			continue
		for entry: Dictionary in vendor.get("products", []):
			if String(entry.get("id", "")) != product:
				continue
			var deal := String(entry.get("deal", "")).strip_edges()
			if deal.is_empty():
				return []
			var lines: Array = [{"speaker": String(vendor.get("title", "摊主")), "text": deal}]
			var reply := String(vendor.get("reply", "")).strip_edges()
			if not reply.is_empty():
				lines.append({"speaker": "主角", "text": reply})
			return lines
	return []

## Sale done: the stall is already closed, so the keeper speaks through the same
## dialogue window every other NPC uses. One frame of distance keeps two modals
## from overlapping.
func _play_vendor_farewell(lines: Array) -> void:
	if lines.is_empty() or not is_inside_tree():
		return
	await get_tree().process_frame
	var manager := _game.get_dialogue_manager()
	if not is_instance_valid(manager):
		return
	var error := manager.start_lines(lines, "market_vendor.farewell.%d" % Time.get_ticks_usec())
	if error != OK:
		last_error = "摊主的成交台词没有播出来：%s" % error_string(error)

func _buy_market_product(product: String, quantity := 1) -> Error:
	if product == "market_insomnia_mushroom" and _state.current_day >= 2:
		var quote: Dictionary = _state.get_transactions().get_product_quote(product)
		if not quote.get("ok", false):
			return ERR_UNAVAILABLE
		return _state.commit_story_transaction("day2.procurement.personal_%d" % Time.get_ticks_usec(), {}, {}, -int(quote.unit_price) * quantity, {"insomnia_mushroom": quantity}, {"day2.procurement.purchased": true})
	var result: Dictionary = _state.get_transactions().purchase(product, quantity, "market-%d" % Time.get_ticks_usec())
	return OK if result.get("ok", false) else ERR_UNAVAILABLE

func close_business() -> Error:
	if not is_instance_valid(_scheduler):
		return ERR_UNCONFIGURED
	if _taste_pending():
		return ERR_UNAVAILABLE
	# Ordinary errands are judged by the scheduler alone: it already treats a
	# cancelled order as settled. A second accepted/completed check here ignored
	# that result and left a cancelled errand blocking the counter forever.
	return _scheduler.request_close()

## Why the counter cannot close, in the player's words. An optional job the
## player accepted but cannot finish must say so and point at the way out.
func get_close_block_reason() -> String:
	if not is_instance_valid(_scheduler):
		return "营业会话还没准备好。"
	for order_id: String in OPTIONAL_ORDERS:
		if _optional_pending(order_id):
			return "还有客人点的特调没有交付：做好再去关店，或在订单板放弃这一单。"
	var progress: Dictionary = _scheduler.get_progress()
	if not progress.get("close_ready", false):
		return "这一天的关店条件还没有配置齐全。"
	return "还有些客人没有交代完，先把他们招待好；做不出来的单可以在订单板放弃。"

## Accepted optional order given up from the order board. Releasing the waiting
## customer keeps the close path open instead of stranding the day.
func cancel_optional_order(order_id: String) -> Error:
	var entry: Dictionary = _game.get_order_board().get_entry(order_id)
	if entry.is_empty() or entry.get("status") != "active" or not bool(entry.get("allow_cancel", false)):
		return ERR_UNAVAILABLE
	var error := _game.get_task_delivery().cancel_order(order_id)
	if error == OK and OPTIONAL_ORDERS.has(order_id):
		# The group's guard is now clear; a story group leaves in its own beat.
		_release_group(OPTIONAL_ORDERS[order_id].group)
	return error

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
	# Anything saved at the handoff is a finished run: reopening it shows the
	# ending again instead of dropping the player into an empty third day.
	if _host == "shop" and _state.story_stage == "day3.handoff" and _state.get_flag("day2.completed") and _quiet():
		# The recap states the two days; the card behind it closes the build.
		if not _recap_shown:
			_recap.present(get_recap_text())
			_recap_shown = _game.get_ui_manager().open_screen(ScreenIds.CHAPTER_RECAP) == OK
		elif not _ending_shown:
			_open_two_days_end()
	var notice := ""
	if _state.current_day in [2, 3]:
		var status := _procurement.get_status()
		if not status.is_empty() and status.status not in ["delivered", "expired"]:
			notice = "胖哥布林的代购款 %dG · %s" % [int(status.escrow), {"funded": "尚未雇人", "hired": "跑腿途中", "returned": "醒神菇已带回，请交给胖哥布林", "delivered": "已向胖哥布林交付", "expired": "已超时"}.get(status.status, "")]
	var gathering_notice := get_gathering_notice()
	if not gathering_notice.is_empty():
		notice += ("\n\n" if not notice.is_empty() else "") + gathering_notice
	var slip_notice := get_slip_notice()
	if not slip_notice.is_empty():
		notice += ("\n\n" if not notice.is_empty() else "") + slip_notice
	var enabled := _quiet(true)
	var signature := JSON.stringify([actions, notice, enabled])
	if signature != _hud_signature:
		_hud_signature = signature
		_hud.show_actions(actions, notice, enabled)

## An accepted special slip keeps its group at the counter, so the next group never
## walks in until it is delivered or given up. Without a word that reads as a stuck
## day; name the hold and the way out.
func get_slip_notice() -> String:
	var waiting := PackedStringArray()
	for id: String in OPTIONAL_ORDERS:
		if _optional_pending(id):
			waiting.append(String(_game.get_order_board().get_entry(id).get("target_name", "客人")))
	if waiting.is_empty():
		return ""
	return "特殊订单待交付：%s · 交付或放弃后才会换下一组客人。" % "、".join(waiting)

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
	var discoveries := PackedStringArray()
	for fact: Array in [["day1.s05.document_read", "取得文书"], ["day1.s05.blood_acquired", "取得血液"], ["day2.s05.special_drink_delivered", "完成守卫招待"]]:
		if _state.get_flag(fact[0]):
			discoveries.append(fact[1])
	var text := "营业成果\n交付 %d 张饮品订单 · 当前余额 %s\n\n探索与发现\n记录了 %d 种自创饮品 · %d 位人物\n%s\n\n未解之谜\n黄金乡、变量，以及格里芬之血的秘密……" % [_delivered_orders(), WalletTransactions.format_money(_state.get_transactions().get_balance()), _discovered_recipes(), _character_records(), " · ".join(discoveries)]
	# Anything still open belongs to the third day, which this build does not
	# contain. Name it instead of letting the deadline judge it.
	var handoffs := _open_handoffs()
	if not handoffs.is_empty():
		text += "\n\n待续\n" + "\n".join(handoffs)
	return text


## Short form for the end card, which follows the recap and should not repeat it.
func get_ending_text() -> String:
	return "交付 %d 张饮品订单 · 结余 %s" % [_delivered_orders(), WalletTransactions.format_money(_state.get_transactions().get_balance())]


func _delivered_orders() -> int:
	var orders := 0
	for task: Dictionary in _game.get_task_catalog().get_tasks():
		var delivery: Dictionary = task.get("delivery", {})
		var id: String = delivery.get("order_id", "")
		if (id.begins_with("day1") or id.begins_with("day2")) and (delivery.has("product_id") or delivery.has("drink")) and _state.get_flag("delivery." + id + ".completed"):
			orders += 1
	return orders


func _discovered_recipes() -> int:
	return _state.get_warehouse_inventory().get_drinks(true).size()


func _character_records() -> int:
	var records: Dictionary = _state.get_variable("characters.entries", {})
	return records.size()


## Commissions whose deadline sits on the day this build stops at.
func _open_handoffs() -> PackedStringArray:
	var lines := PackedStringArray()
	if _state.get_flag("day2.s03.festival_accepted") and not _state.get_flag("day3.festival.delivered"):
		lines.append("七日祭的食材还没送到酒馆")
	if _state.get_flag("day2.casino.debt.active") and not _state.get_flag("day2.casino.debt.paid"):
		lines.append("赌场的十杯奶茶还没还")
	var status: String = _procurement.get_status().get("status", "")
	if status in ["funded", "hired", "returned"] and not _state.get_flag("day3.procurement.delivered"):
		lines.append("醒神菇还没交到胖哥布林手里")
	return lines


func _open_two_days_end() -> void:
	_ending.present(get_ending_text())
	if _game.get_ui_manager().open_screen(ScreenIds.TWO_DAYS_END) != OK:
		return
	_ending_shown = true
	# The end card owns the bed and the cue: no shop ambience under the music.
	var soundscape := _game.get_node_or_null("Systems/SceneSoundscape")
	if soundscape != null and soundscape.has_method("stop_ambience"):
		soundscape.stop_ambience(0.8)
	var audio := _game.get_audio_manager()
	if is_instance_valid(audio):
		audio.play_bgm("music.two_days_end", 1.0, -7.0)


func _finish_two_days() -> void:
	# Only a finished run is marked. Quitting on the card and reloading shows it
	# again, which is where that save actually stands.
	_state.set_flag("ui.two_days_end_seen")
	var audio := _game.get_audio_manager()
	if is_instance_valid(audio):
		audio.stop_bgm(1.0)
	GameEntry.return_to_title.call_deferred(get_tree())
