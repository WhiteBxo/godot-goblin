class_name QuestPointer
extends Control
## A screen-space cursor for the current objective.
##
## It is deliberately not a world sprite: the shop renders near 0.4x, where a
## world-space arrow shrinks with the camera and cannot be drawn once the target
## leaves the viewport. One instance covers the whole frame — a small diamond on
## a visible target, a paper chip pinned to the edge when it is not.
##
## The arrow retires within interaction range, where WorldPrompt takes over.
## A tracked NPC keeps a separate screen-space identity above its head.

const MARGIN := 22.0
const MARKER_LIFT := 44.0
const ARRIVE_RADIUS := 64.0
const CELL := 48.0
const TURN_RATE := 12.0

var _game: Node
var _journal: TaskJournal
var _level: Node2D
var _player: Node2D
var _lookup: Callable
var _known: Callable
var _current_location: Callable
var _target := {}
var _heading := 0.0
var _heading_ready := false
var _enabled := true

@onready var _marker: Control = $Marker
@onready var _chip: PanelContainer = $Chip
@onready var _arrow: Control = $Chip/Row/Arrow
@onready var _name: Label = $Chip/Row/Lines/Name
@onready var _distance: Label = $Chip/Row/Lines/Distance
@onready var _actor_name: PanelContainer = $ActorName
@onready var _actor_text: Label = $ActorName/Text

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	_arrow.draw.connect(_draw_arrow)
	_hide_all()
	set_process(false)

## level and player arrive already placed by the host; the callables keep this
## node out of MainGame's node hierarchy and out of the task business.
func configure(game: Node, journal: TaskJournal, level: Node2D, player: Node2D,
		point_lookup: Callable, known: Callable, current_location: Callable) -> void:
	_game = game
	_level = level
	_player = player
	_lookup = point_lookup
	_known = known
	_current_location = current_location
	if is_instance_valid(_journal) and _journal.projection_changed.is_connected(_resolve):
		_journal.projection_changed.disconnect(_resolve)
	_journal = journal
	if is_instance_valid(_journal):
		_journal.projection_changed.connect(_resolve)
	_resolve()
	set_process(true)

func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		_hide_all()

func get_target() -> Dictionary:
	return _target.duplicate(true)

func is_pointing() -> bool:
	return _chip.visible or _marker.visible or _actor_name.visible

func is_actor_name_visible() -> bool:
	return _actor_name.visible

func _resolve() -> void:
	_target = {}
	if not is_instance_valid(_journal) or not is_instance_valid(_level) or not is_instance_valid(_player):
		_hide_all()
		return
	var task := _journal.get_current_main_task()
	var location: String = str(_current_location.call()) if _current_location.is_valid() else ""
	_target = TaskGuidance.resolve(task, _level, _player, _lookup, _known, location)
	if _target.is_empty():
		_hide_all()
		return
	_name.text = str(_target.get("label", ""))
	_actor_text.text = _name.text
	_actor_name.hide()
	_name.visible = not _name.text.is_empty()
	_apply_hidden_flag()

## Session option: the cursor can be switched off without touching the task.
func _apply_hidden_flag() -> void:
	var state := get_node_or_null("/root/GameState")
	if state != null and state.get_flag("ui.quest_pointer_hidden"):
		set_enabled(false)

func _process(delta: float) -> void:
	if not _enabled or _target.is_empty() or _blocked():
		_hide_all()
		return
	if not is_instance_valid(_player):
		_hide_all()
		return
	if _target.get("source") == "actor":
		var point: Variant = _target.get("node")
		if not is_instance_valid(point) or not point is Node2D or not point.is_visible_in_tree():
			_hide_all()
			return
	var world := _world_position()
	var distance := _player.global_position.distance_to(world)
	var screen := get_viewport().get_canvas_transform() * world
	var limit := get_viewport_rect().size
	var safe := Rect2(Vector2.ZERO, limit).grow(-MARGIN)
	# Task targets keep their identity readable even when the E capsule takes over.
	# These are quest labels, never a second interaction selector or NPC name list.
	_actor_name.visible = safe.has_point(screen) and _target.get("source") == "actor" and not _actor_text.text.is_empty()
	if _actor_name.visible:
		var name_size := _actor_name.get_combined_minimum_size()
		_actor_name.size = name_size
		_actor_name.position = Vector2(
			clampf(screen.x - name_size.x * 0.5, MARGIN, maxf(MARGIN, limit.x - name_size.x - MARGIN)),
			maxf(MARGIN, screen.y - MARKER_LIFT - name_size.y - 28.0)).round()
	if distance <= ARRIVE_RADIUS:
		_chip.hide()
		_marker.hide()
		return
	if safe.has_point(screen):
		if _actor_name.visible:
			_chip.hide()
			_marker.hide()
		else:
			_show_marker(screen, limit)
		return
	_show_chip(screen, distance, limit, delta)

