class_name Day1GuardResponse
extends Node2D
## A stationary Day 1 watch: sight, timed distraction and an explicit drunken interception.

enum Role { ENTRANCE, MANSION_LURE, MANSION_GATE, DRUNKEN }
enum State { WATCHING, ALERT, DISTRACTED, CONFUSED, CLEARED, STUNNED }

@export var role: Role = Role.ENTRANCE
@export var actor: SettlementCharacter
## Assigned by the confirmed payment business, never by this component.
@export var clearance_flag: StringName
@export var encounter_event_id: String
@export_range(1.0, 1200.0) var sight_range := 260.0
@export_range(1.0, 180.0) var sight_half_angle := 55.0
@export_range(0.05, 10.0) var discovery_seconds := 1.0
@export_range(1.0, 1200.0) var hearing_range := 360.0
@export_range(0.05, 30.0) var distraction_seconds := 4.0
## Optional short back-and-forth route around the authored home position.
## Offsets are in world pixels; an empty array keeps the guard stationary.
@export var patrol_offsets: Array[Vector2] = []
@export_range(1.0, 200.0) var patrol_speed := 45.0
@export_range(0.0, 5.0, 0.1) var patrol_pause_seconds := 1.2
@export_range(0.1, 2.0, 0.05) var patrol_stall_seconds := 0.3
## A distracted guard walks toward the impact before returning to the route.
@export_range(8.0, 200.0) var distraction_walk_stop := 28.0

var state: State = State.WATCHING
var exposure := 0.0
var remaining := 0.0
var corrosion_remaining := 0.0
var detection_multiplier := 1.0
var _home_position := Vector2.ZERO
var _home_facing: PlayerController.Facing
var _captured := false
var _patrol_index := 0
var _patrol_wait := 0.0
var _patrol_stall := 0.0
var _distraction_point := Vector2.ZERO
var _feedback_enabled := false
var _sight_polygon := PackedVector2Array()
const FEEDBACK_THEME = preload("res://src/resources/ui/game_theme.tres")
const ALERT_POP_SECONDS := 0.18
var _alert_pop := 0.0

func set_feedback_enabled(enabled: bool) -> void:
	_feedback_enabled = enabled
	if not enabled:
		_sight_polygon.clear()
	queue_redraw()

func get_feedback_text() -> String:
	match state:
		State.ALERT:
			return "! 警戒 %d%%" % roundi(100.0 * exposure / discovery_seconds)
		State.DISTRACTED:
			return "分心 %.1f 秒" % remaining
		State.CONFUSED:
			return "混乱 %.1f 秒" % remaining
		State.CLEARED:
			return "已放行"
		State.STUNNED:
			return "眩晕 %.1f 秒" % remaining
	return "观察中"

func capture_checkpoint() -> void:
	_home_position = actor.global_position
	_home_facing = actor.facing
	_captured = true

func reset_response(restore_actor: bool = true) -> void:
	state = State.WATCHING
	exposure = 0.0
	remaining = 0.0
	corrosion_remaining = 0.0
	detection_multiplier = 1.0
	_alert_pop = 0.0
	_patrol_index = 0
	_patrol_wait = 0.0
	_patrol_stall = 0.0
	_distraction_point = Vector2.ZERO
	if restore_actor and _captured and is_instance_valid(actor) and not actor.is_performance_controlled():
		actor.teleport_to(_home_position)
		actor.face_direction(_home_facing)
	queue_redraw()

func set_cleared(cleared: bool) -> void:
	if cleared:
		state = State.CLEARED
		exposure = 0.0
		remaining = 0.0
		queue_redraw()
	elif state == State.CLEARED:
		reset_response(false)

func distract(impact: Vector2, seconds: float = 0.0) -> bool:
	# A coin never clears the two-guard combination or the mandatory drunken event.
	if role not in [Role.ENTRANCE, Role.MANSION_LURE] or not _available() or state in [State.CONFUSED, State.CLEARED, State.STUNNED]:
		return false
	if actor.global_position.distance_to(impact) > hearing_range:
		return false
	state = State.DISTRACTED
	exposure = 0.0
	remaining = seconds if seconds > 0.0 else distraction_seconds
	_distraction_point = impact
	_patrol_stall = 0.0
	_face_toward(impact)
	queue_redraw()
	return true

func confuse(origin: Vector2, radius: float, seconds: float) -> void:
	if role == Role.DRUNKEN or not _available() or state in [State.CLEARED, State.STUNNED] or actor.global_position.distance_to(origin) > radius:
		return
	var seconds_left := remaining if state == State.CONFUSED else 0.0
	state = State.CONFUSED
	exposure = 0.0
	remaining = maxf(seconds_left, seconds)
	_face_toward(origin)
	queue_redraw()

