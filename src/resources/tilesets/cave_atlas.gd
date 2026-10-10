class_name CaveAtlas
extends RefCounted

const TILE_SIZE := 32
const ATLAS_MARGIN := Vector2i(9, 9)
const ATLAS_SEPARATION := Vector2i(9, 9)
const VOID_RGB_THRESHOLD := 0.04
const MASK_TO_ATLAS := {
	0: Vector2i(0, 3),
	1: Vector2i(3, 3),
	2: Vector2i(0, 2),
	3: Vector2i(1, 2),
	4: Vector2i(0, 0),
	5: Vector2i(3, 2),
	6: Vector2i(2, 3),
	7: Vector2i(3, 1),
	8: Vector2i(1, 3),
	9: Vector2i(0, 1),
	10: Vector2i(1, 0),
	11: Vector2i(2, 2),
	12: Vector2i(3, 0),
	13: Vector2i(2, 0),
	14: Vector2i(1, 1),
	15: Vector2i(2, 1),
}

static func corner_mask(cell: Vector2i, cells: Dictionary) -> int:
	var mask := 0
	for index in range(4):
		var offset := Vector2i(index % 2, index >> 1)
		if cells.has(cell + offset):
			mask |= 1 << index
	return mask