## A moving NPC is re-read every frame; a static anchor keeps its snapshot.
func _world_position() -> Vector2:
	var node: Variant = _target.get("node")
	if node is Node2D and is_instance_valid(node):
		return node.global_position
	return _target.get("position", Vector2.ZERO)

func _blocked() -> bool:
	if get_tree().paused:
		return true
	# Only a player that answers the question can lock the cursor; a bare Node2D
	# in a test fixture simply has no movement gate.
	var movable: Variant = _player.get("movement_enabled") if is_instance_valid(_player) else null
	if movable is bool and not movable:
		return true
	if not is_instance_valid(_game):
		return false
	if _game.has_method("get_ui_manager"):
		var ui: UIManager = _game.get_ui_manager()
		if is_instance_valid(ui) and (ui.has_modal() or ui.is_open(ScreenIds.MAP)
				or ui.is_open(ScreenIds.CHAPTER_ACTIONS)):
			return true
	if _game.has_method("get_dialogue_manager"):
		var dialogue: DialogueManager = _game.get_dialogue_manager()
		if is_instance_valid(dialogue) and dialogue.is_active():
			return true
	return false

## The marker sits just above the target itself.
func _show_marker(screen: Vector2, limit: Vector2) -> void:
	_chip.visible = false
	_marker.visible = true
	var size := _marker.size
	var point := screen + Vector2(0.0, -MARKER_LIFT) - size * 0.5
	point.x = clampf(point.x, MARGIN, maxf(MARGIN, limit.x - size.x - MARGIN))
	point.y = clampf(point.y, MARGIN, maxf(MARGIN, limit.y - size.y - MARGIN))
	_marker.position = point.round()
	_marker.queue_redraw()

## The chip is pinned to the safe rectangle and turns to face the target.
func _show_chip(screen: Vector2, distance: float, limit: Vector2, delta: float) -> void:
	_marker.visible = false
	_chip.visible = true
	var center := limit * 0.5
	var wanted := (screen - center).angle()
	if not _heading_ready:
		_heading = wanted
		_heading_ready = true
	else:
		_heading = lerp_angle(_heading, wanted, 1.0 - exp(-TURN_RATE * delta))
	var size := _chip.get_combined_minimum_size()
	_chip.size = size
	var edge := _edge_point(center, Rect2(Vector2.ZERO, limit).grow(-MARGIN), _heading)
	var point := edge - size * 0.5
	point.x = clampf(point.x, MARGIN, maxf(MARGIN, limit.x - size.x - MARGIN))
	point.y = clampf(point.y, MARGIN, maxf(MARGIN, limit.y - size.y - MARGIN))
	_chip.position = point.round()
	_arrow.pivot_offset = _arrow.size * 0.5
	_arrow.rotation = _heading
	_arrow.queue_redraw()
	_distance.text = "%d 步" % maxi(1, roundi(distance / CELL))

## Where a ray from the centre leaves the safe rectangle.
func _edge_point(center: Vector2, safe: Rect2, angle: float) -> Vector2:
	var direction := Vector2.from_angle(angle)
	var half := safe.size * 0.5
	var reach_x := INF if is_zero_approx(direction.x) else half.x / absf(direction.x)
	var reach_y := INF if is_zero_approx(direction.y) else half.y / absf(direction.y)
	return center + direction * minf(reach_x, reach_y)

func _hide_all() -> void:
	_chip.visible = false
	_marker.visible = false
	_actor_name.visible = false
	_heading_ready = false

## The marker sits on the world itself, so it is a scrap of paper with an ink
## rim: readable on a dark floor and on a pale one.
func _draw_marker() -> void:
	var middle := _marker.size * 0.5
	var points := PackedVector2Array([
		middle + Vector2(0.0, -7.0), middle + Vector2(7.0, 0.0),
		middle + Vector2(0.0, 7.0), middle + Vector2(-7.0, 0.0)])
	_marker.draw_colored_polygon(points, UITokens.PAPER)
	var outline := points.duplicate()
	outline.append(points[0])
	_marker.draw_polyline(outline, UITokens.INK, 1.0)

## A flat chevron on the paper chip: the surface already separates it from the
## world, so an outline would only blunt the tip.
func _draw_arrow() -> void:
	var points := PackedVector2Array([
		Vector2(18.0, 10.0), Vector2(4.0, 3.0), Vector2(10.0, 10.0), Vector2(4.0, 17.0)])
	_arrow.draw_colored_polygon(points, UITokens.ACCENT)
