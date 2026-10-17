class_name IngredientDefinition
extends Resource
## Static catalog data only. Discovery and quantities live in WarehouseInventory.

@export var id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D
@export_enum("human", "otherworld") var origin: String = "human"
@export_enum("tea", "milk", "syrup", "topping", "product", "material", "story_item") var category: String = "tea"
@export var rarity: String = "普通"
@export var flavor_tags: PackedStringArray = []
@export var combat_attributes: PackedStringArray = []
@export var special_effects: PackedStringArray = []
@export var acquisition_sources: PackedStringArray = []
## Design source rows this entry came from, e.g. ["F05", "W02"] when two
## spreadsheet rows describe the same item. Keeps the catalog traceable.
@export var source_ids: PackedStringArray = []
## Spreadsheet 形态 column; empty for the teaching catalog.
@export var form: String = ""
## Spreadsheet 支持加工方式 column; empty for the teaching catalog.
@export var processing_methods: PackedStringArray = []
## Spreadsheet 标价（金币）column; 0 means no public price.
@export var price: int = 0
## Spreadsheet 图鉴描述 column, shown only once the item is discovered.
@export_multiline var description: String = ""
