class_name TeaMenu
extends Resource
## Stock is measured in portions. Fixed teaching recipes consume whole portions;
## free recipes can spend individual uses through WarehouseInventory.

@export var ingredients: Array[IngredientDefinition] = []
@export var initial_stock: Dictionary = {}
## Keys are discovered ingredient IDs; values list initially known property groups.
@export var initial_discovery: Dictionary = {}
@export var orders: Array[Dictionary] = []
## Recipes are the single source of truth for material combinations; orders only name a product.
@export var recipe_book: TeaRecipeBook
@export var recipe_rules: RecipeRules = preload("res://src/resources/milk_tea/recipe_rules.tres")

## Economy configuration. Amounts are integer currency units, stock in portions.
@export_range(0, 2147483647) var initial_balance: int = 0
## product_id -> {item_id: String, price: int, stock?: int}. Omitted stock is unlimited.
@export var products: Dictionary = {}
## reward_id -> {money: int, items: Dictionary, task_id?: String}.
@export var transaction_rewards: Dictionary = {}

func get_recipes() -> Array[TeaRecipe]:
	var result: Array[TeaRecipe] = []
	if recipe_book == null:
		return result
	return recipe_book.recipes
