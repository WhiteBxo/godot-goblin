class_name SettlementMap
extends Node2D
## Saved TileMapLayer cells and scene instances are the editable map authority.

const NIGHT_OVERLAY: PackedScene = preload("res://src/levels/settlement/night_overlay.tscn")

## Explicit task location IDs map only to authored exterior entrances.
## Interior clues and routes are deliberately absent from this allowlist.
const MAP_LOCATIONS := {
	"settlement.shop": "00_shop", "settlement.muster": "01_muster",
	"settlement.vestibule": "02_vestibule", "settlement.training": "03_training",
	"settlement.lodging": "04_lodging", "settlement.kitchen": "05_kitchen",
	"settlement.tavern": "06_tavern", "settlement.casino": "07_casino",
	"settlement.dining": "08_dining", "settlement.ritual": "09_ritual",
	"settlement.elder": "10_elder", "settlement.growing": "11_growing",
	"settlement.warehouse": "12_warehouse", "settlement.yard": "13_yard",
	"settlement.hearth": "14_hearth", "settlement.workshop": "15_workshop",
}

@export var world_size := Vector2(8192, 9216)

var _night_overlay: CanvasLayer
var _state: Node

func _ready() -> void:
	_state = get_node_or_null("/root/GameState")
	_night_overlay = NIGHT_OVERLAY.instantiate() as CanvasLayer
	add_child(_night_overlay)
	if _state != null:
		_state.state_changed.connect(_refresh_phase)
	_refresh_phase()

func _refresh_phase() -> void:
	if is_instance_valid(_night_overlay):
		_night_overlay.call("set_night", DayPhase.is_night(_state))

func _exit_tree() -> void:
	if is_instance_valid(_state) and _state.state_changed.is_connected(_refresh_phase):
		_state.state_changed.disconnect(_refresh_phase)

## The gate is authored in the district beside its existing doorway walls.
func set_elder_access(allowed: bool) -> void:
	$Districts/Elder/Walls/StoryGate.set_collision_layer_value(1, not allowed)

func get_world_bounds() -> Rect2:
	return global_transform * Rect2(Vector2.ZERO, world_size)

## This map *is* the exterior: region positions are this scene's own coordinates.
func shares_map_world() -> bool:
	return true

func get_camera_bounds() -> Rect2:
	return get_world_bounds()

func get_spawn_position() -> Vector2:
	return $Spawn.global_position

func get_scene_entrance(id: StringName) -> SceneEntrance:
	for child in $SceneEntrances.get_children():
		if child is SceneEntrance and child.entrance_id == id:
			return child
	return null

func get_scene_exits() -> Array[SceneExit]:
	var exits: Array[SceneExit] = []
	for child in $SceneExits.get_children():
		if child is SceneExit:
			exits.append(child)
	return exits

func get_interaction_points() -> Array[InteractionPoint]:
	var points: Array[InteractionPoint] = []
	for child in $InteractionPoints.get_children():
		if child is InteractionPoint:
			points.append(child)
	return points

func get_gather_points() -> Array[GatherPoint]:
	var points: Array[GatherPoint] = []
	var container := get_node_or_null("GatherPoints")
	if container == null:
		return points
	for child in container.get_children():
		if child is GatherPoint:
			points.append(child)
	return points

func get_zone_at(world_position: Vector2) -> String:
	for zone: Node2D in $Districts.get_children():
		var area: Rect2 = zone.get_meta("footprint", Rect2(110, 80, 1320, 840))
		if area.has_point(zone.to_local(world_position)):
			return str(zone.get_meta("display_name", zone.name))
	return "洞窟街道"

func get_story_positions() -> Array[Marker2D]:
	var positions: Array[Marker2D] = []
	for marker: Node in $StoryAnchors.get_children():
		if marker is Marker2D:
			positions.append(marker)
	return positions

func get_story_anchor(id: StringName) -> Marker2D:
	return $StoryAnchors.get_node_or_null(NodePath(id)) as Marker2D

func get_stealth_setup() -> Day1StealthSetup:
	return get_node_or_null("Day1StealthSetup") as Day1StealthSetup

## Detached values only: no UI dependency on district nodes or hidden artwork.
func get_map_data(known_locations: Array[String]) -> Dictionary:
	var regions: Array[Dictionary] = []
	for district: Node2D in $Districts.get_children():
		var zone_id := str(district.get_meta("zone_id", ""))
		var location_id := ""
		for id: String in MAP_LOCATIONS:
			if MAP_LOCATIONS[id] == zone_id:
				location_id = id
		if location_id not in known_locations:
			continue
		var anchor := get_story_anchor(StringName(zone_id + "_entrance"))
		if anchor == null:
			continue
		var footprint: Rect2 = district.get_meta("footprint", Rect2())
		regions.append({"location_id": location_id,
			"name": str(district.get_meta("display_name", district.name)),
			"bounds": district.global_transform * footprint,
			"position": anchor.global_position})
	return {"bounds": get_world_bounds(), "regions": regions}
