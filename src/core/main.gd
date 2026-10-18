class_name MainGame
extends Node

@export var day1_story_enabled := false
@export var interaction_audio_scene: PackedScene = preload("res://src/core/audio/interaction_audio.tscn")
var _interaction_audio: InteractionAudio
var _day1_controller: Day1ShopController
var _chapter_controller: Day1ChapterController
var _trigger_zones: Array[StoryTriggerZone] = []
var _title_card: TitleCard
var _business_hud: Day1BusinessHUD

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
var _map_panel: SettlementMapPanel
var _map_button: Button
var _map_registered := false
var _handbook: HandbookPanel
var _handbook_hud: HandbookHUD
var _chronicle_journal: ChronicleJournal
var _tea_production: TeaProduction
var _warehouse_inventory: WarehouseInventory
var _task_catalog: TaskCatalog
var _task_delivery: TaskDelivery
var _order_board: OrderBoardModel
var _gathering_service: GatheringService
var _npc_points: Dictionary = {}
var _story_points: Dictionary[StringName, StoryInteractionPoint] = {}
var _pending_story_document: StoryInteractionPoint
var _world_controller: Day1WorldController
var _stealth_service: Day1StealthService
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
	if get_node("/root/GameState").get_business_profile() == "day1":
		day1_story_enabled = true
	if day1_story_enabled:
		var profile_error: Error = get_node("/root/GameState").select_business_profile("day1")
		if profile_error == ERR_ALREADY_IN_USE and get_node("/root/GameState").get_business_profile() == "tutorial":
			# Existing tutorial sessions must survive door travel and scene reloads.
			day1_story_enabled = false
		elif profile_error != OK:
			push_error("Cannot switch an existing business session to Day 1 (%d)" % profile_error)
			return
	_create_audio_feedback()
	_create_ui_system()
	_create_chronicle_system()
	_create_task_system()
	_create_handbook()
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
		_shop_level.configure_depth_sort($World/EntityRoot)
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
		_create_interaction_feedback(interaction)
		_create_dialogue_system()
		_create_gameplay_bridge()
		if day1_story_enabled:
			_business_hud = preload("res://src/UI/milk_tea/day1_business_hud.tscn").instantiate()
			_ui_manager.register_screen(ScreenIds.BUSINESS_HUD, _business_hud, &"hud", false)
			_business_hud.configure(get_transactions(), _warehouse_inventory)
			_ui_manager.open_screen(ScreenIds.BUSINESS_HUD)
			_day1_controller = Day1ShopController.new()
			_day1_controller.name = "Day1ShopController"
			$Systems.add_child(_day1_controller)
			var setup_error := _day1_controller.configure(self)
			if setup_error != OK:
				push_error("Day 1 initialization failed (%d)" % setup_error)
		_create_world_controller()
		_create_chapter_controller("shop")
		_create_trigger_zones(_shop_level)
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

func _create_audio_feedback() -> void:
	_interaction_audio = interaction_audio_scene.instantiate() as InteractionAudio
	$Systems.add_child(_interaction_audio)
	for message in _interaction_audio.configure(_audio_manager):
		push_warning(message)
	get_transactions().transaction_finished.connect(_interaction_audio.on_transaction_finished)

func _create_interaction_feedback(interaction: ShopInteraction) -> void:
	var feedback := InteractionFeedback.new()
	feedback.name = "InteractionFeedback"
	$World/EffectRoot.add_child(feedback)
	feedback.configure(interaction, _audio_manager, _interaction_audio.play_sound)
	interaction.interaction_failed.connect(func(_point: InteractionPoint) -> void: _interaction_audio.play_event("interaction_failure"))

func get_ui_manager() -> UIManager:
	return _ui_manager if is_instance_valid(_ui_manager) else null

