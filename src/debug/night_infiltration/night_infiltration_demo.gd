extends Node
## Independent F6 composition and movement review, using the existing player and UI.

var _level: NightInfiltrationMap
var _overview := false
var _ui: ShopUI
var _interaction: ShopInteraction
@onready var _player: FloorAwareShopPlayer = $World/EntityRoot/Player
@onready var _overview_camera: Camera2D = $World/OverviewCamera

func _ready() -> void:
	DebugRuntime.apply_release_policy(get_tree())
	if not OS.has_feature("debug"):
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	var probe := get_node_or_null("/root/MCPRuntimeProbe")
	if probe != null:
		probe.process_mode = Node.PROCESS_MODE_DISABLED
	_level = preload("res://src/levels/night_infiltration/night_infiltration_map.tscn").instantiate()
	$World/LevelRoot.add_child(_level)
	_player.global_position = _level.get_spawn_position()
	_player.set_floor_query(_level.can_stand_at)
	_player.configure_camera(_level.get_camera_bounds())
	_ui = preload("res://src/UI/milk_tea/shop_ui.tscn").instantiate()
	_ui.help_text = "夜间潜入 · WASD 移动 · E 查看／开门 · M 全景"
	_ui.close_text = "继续探索  [Esc]"
	$HudLayer.add_child(_ui)
	_ui.set_popup_layer($PopupLayer)
	_ui.opened.connect(_refresh_lock)
	_ui.closed.connect(_refresh_lock)
	_interaction = ShopInteraction.new()
	$Systems.add_child(_interaction)
	_interaction.configure(_player, _ui, _level.get_interaction_points(), _route_interaction)
	get_viewport().size_changed.connect(_fit_overview)
	if "--overview" in OS.get_cmdline_user_args():
		set_overview(true)
	_capture_if_requested.call_deferred()

func get_player() -> ShopPlayer:
	return _player

func get_active_level() -> NightInfiltrationMap:
	return _level

func get_interaction_ui() -> ShopUI:
	return _ui

func _route_interaction(id: StringName) -> Error:
	if id == &"elder_door":
		_level.open_elder_door()
		for point: InteractionPoint in _level.get_interaction_points():
			if point.interaction_id == &"elder_door":
				point.interaction_enabled = false
		return OK
	if id == &"public_street":
		_level.request_public_street()
	return ERR_DOES_NOT_EXIST

func _refresh_lock() -> void:
	var enabled := not _overview and not _ui.is_open()
	_player.set_movement_enabled(enabled)
	_interaction.set_input_enabled(enabled)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or _ui.is_open():
		return
	if event.is_action_pressed("debug_toggle_overview"):
		set_overview(not _overview)
		get_viewport().set_input_as_handled()

func set_overview(enabled: bool) -> void:
	_overview = enabled
	_overview_camera.enabled = enabled
	if enabled:
		_fit_overview()
		_overview_camera.make_current()
	else:
		_player.camera.make_current()
		_player.camera.reset_camera()
	_refresh_lock()

func _fit_overview() -> void:
	if not _overview:
		return
	var bounds := _level.get_camera_bounds()
	var available := get_viewport().get_visible_rect().size - Vector2(12, 42)
	_overview_camera.global_position = bounds.get_center()
	_overview_camera.zoom = Vector2.ONE * minf(available.x / bounds.size.x, available.y / bounds.size.y)
	_overview_camera.force_update_scroll()

func _capture_if_requested() -> void:
	var path := ""
	var clean := "--clean" in OS.get_cmdline_user_args()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			path = arg.trim_prefix("--capture=")
		if arg.begins_with("--anchor="):
			var anchor := _level.get_story_anchor(StringName(arg.trim_prefix("--anchor=")))
			if anchor != null:
				_player.global_position = anchor.global_position
				if anchor.global_position.y < 350:
					_level.open_elder_door()
		if arg.begins_with("--at="):
			var coordinates := arg.trim_prefix("--at=").split(",")
			if coordinates.size() == 2:
				_player.global_position = Vector2(float(coordinates[0]), float(coordinates[1]))
				_level.open_elder_door()
	if path.is_empty():
		return
	var capture_view: SubViewport
	if clean:
		if "--show-player" not in OS.get_cmdline_user_args():
			_player.hide()
		capture_view = SubViewport.new()
		capture_view.size = Vector2i(1678, 937)
		capture_view.world_2d = get_viewport().world_2d
		capture_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(capture_view)
		var camera := Camera2D.new()
		camera.position = Vector2(839, 468.5)
		capture_view.add_child(camera)
		camera.make_current()
	for frame in range(30):
		await get_tree().physics_frame
	if not clean and not _overview:
		_player.camera.reset_camera()
	await RenderingServer.frame_post_draw
	var texture := capture_view.get_texture() if clean else get_viewport().get_texture()
	var error := texture.get_image().save_png(path)
	print("NIGHT_CAPTURE: ", error)
	var tree := get_tree()
	# Queue deletion from outside this node's coroutine, so scene disposal completes.
	tree.create_timer(0.15).timeout.connect(tree.quit.bind(error))
	queue_free()
