class_name TeaMenu
extends Resource
## Stock is measured in portions; each listed ingredient costs one portion per cup.

@export var ingredients: Array[Dictionary] = []
@export var initial_stock: Dictionary = {}
@export var orders: Array[Dictionary] = []
