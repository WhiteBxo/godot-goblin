class_name RpgWorldMapData
extends RefCounted
## Exterior footprints and named doors. No interior layouts or secret item markers.
## Positions match the authored cave chapter scene, in native 48-pixel cells.

const LOCATIONS := {
	"settlement.shop": {"name": "奶茶店", "cell": Vector2i(33, 52), "area": Rect2(1440, 2400, 288, 240), "ordinal": 1, "kind": "shop"},
	"settlement.yard": {"name": "集市", "cell": Vector2i(24, 50), "area": Rect2(336, 2304, 1440, 336), "ordinal": 2, "kind": "market"},
	"settlement.hearth": {"name": "公共火塘", "cell": Vector2i(24, 30), "area": Rect2(864, 960, 480, 1104), "ordinal": 3, "kind": "square"},
	"settlement.tavern": {"name": "酒馆 · 裂牙", "cell": Vector2i(31, 38), "area": Rect2(1344, 1488, 336, 432), "ordinal": 4, "kind": "tavern"},
	"settlement.casino": {"name": "赌场 · 黑齿", "cell": Vector2i(12, 43), "area": Rect2(384, 1776, 480, 384), "ordinal": 5, "kind": "casino"},
	"settlement.elder": {"name": "长老居所", "cell": Vector2i(42, 10), "area": Rect2(1728, 48, 576, 528), "ordinal": 6, "kind": "elder"},
	"settlement.ritual": {"name": "祭坛", "cell": Vector2i(24, 8), "area": Rect2(864, 0, 528, 528), "ordinal": 7, "kind": "ritual"},
	"settlement.training": {"name": "军营", "cell": Vector2i(39, 20), "area": Rect2(1728, 576, 576, 480), "ordinal": 8, "kind": "training"},
	"settlement.warehouse": {"name": "仓库", "cell": Vector2i(10, 12), "area": Rect2(240, 192, 576, 528), "ordinal": 9, "kind": "warehouse"},
	"settlement.workshop": {"name": "河岸工坊", "cell": Vector2i(6, 29), "area": Rect2(144, 1152, 384, 432), "ordinal": 10, "kind": "workshop"},
}

## Schematic connections between exterior areas; the map draws them as paths.
const LINKS: Array[Array] = [
	["settlement.shop", "settlement.yard"],
	["settlement.yard", "settlement.casino"],
	["settlement.yard", "settlement.tavern"],
	["settlement.yard", "settlement.hearth"],
	["settlement.tavern", "settlement.hearth"],
	["settlement.hearth", "settlement.ritual"],
	["settlement.ritual", "settlement.elder"],
	["settlement.elder", "settlement.training"],
	["settlement.ritual", "settlement.warehouse"],
	["settlement.warehouse", "settlement.workshop"],
	["settlement.workshop", "settlement.casino"],
]

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
				"bounds": LOCATIONS[id].area, "position": get_entrance_position(id),
				"ordinal": LOCATIONS[id].ordinal, "kind": LOCATIONS[id].kind})
	regions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ordinal < b.ordinal)
	var view := Rect2()
	for region: Dictionary in regions:
		view = region.bounds if not view.has_area() else view.merge(region.bounds)
	if not view.has_area():
		view = Rect2(0, 0, 2400, 2640)
	view = view.grow(96.0)
	var links: Array[Dictionary] = []
	for link: Array in LINKS:
		if link[0] in known_locations and link[1] in known_locations:
			links.append({"from": get_entrance_position(link[0]), "to": get_entrance_position(link[1])})
	return {"bounds": Rect2(0, 0, 2400, 2640), "view": view, "regions": regions, "links": links}
