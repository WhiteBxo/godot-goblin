class_name MainGame
extends Node

@onready var _audio_manager: AudioManager = $Systems/AudioManager
@onready var _active_level: CaveMap = $World/LevelRoot.get_child(0) as CaveMap
@onready var _player: CavePlayer = $World/EntityRoot/Player as CavePlayer
var _shop_level: MilkTeaShop
var _settlement_level: SettlementMap
var _shop_player: ShopPlayer
var _ui_manager: UIManager
var _shop_ui: ShopUI
var _shop_interaction: ShopInteraction
var _task_journal: TaskJournal
var _task_panel: TaskPanel
var _task_button: Button
var _chronicle_journal: ChronicleJournal
var _chronicle_hud: ChronicleHUD
var _tea_production: TeaProduction
var _warehouse_inventory: WarehouseInventory
var _task_catalog: TaskCatalog
var _task_delivery: TaskDelivery
var _gathering_service: GatheringService
var _npc_points: Dictionary = {}
var _dialogue_manager: DialogueManager
var _story_director: StoryDirector
var _actor_director: ActorDirector
var _camera_director: CameraDirector
var _tea_making: TeaMaking
var _gameplay_bridge: GameplayBridge
var _scene_travel: SceneTravel
var _arrival_entrance: StringName
var _scene_exits: Dictionary[StringName, SceneExit] = {}
var _input_locked: bool = false
var _movement_before_dialogue: bool = true
var _interaction_before_dialogue: bool = true

var _debug_tools: DeveloperTools
var _demo_tools: CaveDemoController
var _debug_panel: DeveloperPanel

func _ready() -> void:
	DebugRuntime.apply_release_policy(get_tree())
	_create_ui_system()
	_create_chronicle_system()
	_create_task_system()
	_settlement_level = $World/LevelRoot.get_child(0) as SettlementMap
	if _settlement_level != null:
		_initialize_settlement()
		_create_debug_components()
		return
	_shop_level = $World/LevelRoot.get_child(0) as MilkTeaShop
	if _shop_level != null:
		_shop_player = $World/EntityRoot/Player as ShopPlayer
		_place_player(_shop_level)
		_shop_player.configure_camera(_shop_level.get_camera_bounds())
		_create_camera_system(_shop_player.camera)
		var ui: ShopUI = preload("res://src/UI/milk_tea/shop_ui.tscn").instantiate()
		$HudLayer.add_child(ui)
		ui.set_popup_layer($PopupLayer)
		_create_shop_business(ui)
		ui.bind_manager(_ui_manager)
		var interaction := ShopInteraction.new()
		interaction.name = "ShopInteraction"
		$Systems.add_child(interaction)
		var points := _with_npc_points(_shop_level.get_interaction_points())
		points.append_array(_shop_level.get_scene_exits())
		interaction.configure(_shop_player, ui, points, _route_story_interaction)
		_shop_ui = ui
		_shop_interaction = interaction
		var feedback := InteractionFeedback.new()
		feedback.name = "InteractionFeedback"
		$World/EffectRoot.add_child(feedback)
		feedback.configure(interaction, _audio_manager)
		_create_dialogue_system()
		_create_gameplay_bridge()
		_create_scene_travel(_shop_level.get_scene_exits())
		_create_debug_components()
		return
	var error := _active_level.load_error
	if DebugRuntime.is_enabled():
		_create_cave_debug_components()
		error = _demo_tools.apply_layout_override()
	if error != OK:
		push_error("Could not initialize MainGame level (error %d)" % error)
		get_tree().quit(1)
		return
	_player.configure(_active_level.can_stand_at)
	_player.global_position = _active_level.get_spawn_position()
	_player.follow_player()
	_create_dialogue_system()
	_create_debug_components()
	if _demo_tools != null:
		_demo_tools.capture_started.connect(_debug_tools.close_panel)
		_demo_tools.start()

func get_ui_manager() -> UIManager:
	return _ui_manager if is_instance_valid(_ui_manager) else null