func _create_ui_system() -> void:
	_ui_manager = UIManager.new()
	_ui_manager.name = "UIManager"
	$Systems.add_child(_ui_manager)
	_ui_manager.configure({&"hud": $HudLayer, &"popup": $PopupLayer, &"pause": $PauseLayer, &"debug": $DebugLayer})
	var pause: PauseMenu = preload("res://src/UI/pause/pause_menu.tscn").instantiate()
	$PauseLayer.add_child(pause)
	_ui_manager.register_screen(ScreenIds.PAUSE, pause, &"pause", true)
	pause.resume_requested.connect(func() -> void: _ui_manager.set_paused(false))
	pause.title_requested.connect(_return_to_title.bind(pause), CONNECT_DEFERRED)
	_ui_manager.modal_changed.connect(_refresh_input_lock)
	var audio_feedback := UIAudioFeedback.new()
	audio_feedback.name = "UIAudioFeedback"
	$Systems.add_child(audio_feedback)
	audio_feedback.configure(_interaction_audio.play_sound, [$HudLayer, $PopupLayer, $PauseLayer], _ui_manager)

func _return_to_title(pause: PauseMenu) -> void:
	var error := ERR_BUSY if is_instance_valid(_scene_travel) and _scene_travel.is_busy() else GameEntry.return_to_title(get_tree())
	if error != OK and is_instance_valid(pause):
		pause.show_navigation_error(error)

func get_task_journal() -> TaskJournal:
	return _task_journal if is_instance_valid(_task_journal) else null

func get_chronicle_journal() -> ChronicleJournal:
	return _chronicle_journal if is_instance_valid(_chronicle_journal) else null

func open_chronicle() -> Error:
	return _open_handbook(ScreenIds.CHRONICLE)

func open_tasks() -> Error:
	return _open_handbook(ScreenIds.TASKS)

func open_handbook() -> Error:
	return _open_handbook(ScreenIds.HANDBOOK)

func open_drinks() -> Error:
	return _open_handbook(ScreenIds.DRINKS)

func _open_handbook(page: StringName) -> Error:
	_refresh_handbook_access()
	if not _handbook_hud.visible:
		return ERR_UNAVAILABLE
	var blocked := (get_tree().paused
		or (_ui_manager.has_modal() and not _ui_manager.is_open(ScreenIds.HANDBOOK))
		or (is_instance_valid(_scene_travel) and _scene_travel.is_busy())
		or (is_instance_valid(_story_director) and _story_director.is_busy())
		or (is_instance_valid(_actor_director) and _actor_director.is_actor_controlled(&"player")))
	if blocked:
		return ERR_BUSY
	_refresh_task_delivery_names()
	return _ui_manager.open_screen(page)

func _refresh_task_delivery_names() -> void:
	var target_names := {}
	var level := get_active_level()
	if is_instance_valid(level) and level.has_method("get_interaction_points"):
		for point: InteractionPoint in level.get_interaction_points():
			target_names[String(point.interaction_id)] = point.display_name
	for point: InteractionPoint in _npc_points.values():
		target_names[String(point.interaction_id)] = point.display_name
	var product_names := {}
	var inventory: WarehouseInventory = get_node("/root/GameState").get_warehouse_inventory()
	for definition: IngredientDefinition in WarehouseInventory.CATALOG.ingredients:
		product_names[definition.id] = definition.display_name
	for task: Dictionary in _task_journal.get_active_tasks():
		if not task.delivery.is_empty():
			if task.delivery.has("drink"):
				continue
			var required: Dictionary = task.delivery.items if task.delivery.has("items") else {String(task.delivery.product_id): 1}
			for id: String in required:
				var product := inventory.get_definition(id)
				if product != null:
					product_names[id] = product.display_name
	_handbook.set_delivery_names(target_names, product_names)
	if is_instance_valid(_order_board):
		_order_board.set_target_names(target_names)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"open_map") and not event.is_echo():
		open_map()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"open_tasks") and not event.is_echo():
		open_tasks()
		get_viewport().set_input_as_handled()

func _create_chronicle_system() -> void:
	_chronicle_journal = ChronicleJournal.new()
	_chronicle_journal.name = "ChronicleJournal"
	$Systems.add_child(_chronicle_journal)
	_chronicle_journal.configure(get_node("/root/GameState"))

func _create_task_system() -> void:
	_task_catalog = TaskCatalog.new()
	var catalog := _task_catalog
	var error := catalog.load_files(Day1ChapterController.TASK_FILES) if day1_story_enabled else catalog.load_file("res://src/resources/tasks/tasks.json")
	if error != OK:
		push_error("Could not load tasks: " + catalog.last_error)
		return
	_task_journal = TaskJournal.new()
	_task_journal.name = "TaskJournal"
	$Systems.add_child(_task_journal)
	_task_journal.configure(catalog, get_node("/root/GameState"))

