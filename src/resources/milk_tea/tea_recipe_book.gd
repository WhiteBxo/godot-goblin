class_name TeaRecipeBook
extends Resource
## Shared recipe catalog; both menus reference the same resource to stay in sync.

@export var recipes: Array[TeaRecipe] = []

## Catalog order is preserved; locked recipes are simply left out for that session.
func get_recipes_for(state: Node) -> Array[TeaRecipe]:
	var result: Array[TeaRecipe] = []
	for recipe: TeaRecipe in recipes:
		if recipe != null and recipe.is_available(state):
			result.append(recipe)
	return result

func find_by_materials(materials: Array) -> TeaRecipe:
	var key := TeaRecipe.key_for(materials)
	for recipe: TeaRecipe in recipes:
		if recipe != null and recipe.get_material_key() == key:
			return recipe
	return null

func find_by_product(product_id: String) -> TeaRecipe:
	if product_id.is_empty():
		return null
	for recipe: TeaRecipe in recipes:
		if recipe != null and recipe.product_id == product_id:
			return recipe
	return null