func _create_ui_system() -> void:
	_ui_manager = UIManager.new()
	_ui_manager.name = "UIManager"
	$Systems.add_child(_ui_manager)
	_ui_manager.configure({&"hud": $HudLayer, &"popup": $PopupLayer, &"pause": $PauseLayer, &"debug": $DebugLayer})
	var pause: PauseMenu = preload("res://src/UI/pause/pause_menu.tscn").instantiate()
	$PauseLayer.add_child(pause)
	_ui_manager.register_screen(&"pause", pause, &"pause", true)
	pause.resume_requested.connect(func() -> void: _ui_manager.set_paused(false))
	pause.title_requested.connect(_return_to_title.bind(pause), CONNECT_DEFERRED)
	_ui_manager.modal_changed.connect(_refresh_input_lock)

func _return_to_title(pause: PauseMenu) -> void:
	var error := ERR_BUSY if is_instance_valid(_scene_travel) and _scene_travel.is_busy() else GameEntry.return_to_title(get_tree())
	if error != OK and is_instance_valid(pause):
		pause.show_navigation_error(error)

func get_task_journal() -> TaskJournal:
	return _task_journal if is_instance_valid(_task_journal) else null

func get_chronicle_journal() -> ChronicleJournal:
	return _chronicle_journal if is_instance_valid(_chronicle_journal) else null

func open_chronicle() -> Error:
	if _ui_manager.is_open(&"chronicle"):
		return OK
	if not _can_start_story() or (is_instance_valid(_story_director) and _story_director.is_busy()) or (is_instance_valid(_actor_director) and _actor_director.is_actor_controlled(&"player")):
		return ERR_BUSY
	return _ui_manager.open_screen(&"chronicle")

func open_tasks() -> Error:
	if _ui_manager.is_open(&"tasks"):
		return OK
	if not _can_start_story() or (is_instance_valid(_story_director) and _story_director.is_busy()) or (is_instance_valid(_actor_director) and _actor_director.is_actor_controlled(&"player")):
		return ERR_BUSY
	_refresh_task_delivery_names()
	return _ui_manager.open_screen(&"tasks")

func _refresh_task_delivery_names() -> void:
	var target_names := {}
	for point: InteractionPoint in _npc_points.values():
		target_names[String(point.interaction_id)] = point.display_name
	var product_names := {}
	var inventory: WarehouseInventory = get_node("/root/GameState").get_warehouse_inventory()
	for task: Dictionary in _task_journal.get_active_tasks():
		if not task.delivery.is_empty():
			var product := inventory.get_definition(task.delivery.product_id)
			if product != null:
				product_names[task.delivery.product_id] = product.display_name
	_task_panel.set_delivery_names(target_names, product_names)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"open_tasks") and not event.is_echo():
		open_tasks()
		get_viewport().set_input_as_handled()

func _create_chronicle_system() -> void:
	_chronicle_journal = ChronicleJournal.new()
	_chronicle_journal.name = "ChronicleJournal"
	$Systems.add_child(_chronicle_journal)
	_chronicle_journal.configure(get_node("/root/GameState"))
	var panel: ChroniclePanel = preload("res://src/UI/chronicle/chronicle_panel.tscn").instantiate()
	_ui_manager.register_screen(&"chronicle", panel, &"popup", true)
	panel.bind_journal(_chronicle_journal)
	panel.close_requested.connect(func() -> void: _ui_manager.close_screen(&"chronicle"))
	_chronicle_hud = preload("res://src/UI/chronicle/chronicle_hud.tscn").instantiate()
	_ui_manager.register_screen(&"chronicle_hud", _chronicle_hud, &"hud", false)
	_chronicle_hud.bind_journal(_chronicle_journal)
	_chronicle_hud.pressed.connect(open_chronicle)
	_ui_manager.open_screen(&"chronicle_hud")

func _create_task_system() -> void:
	_task_catalog = TaskCatalog.new()
	var catalog := _task_catalog
	var error := catalog.load_file("res://src/resources/tasks/tasks.json")
	if error != OK:
		push_error("Could not load tasks: " + catalog.last_error)
		return
	_task_journal = TaskJournal.new()
	_task_journal.name = "TaskJournal"
	$Systems.add_child(_task_journal)
	_task_journal.configure(catalog, get_node("/root/GameState"))
	var hud: TaskHUD = preload("res://src/UI/tasks/task_hud.tscn").instantiate()
	$HudLayer.add_child(hud)
	hud.bind_journal(_task_journal)
	_task_panel = preload("res://src/UI/tasks/task_panel.tscn").instantiate()
	_ui_manager.register_screen(&"tasks", _task_panel, &"popup", true)
	_task_panel.bind_journal(_task_journal)
	_task_journal.projection_changed.connect(_refresh_task_delivery_names)
	_task_panel.close_requested.connect(func() -> void: _ui_manager.close_screen(&"tasks"))
	_task_button = preload("res://src/UI/tasks/task_button.tscn").instantiate()
	_ui_manager.register_screen(&"task_button", _task_button, &"hud", false)
	_task_button.pressed.connect(open_tasks)
	_ui_manager.open_screen(&"task_button")

