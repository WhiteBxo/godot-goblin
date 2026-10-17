class_name IngredientDefinition
extends Resource
## Static catalog data only. Discovery and quantities live in WarehouseInventory.

@export var id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D
@export_enum("human", "otherworld") var origin: String = "human"
@export_enum("tea", "milk", "syrup", "topping", "product", "material") var category: String = "tea"
@export var rarity: String = "普通"
@export var flavor_tags: PackedStringArray = []
@export var combat_attributes: PackedStringArray = []
@export var special_effects: PackedStringArray = []
@export var acquisition_sources: PackedStringArray = []
