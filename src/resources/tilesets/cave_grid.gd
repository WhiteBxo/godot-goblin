class_name CaveGrid
extends RefCounted

# Clockwise-independent bit order matches the 3x3 neighborhood around a ground cell.
const NEIGHBORS := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

static func neighbor_mask(cell: Vector2i, cells: Dictionary) -> int:
	var mask := 0
	for index in range(NEIGHBORS.size()):
		if cells.has(cell + NEIGHBORS[index]):
			mask |= 1 << index
	return mask

static func atlas_coords(mask: int) -> Vector2i:
	return Vector2i(mask % 16, mask >> 4)
