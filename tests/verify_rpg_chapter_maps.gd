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
	await _verify_interaction_reach()
	_verify_presentation_profiles()
	await _verify_host()
	print("RPG_CHAPTER_MAPS: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _verify_interaction_reach() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var player: FloorAwareShopPlayer = load("res://src/gameplay/player/rpg_player.tscn").instantiate()
	player.get_node("Camera2D").enabled = false
	world.add_child(player)
	player.set_physics_process(false)
	var point: InteractionPoint = load("res://src/gameplay/interaction/rpg_interaction_point.tscn").instantiate()
	point.position = Vector2(160, 100)
	world.add_child(point)
	player.teleport_to(Vector2(100, 100))
	for tick in range(4):
		await physics_frame
	_check(not point.is_available(), "RPG interaction rejects the old 60-world-pixel reach")
	player.teleport_to(Vector2(125, 100))
	for tick in range(4):
		await physics_frame
	_check(point.is_available(), "Approaching within the reduced reach enables actual physics interaction")
	var shop_point: InteractionPoint = load("res://src/gameplay/interaction/interaction_point.tscn").instantiate()
	shop_point.position = Vector2(160, 100)
	world.add_child(shop_point)
	player.teleport_to(Vector2(100, 100))
	for tick in range(4):
		await physics_frame
	_check(shop_point.is_available() and not point.is_available(), "RPG shrink does not change the shop's original interaction resource")
	world.queue_free()
	await process_frame

## Inspect independently instantiated hosts so shared scene overrides cannot leak.
func _verify_presentation_profiles() -> void:
	var shop: Node = load("res://src/core/main.tscn").instantiate()
	var rpg: Node = load("res://src/core/tavern.tscn").instantiate()
	var shop_player: ShopPlayer = shop.get_node("World/EntityRoot/Player")
	var rpg_player: FloorAwareShopPlayer = rpg.get_node("World/EntityRoot/Player")
	_check(shop_player.get_node("Visual").scale == Vector2.ONE, "Standalone shop retains its full-size player")
	_check(rpg_player.get_node("Visual").scale == Vector2.ONE * 0.5, "RPG host uses the half-size inherited player")
	var shop_camera: BoundedFollowCamera = shop_player.get_node("Camera2D")
	var rpg_camera: BoundedFollowCamera = rpg_player.get_node("Camera2D")
	_check(shop_camera.preferred_zoom == 0.5 and rpg_camera.preferred_zoom == 1.0, "Only RPG hosts double the camera zoom")
	_check(shop_player.speed == 240.0 and rpg_player.speed == 120.0, "Screen movement speed is preserved after RPG camera compensation")
	_check(shop_player.acceleration == 1800.0 and rpg_player.acceleration == 900.0 and shop_player.deceleration == 2400.0 and rpg_player.deceleration == 1200.0, "Both profiles preserve acceleration and stopping times")
	var shop_shape: CapsuleShape2D = shop_player.get_node("CollisionShape2D").shape
	var rpg_shape: CapsuleShape2D = rpg_player.get_node("CollisionShape2D").shape
	_check(shop_shape.height == 34.0 and shop_shape.radius == 10.0 and rpg_shape.height == 17.0 and rpg_shape.radius == 5.0, "Player foot shapes are isolated by host")
	_check(shop_player.get_node("HeldItemVisual").offset_down == Vector2(24, -52) and rpg_player.get_node("HeldItemVisual").offset_down == Vector2(12, -26), "Held item anchors follow each host's character size")
	for actor_name in ["FatGoblin", "HumanCustomer", "GoblinCustomer", "GoblinA", "GoblinB", "GoblinC"]:
		var actor: Node = shop.get_node("World/EntityRoot/" + actor_name)
		_check(actor.get_node("Visual").scale == Vector2.ONE and actor.get_node("CollisionShape2D").shape.height == 28.0, "Standalone shop preserves NPC size: " + actor_name)
	var map: RpgChapterMap = rpg.get_node("World/LevelRoot/Map")
	for actor: SettlementCharacter in map.get_chapter_characters():
		_check(actor.get_node("Visual").scale == Vector2.ONE * 0.5 and actor.get_node("CollisionShape2D").shape.height == 14.0, "RPG NPC retains the half-size profile")
	rpg.free()
	shop.free()

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
	if map.chapter_host == &"settlement":
		await _verify_door_approaches(map)
		await _verify_north_guidance(map)
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
	for point: GatherPoint in map.get_gather_points():
		_check(reachable.has(map.world_to_cell(point.global_position)), "Gather object can be approached on native floor: " + point.name)
	for point: InteractionPoint in map.get_interaction_points() + map.get_scene_exits() + map.get_gather_points():
		_check(point.get_node("CollisionShape2D").global_scale == Vector2.ONE * (0.28 if point.is_in_group("wayfinding") else 0.5), "All RPG interactions, doors and gathering points use the same reach scale: " + point.name)
	if map.chapter_host == &"settlement":
		_check(map.get_node("DrunkenEncounter/CollisionShape2D").global_scale == Vector2.ONE * 0.5, "NPC encounter trigger follows the half-size character range")
	var setup := map.get_stealth_setup()
	if setup != null:
		_check(setup.throw_range == 230.0 and setup.effect_scale == 0.5, "RPG throw range and effect distances are halved")
		for guard: Day1GuardResponse in setup.guards:
			var old_ranges := {Day1GuardResponse.Role.ENTRANCE: 84.0, Day1GuardResponse.Role.MANSION_LURE: 48.0, Day1GuardResponse.Role.MANSION_GATE: 60.0, Day1GuardResponse.Role.DRUNKEN: 48.0}
			if old_ranges.has(guard.role):
				_check(guard.sight_range >= float(old_ranges[guard.role]) * 2.0, "Published guard sight radius is at least doubled")
			_check(guard.hear_footsteps and guard.hearing_range > 0, "Published guards can hear footsteps")
			_check(guard.sight_half_angle == 55.0, "Published guard sight uses the widened forward cone")
			if guard.role in [Day1GuardResponse.Role.MANSION_LURE, Day1GuardResponse.Role.MANSION_GATE]:
				_check(guard.patrol_offsets.is_empty(), "Mansion door guards keep their posts")
			else:
				_check(not guard.patrol_offsets.is_empty(), "Street and indoor guards have authored patrols")

	var data := map.get_map_data(["settlement.shop", "settlement.elder"])
	_check(data.regions.size() == 2, "Map exposes only requested known exterior locations")
	_check(map.get_scene_entrance(&"unknown") == null, "Unknown entrances fail closed")
	map.free()
	await process_frame

func _verify_door_approaches(map: RpgChapterMap) -> void:
	var player: FloorAwareShopPlayer = load("res://src/gameplay/player/rpg_player.tscn").instantiate()
	player.get_node("Camera2D").enabled = false
	root.add_child(player)
	player.set_physics_process(false)
	for id: String in ["shop", "tavern", "casino", "elder"]:
		var arrival := map.get_scene_entrance(StringName(id + "_door"))
		var door: SceneExit
		for point: SceneExit in map.get_scene_exits():
			if String(point.interaction_id) == id + "_enter":
				door = point
		for offset: float in [-24.0, 0.0, 24.0]:
			player.teleport_to(arrival.global_position + Vector2(offset, 0))
			for tick in range(4):
				await physics_frame
			_check(map.can_stand_at(player.global_position, Vector2(8.5, 5)) and door.is_available(), "Returned player can find door from left/center/right: %s %s" % [id, offset])
	player.free()
	await process_frame

func _verify_north_guidance(map: RpgChapterMap) -> void:
	var player: FloorAwareShopPlayer = load("res://src/gameplay/player/rpg_player.tscn").instantiate()
	player.get_node("Camera2D").enabled = false
	root.add_child(player)
	player.set_physics_process(false)
	var setup := map.get_stealth_setup()
	var watch: Day1GuardResponse = setup.guards[0]
	watch.actor.visible = true
	watch.capture_checkpoint()
	player.teleport_to(map.get_story_anchor(&"day1_observation").global_position)
	await physics_frame
	var space := map.get_world_2d().direct_space_state
	_check(not watch.advance(1.0, player, space), "Northern observation position remains outside real sight")
	var landing: Node2D = map.get_node("Wayfinding/NightGuidance/CoinLanding")
	_check(map.can_stand_at(landing.global_position, Vector2(8.5, 5)) and player.global_position.distance_to(landing.global_position) <= setup.throw_range, "Optional coin landing is on floor and within actual throw range from observation")
	_check(watch.distract(landing.global_position), "Coin landing lies inside this guard's actual hearing range")
	# Isolate the sight lane from the authored patrol: the watch stands still here.
	var patrol := watch.patrol_offsets.duplicate()
	watch.patrol_offsets = []
	for x: float in [1128.0, 1176.0, 1224.0]:
		watch.reset_response()
		player.teleport_to(Vector2(x, 504))
		await physics_frame
		_check(watch.advance(1.0, player, space), "Forward watch covers native street lane: " + str(x))
	for x: float in [1104.0, 1248.0]:
		watch.reset_response()
		player.teleport_to(Vector2(x, 504))
		await physics_frame
		_check(not watch.advance(1.0, player, space), "Outside the forward sector stays safe: " + str(x))
	watch.patrol_offsets = patrol
	# The authored patrol actually moves the body and reset restores its post.
	var start := watch.actor.global_position
	for tick in range(24):
		watch.advance(0.1, player, space)
	_check(watch.actor.global_position.distance_to(start) > 4.0, "Patrolling guard leaves its starting post")
	_check(watch.actor.global_position.distance_to(start) <= 60.0, "Patrol stays within its authored segment")
	watch.reset_response()
	_check(watch.actor.global_position.distance_to(start) < 1.0, "Retry restores the guard's patrol start")
	watch.actor.visible = false
	player.free()
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
	_check(game.get_player().camera.zoom == Vector2.ONE, "Formal RPG host uses the compensated 1x camera after initialization")
	_check(game.get_task_delivery() != null, "Chapter room has real delivery service")
	var owner: SettlementCharacter = game.get_actor_director().get_actor(&"tavern")
	_check(owner.get_node("InteractionPoint/CollisionShape2D").global_scale == Vector2.ONE * 0.5, "Dynamically assembled NPC interaction also has half reach")
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