func stun(seconds: float) -> bool:
	if not can_receive_drink():
		return false
	remaining = maxf(remaining if state == State.STUNNED else 0.0, seconds)
	state = State.STUNNED
	exposure = 0.0
	queue_redraw()
	return true

func corrode(multiplier: float, seconds: float) -> bool:
	if not can_receive_drink():
		return false
	detection_multiplier = maxf(detection_multiplier, multiplier)
	corrosion_remaining = maxf(corrosion_remaining, seconds)
	return true

func can_receive_drink() -> bool:
	return _available() and state != State.CLEARED

func displace(motion: Vector2) -> bool:
	return can_receive_drink() and not actor.displace_by(motion).is_zero_approx()

func effective_sight_range() -> float:
	return 0.0 if state == State.STUNNED else sight_range

## Called only by the service's physics tick. Returns true on actual discovery.
func advance(delta: float, player: PlayerController, space: PhysicsDirectSpaceState2D) -> bool:
	_update_sight_feedback(player, space)
	_alert_pop = maxf(0.0, _alert_pop - delta)
	queue_redraw()
	if not _available() or state == State.CLEARED:
		_stop_walking(delta)
		return false
	corrosion_remaining = maxf(0.0, corrosion_remaining - delta)
	if corrosion_remaining <= 0.0:
		detection_multiplier = 1.0
	if state == State.DISTRACTED:
		_advance_distraction(delta)
		remaining = maxf(0.0, remaining - delta)
		if remaining <= 0.0:
			state = State.WATCHING
			_distraction_point = Vector2.ZERO
			actor.face_direction(_home_facing)
		queue_redraw()
		return false
	if state in [State.CONFUSED, State.STUNNED]:
		_stop_walking(delta)
		remaining = maxf(0.0, remaining - delta)
		if remaining <= 0.0:
			state = State.WATCHING
			actor.face_direction(_home_facing)
		queue_redraw()
		return false
	_advance_patrol(delta)
	var offset := player.global_position - actor.global_position
	var seen := offset.length() <= sight_range and (offset.is_zero_approx() or actor.get_facing_vector().dot(offset.normalized()) >= cos(deg_to_rad(sight_half_angle)))
	if seen and not offset.is_zero_approx():
		var query := PhysicsRayQueryParameters2D.create(actor.global_position, player.global_position, 1)
		query.hit_from_inside = true
		seen = space.intersect_ray(query).is_empty()
	var was_watching := exposure <= 0.0
	exposure = clampf(exposure + (delta / detection_multiplier if seen else -delta * 2.0), 0.0, discovery_seconds)
	state = State.ALERT if exposure > 0.0 else State.WATCHING
	if was_watching and exposure > 0.0:
		_alert_pop = ALERT_POP_SECONDS
	queue_redraw()
	return exposure >= discovery_seconds

func _available() -> bool:
	return is_instance_valid(actor) and actor.is_inside_tree() and actor.is_visible_in_tree() and not actor.is_performance_controlled()

func _face_toward(target: Vector2) -> void:
	var offset := target - actor.global_position
	if absf(offset.x) > absf(offset.y):
		actor.face_direction(PlayerController.Facing.RIGHT if offset.x > 0 else PlayerController.Facing.LEFT)
	elif not offset.is_zero_approx():
		actor.face_direction(PlayerController.Facing.DOWN if offset.y > 0 else PlayerController.Facing.UP)

## Short authored beat: walk to each offset, pause, turn, repeat. The service
## already ticks this once per physics frame, so no extra node or autoload.
func _advance_patrol(delta: float) -> void:
	if patrol_offsets.is_empty() or not _available():
		return
	if _patrol_wait > 0.0:
		_patrol_wait = maxf(0.0, _patrol_wait - delta)
		actor.move_direction(Vector2.ZERO, delta, patrol_speed)
		return
	var target := _home_position + patrol_offsets[_patrol_index % patrol_offsets.size()]
	var offset := target - actor.global_position
	var distance := offset.length()
	if distance <= 2.0:
		_patrol_index = (_patrol_index + 1) % patrol_offsets.size()
		_patrol_wait = patrol_pause_seconds
		actor.move_direction(Vector2.ZERO, delta, patrol_speed)
		return
	var before := actor.global_position
	actor.move_direction(offset / distance, delta, minf(patrol_speed, distance / maxf(delta, 0.001)))
	# A body that cannot advance for a moment must not wedge the route.
	if actor.global_position.distance_to(before) < 0.05:
		_patrol_stall += delta
		if _patrol_stall >= patrol_stall_seconds:
			_patrol_index = (_patrol_index + 1) % patrol_offsets.size()
			_patrol_wait = patrol_pause_seconds
			_patrol_stall = 0.0
	else:
		_patrol_stall = 0.0

