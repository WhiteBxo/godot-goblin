class_name TeaRecipe
extends Resource
## Static catalog data. Runtime inventory and order progress never live here.

@export var id: String = ""
## Must reference an ingredient whose category is "product".
@export var product_id: String = ""
## Ingredient IDs; duplicates allowed and selection order never matters.
@export var materials: Array[String] = []
## Fixed cup price in G. -1 keeps the legacy dynamic price for teaching recipes.
## The human menu H01-H06 uses the 2026-10-19 flat 3G price.
@export var sell_price: int = -1
@export var hint: String = ""
## GameState flag that must be true before this recipe may be previewed or crafted.
## Empty means the recipe is always available.
@export var required_flag: String = ""
@export var required_flags: Array[String] = []
@export var required_stages: Array[String] = []

## Availability is a reading of session facts; the recipe never stores progress.
func is_available(state: Node) -> bool:
	if required_flag.is_empty() and required_flags.is_empty() and required_stages.is_empty():
		return true
	if not is_instance_valid(state) or not state.has_method("get_flag"):
		return false
	if not required_flag.is_empty() and not state.get_flag(required_flag):
		return false
	for flag: String in required_flags:
		if not state.get_flag(flag):
			return false
	if not required_stages.is_empty():
		for stage: String in required_stages:
			if Day1Access.at_stage(state, stage):
				return true
		return false
	return true

## Multiset key: sorting makes the order of the selection irrelevant.
static func key_for(materials: Array) -> String:
	var ids: Array[String] = []
	for id: Variant in materials:
		if id is String and not id.is_empty():
			ids.append(id)
	ids.sort()
	return "|".join(PackedStringArray(ids))

func get_material_key() -> String:
	return key_for(materials)
