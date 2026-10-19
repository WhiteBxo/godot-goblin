class_name NavigationHUD
extends UIScreen
## A live minimap and a floor-route arrow. No chapter facts are written here.

var _level: Node2D
var _provider: Object
var _player: Node2D
var _journal: TaskJournal
var _state: Node
var _known: Callable
var _clock := 0.0
var _target := {}
var _route := PackedVector2Array()
var _enabled := true

func configure(level: Node2D, provider: Object, player: Node2D, journal: TaskJournal, state: Node, known: Callable) -> void:
	_level = level
	_provider = provider
	_player = player
	_journal = journal
	_state = state
	_known = known

func set_display_enabled(enabled: bool) -> void:
	_enabled = enabled
	_update_visibility()

func _update_visibility() -> void:
	visible = (_enabled and is_instance_valid(_state) and _state.get_business_profile() == "day1"
		and (_state.get_flag("day1.s03.exited_shop") or Day1Access.is_later_stage(_state) or _state.current_day >= 2)
		and _level is RpgChapterMap)

func _process(delta: float) -> void:
	_update_visibility()
	if not visible or not is_instance_valid(_player) or not _known.is_valid():
		return
	_clock -= delta
	if _clock <= 0.0:
		_clock = 0.2
		var known: Array[String] = _known.call()
		_target = ObjectiveNavigation.resolve(_level, _provider, _journal, known)
		var canvas: SettlementMapCanvas = $Panel/Body/Canvas
		canvas.map_data = _provider.get_map_data(known)
		canvas.map_data.view = Rect2(_player.global_position - Vector2(336, 336), Vector2(672, 672))
		var floors: Array[Rect2] = []
		var center := (_level as RpgChapterMap).world_to_cell(_player.global_position)
		for y in range(center.y - 7, center.y + 8):
			for x in range(center.x - 7, center.x + 8):
				var cell := Vector2i(x, y)
				if _level.is_cell_walkable(cell):
					floors.append(Rect2(_level.cell_to_world(cell) - Vector2(24, 24), Vector2(48, 48)))
		canvas.map_data.floor_cells = floors
		canvas.player_position = _player.global_position
		canvas.target = {"position": _target.world_position} if _target.has("world_position") else {}
		canvas.queue_redraw()
		$Panel/Body/Target.text = str(_target.get("text", "自由探索"))
		_route = _level.get_navigation_path(_player.global_position, _target.world_position) if _target.has("world_position") else PackedVector2Array()
	queue_redraw()

func _draw() -> void:
	if not visible or not _target.has("world_position") or not is_instance_valid(_player):
		return
	var waypoint: Vector2 = _target.world_position
	for point: Vector2 in _route:
		waypoint = point
		if point.distance_to(_player.global_position) >= 40.0:
			break
	var offset := waypoint - _player.global_position
	if offset.length() < 12.0:
		return
	var direction := offset.normalized()
	var player_screen := _player.get_global_transform_with_canvas().origin
	var clearance := 38.0
	if direction.y < -0.35 and _player is PlayerController:
		var head: Vector2 = _player.get_global_transform_with_canvas() * _player.get_emote_offset()
		clearance = maxf(clearance, (player_screen.y - head.y + 12.0) / -direction.y)
	var center := (player_screen + direction * clearance).clamp(Vector2(22, 22), size - Vector2(22, 22))
	var side := direction.orthogonal()
	var points := PackedVector2Array([center + direction * 10, center - direction * 6 + side * 6, center - direction * 2, center - direction * 6 - side * 6])
	draw_colored_polygon(points, get_theme_color("font_color", "Warning"))
	draw_polyline(points + PackedVector2Array([points[0]]), get_theme_color("font_color", "Label"), 1.0)

func get_target() -> Dictionary:
	return _target.duplicate(true)
