class_name RecipeRules
extends Resource
## One shared input for formula evaluation, UI slots and signature matching.

const MAX_SLOTS := 3

@export_range(1, 3) var slot_count := MAX_SLOTS
@export_range(0, 2147483647) var ordinary_price := 20
## {id, name, ingredients: [base, additives...], price}. Empty until design supplies recipes.
@export var signatures: Array[Dictionary] = []
@export var throw_tuning: ThrowTuning