func get_active_level() -> Node2D:
	if _settlement_level != null:
		return _settlement_level
	return _shop_level if _shop_level != null else _active_level

## Called on a detached, instantiated destination, before the source is removed.
func prepare_scene_arrival(id: StringName) -> Error:
	if is_inside_tree() or id == &"":
		return ERR_INVALID_PARAMETER
	var level := get_node_or_null("World/LevelRoot")
	var player := get_node_or_null("World/EntityRoot/Player") as ShopPlayer
	if level == null or level.get_child_count() != 1 or player == null:
		return ERR_UNCONFIGURED
	var map := level.get_child(0)
	if not map is MilkTeaShop and not map is SettlementMap:
		return ERR_UNCONFIGURED
	if map.get_scene_entrance(id) == null:
		return ERR_DOES_NOT_EXIST
	_arrival_entrance = id
	return OK

func _place_player(level: Node2D) -> void:
	if _arrival_entrance != &"":
		var entrance: SceneEntrance = level.get_scene_entrance(_arrival_entrance)
		entrance.place_player(_shop_player)
	else:
		_shop_player.teleport_to(level.get_spawn_position())

func get_scene_travel() -> SceneTravel:
	return _scene_travel

func _create_scene_travel(exits: Array[SceneExit]) -> void:
	for point in exits:
		_scene_exits[point.interaction_id] = point
	var visual: ScreenTransition = preload("res://src/UI/screen_transition/screen_transition.tscn").instantiate()
	$TransitionLayer.add_child(visual)
	_scene_travel = SceneTravel.new()
	_scene_travel.name = "SceneTravel"
	$Systems.add_child(_scene_travel)
	_scene_travel.configure(visual, _can_leave_scene)
	_scene_travel.busy_changed.connect(_refresh_input_lock)
	_scene_travel.travel_failed.connect(_on_scene_travel_failed)
	if _arrival_entrance != &"":
		_scene_travel.begin_arrival()

func _can_leave_scene() -> bool:
	var owns_lock := is_instance_valid(_scene_travel) and _scene_travel.is_busy()
	var movement_available := _movement_before_dialogue if owns_lock else _shop_player.movement_enabled
	return (not get_tree().paused and not _ui_manager.has_modal() and movement_available
		and not _shop_player.is_performance_controlled()
		and not _story_director.is_busy() and not _dialogue_manager.is_active()
		and _gameplay_bridge.allows_story_start())

func _on_scene_travel_failed(point: SceneExit, _error: Error) -> void:
	if get_tree().paused or _ui_manager.has_modal():
		return
	_shop_ui.open(point)
	_shop_ui.show_interaction_result("暂时无法通过这扇门，请重试。")

func _initialize_settlement() -> void:
	_shop_player = $World/EntityRoot/Player as ShopPlayer
	_place_player(_settlement_level)
	_shop_player.configure_camera(_settlement_level.get_camera_bounds())
	_create_camera_system(_shop_player.camera)
	_shop_ui = preload("res://src/UI/milk_tea/shop_ui.tscn").instantiate()
	_shop_ui.help_text = "洞窟聚落                  WASD 移动 · E 交互 · Esc / P 暂停"
	_shop_ui.show_help = not DebugRuntime.is_enabled()
	_shop_ui.close_text = "继续探索  [Esc]"
	$HudLayer.add_child(_shop_ui)
	_shop_ui.set_popup_layer($PopupLayer)
	_create_shop_business(_shop_ui)
	var gather_points := _settlement_level.get_gather_points()
	_create_gathering(gather_points)
	_shop_ui.bind_manager(_ui_manager)
	var points := _with_npc_points(_settlement_level.get_interaction_points())
	points.append_array(_settlement_level.get_scene_exits())
	for point: GatherPoint in gather_points:
		points.append(point)
	_shop_interaction = ShopInteraction.new()
	_shop_interaction.name = "SettlementInteraction"
	$Systems.add_child(_shop_interaction)
	_shop_interaction.configure(_shop_player, _shop_ui, points, _route_story_interaction)
	_create_dialogue_system()
	_create_gameplay_bridge(false)
	_create_scene_travel(_settlement_level.get_scene_exits())
	if DebugRuntime.is_enabled():
		var preview := Node.new()
		preview.name = "SettlementPreview"
		preview.set_script(load("res://src/debug/settlement/settlement_preview.gd"))
		preview.call("configure", self, $DebugLayer)
		$Systems.add_child(preview)

