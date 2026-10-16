class_name MainGame
extends Node

@onready var _audio_manager: AudioManager = $Systems/AudioManager
@onready var _active_level: CaveMap = $World/LevelRoot.get_child(0) as CaveMap
@onready var _player: CavePlayer = $World/EntityRoot/Player as CavePlayer
var _shop_level: MilkTeaShop
var _shop_player: ShopPlayer
var _shop_ui: ShopUI
var _shop_interaction: ShopInteraction
var _dialogue_manager: DialogueManager
var _story_director: StoryDirector
var _actor_director: ActorDirector
var _camera_director: CameraDirector
var _input_locked: bool = false
var _movement_before_dialogue: bool = true
var _interaction_before_dialogue: bool = true

var _debug_tools: DeveloperTools
var _demo_tools: CaveDemoController
var _debug_panel: DeveloperPanel

func _ready() -> void:
	DebugRuntime.apply_release_policy(get_tree())
	_shop_level = $World/LevelRoot.get_child(0) as MilkTeaShop
	if _shop_level != null:
		_shop_player = $World/EntityRoot/Player as ShopPlayer
		_shop_player.global_position = _shop_level.get_spawn_position()
		_shop_player.configure_camera(_shop_level.get_camera_bounds())
		_create_camera_system(_shop_player.camera)
		var ui: ShopUI = preload("res://src/UI/milk_tea/shop_ui.tscn").instantiate()
		$HudLayer.add_child(ui)
		ui.set_popup_layer($PopupLayer)
		var interaction := ShopInteraction.new()
		interaction.name = "ShopInteraction"
		$Systems.add_child(interaction)
		interaction.configure(_shop_player, ui, _shop_level.get_interaction_points(), _route_story_interaction)
		_shop_ui = ui
		_shop_interaction = interaction
		_create_dialogue_system()
		return
	var error := _active_level.load_error
	if DebugRuntime.is_enabled():
		_create_debug_components()
		error = _demo_tools.apply_layout_override()
	if error != OK:
		push_error("Could not initialize MainGame level (error %d)" % error)
		get_tree().quit(1)
		return
	_player.configure(_active_level.can_stand_at)
	_player.global_position = _active_level.get_spawn_position()
	_player.follow_player()
	_create_dialogue_system()
	if _debug_tools != null:
		_debug_tools.configure(_player.set_speed_multiplier, _player.get_speed_multiplier, _debug_panel)
		_demo_tools.start()

func get_active_level() -> Node2D:
	return _shop_level if _shop_level != null else _active_level

func get_player() -> CharacterBody2D:
	return _shop_player if is_instance_valid(_shop_player) else (_player if is_instance_valid(_player) else null)

func get_dialogue_manager() -> DialogueManager:
	return _dialogue_manager

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

func _route_story_interaction(id: StringName) -> bool:
	# An unavailable service or absent route falls through to the existing ShopUI.
	if not is_instance_valid(_story_director):
		return false
	return _story_director.request_interaction(String(id)) != ERR_DOES_NOT_EXIST

func _create_dialogue_system() -> void:
	_actor_director = ActorDirector.new()
	_actor_director.name = "ActorDirector"
	$Systems.add_child(_actor_director)
	_actor_director.configure($World/EntityRoot)
	_actor_director.actor_register(&"player", get_player() as PlayerController)
	_actor_director.actor_control_changed.connect(_on_actor_control_changed)
	var ui: DialogueUI = preload("res://src/UI/dialogue/dialogue_ui.tscn").instantiate()
	$PopupLayer.add_child(ui)
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

func _can_start_story() -> bool:
	return not is_instance_valid(_shop_ui) or not _shop_ui.is_open()

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
		(is_instance_valid(_dialogue_manager) and _dialogue_manager.is_active())
		or (is_instance_valid(_story_director) and _story_director.is_busy())
		or (is_instance_valid(_actor_director) and _actor_director.is_actor_controlled(&"player"))
	)
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
	var panel: DeveloperPanel = load("res://src/debug/developer_tools/developer_panel.tscn").instantiate()
	_debug_panel = panel
	$DebugLayer.add_child(panel)
	_debug_tools = load("res://src/debug/developer_tools/developer_tools.tscn").instantiate()
	$Systems.add_child(_debug_tools)
	var overlay: CaveDebugOverlay = load("res://src/debug/cave_demo/debug_overlay.tscn").instantiate()
	$DebugLayer.add_child(overlay)
	_demo_tools = load("res://src/debug/cave_demo/cave_demo.tscn").instantiate()
	$Systems.add_child(_demo_tools)
	_demo_tools.configure(_active_level, _player, overlay)
	_demo_tools.capture_started.connect(panel.hide)
