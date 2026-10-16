class_name TeaMaking
extends Node
## Fixed recipe gameplay; no story IDs or flags belong here.

signal changed
signal recipe_completed(recipe_id: String, session: int)

const RECIPES: Dictionary = {"pearl_milk_tea": ["tea", "milk", "pearls"]}
const LABELS: Dictionary = {"tea": "红茶", "milk": "牛奶", "pearls": "珍珠"}

var _recipe: String = ""
var _session: int = 0
var _progress: int = 0
var _completed := false
var _can_make: Callable

func configure(can_make: Callable) -> void:
	_can_make = can_make

func begin(recipe_id: String) -> int:
	cancel()
	if not RECIPES.has(recipe_id):
		return 0
	_recipe = recipe_id
	changed.emit()
	return _session

func cancel() -> void:
	_session += 1
	_recipe = ""
	_progress = 0
	_completed = false
	changed.emit()

func is_active() -> bool:
	return not _recipe.is_empty() and not _completed

func get_instruction() -> String:
	if _completed:
		return "制作完成！关闭弹窗后继续剧情。"
	if not is_active():
		return "当前没有制作目标。"
	return "珍珠奶茶：红茶 → 牛奶 → 珍珠（%d/3）\n下一步：%s" % [_progress, LABELS[RECIPES[_recipe][_progress]]]

func add_ingredient(ingredient: String) -> Error:
	if not is_active() or not can_process() or get_tree().paused or not _can_make.is_valid() or not _can_make.call():
		return ERR_BUSY
	if ingredient != RECIPES[_recipe][_progress]:
		_progress = 0
		changed.emit()
		return ERR_INVALID_DATA
	_progress += 1
	if _progress == RECIPES[_recipe].size():
		_completed = true # Consume before any synchronous completion listener.
		var recipe := _recipe
		var session := _session
		changed.emit()
		recipe_completed.emit(recipe, session)
	else:
		changed.emit()
	return OK