func _create_handbook() -> void:
	_handbook = preload("res://src/UI/handbook/handbook_panel.tscn").instantiate()
	_ui_manager.register_screen(ScreenIds.HANDBOOK, _handbook, &"popup", true)
	_handbook.bind_journals(_task_journal, _chronicle_journal)
	_handbook.bind_inventory(get_node("/root/GameState").get_warehouse_inventory())
	_handbook.get_drinks_page().remake_requested.connect(func(materials: Array[String], iced: bool) -> void:
		_handbook.get_drinks_page().show_remake_result(is_instance_valid(_shop_ui) and _shop_ui.select_formula(materials, iced)))
	_handbook.close_requested.connect(func() -> void: _ui_manager.close_screen(ScreenIds.HANDBOOK))
	_ui_manager.register_screen_alias(ScreenIds.TASKS, ScreenIds.HANDBOOK, _handbook.select_page.bind(ScreenIds.TASKS))
	_ui_manager.register_screen_alias(ScreenIds.CHRONICLE, ScreenIds.HANDBOOK, _handbook.select_page.bind(ScreenIds.CHRONICLE))
	_ui_manager.register_screen_alias(ScreenIds.DRINKS, ScreenIds.HANDBOOK, _handbook.select_page.bind(ScreenIds.DRINKS))
	_handbook_hud = preload("res://src/UI/handbook/handbook_hud.tscn").instantiate()
	_ui_manager.register_screen(ScreenIds.HANDBOOK_HUD, _handbook_hud, &"hud", false)
	_ui_manager.open_screen(ScreenIds.HANDBOOK_HUD)
	_handbook_hud.pressed.connect(open_handbook)
	_task_journal.projection_changed.connect(_refresh_handbook_access)
	_task_journal.projection_changed.connect(_refresh_task_delivery_names)
	_chronicle_journal.changed.connect(_refresh_handbook_access)
	get_node("/root/GameState").get_warehouse_inventory().changed.connect(_refresh_handbook_access)
	get_node("/root/GameState").state_changed.connect(_refresh_handbook_access)
	_refresh_handbook_access()

func _refresh_handbook_access() -> void:
	if not is_inside_tree() or not is_instance_valid(_handbook):
		return
	var state := get_node("/root/GameState")
	var tasks: bool = state.get_flag("ui.handbook.tasks_unlocked")
	if not tasks and is_instance_valid(_task_journal) and _task_journal.has_started_tasks():
		tasks = true
		if not state.set_flag("ui.handbook.tasks_unlocked"):
			# GameState rejects writes while restoring; persist migration after commit.
			_refresh_handbook_access.call_deferred()
	var chronicle: bool = state.get_flag("day1.chronicle_unlocked") if day1_story_enabled else not _chronicle_journal.get_entries().is_empty()
	var drinks: bool = not state.get_warehouse_inventory().get_drinks(true).is_empty()
	_handbook.refresh_access(tasks, chronicle, drinks)
	if not tasks and not chronicle and not drinks:
		_ui_manager.close_screen(ScreenIds.HANDBOOK)
	_handbook_hud.refresh_access(tasks or chronicle or drinks, _chronicle_journal.get_unread_count() if chronicle else 0)


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

func has_scene_arrival() -> bool:
	return _arrival_entrance != &""

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
	_scene_travel.busy_changed.connect(_refresh_transition_layer)
	_scene_travel.travel_failed.connect(_on_scene_travel_failed)
	if _arrival_entrance != &"":
		_scene_travel.begin_arrival()

