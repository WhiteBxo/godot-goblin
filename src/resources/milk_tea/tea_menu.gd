class_name TeaMenu
extends Resource
## Stock is measured in portions; each listed ingredient costs one portion per cup.

@export var ingredients: Array[IngredientDefinition] = []
@export var initial_stock: Dictionary = {}
## Keys are discovered ingredient IDs; values list initially known property groups.
@export var initial_discovery: Dictionary = {}
@export var orders: Array[Dictionary] = []
