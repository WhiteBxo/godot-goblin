class_name RpgChapterMap
extends RpgMakerMap
## Chapter-facing bindings over the unchanged imported TileMapLayer scene.
## Layout and gates are authored nodes; this map never advances a chapter.

@export var chapter_host: StringName = &"settlement"
@export var exterior_location: String = "settlement.shop"
## Scene-authored first-visit areas, in map coordinates.
@export var first_visit_bounds := Rect2()
@export var market_observation_area := Rect2()
@export_multiline var first_visit_blocked_message := ""
var market_only := false
signal market_boundary_reached

func can_stand_at(world_position: Vector2, half_size := Vector2.ZERO) -> bool:
	if market_only and first_visit_bounds.has_area():
		var footprint := Rect2(to_local(world_position) - half_size, half_size * 2.0)
		if not first_visit_bounds.encloses(footprint):
			market_boundary_reached.emit()
			return false
	return super.can_stand_at(world_position, half_size)

func is_observing_market(world_position: Vector2) -> bool:
	return market_observation_area.has_area() and market_observation_area.has_point(to_local(world_position))

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
	for node: Node in find_children("*", "", true, false):
		if node is InteractionPoint and node not in points and node.is_in_group("wayfinding"):
			points.append(node)
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