func _can_leave_scene() -> bool:
	if _shop_level != null and not Day1Access.can_leave_shop(get_node("/root/GameState")):
		return false
	var owns_lock := is_instance_valid(_scene_travel) and _scene_travel.is_busy()
	var movement_available := _movement_before_dialogue if owns_lock else _shop_player.movement_enabled
	return (not get_tree().paused and not _ui_manager.has_modal() and movement_available
		and (not is_instance_valid(_stealth_service) or not _stealth_service.is_blocking())
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
	for point: InteractionPoint in points:
		if point is StoryInteractionPoint:
			if _story_points.has(point.interaction_id):
				push_error("Duplicate story interaction ID: " + String(point.interaction_id))
				point.interaction_enabled = false
			else:
				_story_points[point.interaction_id] = point
	points.append_array(_settlement_level.get_scene_exits())
	for point: GatherPoint in gather_points:
		points.append(point)
	_shop_interaction = ShopInteraction.new()
	_shop_interaction.name = "SettlementInteraction"
	$Systems.add_child(_shop_interaction)
	_shop_interaction.configure(_shop_player, _shop_ui, points, _route_story_interaction)
	_create_interaction_feedback(_shop_interaction)
	_create_dialogue_system()
	for marker: Marker2D in _settlement_level.get_story_positions():
		_actor_director.register_position(StringName(marker.name), marker)
	_create_gameplay_bridge(false)
	_create_world_controller()
	_create_chapter_controller("settlement")
	_create_trigger_zones(_settlement_level)
	_create_scene_travel(_settlement_level.get_scene_exits())
	_create_stealth_system()
	_create_map_ui()
	if DebugRuntime.is_enabled():
		var preview := Node.new()
		preview.name = "SettlementPreview"
		preview.set_script(load("res://src/debug/settlement/settlement_preview.gd"))
		preview.call("configure", self, $DebugLayer)
		$Systems.add_child(preview)

func get_tea_production() -> TeaProduction:
	return _tea_production

func get_stealth_service() -> Day1StealthService:
	return _stealth_service

func _create_stealth_system() -> void:
	_stealth_service = Day1StealthService.new()
	_stealth_service.name = "Day1StealthService"
	$Systems.add_child(_stealth_service)
	_stealth_service.changed.connect(_refresh_input_lock)
	_stealth_service.guard_intercepted.connect(_on_stealth_intercepted)
	_stealth_service.configure(get_node("/root/GameState"), _warehouse_inventory, _shop_player,
		$World/EffectRoot, _settlement_level.get_stealth_setup(), _actor_director.get_actor, _can_operate_stealth)
	var hud: Day1StealthHUD = preload("res://src/UI/hud/day1_stealth_hud.tscn").instantiate()
	_ui_manager.register_screen(ScreenIds.STEALTH_HUD, hud, &"hud", false)
	hud.configure(_stealth_service)
	_ui_manager.open_screen(ScreenIds.STEALTH_HUD)

func _can_operate_stealth() -> bool:
	return (not get_tree().paused and not _ui_manager.has_modal()
		and not _dialogue_manager.is_active() and not _story_director.is_busy()
		and not _shop_player.is_performance_controlled()
		and (not is_instance_valid(_scene_travel) or not _scene_travel.is_busy())
		and (_shop_player.movement_enabled or (_stealth_service.is_blocking() and _movement_before_dialogue)))

func _on_stealth_intercepted(event_id: String) -> void:
	var error := _story_director.request_event(event_id)
	if error != OK:
		push_warning("Drunken guard event is not available (%s); no payment or clearance was recorded" % error_string(error))

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
	_task_delivery.delivered.connect(func(_id: String) -> void: _interaction_audio.play_event("delivery_success"))
	_task_delivery.delivery_failed.connect(func(_id: String, _reason: String) -> void: _interaction_audio.play_event("delivery_failure"))
	_order_board = OrderBoardModel.new()
	_order_board.name = "OrderBoardModel"
	$Systems.add_child(_order_board)
	_order_board.configure(_task_catalog, _task_journal, state, _warehouse_inventory, _tea_production, _task_delivery)
	_handbook.get_tasks_page().bind_orders(_order_board)
	_task_journal.projection_changed.connect(_refresh_order_requirements.bind(ui))
	ui.point_opened.connect(_on_shop_point_opened)
	ui.configure_inventory(_warehouse_inventory)
	ui.configure_production(_tea_production)
	ui.configure_orders(_order_board)
	ui.track_requested.connect(_track_order)
	ui.accept_requested.connect(func(id: String) -> void:
		var accepted := _task_delivery.accept_order(id)
		if accepted == OK:
			_interaction_audio.play_event("order_accepted")
			_track_order(id)
		elif accepted != ERR_ALREADY_EXISTS:
			_interaction_audio.play_event("order_failure")
			ui.show_feedback("暂时无法接取这张订单，请核对当前阶段。", false))
	var task_hud: TaskHUD = preload("res://src/UI/tasks/task_hud.tscn").instantiate()
	_ui_manager.register_screen(ScreenIds.TASK_HUD, task_hud, &"hud", false)
	_ui_manager.open_screen(ScreenIds.TASK_HUD)
	task_hud.bind_journal(_task_journal)
	task_hud.bind_orders(_order_board)
	ui.craft_requested.connect(func(materials: Array[String], quantity: int) -> void:
		var result := _tea_production.craft(materials, quantity)
		_interaction_audio.play_event("craft_success" if result.ok else "craft_failure")
		ui.show_production_result(result))
	ui.formula_requested.connect(func(materials: Array[String], iced: bool) -> void:
		var result := _tea_production.craft_formula(materials, 1, "", iced)
		_interaction_audio.play_event("craft_success" if result.ok else "craft_failure")
		ui.show_formula_result(result))

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

func get_order_board() -> OrderBoardModel:
	return _order_board

func get_delivery_point(target_id: String) -> InteractionPoint:
	return _npc_points.get(StringName(target_id))

func _track_order(order_id: String) -> void:
	if _order_board.get_entry(order_id).get("status") == "active":
		get_node("/root/GameState").set_variable(OrderBoardModel.TRACKED_KEY, order_id)

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
	_gathering_service.harvested.connect(func(_point: GatherPoint, _id: String, _amount: int, _stock: int) -> void:
		_interaction_audio.play_event("gather_success"))

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
		if day1_story_enabled and entity.actor_id != &"fat_goblin":
			point.position = Vector2(0, -150)
			point.get_node("Marker").hide()
			point.get_node("Label").hide()
		points.append(point)
		_npc_points[point.interaction_id] = point
	return points

func _route_story_interaction(id: StringName) -> Error:
	# Existing story routes retain priority; gathering and delivery are gameplay fallbacks.
	if is_instance_valid(_story_director):
		var error := _story_director.request_interaction(String(id))
		if error != ERR_DOES_NOT_EXIST:
			return error
	if _story_points.has(id):
		var point := _story_points[id]
		if not point.is_available():
			return ERR_UNAVAILABLE
		_shop_ui.open(point)
		if point.kind == StoryInteractionPoint.Kind.DOCUMENT:
			_pending_story_document = point
			return OK
		var result := point.resolve()
		_shop_ui.show_interaction_result(result.message)
		return OK if result.ok else ERR_UNAVAILABLE
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
		var tracked := _order_board.get_tracked_entry()
		var delivery_result := _task_delivery.deliver_to(String(id), tracked.get("order_id", ""))
		_shop_ui.show_feedback(delivery_result.message, delivery_result.ok)
		return OK if delivery_result.ok else ERR_UNAVAILABLE
	return ERR_DOES_NOT_EXIST

func _create_world_controller() -> void:
	_world_controller = Day1WorldController.new()
	$Systems.add_child(_world_controller)
	var actors: Array[SettlementCharacter] = []
	for entity: Node in $World/EntityRoot.get_children():
		if entity is SettlementCharacter:
			actors.append(entity)
	_world_controller.configure(get_node("/root/GameState"), get_active_level(), actors, _npc_points)
	_shop_ui.closed.connect(_complete_story_document)
	# Only a successfully instantiated destination can publish an arrival fact.
	if _shop_level != null and _arrival_entrance == &"street_door":
		_world_controller.record_shop_arrival()

func _complete_story_document() -> void:
	var point := _pending_story_document
	_pending_story_document = null
	if is_instance_valid(point):
		point.resolve()

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
	_ui_manager.register_screen(ScreenIds.DIALOGUE, ui, &"popup", true)
	_dialogue_manager = DialogueManager.new()
	_dialogue_manager.name = "DialogueManager"
	$Systems.add_child(_dialogue_manager)
	_dialogue_manager.configure(ui, _can_start_dialogue)
	_dialogue_manager.dialogue_started.connect(_on_dialogue_started)
	_dialogue_manager.dialogue_ended.connect(_on_dialogue_ended)
	_dialogue_manager.line_changed.connect(func(_line: String) -> void: _interaction_audio.play_event("dialogue_line"))
	_dialogue_manager.choice_selected.connect(func(_dialogue: String, _line: String, _choice: String) -> void:
		_interaction_audio.play_event("dialogue_choice"))
	_story_director = StoryDirector.new()
	_story_director.name = "StoryDirector"
	$Systems.add_child(_story_director)
	_story_director.configure(_dialogue_manager, _can_start_story)
	_story_director.set_chronicle_journal(_chronicle_journal)
	_story_director.configure_cinematic(_actor_director, _camera_director)
	_story_director.tree_exiting.connect(_on_story_exiting)
	_story_director.set_audio_adapter(StoryAudioAdapter.new(_audio_manager))
	_story_director.set_title_card(_create_title_card())
	_story_director.event_started.connect(func(_id: String) -> void: _refresh_input_lock())
	_story_director.event_finished.connect(_on_story_finished)

## The existing transition layer owns full-screen presentation. SceneTravel adds
## its transition after this card, so scene changes can still cover it.
func _create_title_card() -> TitleCard:
	_title_card = preload("res://src/UI/title_card/title_card.tscn").instantiate()
	$TransitionLayer.add_child(_title_card)
	_title_card.showing_changed.connect(_refresh_transition_layer)
	return _title_card

func get_title_card() -> TitleCard:
	return _title_card

func _refresh_transition_layer() -> void:
	$TransitionLayer.visible = (is_instance_valid(_title_card) and _title_card.is_showing()) or (is_instance_valid(_scene_travel) and _scene_travel.is_busy())

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
	_tea_making.recipe_completed.connect(func(_recipe: String, _session: int) -> void: _interaction_audio.play_event("craft_success"))

func _on_shop_point_opened(id: StringName) -> void:
	if id == &"orders":
		get_node("/root/GameState").set_flag("shop.orders_viewed")
		_refresh_order_requirements(_shop_ui)

func _refresh_order_requirements(ui: ShopUI) -> void:
	var names := {}
	for point: InteractionPoint in _npc_points.values():
		names[String(point.interaction_id)] = point.display_name
	var requirements := _task_delivery.get_requirements_text(names)
	if is_instance_valid(_order_board):
		_order_board.set_target_names(names)
	ui.show_order_requirements("已接取订单：\n" + requirements + "\n准备所需成品或物资，携带到指定 NPC 按 E 交付。" if not requirements.is_empty() else "当前没有待交付订单。")

func _can_start_story() -> bool:
	return (not get_tree().paused and not _ui_manager.has_modal()
		and (not is_instance_valid(_stealth_service) or _stealth_service.status != Day1StealthService.Status.FAILED)
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
		or (is_instance_valid(_stealth_service) and _stealth_service.is_blocking())
	)
	if is_instance_valid(_map_button):
		_map_button.disabled = should_lock
	if is_instance_valid(_handbook_hud):
		_handbook_hud.disabled = should_lock
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
		"dialogue": _dialogue_manager,
		"ui_manager": _ui_manager,
		"transactions": get_transactions(),
		"inventory": get_warehouse_inventory(),
		"production": get_tea_production(),
		"tasks": get_task_journal(),
		"delivery": get_task_delivery(),
		"bridge": get_gameplay_bridge(),
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

func get_business_hud() -> Day1BusinessHUD:
	return _business_hud

func get_day1_controller() -> Day1ShopController:
	return _day1_controller

func get_chapter_controller() -> Day1ChapterController:
	return _chapter_controller if is_instance_valid(_chapter_controller) else null

func get_trigger_zones() -> Array[StoryTriggerZone]:
	return _trigger_zones.duplicate()

## Day 1 sessions only; the tutorial shop and debug hosts keep their own story data.
func _create_chapter_controller(host: String) -> void:
	if not day1_story_enabled:
		return
	_chapter_controller = Day1ChapterController.new()
	_chapter_controller.name = "Day1ChapterController"
	$Systems.add_child(_chapter_controller)
	if _chapter_controller.configure(self, host) == OK:
		_world_controller.set_staging_lookup(_chapter_controller.get_staged_visibility)

## Walk-in triggers route exactly like interaction IDs, so story data stays the only gate.
func _create_trigger_zones(level: Node) -> void:
	var pending: Array[Node] = [level]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is StoryTriggerZone:
			node.configure(get_node("/root/GameState"), _shop_player, _route_trigger)
			_trigger_zones.append(node)

func _route_trigger(id: String) -> Error:
	if not _can_start_story() or _dialogue_manager.is_active() or _story_director.is_busy():
		return ERR_BUSY
	return _story_director.request_interaction(id)

func refresh_day1_access() -> void:
	if not day1_story_enabled:
		return
	_refresh_handbook_access()
	for id: StringName in _npc_points:
		var available := false
		for task: Dictionary in _task_catalog.get_tasks():
			if task.has("delivery") and task.delivery.target_object_id == String(id) and _task_journal.get_task(task.id).get("status") == "active":
				available = not task.delivery.has("accepted_flag") or get_node("/root/GameState").get_flag(task.delivery.accepted_flag)
		_npc_points[id].interaction_enabled = available

## Capability only; the S04 story decides when to call this, not the UI.
func unlock_map() -> Error:
	if not is_instance_valid(_map_panel) or not is_instance_valid(_settlement_level):
		return ERR_UNCONFIGURED
	var error := _register_map()
	if error != OK:
		return error
	if get_node("/root/GameState").get_flag("day1.s04.map_available"):
		return OK
	if not get_node("/root/GameState").set_flag("day1.s04.map_available"):
		_refresh_map_access()
		return ERR_BUSY
	return OK

func _register_map() -> Error:
	if _map_registered:
		return OK
	var error := _ui_manager.register_screen(ScreenIds.MAP, _map_panel, &"popup", true)
	_map_registered = error == OK
	return error

func _create_map_ui() -> void:
	_map_panel = preload("res://src/UI/map/map_panel.tscn").instantiate()
	$PopupLayer.add_child(_map_panel)
	_map_panel.configure(_settlement_level, _shop_player, _task_journal, _get_known_map_locations)
	_map_panel.close_requested.connect(func() -> void: _ui_manager.close_screen(ScreenIds.MAP))
	_map_button = preload("res://src/UI/map/map_button.tscn").instantiate()
	$HudLayer.add_child(_map_button)
	_map_button.pressed.connect(open_map)
	get_node("/root/GameState").state_changed.connect(_refresh_map_access)
	_refresh_map_access()

func _get_known_map_locations() -> Array[String]:
	# Only the shop is initially established. Other areas require explicit knowledge.
	var known: Array[String] = ["settlement.shop"]
	var state := get_node("/root/GameState")
	for id: String in SettlementMap.MAP_LOCATIONS:
		if state.get_flag("ui.map.known." + id) and id not in known:
			known.append(id)
	return known

func _refresh_map_access() -> void:
	if not is_instance_valid(_map_panel):
		return
	var unlocked: bool = get_node("/root/GameState").get_flag("day1.s04.map_available")
	if unlocked:
		unlocked = _register_map() == OK
	elif _map_registered:
		_ui_manager.unregister_screen(ScreenIds.MAP)
		_map_registered = false
	if _ui_manager.is_open(ScreenIds.MAP):
		_map_panel.refresh()
	_map_button.visible = unlocked
	_map_button.focus_mode = Control.FOCUS_ALL if unlocked else Control.FOCUS_NONE

func open_map() -> Error:
	if not is_instance_valid(_map_panel) or not get_node("/root/GameState").get_flag("day1.s04.map_available"):
		return ERR_UNAVAILABLE
	if (get_tree().paused or _ui_manager.has_modal()
		or (is_instance_valid(_scene_travel) and _scene_travel.is_busy())
		or (is_instance_valid(_story_director) and _story_director.is_busy())
		or (is_instance_valid(_actor_director) and _actor_director.is_actor_controlled(&"player"))
		or (is_instance_valid(_stealth_service) and _stealth_service.is_blocking())
		or not _shop_player.movement_enabled):
		return ERR_BUSY
	return _ui_manager.open_screen(ScreenIds.MAP)