func get_tea_production() -> TeaProduction:
	return _tea_production

func get_transactions() -> WalletTransactions:
	return get_node("/root/GameState").get_transactions()

func get_warehouse_inventory() -> WarehouseInventory:
	return _warehouse_inventory

func _create_shop_business(ui: ShopUI) -> void:
	var state := get_node("/root/GameState")
	get_transactions().set_task_lookup(_task_journal.get_task)
	_warehouse_inventory = state.get_warehouse_inventory()
	_tea_production = state.get_tea_production()
	_task_delivery = TaskDelivery.new()
	_task_delivery.name = "TaskDelivery"
	$Systems.add_child(_task_delivery)
	var error := _task_delivery.configure(_task_catalog, _task_journal, get_node("/root/GameState"), _warehouse_inventory)
	if error != OK:
		push_error("Could not configure task delivery (%d)" % error)
	_task_journal.projection_changed.connect(_refresh_order_requirements.bind(ui))
	ui.point_opened.connect(_on_shop_point_opened)
	ui.configure_inventory(_warehouse_inventory)
	ui.configure_production(_tea_production)
	ui.make_requested.connect(func(recipe: Array[String], order_id: String) -> void:
		ui.show_production_result(_tea_production.make_drink(recipe, order_id)))

func get_player() -> CharacterBody2D:
	return _shop_player if is_instance_valid(_shop_player) else (_player if is_instance_valid(_player) else null)

func get_dialogue_manager() -> DialogueManager:
	return _dialogue_manager

func get_interaction_ui() -> ShopUI:
	return _shop_ui

func get_audio_manager() -> AudioManager:
	return _audio_manager

func get_camera_director() -> CameraDirector:
	return _camera_director if is_instance_valid(_camera_director) else null

func _create_camera_system(camera: BoundedFollowCamera) -> void:
	_camera_director = CameraDirector.new()
	_camera_director.name = "CameraDirector"
	$Systems.add_child(_camera_director)
	_camera_director.configure(camera)

func get_story_director() -> StoryDirector:
	return _story_director if is_instance_valid(_story_director) else null

func get_actor_director() -> ActorDirector:
	return _actor_director if is_instance_valid(_actor_director) else null

func get_task_delivery() -> TaskDelivery:
	return _task_delivery

func get_gathering_service() -> GatheringService:
	return _gathering_service if is_instance_valid(_gathering_service) else null

func _create_gathering(points: Array[GatherPoint]) -> void:
	if points.is_empty():
		return
	_gathering_service = GatheringService.new()
	_gathering_service.name = "GatheringService"
	$Systems.add_child(_gathering_service)
	var error := _gathering_service.configure(get_node("/root/GameState"), _warehouse_inventory, points)
	if error != OK:
		push_error("Could not configure gathering (%d)" % error)

func _with_npc_points(points: Array[InteractionPoint]) -> Array[InteractionPoint]:
	for entity in $World/EntityRoot.get_children():
		if not entity is SettlementCharacter:
			continue
		var point: InteractionPoint = preload("res://src/gameplay/interaction/interaction_point.tscn").instantiate()
		point.name = "InteractionPoint"
		point.interaction_id = entity.actor_id
		point.display_name = entity.display_name
		point.description = entity.story_role
		entity.add_child(point)
		points.append(point)
		_npc_points[point.interaction_id] = point
	return points

