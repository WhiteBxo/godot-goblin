extends SceneTree
## 赌场客人分散在整间屋子里，不再围在门口那张赌桌旁。

const SCENE := "res://src/levels/rpg_maker/chapter_casino.tscn"
## 赌桌与出口所在的格子：客人不得挤在这附近。
const HOTSPOTS: Array[Vector2i] = [Vector2i(13, 16), Vector2i(13, 17)]
## 两名客人之间至少隔开的格数（切比雪夫距离）。
const MIN_SPREAD := 3
const CROWD_PREFIX := "casino_crowd_"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)


func _run() -> void:
	var map: Node2D = load(SCENE).instantiate()
	root.add_child(map)
	await process_frame
	var cells: Array[Vector2i] = []
	for child in map.get_node("Characters").get_children():
		if not child is SettlementCharacter:
			continue
		var cell: Vector2i = map.world_to_cell(child.position)
		_check(map.is_cell_walkable(cell), "Character stands on walkable floor: %s at %s" % [child.name, cell])
		if String(child.actor_id).begins_with(CROWD_PREFIX):
			cells.append(cell)
	_check(cells.size() == 9, "The casino keeps its nine punters: %d" % cells.size())
	for index in range(cells.size()):
		var near_table := (cells[index] - HOTSPOTS[0]).abs()
		var near_door := (cells[index] - HOTSPOTS[1]).abs()
		_check(maxi(near_table.x, near_table.y) > 2, "No punter crowds the gambling table: %s" % cells[index])
		_check(maxi(near_door.x, near_door.y) > 2, "No punter crowds the entrance: %s" % cells[index])
		for other in range(index + 1, cells.size()):
			var gap: Vector2i = (cells[index] - cells[other]).abs()
			_check(maxi(gap.x, gap.y) >= MIN_SPREAD,
				"Punters stay spread out: %s vs %s" % [cells[index], cells[other]])
	print("CASINO_LAYOUT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
