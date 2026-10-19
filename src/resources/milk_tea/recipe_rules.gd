class_name RecipeRules
extends Resource
## One shared input for formula evaluation, UI slots and signature matching.

const MAX_SLOTS := 3

@export_range(1, 3) var slot_count := MAX_SLOTS
@export_range(0, 2147483647) var ordinary_price := 20
## Source-backed signatures: ingredients, exact iced state, price, first_reward,
## appearance/tasting/discovery notes, tags and discovery_kind (experiment/clue).
@export var signatures: Array[Dictionary] = []
@export var throw_tuning: ThrowTuning

func get_signature(id: String) -> Dictionary:
	for signature: Dictionary in signatures:
		if signature.get("id") == id:
			return signature.duplicate(true)
	return {}
