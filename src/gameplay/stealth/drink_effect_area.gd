class_name DrinkEffectArea
extends Node2D
## Service-driven physics time: no independent timers survive pause or retry.

var payload: Dictionary = {}
var remaining := 0.0
var armed := false
var finished := false
var affected := false
var confusion_created := false
var pulse_count := 0
var attached_guard: Day1GuardResponse
var _wait := 0.0
var _pulse := 0.0
var _entered := {}
var _distance_scale := 1.0
var _cell := 1.0
var _side := 1.0
var _max_duration := 1.0
var _max_cells := 1.0
var _modifiers: Dictionary = {}
var _effects: Dictionary = {}

func configure(parameters: Dictionary, distance_scale: float = 1.0) -> void:
	payload = parameters.duplicate(true)
	_distance_scale = distance_scale
	if payload.is_empty():
		# A historical cup without throw parameters must not become a live zero
		# timer that keeps pulsing and querying physics forever.
		finished = true
		remaining = 0.0
		return
	_cell = float(payload.cell) * _distance_scale
	_side = float(payload.area_cells) * _cell
	_max_duration = float(payload.max_duration)
	_max_cells = float(payload.max_area_cells)
	remaining = float(payload.duration)
	_modifiers = payload.modifiers
	_effects = payload.effects
	armed = _modifiers.has("mine")
	_wait = float(_modifiers.get("mine", {}).get("arm_timeout", 0.0))
	_pulse = float(_effects.get("lure", {}).get("pulse_seconds", 1.0))
	queue_redraw()

func is_silent() -> bool:
	return _modifiers.get("phantom", {}).get("silent", false)

func ignores_walls() -> bool:
	return _modifiers.get("phantom", {}).get("ignore_walls", false)

func contains_point(point: Vector2, side: float = -1.0) -> bool:
	var offset := (point - global_position).abs()
	var half := (side if side > 0.0 else _side) * 0.5
	return offset.x <= half and offset.y <= half

func reaches(point: Vector2, space: PhysicsDirectSpaceState2D, exclude: Array[RID] = []) -> bool:
	if ignores_walls() or global_position.is_equal_approx(point):
		return true
	var query := PhysicsRayQueryParameters2D.create(global_position, point, 1, exclude)
	query.hit_from_inside = true
	return space.intersect_ray(query).is_empty()

func advance(delta: float, setup: Day1StealthSetup, space: PhysicsDirectSpaceState2D) -> void:
	if finished:
		return
	if is_instance_valid(attached_guard) and attached_guard.can_receive_drink():
		global_position = attached_guard.actor.global_position
	var active_delta := delta
	if armed:
		_wait -= delta
		var trigger_side := minf(_max_cells, float(_modifiers.mine.arm_trigger_cells) * int(_modifiers.mine.stacks)) * _cell
		var triggered := false
		for guard: Day1GuardResponse in setup.guards:
			if guard.can_receive_drink() and contains_point(guard.actor.global_position, trigger_side) and reaches(guard.actor.global_position, space):
				triggered = true
		if not triggered and _wait > 0.0:
			queue_redraw()
			return
		if not triggered:
			active_delta = maxf(0.0, -_wait)
		armed = false
	# Clamp the final partial tick so corrosion never deals a frame of extra damage.
	var elapsed := minf(active_delta, remaining)
	_apply(elapsed, setup, space)
	if finished:
		return
	if is_instance_valid(attached_guard) and attached_guard.can_receive_drink():
		global_position = attached_guard.actor.global_position
	remaining = maxf(0.0, remaining - elapsed)
	if is_zero_approx(remaining):
		remaining = 0.0
	finished = remaining <= 0.0
	queue_redraw()

