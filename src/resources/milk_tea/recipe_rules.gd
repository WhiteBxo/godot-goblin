class_name RecipeRules
extends Resource
## One shared input for formula evaluation, UI slots and signature matching.

@export_range(1, 16) var slot_count := 3
@export_range(0, 2147483647) var ordinary_price := 20
## {id, name, ingredients: [base, additives...], price}. Empty until design supplies recipes.
@export var signatures: Array[Dictionary] = []
@export var throw_tuning: ThrowTuning
