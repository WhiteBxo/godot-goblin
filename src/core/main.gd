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
var _chronicle_journal: ChronicleJournal
var _chronicle_hud: ChronicleHUD
var _tea_production: TeaProduction
var _warehouse_inventory: WarehouseInventory
var _observed_deliveries := 0
var _dialogue_manager: DialogueManager
var _story_director: StoryDirector
var _actor_director: ActorDirector
var _camera_director: CameraDirector
var _tea_making: TeaMaking
var _gameplay_bridge: GameplayBridge
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
		_shop_player.global_position = _shop_level.get_spawn_position()
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
		interaction.configure(_shop_player, ui, _shop_level.get_interaction_points(), _route_story_interaction)
		_shop_ui = ui
		_shop_interaction = interaction
		var feedback := InteractionFeedback.new()
		feedback.name = "InteractionFeedback"
		$World/EffectRoot.add_child(feedback)
		feedback.configure(interaction, _audio_manager)
		_create_dialogue_system()
		_create_gameplay_bridge()
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
	_ui_manager.modal_changed.connect(_refresh_input_lock)

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
	var catalog := TaskCatalog.new()
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

func get_active_level() -> Node2D:
	if _settlement_level != null:
		return _settlement_level
	return _shop_level if _shop_level != null else _active_level

func _initialize_settlement() -> void:
	_shop_player = $World/EntityRoot/Player as ShopPlayer
	_shop_player.global_position = _settlement_level.get_spawn_position()
	_shop_player.configure_camera(_settlement_level.get_camera_bounds())
	_create_camera_system(_shop_player.camera)
	_shop_ui = preload("res://src/UI/milk_tea/shop_ui.tscn").instantiate()
	_shop_ui.help_text = "洞窟聚落                  WASD 移动 · E 查看 · Esc 关闭"
	_shop_ui.show_help = not DebugRuntime.is_enabled()
	_shop_ui.close_text = "继续探索  [Esc]"
	$HudLayer.add_child(_shop_ui)
	_shop_ui.set_popup_layer($PopupLayer)
	_create_shop_business(_shop_ui)
	_shop_ui.bind_manager(_ui_manager)
	_shop_interaction = ShopInteraction.new()
	_shop_interaction.name = "SettlementInteraction"
	$Systems.add_child(_shop_interaction)
	_shop_interaction.configure(_shop_player, _shop_ui, _settlement_level.get_interaction_points(), _route_story_interaction)
	_create_dialogue_system()
	_create_gameplay_bridge(false)
	if DebugRuntime.is_enabled():
		var preview := Node.new()
		preview.name = "SettlementPreview"
		preview.set_script(load("res://src/debug/settlement/settlement_preview.gd"))
		preview.call("configure", self, $DebugLayer)
		$Systems.add_child(preview)

func get_tea_production() -> TeaProduction:
	return _tea_production

func get_warehouse_inventory() -> WarehouseInventory:
	return _warehouse_inventory

func _create_shop_business(ui: ShopUI) -> void:
	_warehouse_inventory = WarehouseInventory.new()
	_warehouse_inventory.name = "WarehouseInventory"
	$Systems.add_child(_warehouse_inventory)
	_tea_production = TeaProduction.new()
	_tea_production.name = "TeaProduction"
	$Systems.add_child(_tea_production)
	_tea_production.configure(_warehouse_inventory)
	_tea_production.changed.connect(_on_orders_changed)
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

func _route_story_interaction(id: StringName) -> Error:
	# An unavailable service or absent route falls through to the existing ShopUI.
	if not is_instance_valid(_story_director):
		return ERR_DOES_NOT_EXIST
	return _story_director.request_interaction(String(id))

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

func _on_orders_changed() -> void:
	# changed also refreshes UI: count the committed business result, not notifications.
	var delivered := _tea_production.get_completed_count()
	if delivered <= _observed_deliveries:
		return
	var previous := _observed_deliveries
	_observed_deliveries = delivered # Consume before GameState's synchronous listeners.
	var state := get_node("/root/GameState")
	for index in range(previous + 1, delivered + 1):
		state.set_flag("shop.order_%03d_delivered" % index)
	state.set_variable("shop.orders_completed", maxi(int(state.get_variable("shop.orders_completed", 0)), delivered))

func _can_start_story() -> bool:
	return (not get_tree().paused and not _ui_manager.has_modal()
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
		(is_instance_valid(_ui_manager) and _ui_manager.has_modal())
		or (is_instance_valid(_dialogue_manager) and _dialogue_manager.is_active())
		or (is_instance_valid(_story_director) and _story_director.is_busy())
		or (is_instance_valid(_actor_director) and _actor_director.is_actor_controlled(&"player"))
	)
	if is_instance_valid(_chronicle_hud):
		_chronicle_hud.disabled = should_lock
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
	# Reload the host scene, retaining cross-scene GameState through its autoload.
	get_tree().reload_current_scene.call_deferred()

func _create_cave_debug_components() -> void:
	var overlay: CaveDebugOverlay = load("res://src/debug/cave_demo/debug_overlay.tscn").instantiate()
	$DebugLayer.add_child(overlay)
	_demo_tools = load("res://src/debug/cave_demo/cave_demo.tscn").instantiate()
	$Systems.add_child(_demo_tools)
	_demo_tools.configure(_active_level, _player, overlay)