func _apply(delta: float, setup: Day1StealthSetup, space: PhysicsDirectSpaceState2D) -> void:
	if _effects.has("lure"):
		_pulse -= delta
		var interval := maxf(0.01, float(_effects.lure.pulse_seconds))
		while _pulse <= 0.000001:
			_pulse += interval
			pulse_count += 1
			var lure: Dictionary = _effects.lure
			var pulse_side := maxf(_side, minf(_max_cells, float(lure.pulse_cells) * int(lure.stacks)) * _cell)
			for guard: Day1GuardResponse in setup.guards:
				if guard.can_receive_drink() and contains_point(guard.actor.global_position, pulse_side) and reaches(guard.actor.global_position, space):
					affected = guard.distract(global_position, minf(_max_duration, guard.distraction_seconds * int(lure.stacks))) or affected
	for guard: Day1GuardResponse in setup.guards:
		if not guard.can_receive_drink() or not contains_point(guard.actor.global_position) or not reaches(guard.actor.global_position, space):
			continue
		if _modifiers.has("contagion") and not is_instance_valid(attached_guard):
			attached_guard = guard
			var follow: Dictionary = _modifiers.contagion
			remaining = maxf(remaining, minf(_max_duration, float(follow.follow_seconds) * int(follow.stacks)))
			_side = maxf(_side, minf(_max_cells, float(follow.follow_area_cells) * int(follow.stacks)) * _cell)
		if not _entered.has(guard.get_instance_id()):
			_entered[guard.get_instance_id()] = true
			# Each modifier displaces a given guard once per thrown cup.
			var offset := guard.actor.global_position - global_position
			var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT
			if _modifiers.has("vortex"):
				var pull: Dictionary = _modifiers.vortex
				affected = guard.displace(-direction * minf(offset.length(), float(pull.pull_cells) * int(pull.stacks) * _cell)) or affected
			if _modifiers.has("burst"):
				var push: Dictionary = _modifiers.burst
				affected = guard.displace(direction * minf(_max_cells, float(push.push_cells) * int(push.stacks)) * _cell) or affected
		if _effects.has("paralyze") and _effects.paralyze.get("stun", false):
			affected = guard.stun(_seconds(_effects.paralyze)) or affected
		if _effects.has("corrode"):
			var corrosion: Dictionary = _effects.corrode
			var multiplier := float(corrosion.detect_multiplier) * int(corrosion.stacks)
			affected = guard.corrode(multiplier, remaining) or affected
		for kind: String in ["burn", "hallucinate"]:
			if _effects.has(kind) and _effects[kind].get("confuse", false):
				guard.confuse(global_position, _side, _seconds(_effects[kind]))
				confusion_created = confusion_created or guard.state == Day1GuardResponse.State.CONFUSED
				affected = affected or guard.state == Day1GuardResponse.State.CONFUSED
		if _effects.has("toxic") and _effects.toxic.get("repel", false) and guard.state != Day1GuardResponse.State.STUNNED:
			var offset := guard.actor.global_position - global_position
			var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT
			affected = guard.displace(direction * guard.actor.get_movement_speed() * _distance_scale * int(_effects.toxic.stacks) * delta) or affected
	if _effects.has("burn") and _effects.burn.get("ignite", false):
		for target: Day1FlammableTarget in setup.flammable_targets:
			if contains_point(target.global_position) and reaches(target.global_position, space):
				if target.ignite():
					affected = true
					confusion_created = true
					for guard: Day1GuardResponse in setup.guards:
						if guard.can_receive_drink() and reaches(guard.actor.global_position, space):
							guard.confuse(target.global_position, target.confusion_radius * _distance_scale, target.confusion_seconds)
	if _effects.has("corrode"):
		var corrosion: Dictionary = _effects.corrode
		for target: Day1DestructibleTarget in setup.destructible_targets:
			var exclude: Array[RID] = []
			if is_instance_valid(target.blocker):
				exclude.append(target.blocker.get_rid())
			if contains_point(target.global_position) and reaches(target.global_position, space, exclude):
				affected = target.corrode(float(corrosion.damage_per_second) * int(corrosion.stacks) * delta) or affected
				if finished:
					return

func _seconds(effect: Dictionary) -> float:
	return minf(_max_duration, remaining * int(effect.stacks))

func _draw() -> void:
	var color := Color(0.55, 0.25, 0.85, 0.18)
	if armed:
		color = Color(0.9, 0.7, 0.1, 0.15)
	elif _effects.has("burn"):
		color = Color(1.0, 0.25, 0.05, 0.22)
	elif _effects.has("toxic") or _effects.has("corrode"):
		color = Color(0.45, 0.85, 0.1, 0.2)
	var rect := Rect2(Vector2.ONE * -_side * 0.5, Vector2.ONE * _side)
	draw_rect(rect, color)
	draw_rect(rect, Color(color, 0.8), false, 2.0 * _distance_scale)
	if pulse_count > 0:
		draw_circle(Vector2.ZERO, 5.0 * _distance_scale, Color.GOLD)
