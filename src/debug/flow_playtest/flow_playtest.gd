extends Node
## F6 composition only. No MainGame, map, story loader or autoload state writes.

const Fixture = preload("res://src/debug/flow_playtest/flow_fixture.gd")
const Session = preload("res://src/debug/flow_playtest/flow_session.gd")
const FlowPanel = preload("res://src/debug/flow_playtest/flow_panel.gd")

var session: Session
var panel: FlowPanel
var shop_ui: ShopUI
var ui: UIManager
var actors: ActorDirector
var _systems: Node
var _entity_root: Node2D
var _points: Dictionary = {}

func _ready() -> void:
	if not OS.has_feature("debug"):
		queue_free()
		return
	_systems = Node.new()
	_systems.name = "Systems"
	add_child(_systems)
	var world := Node2D.new()
	world.name = "World"
	add_child(world)
	_entity_root = Node2D.new()
	_entity_root.name = "EntityRoot"
	world.add_child(_entity_root)
	actors = ActorDirector.new()
	_systems.add_child(actors)
	actors.configure(_entity_root)
	var layers := {}
	for entry: Array in [["hud", 10], ["popup", 20], ["pause", 30], ["transition", 40], ["debug", 50]]:
		var layer := CanvasLayer.new()
		layer.name = String(entry[0]).capitalize() + "Layer"
		layer.layer = entry[1]
		layer.process_mode = Node.PROCESS_MODE_WHEN_PAUSED if entry[0] == "pause" else Node.PROCESS_MODE_ALWAYS
		add_child(layer)
		layers[entry[0]] = layer
	# Actor visuals sit above the panel background, below real modal screens.
	var actor_layer := CanvasLayer.new()
	actor_layer.layer = 15
	add_child(actor_layer)
	_entity_root.reparent(actor_layer)
	ui = UIManager.new()
	_systems.add_child(ui)
	ui.configure(layers)
	session = Session.new()
	_systems.add_child(session)
	session.configure(_arrive, _depart)
	shop_ui = preload("res://src/UI/milk_tea/shop_ui.tscn").instantiate()
	shop_ui.show_help = false
	layers.hud.add_child(shop_ui)
	shop_ui.set_popup_layer(layers.popup)
	shop_ui.configure_inventory(session.state.get_warehouse_inventory())
	shop_ui.configure_production(session.state.get_tea_production())
	shop_ui.configure_orders(session.orders)
	shop_ui.bind_manager(ui)
	shop_ui.accept_requested.connect(session.accept_order)
	shop_ui.track_requested.connect(func(id: String) -> void: session.state.set_variable(OrderBoardModel.TRACKED_KEY, id))
	shop_ui.craft_requested.connect(func(materials: Array[String], quantity: int) -> void: shop_ui.show_production_result(session.craft(materials, quantity)))
	shop_ui.formula_requested.connect(func(_materials: Array[String], _iced: bool) -> void:
		shop_ui.show_formula_result({"ok": false, "message": "本试玩请切回「按订单制作」，完成测试订单。"}))
	# These are presentation descriptors, not extra proximity/detection areas.
	for id: String in ["orders", "tea_station", "storage"]:
		var point := InteractionPoint.new()
		point.interaction_id = StringName(id)
		point.display_name = {"orders": "【测试订单板】", "tea_station": "【真实制作台 · 测试订单】", "storage": "【测试会话仓库】"}[id]
		_points[id] = point
	panel = FlowPanel.new()
	# The nonmodal dashboard is below popup layer 20 so it cannot cover modals.
	layers.hud.add_child(panel)
	panel.action_requested.connect(_request)
	session.changed.connect(_refresh)
	ui.modal_changed.connect(_refresh)
	_refresh()

func _request(action: String) -> void:
	if ui.has_modal():
		return
	match action:
		"start": session.start_business()
		"orders": shop_ui.open(_points.orders)
		"make": shop_ui.open(_points.tea_station)
		"storage": shop_ui.open(_points.storage)
		"deliver": session.submit_delivery()
		"close": session.close_business()
		"buy": session.purchase()
		"one": session.settle_round(1)
		"two": session.settle_round(2)
		"debt": session.waive_debt()
		"restart": get_tree().reload_current_scene()

func _refresh() -> void:
	panel.refresh(session, ui.has_modal())

func _arrive() -> bool:
	var spawn := await actors.actor_spawn(StringName(Fixture.CUSTOMER), Fixture.CUSTOMER_SCENE, Fixture.DOOR).wait()
	if not spawn.succeeded:
		return false
	actors.get_actor(StringName(Fixture.CUSTOMER)).scale = Fixture.CUSTOMER_SCALE
	var move := await actors.actor_move(StringName(Fixture.CUSTOMER), Fixture.COUNTER, Fixture.MOVE_SPEED).wait()
	return move.succeeded

func _depart() -> bool:
	var move := await actors.actor_move(StringName(Fixture.CUSTOMER), Fixture.DOOR, Fixture.MOVE_SPEED).wait()
	if not move.succeeded:
		return false
	var hide := await actors.actor_hide(StringName(Fixture.CUSTOMER)).wait()
	return hide.succeeded

func _exit_tree() -> void:
	if is_instance_valid(actors):
		actors.cancel_all("Test host exited")
	for point: InteractionPoint in _points.values():
		point.free()
