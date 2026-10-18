extends SceneTree
## Real inherited maps, real destination preflight, and native directional passages.

const CHAPTERS := ["cave", "tavern", "casino", "elder_house"]
const IMPORT_IDS := [1, 4, 5, 6]
const HOSTS := ["settlement", "tavern", "casino", "elder_house"]
var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, text: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(text)
		push_error(text)

func _run() -> void:
	for index in CHAPTERS.size():
		await _verify_map(index)
	await _verify_host()
	print("RPG_CHAPTER_MAPS: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _verify_map(index: int) -> void:
	var map := load("res://src/levels/rpg_maker/chapter_%s.tscn" % CHAPTERS[index]).instantiate() as RpgChapterMap
	_check(map != null, "Chapter map has the public RPG binding")
	if map == null:
		return
	root.add_child(map)
	await process_frame
	var imported := load("res://src/levels/rpg_maker/map_%03d.tscn" % IMPORT_IDS[index]).instantiate() as RpgMakerMap
	for layer: String in ["Ground0", "Ground1", "Ground2", "Ground3", "Upper0", "Upper1", "Upper2", "Upper3", "Shadows", "TableEdges"]:
		_check(map.get_node(layer).tile_map_data == imported.get_node(layer).tile_map_data,
			"Chapter bindings retain the imported cells: %s/%s" % [CHAPTERS[index], layer])
	imported.free()
	var reachable := _reachable_cells(map, map.world_to_cell(map.get_spawn_position()))
	for entrance: Node in map.get_node("Entrances").get_children():
		_check(map.get_scene_entrance(entrance.entrance_id) == entrance, "Stable named entrance lookup")
		_check(map.can_stand_at(entrance.global_position, Vector2(17, 10)), "Entrance fits native player feet: " + entrance.name)
		_check(reachable.has(map.world_to_cell(entrance.global_position)), "Entrance reachable with directional passage: " + entrance.name)
	for point: SceneExit in map.get_scene_exits():
		_check(reachable.has(map.world_to_cell(point.global_position)), "Door can be approached: %s/%s %s" % [CHAPTERS[index], point.name, map.world_to_cell(point.global_position)])
		var destination := load(point.destination_scene).instantiate() as MainGame
		_check(destination != null and destination.prepare_scene_arrival(point.destination_entrance) == OK,
			"Real destination accepts arrival: " + point.name)
		if destination != null:
			destination.free()
	for point: InteractionPoint in map.get_interaction_points():
		_check(reachable.has(map.world_to_cell(point.global_position)), "Story point reachable: " + point.name)
	var data := map.get_map_data(["settlement.shop", "settlement.elder"])
	_check(data.regions.size() == 2, "Map exposes only requested known exterior locations")
	_check(map.get_scene_entrance(&"unknown") == null, "Unknown entrances fail closed")
	map.free()
	await process_frame

func _reachable_cells(map: RpgMakerMap, start: Vector2i) -> Dictionary:
	var reached := {start: true}
	var pending: Array[Vector2i] = [start]
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + direction
			if not reached.has(next) and map.can_cross_edge(cell, direction):
				reached[next] = true
				pending.append(next)
	return reached

func _verify_host() -> void:
	var state := root.get_node("GameState")
	state.reset_state()
	state.set_story_stage("day2.s03")
	var game := load("res://src/core/tavern.tscn").instantiate() as MainGame
	_check(game.prepare_scene_arrival(&"exterior_door") == OK, "Indoor host preflights authored door")
	root.add_child(game)
	await process_frame
	await process_frame
	var map := game.get_active_level() as RpgChapterMap
	_check(map != null and map.chapter_host == &"tavern", "MainGame hosts new indoor map")
	_check(game.get_player() is FloorAwareShopPlayer, "Real player uses native floor constraint")
	_check(game.get_task_delivery() != null, "Chapter room has real delivery service")
	_check(game.get_actor_director().get_position(&"tavern_bartender") != null, "Chapter room registers scene Marker")
	_check(game.unlock_map() == OK, "Map assembles inside a room")
	var point := map.get_scene_exits()[0]
	_check(point.are_conditions_met(state), "Indoor return does not depend on a debug service")
	var cave := load("res://src/levels/rpg_maker/chapter_cave.tscn").instantiate() as RpgChapterMap
	var tavern_exit: SceneExit = cave.get_node("Exits/TavernDoor")
	state.set_story_stage("day1.s03")
	_check(not tavern_exit.are_conditions_met(state), "Day 1 exploration cannot enter Day 2 interior")
	state.set_story_stage("day2.s03")
	_check(tavern_exit.are_conditions_met(state), "Day 2 opens authored tavern route")
	cave.free()
	game.free()
	state.reset_state()
	await process_frame
