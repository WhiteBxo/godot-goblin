extends Node
## Independent art/playability trial. Production entry and story state are untouched.

const STREET := "res://src/levels/disappeared_street/disappeared_street_map.tscn"
const INTERIOR := preload("res://src/levels/milkTea/milk_tea_shop.tscn")
var _level: Node2D
var _inside := false
var _changing := false
var _overview := false
var _ui: ShopUI
var _manager: UIManager
var _interaction: ShopInteraction
var _transition: ScreenTransition
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
	_manager = UIManager.new()
	$Systems.add_child(_manager)
	_manager.configure({&"hud": $HudLayer, &"popup": $PopupLayer, &"pause": $PauseLayer})
	var pause: PauseMenu = preload("res://src/UI/pause/pause_menu.tscn").instantiate()
	$PauseLayer.add_child(pause)
	_manager.register_screen(&"pause", pause, &"pause", true)
	pause.resume_requested.connect(func() -> void: _manager.set_paused(false))
	_ui = preload("res://src/UI/milk_tea/shop_ui.tscn").instantiate()
	_ui.help_text = "消失的街道 · WASD 移动 · E 交互 · M 全景 · P 暂停"
	_ui.close_text = "继续探索  [Esc]"
	$HudLayer.add_child(_ui)
	_ui.set_popup_layer($PopupLayer)
	_ui.bind_manager(_manager)
	_interaction = ShopInteraction.new()
	_interaction.name = "StreetInteraction"
	$Systems.add_child(_interaction)
	_transition = preload("res://src/UI/screen_transition/screen_transition.tscn").instantiate()
	$TransitionLayer.add_child(_transition)
	_manager.modal_changed.connect(_refresh_lock)
	_install_level(false)
	var feedback := InteractionFeedback.new()
	$World/EffectRoot.add_child(feedback)
	feedback.configure(_interaction)
	get_viewport().size_changed.connect(_fit_overview)
	if "--overview" in OS.get_cmdline_user_args():
		set_overview(true)

func get_player() -> ShopPlayer:
	return _player

func get_active_level() -> Node2D:
	return _level

func get_interaction_ui() -> ShopUI:
	return _ui

func is_changing_level() -> bool:
	return _changing

func is_inside_shop() -> bool:
	return _inside

func _route_interaction(id: StringName) -> Error:
	if id != &"shop_door" and id != &"street_door":
		return ERR_DOES_NOT_EXIST
	if _changing or _overview or _manager.has_modal():
		return ERR_BUSY
	_changing = true
	_refresh_lock()
	_switch_level.call_deferred(not _inside)
	return OK

func _switch_level(inside: bool) -> void:
	var out_action := _transition.fade_out(0.25)
	if not out_action.is_finished():
		await out_action.finished
	if out_action.result != TransitionAction.Result.COMPLETED:
		_changing = false
		_refresh_lock()
		return
	# Disconnect before freeing points; retain the player, UI and transition host.
	_interaction.configure(_player, _ui, [], _route_interaction)
	$World/LevelRoot.remove_child(_level)
	_level.queue_free()
	_install_level(inside)
	# Wait for the new map's Area2D overlaps before accepting another key press.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var in_action := _transition.fade_in(0.25)
	if not in_action.is_finished():
		await in_action.finished
	_changing = false
	_refresh_lock()

func _install_level(inside: bool) -> void:
	_inside = inside
	_level = INTERIOR.instantiate() if inside else load(STREET).instantiate()
	$World/LevelRoot.add_child(_level)
	var points: Array[InteractionPoint] = _level.get_interaction_points()
	if inside:
		var exit: InteractionPoint = preload("res://src/gameplay/interaction/interaction_point.tscn").instantiate()
		exit.name = "ReturnToStreet"
		exit.interaction_id = &"street_door"
		exit.display_name = "走出奶茶店"
		exit.position = Vector2(1120, 685)
		_level.add_child(exit)
		exit.get_node("Label").hide()
		exit.get_node("Marker").hide()
		points.append(exit)
		_player.global_position = _level.to_global(Vector2(1120, 640))
	else:
		_player.global_position = _level.get_spawn_position()
	_player.set_floor_query(Callable() if inside else _level.can_stand_at)
	for point: InteractionPoint in points:
		point.get_node("Label").hide()
		point.get_node("Marker").hide()
	_player.velocity = Vector2.ZERO
	_player.configure_camera(_level.get_camera_bounds())
	_interaction.configure(_player, _ui, points, _route_interaction)
	_refresh_lock()

func _refresh_lock() -> void:
	var enabled := not _changing and not _overview and not _manager.has_modal()
	_player.set_movement_enabled(enabled)
	_interaction.set_input_enabled(enabled)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or _changing or _manager.has_modal():
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
		_player.camera.reset_smoothing()
	_refresh_lock()

func _fit_overview() -> void:
	if not _overview:
		return
	var bounds: Rect2 = _level.get_camera_bounds()
	var available := get_viewport().get_visible_rect().size - Vector2(16, 48)
	_overview_camera.global_position = bounds.get_center()
	_overview_camera.zoom = Vector2.ONE * minf(available.x / bounds.size.x, available.y / bounds.size.y)
	_overview_camera.force_update_scroll()
