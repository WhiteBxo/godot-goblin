class_name RpgChapterMap
extends RpgMakerMap
## Chapter-facing bindings over the unchanged imported TileMapLayer scene.
## Layout and gates are authored nodes; this map never advances a chapter.

@export var chapter_host: StringName = &"settlement"
@export var exterior_location: String = "settlement.shop"

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

func get_blocked_passages() -> Array[Rect2]:
	var result: Array[Rect2] = []
	var container := get_node_or_null("ClosedRoads")
	if container != null:
		for barrier: Node in container.get_children():
			result.append(barrier.get_blocked_bounds())
	return result

func can_stand_at(world_position: Vector2, half_size: Vector2) -> bool:
	if not super.can_stand_at(world_position, half_size):
		return false
	for blocked: Rect2 in get_blocked_passages():
		if blocked.intersects(Rect2(world_position - half_size, half_size * 2)):
			return false
	return true

func can_cross_edge(cell: Vector2i, direction: Vector2i) -> bool:
	if not super.can_cross_edge(cell, direction):
		return false
	var midpoint := (cell_to_world(cell) + cell_to_world(cell + direction)) * 0.5
	for blocked: Rect2 in get_blocked_passages():
		if blocked.grow(1).has_point(midpoint):
			return false
	return true

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

func configure_depth_sort(character_root: Node2D) -> void:
	character_root.y_sort_enabled = true
	for character: Node in character_root.get_children():
		if character is Node2D:
			character.z_index = 0

func get_map_data(known_locations: Array[String]) -> Dictionary:
	return RpgWorldMapData.describe(known_locations)

func get_map_location_ids() -> Array[String]:
	return RpgWorldMapData.location_ids()

func get_map_player_position(player: Node2D) -> Vector2:
	if chapter_host == &"settlement":
		return player.global_position
	return RpgWorldMapData.get_entrance_position(exterior_location)
