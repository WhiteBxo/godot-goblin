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

var state: State = State.WATCHING
var exposure := 0.0
var remaining := 0.0
var corrosion_remaining := 0.0
var detection_multiplier := 1.0
var _home_position := Vector2.ZERO
var _home_facing: PlayerController.Facing
var _captured := false

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
	queue_redraw()
	if not _available() or state == State.CLEARED:
		return false
	corrosion_remaining = maxf(0.0, corrosion_remaining - delta)
	if corrosion_remaining <= 0.0:
		detection_multiplier = 1.0
	if state in [State.DISTRACTED, State.CONFUSED, State.STUNNED]:
		remaining = maxf(0.0, remaining - delta)
		if remaining <= 0.0:
			state = State.WATCHING
			actor.face_direction(_home_facing)
		queue_redraw()
		return false
	var offset := player.global_position - actor.global_position
	var seen := offset.length() <= sight_range and (offset.is_zero_approx() or actor.get_facing_vector().dot(offset.normalized()) >= cos(deg_to_rad(sight_half_angle)))
	if seen and not offset.is_zero_approx():
		var query := PhysicsRayQueryParameters2D.create(actor.global_position, player.global_position, 1)
		query.hit_from_inside = true
		seen = space.intersect_ray(query).is_empty()
	exposure = clampf(exposure + (delta / detection_multiplier if seen else -delta * 2.0), 0.0, discovery_seconds)
	state = State.ALERT if exposure > 0.0 else State.WATCHING
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

func _draw() -> void:
	if not is_instance_valid(actor) or not actor.is_visible_in_tree() or state == State.WATCHING:
		return
	var colors := [Color.WHITE, Color.YELLOW, Color.SKY_BLUE, Color.ORANGE_RED, Color.GREEN, Color.MEDIUM_PURPLE]
	var center := to_local(actor.global_position) + actor.get_emote_offset()
	draw_circle(center, 7.0, colors[state])
	if state == State.ALERT:
		draw_arc(center, 11.0, -PI * 0.5, -PI * 0.5 + TAU * exposure / discovery_seconds, 24, Color.RED, 3.0)
