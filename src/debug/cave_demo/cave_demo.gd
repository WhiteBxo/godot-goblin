extends "res://src/core/main.gd"

const ORIGINAL_LAYOUT := "res://src/levels/cave/cave_layout_original.json"

func _ready() -> void:
	if "--original-layout" in OS.get_cmdline_user_args():
		cave_map.load_error = cave_map.load_layout(ORIGINAL_LAYOUT)
	super._ready()
	if cave_map.load_error != OK:
		return
	set_wall_mode(CaveMap.WallMode.TEXTURED)
	print("Cave ready: %d walkable cells, %d river cells, %d wall conflicts" % [
		cave_map.walkable_cells.size(), cave_map.river_layer.get_used_cells().size(), cave_map.walls.conflicts.size()
	])
	_setup_capture_mode()

func set_wall_mode(mode: int) -> void:
	cave_map.set_wall_mode(mode)
	hud.set_hint("WASD / 方向键移动   F2 切换墙体   M 全图\n当前：%s   墙高 %dpx" % [
		cave_map.get_wall_mode_name(), cave_map.walls.wall_height
	])

func toggle_overview() -> void:
	if player.overview_enabled:
		player.follow_player()
	else:
		player.show_overview(cave_map.get_world_bounds().grow(64.0), get_viewport_rect().size)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_cycle_walls"):
		set_wall_mode((cave_map.wall_mode + 1) % 3)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_toggle_overview"):
		toggle_overview()
		get_viewport().set_input_as_handled()

func _setup_capture_mode() -> void:
	var args := OS.get_cmdline_user_args()
	if "--capture-walls-map" in args:
		set_wall_mode(CaveMap.WallMode.FLAT)
		player.show_overview(cave_map.get_world_bounds().grow(64.0), get_viewport_rect().size)
		_capture_viewport("walls_overview.png")
	elif "--capture-walls-top" in args:
		player.global_position = cave_map.cell_to_world(Vector2(78.5, -1.5))
		player.center_camera_on(cave_map.cell_to_world(Vector2(78.5, 1.5)))
		_capture_viewport("walls_top_bypass.png")
	elif "--capture-walls-junction" in args:
		player.global_position = cave_map.cell_to_world(Vector2(62.5, 43.0))
		_capture_viewport("walls_junction.png")
	elif "--capture-walls-river" in args:
		player.global_position = cave_map.cell_to_world(Vector2(15.5, 52.5))
		_capture_viewport("walls_river.png")
	elif "--capture-atlas-compare" in args:
		_capture_atlas_comparison()

func _capture_atlas_comparison() -> void:
	cave_map.hide()
	player.hide()
	hud.hide()
	var comparison := CanvasLayer.new()
	add_child(comparison)
	_add_comparison_panel(comparison, load("res://assets/map/cave/cave_floor_atlas.png"), "原始图集", Vector2(28.0, 90.0))
	_add_comparison_panel(comparison, load("res://assets/map/cave/cave_floor_processed.png"), "预处理图集", Vector2(505.0, 90.0))
	_capture_viewport("atlas_processing_comparison.png")

func _add_comparison_panel(parent: CanvasLayer, texture: Texture2D, title: String, position: Vector2) -> void:
	var label := Label.new()
	label.position = position
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 18)
	label.text = title
	parent.add_child(label)
	var preview := TextureRect.new()
	preview.position = position + Vector2(0.0, 34.0)
	preview.size = Vector2(420.0, 420.0)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.texture = texture
	parent.add_child(preview)

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
	player.set_physics_process(false)
	await RenderingServer.frame_post_draw
	var path := output_directory.path_join(filename)
	error = get_viewport().get_texture().get_image().save_png(path)
	print("Capture saved: ", path)
	get_tree().quit(0 if error == OK else 1)
