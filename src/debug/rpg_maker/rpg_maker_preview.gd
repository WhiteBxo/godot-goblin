extends Node
## Independent map trial using the real player and saved, editable map scenes.

const MAP_IDS: Array[int] = [1, 4, 5, 6]
const MAP_SCENES: Array[PackedScene] = [
	preload("res://src/levels/rpg_maker/map_001.tscn"),
	preload("res://src/levels/rpg_maker/map_004.tscn"),
	preload("res://src/levels/rpg_maker/map_005.tscn"),
	preload("res://src/levels/rpg_maker/map_006.tscn"),
]
const PLAYER_SCENE := preload("res://src/gameplay/player/rpg_player.tscn")
const PREVIEW_ACTIONS := {
	&"rpg_preview_map_1": KEY_1,
	&"rpg_preview_map_2": KEY_2,
	&"rpg_preview_map_3": KEY_3,
	&"rpg_preview_map_4": KEY_4,
	&"rpg_preview_overview": KEY_TAB,
	&"rpg_preview_reset": KEY_R,
}

@export var initial_map_id: int = 1
@export_range(0.1, 4.0, 0.1) var player_zoom: float = 2.0

var _level: RpgMakerMap
var _player: FloorAwareShopPlayer
var _overview := false
var _added_actions: Array[StringName] = []
var _capture_path := ""

@onready var _map_label: Label = $DebugLayer/Panel/Content/MapTitle

func _ready() -> void:
	DebugRuntime.apply_release_policy(get_tree())
	if not OS.has_feature("debug"):
		$DebugLayer.hide()
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	var probe := get_node_or_null("/root/MCPRuntimeProbe")
	if probe != null:
		probe.process_mode = Node.PROCESS_MODE_DISABLED
	_register_actions()
	var start_overview := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rpg-map="):
			initial_map_id = argument.trim_prefix("--rpg-map=").to_int()
		elif argument.begins_with("--rpg-capture="):
			_capture_path = argument.trim_prefix("--rpg-capture=")
		elif argument == "--rpg-overview":
			start_overview = true
	_player = PLAYER_SCENE.instantiate() as FloorAwareShopPlayer
	_player.z_index = 0
	$World/EntityRoot.add_child(_player)
	get_viewport().size_changed.connect(_fit_overview)
	$DebugLayer/Panel.resized.connect(_fit_overview)
	show_map(initial_map_id if initial_map_id in MAP_IDS else MAP_IDS[0])
	set_overview(start_overview)
	if not _capture_path.is_empty():
		_capture_and_quit.call_deferred()

func _exit_tree() -> void:
	for action in _added_actions:
		InputMap.erase_action(action)

func get_player() -> FloorAwareShopPlayer:
	return _player

func get_active_level() -> RpgMakerMap:
	return _level

func is_overview_enabled() -> bool:
	return _overview

func show_map(id: int) -> void:
	var index := MAP_IDS.find(id)
	if index < 0 or not is_instance_valid(_player):
		return
	_player.set_floor_query(Callable())
	if is_instance_valid(_level):
		$World/LevelRoot.remove_child(_level)
		_level.queue_free()
	_level = MAP_SCENES[index].instantiate() as RpgMakerMap
	$World/LevelRoot.add_child(_level)
	_player.set_floor_query(_level.can_stand_at)
	_player.teleport_to(_level.get_spawn_position())
	_player.configure_camera(_level.get_camera_bounds())
	_player.camera.set_directed_zoom(player_zoom)
	set_overview(_overview)
	_map_label.text = "%d / 4  ·  %s  ·  Map%03d" % [index + 1, _level.map_title, _level.map_id]

func reset_player() -> void:
	if is_instance_valid(_level):
		_player.teleport_to(_level.get_spawn_position())

func set_overview(enabled: bool) -> void:
	_overview = enabled
	_player.set_movement_enabled(not enabled)
	if enabled:
		_fit_overview()
	else:
		_player.configure_camera(_level.get_camera_bounds())
		_player.camera.set_directed_zoom(player_zoom)
		_player.camera.restore_follow()
		_player.camera.reset_smoothing()
		_player.camera.force_update_scroll()

func _fit_overview() -> void:
	if not _overview or not is_instance_valid(_level):
		return
	var bounds := _level.get_camera_bounds()
	var viewport_size := get_viewport().get_visible_rect().size
	var panel: Control = $DebugLayer/Panel
	var panel_height := maxf(panel.size.y, panel.get_combined_minimum_size().y)
	var top_inset := panel.position.y + panel_height + 12.0
	var bottom_inset := 12.0
	var available := (viewport_size - Vector2(24, top_inset + bottom_inset)).max(Vector2.ONE)
	var overview_zoom := minf(available.x / bounds.size.x, available.y / bounds.size.y)
	# Leave the top of the view free for the map selector and controls legend.
	var center := bounds.get_center() - Vector2(0, (top_inset - bottom_inset) * 0.5) / overview_zoom
	var view_size := viewport_size / overview_zoom
	# Extend only the debug observation bounds to fit the whole map with margins.
	# The same camera restores the map's physical bounds when following resumes.
	_player.camera.begin_cinematic()
	_player.camera.configure(Rect2(center - view_size * 0.5, view_size))
	_player.camera.set_directed_zoom(overview_zoom)
	_player.camera.set_cinematic_position(center)

func _unhandled_input(event: InputEvent) -> void:
	if not OS.has_feature("debug") or event.is_echo():
		return
	for index in range(MAP_IDS.size()):
		if event.is_action_pressed(StringName("rpg_preview_map_%d" % (index + 1))):
			show_map(MAP_IDS[index])
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"rpg_preview_overview") or event.is_action_pressed(&"debug_toggle_overview"):
		set_overview(not _overview)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"rpg_preview_reset"):
		reset_player()
		get_viewport().set_input_as_handled()

func _register_actions() -> void:
	# These keys exist only while this standalone Debug host is open.
	for action: StringName in PREVIEW_ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = PREVIEW_ACTIONS[action]
		InputMap.action_add_event(action, event)
		_added_actions.append(action)

func _capture_and_quit() -> void:
	if not _capture_path.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("RPG capture requires an absolute PNG path and a rendering display.")
		get_tree().quit(1)
		return
	var error := DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	if error != OK:
		push_error("Cannot create RPG capture directory: %s" % error_string(error))
		get_tree().quit(1)
		return
	for frame in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	error = get_viewport().get_texture().get_image().save_png(_capture_path)
	if error != OK:
		push_error("Cannot save RPG capture: %s" % error_string(error))
	else:
		print("RPG_CAPTURE: ", _capture_path)
	get_tree().quit(0 if error == OK else 1)
