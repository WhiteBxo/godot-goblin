class_name RpgChapterMap
extends RpgMakerMap
## Chapter-facing bindings over the unchanged imported TileMapLayer scene.
## Layout and gates are authored nodes; this map never advances a chapter.

@export var chapter_host: StringName = &"settlement"
@export var exterior_location: String = "settlement.shop"
## Scene-authored first-visit areas, in map coordinates.
@export var first_visit_bounds := Rect2()
@export var market_observation_area := Rect2()
## Music covers the whole market, including the shop frontage; observation is a smaller story zone.
@export var market_music_area := Rect2()
@export_multiline var first_visit_blocked_message := ""
## Task/objective -> authored scene node. Scene-local anchors do not expose hierarchy.
@export var objective_points: Dictionary = {}
var market_only := false
signal market_boundary_reached

func can_stand_at(world_position: Vector2, half_size := Vector2.ZERO) -> bool:
	if _blocks_market(world_position, half_size):
		market_boundary_reached.emit()
		return false
	return super.can_stand_at(world_position, half_size)

## Ambient actors probe candidate steps with this variant: the market gate still
## rejects the position, but a townsfolk detour never tells the player they left.
func is_walkable_at(world_position: Vector2, half_size := Vector2.ZERO) -> bool:
	if _blocks_market(world_position, half_size):
		return false
	return super.is_walkable_at(world_position, half_size)

func _blocks_market(world_position: Vector2, half_size: Vector2) -> bool:
	if not market_only or not first_visit_bounds.has_area():
		return false
	var footprint := Rect2(to_local(world_position) - half_size, half_size * 2.0)
	return not first_visit_bounds.encloses(footprint)

func is_observing_market(world_position: Vector2) -> bool:
	return market_observation_area.has_area() and market_observation_area.has_point(to_local(world_position))

func is_in_market(world_position: Vector2) -> bool:
	return market_music_area.has_area() and market_music_area.has_point(to_local(world_position))

func get_objective_position(task_id: String, objective_id: String) -> Variant:
	var key := task_id + ":" + objective_id
	if not objective_points.has(key):
		return null
	var point := get_node_or_null(NodePath(objective_points[key])) as Node2D
	return point.global_position if point != null else null

## Exterior map coordinates only describe this scene when it *is* the exterior.
## A room map draws the wider map too, but its own floor has a different origin.
func shares_map_world() -> bool:
	return chapter_host == &"settlement"

## The arrow follows actual saved floor passages rather than pointing through walls.
func get_navigation_path(start: Vector2, goal: Vector2) -> PackedVector2Array:
	var first := world_to_cell(start)
	var last := world_to_cell(goal)
	var frontier: Array[Vector2i] = [first]
	var previous := {first: first}
	var occupied := {}
	var shape := RectangleShape2D.new()
	var bounds := get_camera_bounds()
	shape.size = bounds.size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, bounds.get_center())
	query.collision_mask = 1 << (PlayerController.NPC_LAYER - 1)
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 64):
		if hit.collider is SettlementCharacter:
			occupied[world_to_cell(hit.collider.global_position)] = true
	var cursor := 0
	while cursor < frontier.size() and not previous.has(last) and cursor < 4000:
		var cell := frontier[cursor]
		cursor += 1
		for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next := cell + direction
			if previous.has(next) or not can_cross_edge(cell, direction):
				continue
			if occupied.has(next) and next != last:
				continue
			if market_only and not first_visit_bounds.has_point(to_local(cell_to_world(next))):
				continue
			previous[next] = cell
			frontier.append(next)
	if not previous.has(last):
		return PackedVector2Array()
	var reverse: Array[Vector2] = []
	var current := last
	while current != first:
		reverse.append(cell_to_world(current))
		current = previous[current]
	reverse.reverse()
	return PackedVector2Array(reverse)

func _ready() -> void:
	super._ready()
	for point: InteractionPoint in get_interaction_points() + get_scene_exits() + get_gather_points():
		point.hide_development_markers()

func get_chapter_host() -> String:
	return String(chapter_host)

func get_chapter_characters() -> Array[SettlementCharacter]:
	var result: Array[SettlementCharacter] = []
	var container := get_node_or_null("Characters")
	if container != null:
		for actor: Node in container.get_children():
			if actor is SettlementCharacter:
				result.append(actor)
	return result

func get_stealth_setup() -> Day1StealthSetup:
	return get_node_or_null("StealthSetup") as Day1StealthSetup

func get_scene_entrance(id: StringName) -> SceneEntrance:
	for entrance: Node in get_node("Entrances").get_children():
		if entrance is SceneEntrance and entrance.entrance_id == id:
			return entrance
	return null

func get_scene_exits() -> Array[SceneExit]:
	var exits: Array[SceneExit] = []
	for point: Node in get_node("Exits").get_children():
		if point is SceneExit:
			exits.append(point)
	return exits

func get_interaction_points() -> Array[InteractionPoint]:
	var points: Array[InteractionPoint] = []
	for point: Node in get_node("Interactions").get_children():
		if point is InteractionPoint:
			points.append(point)
	return points

func get_story_positions() -> Array[Marker2D]:
	var positions: Array[Marker2D] = []
	for marker: Node in get_node("StoryPositions").get_children():
		if marker is Marker2D:
			positions.append(marker)
	return positions

func get_story_anchor(id: StringName) -> Marker2D:
	return get_node_or_null("StoryPositions/" + String(id)) as Marker2D

func get_gather_points() -> Array[GatherPoint]:
	var points: Array[GatherPoint] = []
	var container := get_node_or_null("GatherPoints")
	if container != null:
		for point: Node in container.get_children():
			if point is GatherPoint:
				points.append(point)
	return points

func get_map_data(known_locations: Array[String]) -> Dictionary:
	return RpgWorldMapData.describe(known_locations)

func get_map_location_ids() -> Array[String]:
	return RpgWorldMapData.location_ids()

func get_map_player_position(player: Node2D) -> Vector2:
	if chapter_host == &"settlement":
		return player.global_position
	return RpgWorldMapData.get_entrance_position(exterior_location)
