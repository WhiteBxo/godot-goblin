class_name NavigationHUD
extends UIScreen
## A live minimap and a floor-route arrow. No chapter facts are written here.

const POLL_SECONDS := 0.2
## Floor ring around the player, 15 x 15 cells.
const FLOOR_RADIUS := 7

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
var _floor_cell := Vector2i.MAX
var _route_cell := Vector2i.MAX
var _route_target := Vector2.INF
var _painted_player := Vector2.INF

@onready var _canvas: SettlementMapCanvas = $Panel/Body/Canvas
@onready var _target_label: Label = $Panel/Body/Target

func configure(level: Node2D, provider: Object, player: Node2D, journal: TaskJournal, state: Node, known: Callable) -> void:
	_level = level
	_provider = provider
	_player = player
	_journal = journal
	_state = state
	_known = known
	if is_instance_valid(_state) and not _state.state_changed.is_connected(_update_visibility):
		_state.state_changed.connect(_update_visibility)
	_update_visibility()

func _exit_tree() -> void:
	if is_instance_valid(_state) and _state.state_changed.is_connected(_update_visibility):
		_state.state_changed.disconnect(_update_visibility)

func set_display_enabled(enabled: bool) -> void:
	_enabled = enabled
	_update_visibility()

## Visibility only depends on session facts, so it follows state_changed instead
## of re-reading flags every frame.
func _update_visibility() -> void:
	visible = (_enabled and is_instance_valid(_state) and _state.get_business_profile() == "day1"
		and (_state.get_flag("day1.s03.exited_shop") or Day1Access.is_later_stage(_state) or _state.current_day >= 2)
		and _level is RpgChapterMap)

func _process(delta: float) -> void:
	if not visible or not is_instance_valid(_player) or not _known.is_valid():
		return
	# The arrow follows the player, so movement needs a repaint; standing still
	# only needs the slow objective poll.
	if _player.global_position != _painted_player:
		_painted_player = _player.global_position
		queue_redraw()
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = POLL_SECONDS
	_poll()

func _poll() -> void:
	var known: Array[String] = _known.call()
	_target = ObjectiveNavigation.resolve(_level, _provider, _journal, known)
	var center := (_level as RpgChapterMap).world_to_cell(_player.global_position)
	var target_position: Vector2 = _target.get("world_position", Vector2.INF)
	_canvas.map_data = _provider.get_map_data(known)
	_canvas.map_data.view = Rect2(_player.global_position - Vector2(336, 336), Vector2(672, 672))
	# The floor ring and the route only change when the player crosses a cell or
	# the objective moves; probing 225 cells every tick would be wasted work.
	if center != _floor_cell:
		_floor_cell = center
		_canvas.map_data.floor_cells = _floor_cells(center)
	if center != _route_cell or target_position != _route_target:
		_route_cell = center
		_route_target = target_position
		_route = _level.get_navigation_path(_player.global_position, target_position) if _target.has("world_position") else PackedVector2Array()
	_canvas.player_position = _player.global_position
	_canvas.target = {"position": target_position} if _target.has("world_position") else {}
	_canvas.queue_redraw()
	_target_label.text = str(_target.get("text", "自由探索"))
	queue_redraw()

func _floor_cells(center: Vector2i) -> Array[Rect2]:
	var floors: Array[Rect2] = []
	for y in range(center.y - FLOOR_RADIUS, center.y + FLOOR_RADIUS + 1):
		for x in range(center.x - FLOOR_RADIUS, center.x + FLOOR_RADIUS + 1):
			var cell := Vector2i(x, y)
			if _level.is_cell_walkable(cell):
				floors.append(Rect2(_level.cell_to_world(cell) - Vector2(24, 24), Vector2(48, 48)))
	return floors

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
