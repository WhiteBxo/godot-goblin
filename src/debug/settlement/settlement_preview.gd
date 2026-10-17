extends Node
## Map inspection stays outside the production map and story systems.

const LAYOUT_PATH := "res://src/levels/settlement/settlement_layout.json"
const NIGHT_FLAG := "world.phase.night"
var _game: MainGame
var _level: SettlementMap
var _player: ShopPlayer
var _state: Node
var _overview_camera: Camera2D
var _overview := false
var _labels: Node2D
var _routes: Node2D
var _status: Label
var _panel: PanelContainer
var _debug_layer: CanvasLayer
var _route_index := 0
var _route_names: Array[String] = ["隐藏路线", "第一天动线", "第二天动线", "河岸补给线"]

func configure(game: MainGame, debug_layer: CanvasLayer) -> void:
	_game = game
	_debug_layer = debug_layer

func _ready() -> void:
	if not DebugRuntime.is_enabled():
		queue_free()
		return
	_level = _game.get_active_level() as SettlementMap
	_player = _game.get_player() as ShopPlayer
	_state = get_node_or_null("/root/GameState")
	_labels = Node2D.new()
	_labels.name = "OverviewLabels"
	_labels.z_index = 100
	_level.add_child(_labels)
	var font: Font = load("res://assets/fonts/fusion_pixel/fusion-pixel-12px-monospaced-zh_hans.otf.woff2")
	for district: Node2D in _level.get_node("Districts").get_children():
		var label := Label.new()
		label.text = str(district.get_meta("display_name", district.name))
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 36)
		label.add_theme_color_override("font_color", Color("f2dfac"))
		label.add_theme_color_override("font_outline_color", Color("171923"))
		label.add_theme_constant_override("outline_size", 8)
		label.position = district.position + Vector2(450, 950)
		label.scale = Vector2(5, 5)
		_labels.add_child(label)
	_labels.hide()
	_routes = Node2D.new()
	_routes.name = "RouteOverlays"
	_routes.z_index = 90
	_level.add_child(_routes)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	var colors: Array[Color] = [Color("efcc78"), Color("d899c0"), Color("82cbb8")]
	var index := 0
	for key: String in ["day1", "day2", "supply"]:
		var line := Line2D.new()
		line.name = key
		line.width = 22
		line.default_color = colors[index]
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		for point: Array in data.routes[key]:
			line.add_point(Vector2(point[0], point[1]))
		line.hide()
		_routes.add_child(line)
		index += 1
	_overview_camera = Camera2D.new()
	_overview_camera.name = "OverviewCamera"
	_overview_camera.enabled = false
	_level.add_child(_overview_camera)
	var panel := PanelContainer.new()
	_panel = panel
	panel.position = Vector2(8, 8)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.92)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	_debug_layer.add_child(panel)
	_status = Label.new()
	_status.add_theme_font_override("font", font)
	_status.add_theme_font_size_override("font_size", 12)
	panel.add_child(_status)
	get_viewport().size_changed.connect(_fit_overview)
	var args := OS.get_cmdline_user_args()
	if "--overview" in args:
		set_overview(true)
	if "--route-day1" in args:
		set_route(1)
	if "--route-day2" in args:
		set_route(2)

func _process(_delta: float) -> void:
	if is_instance_valid(_status):
		_status.text = "%s  ·  WASD 移动 / E 查看\nM 全图 / 跟随  ·  Tab 切换动线  ·  F4 %s  ·  %s" % [
			_level.get_zone_at(_player.global_position), _phase_text(), _route_names[_route_index]]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if _game.get_dialogue_manager().is_active() or _game.get_story_director().is_busy():
		return
	var ui := _game.get_interaction_ui()
	if ui.is_open():
		return
	if event.is_action_pressed("debug_toggle_overview"):
		set_overview(not _overview)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_settlement_routes"):
		set_route((_route_index + 1) % 4)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_toggle_night"):
		toggle_night()
		get_viewport().set_input_as_handled()

## Use the same atomic phase transition as formal gameplay.
func toggle_night() -> void:
	if is_instance_valid(_state):
		if DayPhase.is_night(_state):
			DayPhase.enter_day(_state)
		else:
			DayPhase.enter_night(_state)

func _phase_text() -> String:
	return "夜晚" if DayPhase.is_night(_state) else "白天"

func _exit_tree() -> void:
	for node: Node in [_labels, _routes, _overview_camera, _panel]:
		if is_instance_valid(node):
			node.queue_free()

func set_route(index: int) -> void:
	_route_index = clampi(index, 0, 3)
	for child: Node2D in _routes.get_children():
		child.visible = child.get_index() == _route_index - 1

func set_overview(enabled: bool) -> void:
	_overview = enabled
	_labels.visible = enabled
	_player.set_movement_enabled(not enabled)
	if enabled:
		_overview_camera.enabled = true
		_fit_overview()
		_overview_camera.make_current()
	else:
		_overview_camera.enabled = false
		_player.camera.make_current()
		_player.camera.reset_smoothing()

func _fit_overview() -> void:
	var bounds := _level.get_world_bounds()
	var available := get_viewport().get_visible_rect().size - Vector2(36, 60)
	_overview_camera.global_position = bounds.get_center()
	_overview_camera.zoom = Vector2.ONE * minf(available.x / bounds.size.x, available.y / bounds.size.y)
	_overview_camera.force_update_scroll()
