class_name CaveDemoController
extends Node

const ORIGINAL_LAYOUT := "res://src/levels/cave/cave_layout_original.json"

var _level: CaveMap
var _player: CavePlayer
var _overlay: CaveDebugOverlay
var _started := false

func configure(level: CaveMap, player: CavePlayer, overlay: CaveDebugOverlay) -> void:
	_level = level
	_player = player
	_overlay = overlay

func prepare_level() -> Error:
	if _level == null or _player == null or _overlay == null:
		return ERR_UNCONFIGURED
	if "--original-layout" in OS.get_cmdline_user_args():
		return _level.load_layout(ORIGINAL_LAYOUT)
	return _level.load_error

func start() -> void:
	if _started:
		return
	_started = true
	set_wall_mode(CaveMap.WallMode.TEXTURED)
	print("Cave ready: %d walkable cells, %d river cells, %d wall conflicts" % [
		_level.walkable_cells.size(), _level.river_layer.get_used_cells().size(), _level.walls.conflicts.size()
	])
	_setup_capture_mode()

func get_overlay() -> CaveDebugOverlay:
	return _overlay

func set_wall_mode(mode: int) -> void:
	_level.set_wall_mode(mode)
	_overlay.set_hint("WASD / 方向键移动   F2 切换墙体   M 全图\n当前：%s   墙高 %dpx" % [
		_level.get_wall_mode_name(), _level.walls.wall_height
	])

func toggle_overview() -> void:
	if _player.overview_enabled:
		_player.follow_player()
	else:
		_player.show_overview(_level.get_world_bounds().grow(64.0), get_viewport().get_visible_rect().size)

func _unhandled_input(event: InputEvent) -> void:
	if not _started:
		return
	if event.is_action_pressed("debug_cycle_walls"):
		set_wall_mode((_level.wall_mode + 1) % 3)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_toggle_overview"):
		toggle_overview()
		get_viewport().set_input_as_handled()

func _setup_capture_mode() -> void:
	var args := OS.get_cmdline_user_args()
	if "--capture-walls-map" in args:
		set_wall_mode(CaveMap.WallMode.FLAT)
		_player.show_overview(_level.get_world_bounds().grow(64.0), get_viewport().get_visible_rect().size)
		_capture_viewport("walls_overview.png")
	elif "--capture-walls-top" in args:
		_player.global_position = _level.cell_to_world(Vector2(78.5, -1.5))
		_player.center_camera_on(_level.cell_to_world(Vector2(78.5, 1.5)))
		_capture_viewport("walls_top_bypass.png")
	elif "--capture-walls-junction" in args:
		_player.global_position = _level.cell_to_world(Vector2(62.5, 43.0))
		_capture_viewport("walls_junction.png")
	elif "--capture-walls-river" in args:
		_player.global_position = _level.cell_to_world(Vector2(15.5, 52.5))
		_capture_viewport("walls_river.png")
	elif "--capture-atlas-compare" in args:
		_capture_atlas_comparison()

func _capture_atlas_comparison() -> void:
	_level.hide()
	_player.hide()
	_overlay.show_atlas_comparison(
		load("res://assets/map/cave/cave_floor_atlas.png"),
		load("res://assets/map/cave/cave_floor_processed.png")
	)
	_capture_viewport("atlas_processing_comparison.png")

func _capture_viewport(filename: String) -> void:
	var directory := "user://captures"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	var output_directory := ProjectSettings.globalize_path(directory)
	var error := DirAccess.make_dir_recursive_absolute(output_directory)
	if error != OK:
		push_error("Could not create capture directory: " + output_directory)
		get_tree().quit(1)
		return
	_player.set_physics_process(false)
	await RenderingServer.frame_post_draw
	var path := output_directory.path_join(filename)
	error = get_viewport().get_texture().get_image().save_png(path)
	print("Capture saved: ", path)
	get_tree().quit(0 if error == OK else 1)
