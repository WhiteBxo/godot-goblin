class_name MainGame
extends Node

@onready var _active_level: CaveMap = $World/LevelRoot.get_child(0) as CaveMap
@onready var _player: CavePlayer = $World/EntityRoot/Player as CavePlayer
var _shop_level: MilkTeaShop
var _shop_player: ShopPlayer
var _shop_ui: ShopUI
var _shop_interaction: ShopInteraction
var _dialogue_manager: DialogueManager
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
		_shop_player.configure_camera(_shop_level.get_world_bounds())
		var ui: ShopUI = preload("res://src/UI/milk_tea/shop_ui.tscn").instantiate()
		$HudLayer.add_child(ui)
		ui.set_popup_layer($PopupLayer)
		var interaction := ShopInteraction.new()
		interaction.name = "ShopInteraction"
		$Systems.add_child(interaction)
		interaction.configure(_shop_player, ui, _shop_level.get_interaction_points())
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
	return _shop_player if _shop_player != null else _player

func get_dialogue_manager() -> DialogueManager:
	return _dialogue_manager

func _create_dialogue_system() -> void:
	var ui: DialogueUI = preload("res://src/UI/dialogue/dialogue_ui.tscn").instantiate()
	$PopupLayer.add_child(ui)
	_dialogue_manager = DialogueManager.new()
	_dialogue_manager.name = "DialogueManager"
	$Systems.add_child(_dialogue_manager)
	_dialogue_manager.configure(ui, _can_start_dialogue)
	_dialogue_manager.dialogue_started.connect(_on_dialogue_started)
	_dialogue_manager.dialogue_ended.connect(_on_dialogue_ended)

func _can_start_dialogue() -> bool:
	return not is_instance_valid(_shop_ui) or not _shop_ui.is_open()

func _on_dialogue_started(_id: String) -> void:
	var player := get_player() as PlayerController
	_movement_before_dialogue = player.movement_enabled
	player.set_movement_enabled(false)
	if is_instance_valid(_shop_interaction):
		_interaction_before_dialogue = _shop_interaction.is_input_enabled()
		_shop_interaction.set_input_enabled(false)

func _on_dialogue_ended(_id: String, _cancelled: bool) -> void:
	var player := get_player() as PlayerController
	if is_instance_valid(player):
		player.set_movement_enabled(_movement_before_dialogue)
	if is_instance_valid(_shop_interaction):
		_shop_interaction.set_input_enabled(_interaction_before_dialogue)

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