## A coin does not merely freeze the guard: it walks to the sound, looks
## around, then resumes the route when the timer ends.
func _advance_distraction(delta: float) -> void:
	# Stationary fixture watches keep their exact post; authored patrol guards
	# investigate the sound before resuming the route.
	if _distraction_point == Vector2.ZERO or patrol_offsets.is_empty() or not _available():
		_stop_walking(delta)
		return
	var offset := _distraction_point - actor.global_position
	if offset.length() <= distraction_walk_stop:
		_stop_walking(delta)
		return
	var before := actor.global_position
	var step_speed := minf(patrol_speed * 1.5, offset.length() / maxf(delta, 0.001))
	actor.move_direction(offset.normalized(), delta, step_speed)
	if actor.global_position.distance_to(before) < 0.05:
		_patrol_stall += delta
		if _patrol_stall >= patrol_stall_seconds:
			_distraction_point = Vector2.ZERO
			_patrol_stall = 0.0
	else:
		_patrol_stall = 0.0

func _stop_walking(delta: float) -> void:
	if _available():
		actor.move_direction(Vector2.ZERO, delta, patrol_speed)

## Read-only geometry uses the same origin, range, angle and world layer as sight.
func _update_sight_feedback(player: PlayerController, space: PhysicsDirectSpaceState2D) -> void:
	_sight_polygon.clear()
	if not _feedback_enabled or not _available() or actor.global_position.distance_to(player.global_position) > sight_range + 320.0:
		return
	var origin := actor.global_position
	_sight_polygon.append(to_local(origin))
	var direction := actor.get_facing_vector().angle()
	for index in range(25):
		var angle := direction + deg_to_rad(lerpf(-sight_half_angle, sight_half_angle, index / 24.0))
		var endpoint := origin + Vector2.from_angle(angle) * sight_range
		var ray := PhysicsRayQueryParameters2D.create(origin, endpoint, 1)
		ray.hit_from_inside = true
		var hit := space.intersect_ray(ray)
		_sight_polygon.append(to_local(hit.get("position", endpoint)))

func _draw() -> void:
	if not _feedback_enabled or not _available():
		return
	var colors := [Color("e6c67e"), Color("ffb35c"), Color("8cdbed"), Color("f3a36a"), Color("a8dd9a"), Color("c8a5e8")]
	var alert_ratio := clampf(exposure / maxf(discovery_seconds, 0.001), 0.0, 1.0)
	var color: Color = colors[state]
	if state == State.ALERT:
		# The cone heats up as exposure fills so sight itself carries the warning.
		var watching: Color = colors[State.WATCHING]
		color = watching.lerp(Color("ff7a4d"), alert_ratio)
	if state in [State.WATCHING, State.ALERT] and _sight_polygon.size() > 3:
		var fill := 0.10 if state == State.WATCHING else 0.20 + 0.12 * alert_ratio
		draw_colored_polygon(_sight_polygon, Color(color, fill))
		draw_polyline(_sight_polygon + PackedVector2Array([_sight_polygon[0]]), Color(color, 0.45), 1.0)
	if state == State.WATCHING:
		return
	var center := to_local(actor.global_position) + actor.get_emote_offset()
	var pop := _alert_pop / ALERT_POP_SECONDS
	center.y -= roundf(4.0 * pop)
	color = color.lerp(Color.WHITE, 0.35 * pop)
	var font := FEEDBACK_THEME.default_font
	var text := get_feedback_text()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var box := Rect2(center + Vector2(-width * 0.5 - 8, -26), Vector2(width + 16, 32))
	draw_style_box(FEEDBACK_THEME.get_stylebox("panel", "PanelContainer"), box)
	draw_string(font, center + Vector2(-width * 0.5, -3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, color)
	if state in [State.ALERT, State.DISTRACTED]:
		var progress := alert_ratio if state == State.ALERT else remaining / distraction_seconds
		draw_line(box.position + Vector2(4, 29), box.position + Vector2(4 + (box.size.x - 8) * clampf(progress, 0, 1), 29), color, 2.0)