func _route_story_interaction(id: StringName) -> Error:
	# Existing story routes retain priority; gathering and delivery are gameplay fallbacks.
	if is_instance_valid(_story_director):
		var error := _story_director.request_interaction(String(id))
		if error != ERR_DOES_NOT_EXIST:
			return error
	if _scene_exits.has(id):
		return _scene_travel.request_exit(_scene_exits[id])
	if is_instance_valid(_gathering_service) and _gathering_service.has_point(id):
		var point := _gathering_service.get_point(id)
		var result := _gathering_service.harvest(id)
		if is_instance_valid(point):
			_shop_ui.open(point)
			_shop_ui.show_interaction_result(result.message)
		return OK if result.ok else ERR_UNAVAILABLE
	if _npc_points.has(id) and is_instance_valid(_task_delivery):
		var delivery_result := _task_delivery.deliver_to(String(id))
		_shop_ui.open(_npc_points[id])
		_shop_ui.show_interaction_result(delivery_result.message)
		return OK if delivery_result.ok else ERR_UNAVAILABLE
	return ERR_DOES_NOT_EXIST

func _create_dialogue_system() -> void:
	_actor_director = ActorDirector.new()
	_actor_director.name = "ActorDirector"
	$Systems.add_child(_actor_director)
	_actor_director.configure($World/EntityRoot)
	_actor_director.actor_register(&"player", get_player() as PlayerController)
	for entity in $World/EntityRoot.get_children():
		if entity is SettlementCharacter:
			_actor_director.actor_register(entity.actor_id, entity)
	_actor_director.actor_control_changed.connect(_on_actor_control_changed)
	var ui: DialogueUI = preload("res://src/UI/dialogue/dialogue_ui.tscn").instantiate()
	$PopupLayer.add_child(ui)
	_ui_manager.register_screen(&"dialogue", ui, &"popup", true)
	_dialogue_manager = DialogueManager.new()
	_dialogue_manager.name = "DialogueManager"
	$Systems.add_child(_dialogue_manager)
	_dialogue_manager.configure(ui, _can_start_dialogue)
	_dialogue_manager.dialogue_started.connect(_on_dialogue_started)
	_dialogue_manager.dialogue_ended.connect(_on_dialogue_ended)
	_story_director = StoryDirector.new()
	_story_director.name = "StoryDirector"
	$Systems.add_child(_story_director)
	_story_director.configure(_dialogue_manager, _can_start_story)
	_story_director.set_chronicle_journal(_chronicle_journal)
	_story_director.configure_cinematic(_actor_director, _camera_director)
	_story_director.tree_exiting.connect(_on_story_exiting)
	_story_director.set_audio_adapter(StoryAudioAdapter.new(_audio_manager))
	_story_director.event_started.connect(func(_id: String) -> void: _refresh_input_lock())
	_story_director.event_finished.connect(_on_story_finished)

func _on_story_finished(_id: String, _ok: bool, _reason: String) -> void:
	if is_instance_valid(_camera_director):
		_camera_director.cancel_all("Story finished")
	_refresh_input_lock()

func _on_story_exiting() -> void:
	if is_instance_valid(_camera_director):
		_camera_director.cancel_all("StoryDirector exited")

func get_gameplay_bridge() -> GameplayBridge:
	return _gameplay_bridge

func get_tea_making() -> TeaMaking:
	return _tea_making

func get_shop_ui() -> ShopUI:
	return _shop_ui

func _create_gameplay_bridge(with_tea: bool = true) -> void:
	if with_tea:
		_create_tea_making()
	_gameplay_bridge = GameplayBridge.new()
	_gameplay_bridge.name = "GameplayBridge"
	$Systems.add_child(_gameplay_bridge)
	_gameplay_bridge.configure(_story_director, _ui_manager, _tea_making)

func _create_tea_making() -> void:
	_tea_making = TeaMaking.new()
	_tea_making.name = "TeaMaking"
	$Systems.add_child(_tea_making)
	_shop_ui.bind_tea_making(_tea_making)

func _on_shop_point_opened(id: StringName) -> void:
	if id == &"orders":
		get_node("/root/GameState").set_flag("shop.orders_viewed")
		for order: Dictionary in _task_delivery.get_orders():
			_task_delivery.accept_order(order.order_id)
		_refresh_order_requirements(_shop_ui)

func _refresh_order_requirements(ui: ShopUI) -> void:
	var names := {}
	for point: InteractionPoint in _npc_points.values():
		names[String(point.interaction_id)] = point.display_name
	var requirements := _task_delivery.get_requirements_text(names)
	ui.show_order_requirements("已接取订单：\n" + requirements + "\n准备所需成品或物资，携带到指定 NPC 按 E 交付。" if not requirements.is_empty() else "当前没有待交付订单。")

