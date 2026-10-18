class_name RpgWorldMapData
extends RefCounted
## Exterior footprints and named doors. No interior layouts or secret item markers.
## Positions match the authored cave chapter scene, in native 48-pixel cells.

const LOCATIONS := {
	"settlement.shop": {"name": "奶茶店", "cell": Vector2i(33, 52), "area": Rect2(1440, 2400, 288, 240)},
	"settlement.yard": {"name": "集市", "cell": Vector2i(24, 50), "area": Rect2(336, 2304, 1440, 336)},
	"settlement.hearth": {"name": "公共火塘", "cell": Vector2i(24, 30), "area": Rect2(864, 960, 480, 1104)},
	"settlement.tavern": {"name": "酒馆 · 裂牙", "cell": Vector2i(31, 38), "area": Rect2(1344, 1488, 336, 432)},
	"settlement.casino": {"name": "赌场 · 黑齿", "cell": Vector2i(12, 43), "area": Rect2(384, 1776, 480, 384)},
	"settlement.elder": {"name": "长老居所", "cell": Vector2i(42, 10), "area": Rect2(1728, 48, 576, 528)},
	"settlement.ritual": {"name": "祭坛", "cell": Vector2i(24, 8), "area": Rect2(864, 0, 528, 528)},
	"settlement.training": {"name": "军营", "cell": Vector2i(39, 20), "area": Rect2(1728, 576, 576, 480)},
	"settlement.warehouse": {"name": "仓库", "cell": Vector2i(10, 12), "area": Rect2(240, 192, 576, 528)},
	"settlement.workshop": {"name": "河岸工坊", "cell": Vector2i(6, 29), "area": Rect2(144, 1152, 384, 432)},
}

var current_location := "settlement.shop"

func get_map_data(known_locations: Array[String]) -> Dictionary:
	return describe(known_locations)

func get_map_location_ids() -> Array[String]:
	return location_ids()

func get_map_player_position(_player: Node2D) -> Vector2:
	return get_entrance_position(current_location)

static func location_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(LOCATIONS.keys())
	return ids

static func get_entrance_position(id: String) -> Vector2:
	if not LOCATIONS.has(id):
		return Vector2.ZERO
	return (Vector2(LOCATIONS[id].cell) + Vector2(0.5, 0.5)) * 48.0

static func describe(known_locations: Array[String]) -> Dictionary:
	var regions: Array[Dictionary] = []
	for id: String in LOCATIONS:
		if id in known_locations:
			regions.append({"location_id": id, "name": LOCATIONS[id].name,
				"bounds": LOCATIONS[id].area, "position": get_entrance_position(id)})
	return {"bounds": Rect2(0, 0, 2400, 2640), "regions": regions}
