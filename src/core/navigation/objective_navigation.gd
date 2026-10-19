class_name ObjectiveNavigation
extends RefCounted
## Read-only objective projection, shared by the full map and the minimap.

static func resolve(level: Object, provider: Object, journal: TaskJournal, known: Array[String]) -> Dictionary:
	if not is_instance_valid(journal) or not is_instance_valid(provider):
		return {}
	var task := journal.get_current_main_task()
	var objective: Dictionary = task.get("current_objective", {})
	if task.is_empty() or objective.is_empty() or not objective.get("revealed", false):
		return {}
	var location: String = objective.get("location_id", "")
	if location.is_empty():
		location = task.get("location_id", "")
	var data: Dictionary = provider.get_map_data(known)
	var result := {"text": objective.text, "name": "", "location_id": location}
	for region: Dictionary in data.regions:
		if region.location_id == location:
			result.position = region.position
			result.name = region.name
	if is_instance_valid(level) and level.has_method("get_objective_position"):
		var point: Variant = level.get_objective_position(task.id, objective.id)
		if point is Vector2:
			result.world_position = point
	if not result.has("world_position") and result.has("position"):
		# Interior hosts use an exterior provider, so exterior coordinates never drive
		# an indoor arrow. The current room supplies its own objective anchors.
		if level is RpgChapterMap and level.get_chapter_host() == "settlement":
			result.world_position = result.position
	return result
