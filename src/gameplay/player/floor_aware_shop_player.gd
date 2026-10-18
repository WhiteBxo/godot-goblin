class_name FloorAwareShopPlayer
extends ShopPlayer
## Optional saved-floor constraint, in addition to ordinary physical collisions.

var _floor_query: Callable
## World pixels matching the inherited, unscaled horizontal foot capsule.
@export var footprint_half_size := Vector2(8.5, 5)

func set_floor_query(query: Callable) -> void:
	_floor_query = query

func _move_velocity(delta: float) -> void:
	if not _floor_query.is_valid():
		super._move_velocity(delta)
		return
	var motion := velocity * delta
	var steps := maxi(1, ceili(motion.length() / 6.0))
	for step in range(steps):
		var part := motion / steps
		for axis in range(2):
			var movement := Vector2.ZERO
			movement[axis] = part[axis]
			if _floor_query.call(global_position + movement, footprint_half_size):
				move_and_collide(movement)
			else:
				velocity[axis] = 0.0
