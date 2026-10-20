extends Node
## Small scene-local idle route for townsfolk. It never claims story control:
## performances, hidden actors and modal menus stop it without extra state.

@export_range(8.0, 160.0, 4.0) var radius := 28.0
@export_range(8.0, 120.0, 2.0) var speed := 34.0
@export_range(0.2, 10.0, 0.1) var minimum_pause := 1.4
@export_range(0.2, 10.0, 0.1) var maximum_pause := 3.2
@export_range(0.05, 1.0, 0.05) var stall_seconds := 0.4

## Feet footprint shared by the map grid query and the physics fallback, so a
## candidate step is accepted by the same box the body actually occupies.
const FOOT_HALF_SIZE := Vector2(5.0, 4.0)
const PICK_ATTEMPTS := 8

var _home := Vector2.ZERO
var _target := Vector2.ZERO
var _pause := 0.0
var _stall := 0.0
var _floor: Node
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	var actor := get_parent() as PlayerController
	if actor != null:
		_home = actor.global_position
		_rng.seed = hash(actor.name)
	var settlement := get_parent() as SettlementCharacter
	if settlement != null:
		_rng.seed = hash(settlement.actor_id)
	var node := get_parent().get_parent()
	while node != null:
		if node.has_method("is_walkable_at") or node.has_method("can_stand_at"):
			_floor = node
			break
		node = node.get_parent()
	_pause = _rng.randf_range(minimum_pause, maximum_pause)

func _physics_process(delta: float) -> void:
	var actor := get_parent() as PlayerController
	if actor == null or not actor.is_visible_in_tree() or actor.is_performance_controlled():
		return
	if _pause > 0.0:
		_pause = maxf(0.0, _pause - delta)
		actor.move_direction(Vector2.ZERO, delta, speed)
		return
	if _target == Vector2.ZERO:
		_target = _pick_target()
		_stall = 0.0
	var offset := _target - actor.global_position
	if offset.length() <= 2.0:
		_finish_step(actor)
		actor.move_direction(Vector2.ZERO, delta, speed)
		return
	var before := actor.global_position
	actor.move_direction(offset / offset.length(), delta, minf(speed, offset.length() / maxf(delta, 0.001)))
	if actor.global_position.distance_to(before) < 0.05:
		_stall += delta
		if _stall >= stall_seconds:
			_finish_step(actor)
	else:
		_stall = 0.0

## Keep each idle step on the map's own walkable cells; an invalid pick simply
## falls back to the authored home instead of pushing the NPC into a wall.
func _pick_target() -> Vector2:
	for attempt in PICK_ATTEMPTS:
		var candidate := _home + Vector2.from_angle(_rng.randf_range(0.0, TAU)) * _rng.randf_range(radius * 0.35, radius)
		if _can_stand_at(candidate):
			return candidate
	return _home

## The player-facing map query reports rejected positions to the HUD, so an NPC
## detour prefers the silent variant and then confirms the spot is physically
## empty: hand-painted levels have furniture bodies but no tile passability data.
func _can_stand_at(candidate: Vector2) -> bool:
	if _floor != null:
		if _floor.has_method("is_walkable_at"):
			return _floor.is_walkable_at(candidate, FOOT_HALF_SIZE) and _space_is_clear(candidate)
		if _floor.has_method("can_stand_at"):
			return _floor.can_stand_at(candidate, FOOT_HALF_SIZE) and _space_is_clear(candidate)
	return _space_is_clear(candidate)

func _space_is_clear(point: Vector2) -> bool:
	if not is_inside_tree():
		return true
	var world := get_viewport().world_2d
	if world == null:
		return true
	var space := world.direct_space_state
	if space == null:
		return true
	var shape := RectangleShape2D.new()
	shape.size = FOOT_HALF_SIZE * 2.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1 << (PlayerController.WORLD_LAYER - 1)
	query.collide_with_areas = false
	return space.intersect_shape(query, 1).is_empty()

func _finish_step(actor: PlayerController) -> void:
	_target = Vector2.ZERO
	_pause = _rng.randf_range(minimum_pause, maximum_pause)
	_stall = 0.0
	# Stay inside the authored home area even after a collision detour.
	if actor.global_position.distance_to(_home) > radius * 1.4:
		_target = _home