func _can_start_story() -> bool:
	return (not get_tree().paused and not _ui_manager.has_modal()
		and (not is_instance_valid(_scene_travel) or not _scene_travel.is_busy())
		and (not is_instance_valid(_gameplay_bridge) or _gameplay_bridge.allows_story_start()))

func _can_start_dialogue() -> bool:
	return _can_start_story() and (not is_instance_valid(_story_director) or not _story_director.is_busy() or _story_director.is_starting_dialogue())

func _on_dialogue_started(_id: String) -> void:
	_refresh_input_lock()

func _on_dialogue_ended(_id: String, _cancelled: bool) -> void:
	_refresh_input_lock()

func _on_actor_control_changed(actor_id: StringName, _controlled: bool) -> void:
	if actor_id == &"player":
		_refresh_input_lock()

func _refresh_input_lock() -> void:
	var should_lock := (
		(is_instance_valid(_scene_travel) and _scene_travel.is_busy())
		or (is_instance_valid(_ui_manager) and _ui_manager.has_modal())
		or (is_instance_valid(_dialogue_manager) and _dialogue_manager.is_active())
		or (is_instance_valid(_story_director) and _story_director.is_busy())
		or (is_instance_valid(_actor_director) and _actor_director.is_actor_controlled(&"player"))
	)
	if is_instance_valid(_chronicle_hud):
		_chronicle_hud.disabled = should_lock
	if is_instance_valid(_task_button):
		_task_button.disabled = should_lock
	if should_lock == _input_locked:
		return
	var player := get_player() as PlayerController
	if should_lock:
		if is_instance_valid(player):
			_movement_before_dialogue = player.movement_enabled
			player.set_movement_enabled(false)
		if is_instance_valid(_shop_interaction):
			_interaction_before_dialogue = _shop_interaction.is_input_enabled()
			_shop_interaction.set_input_enabled(false)
	else:
		if is_instance_valid(player):
			player.set_movement_enabled(_movement_before_dialogue)
		if is_instance_valid(_shop_interaction):
			_shop_interaction.set_input_enabled(_interaction_before_dialogue)
	_input_locked = should_lock

func get_debug_tools() -> DeveloperTools:
	return _debug_tools

func get_demo_tools() -> CaveDemoController:
	return _demo_tools

func _create_debug_components() -> void:
	if not DebugRuntime.is_enabled():
		return
	var player := get_player() as PlayerController
	_debug_panel = load("res://src/debug/developer_tools/developer_panel.tscn").instantiate()
	$DebugLayer.add_child(_debug_panel)
	_debug_tools = load("res://src/debug/developer_tools/developer_tools.tscn").instantiate()
	$Systems.add_child(_debug_tools)
	_debug_tools.configure(player.set_speed_multiplier, player.get_speed_multiplier, _debug_panel, {
		"status": _get_developer_status,
		"respawn": _return_player_to_spawn,
		"restart": _restart_current_scene,
		"can_control": _can_control_debug_player,
		"can_restart": func() -> bool: return get_tree().current_scene == self,
		"state": get_node_or_null("/root/GameState"),
		"story": get_story_director(),
		"ui_manager": _ui_manager,
	})

func _get_developer_status() -> Dictionary:
	var level := get_active_level()
	return {"scene": scene_file_path, "level": level.name, "position": get_player().global_position}

func _can_control_debug_player() -> bool:
	var player := get_player() as PlayerController
	return (DebugRuntime.is_enabled() and is_instance_valid(player)
		and not player.is_performance_controlled()
		and not (is_instance_valid(_story_director) and _story_director.is_busy())
		and not (is_instance_valid(_dialogue_manager) and _dialogue_manager.is_active()))

func _return_player_to_spawn() -> void:
	if _can_control_debug_player():
		(get_player() as PlayerController).teleport_to(get_active_level().get_spawn_position())

func _restart_current_scene() -> void:
	if not DebugRuntime.is_enabled() or get_tree().current_scene != self:
		return
	# Reload the host only; GameState retains business services and story facts.
	get_tree().reload_current_scene.call_deferred()

func _create_cave_debug_components() -> void:
	var overlay: CaveDebugOverlay = load("res://src/debug/cave_demo/debug_overlay.tscn").instantiate()
	$DebugLayer.add_child(overlay)
	_demo_tools = load("res://src/debug/cave_demo/cave_demo.tscn").instantiate()
	$Systems.add_child(_demo_tools)
	_demo_tools.configure(_active_level, _player, overlay)
