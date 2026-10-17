class_name CraftingPanel
extends VBoxContainer
## Two-column crafting view: materials and owned cups on the left, the mixing tray on the right.
## Read-only towards services; every commit goes through craft_requested().

signal craft_requested(materials: Array[String])

const CATEGORY_ORDER: Dictionary = {"tea": 0, "milk": 1, "syrup": 2, "topping": 3, "material": 4}
const COLOR_OK := Color("bde3a5")
const COLOR_WARN := Color("ffd08c")

var _production: TeaProduction
var _selected: Array[String] = []
var _selected_product_id: String = ""
var _last_result: Dictionary = {}
var _refreshing := false
## Derived from the recipes this session may offer; locked recipes never reach the lists.
var _available_materials: Dictionary = {}
var _available_products: Dictionary = {}

@onready var _list: ItemList = $Body/Left/MaterialList
@onready var _detail: Label = $Body/Left/ProductDetail
@onready var _redo: Button = $Body/Left/RedoButton
@onready var _order_line: Label = $Body/Right/OrderLine
@onready var _clear: Button = $Body/Right/SelectedHeader/ClearButton
@onready var _chips: GridContainer = $Body/Right/SelectedScroll/ChipGrid
@onready var _preview: Label = $Body/Right/PreviewLine
@onready var _craft: Button = $Body/Right/CraftButton
@onready var _result: Label = $Body/Right/ResultLabel

func _ready() -> void:
	_list.item_clicked.connect(_on_item_clicked)
	_list.item_activated.connect(_on_item_activated)
	_list.item_selected.connect(_on_item_selected)
	_redo.pressed.connect(redo_selected_product)
	_clear.pressed.connect(func() -> void: clear_selection())
	_craft.pressed.connect(func() -> void: submit())
	_refresh_preview()

func configure(production: TeaProduction) -> void:
	if is_instance_valid(_production) and _production.changed.is_connected(refresh):
		_production.changed.disconnect(refresh)
	_production = production
	if is_instance_valid(_production):
		_production.changed.connect(refresh)
	refresh(true)

func refresh(clear_result: bool = false) -> void:
	if _refreshing or not is_instance_valid(_production):
		return
	_refreshing = true
	var scroll := int(_list.get_v_scroll_bar().value)
	_collect_available(_production.get_available_recipes())
	_prune_selection()
	_rebuild_list()
	_order_line.text = _production.get_order_text()
	if clear_result:
		_result.text = ""
		_result.remove_theme_color_override("font_color")
	_rebuild_chips()
	_refresh_preview()
	_sync_selected_product()
	_refreshing = false
	_list.get_v_scroll_bar().set_deferred("value", scroll)

func add_material(id: String) -> bool:
	if not is_instance_valid(_production) or id.is_empty():
		return false
	if _production.get_stock(id) <= _selected_count(id):
		return false
	_selected.append(id)
	_after_selection_change(false)
	return true

func remove_material(id: String) -> bool:
	var index := _selected.rfind(id)
	if index < 0:
		return false
	_selected.remove_at(index)
	_after_selection_change(false)
	return true

func clear_selection() -> bool:
	if _selected.is_empty():
		return false
	_selected.clear()
	_after_selection_change(false)
	return true

func selected_materials() -> Array[String]:
	return _selected.duplicate()

func selection_count() -> int:
	return _selected.size()

func select_product(id: String) -> bool:
	if not is_instance_valid(_production) or id.is_empty():
		return false
	_selected_product_id = id
	_sync_selected_product()
	return true

func selected_product_id() -> String:
	return _selected_product_id

func redo_selected_product() -> bool:
	if not is_instance_valid(_production) or _selected_product_id.is_empty():
		return false
	if not _is_product_available(_selected_product_id):
		return false
	var recipe := _production.get_recipe_by_product(_selected_product_id)
	if recipe == null:
		return false
	_selected.clear()
	for id: String in recipe.materials:
		_selected.append(id)
	_after_selection_change(true)
	return true

## Emits the request and returns the result the host filled in synchronously.
func submit() -> Dictionary:
	_last_result = {}
	if not is_instance_valid(_production):
		_last_result = {"ok": false, "code": "busy", "message": "制作系统尚未就绪。"}
		return _last_result
	craft_requested.emit(selected_materials())
	if _last_result.is_empty():
		_last_result = {"ok": false, "code": "busy", "message": "制作请求没有响应。"}
	return _last_result

func show_result(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	var succeeded: bool = bool(result.get("ok", false))
	_result.text = str(result.get("message", ""))
	_result.add_theme_color_override("font_color", COLOR_OK if succeeded else COLOR_WARN)
	if succeeded:
		_selected.clear()
		_selected_product_id = ""
		_detail.text = "选中成品可查看详情并重做"
		_redo.disabled = true
		_rebuild_chips()
		refresh(false)
	else:
		_refresh_preview()

func result_text() -> String:
	return _result.text

func preview_text() -> String:
	return _preview.text

func order_text() -> String:
	return _order_line.text

func is_craft_enabled() -> bool:
	return not _craft.disabled

func is_material_available(id: String) -> bool:
	return is_instance_valid(_production) and _production.get_stock(id) > 0

func selection_rows() -> int:
	return _chips.get_child_count()

func grab_default_focus() -> void:
	if is_inside_tree():
		_list.grab_focus()

func uses_native_gui_input() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return is_instance_valid(focus) and (focus == _list or _list.is_ancestor_of(focus))

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not _list.has_focus():
		return
	if not event.is_action_pressed("interact") or event.is_echo():
		return
	var items := _list.get_selected_items()
	if items.is_empty():
		return
	_activate_index(items[0])
	get_viewport().set_input_as_handled()

func _on_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	_activate_index(index)

func _on_item_activated(index: int) -> void:
	_activate_index(index)

func _on_item_selected(index: int) -> void:
	if _refreshing:
		return
	var metadata: Variant = _list.get_item_metadata(index)
	if metadata is Dictionary and metadata.get("kind", "") == "product":
		select_product(str(metadata.get("id", "")))

func _activate_index(index: int) -> void:
	var metadata: Variant = _list.get_item_metadata(index)
	if not metadata is Dictionary:
		return
	var id := str(metadata.get("id", ""))
	if metadata.get("kind", "") == "product":
		select_product(id)
	else:
		add_material(id)

func _after_selection_change(clear_result: bool) -> void:
	if clear_result:
		_result.text = ""
		_result.remove_theme_color_override("font_color")
	_rebuild_chips()
	_refresh_preview()

func _prune_selection() -> void:
	if _selected.is_empty() or not is_instance_valid(_production):
		return
	var known: Dictionary = {}
	for ingredient: Dictionary in _production.get_ingredients():
		known[ingredient.id] = true
	var kept: Array[String] = []
	for id: String in _selected:
		if known.has(id) and _available_materials.has(id):
			kept.append(id)
	_selected = kept

func _rebuild_list() -> void:
	var ingredients: Array[Dictionary] = []
	var products: Array[Dictionary] = []
	for ingredient: Dictionary in _production.get_ingredients():
		if ingredient.category == "product":
			if _available_products.has(ingredient.id):
				products.append(ingredient)
		elif ingredient.category != "story_item" and _available_materials.has(ingredient.id):
			ingredients.append(ingredient)
	ingredients.sort_custom(_compare_ingredients)
	products.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.name) < str(b.name))
	var order := _production.get_order()
	var order_product := str(order.get("product_id", ""))
	_list.clear()
	_add_header("原料")
	for ingredient: Dictionary in ingredients:
		_add_row(ingredient, "ingredient", order_product)
	if products.is_empty():
		_add_header("已有成品")
		var empty := _list.add_item("（还没有成品）", null, false)
		_list.set_item_disabled(empty, true)
		return
	_add_header("已有成品 · %d 种" % products.size())
	for product: Dictionary in products:
		_add_row(product, "product", order_product)

func _add_header(title: String) -> void:
	var index := _list.add_item(title, null, false)
	_list.set_item_disabled(index, true)

func _add_row(item: Dictionary, kind: String, order_product: String) -> void:
	var amount := int(item.quantity)
	var suffix := ""
	if kind == "ingredient" and amount <= 0:
		suffix = " · 缺货"
	elif kind == "product" and str(item.id) == order_product:
		suffix = " · 当前订单"
	var index := _list.add_item("%s  ×%d%s" % [item.name, amount, suffix], item.icon)
	_list.set_item_metadata(index, {"kind": kind, "id": item.id})
	if kind == "ingredient" and amount <= 0:
		_list.set_item_disabled(index, true)

func _rebuild_chips() -> void:
	for child in _chips.get_children():
		_chips.remove_child(child)
		child.queue_free()
	var counts := _counts(_selected)
	if counts.is_empty():
		var hint := Label.new()
		hint.text = "尚未选择材料"
		hint.theme_type_variation = &"Hint"
		_chips.add_child(hint)
	for id: String in counts:
		_chips.add_child(_make_chip(id, counts[id]))
	_clear.disabled = _selected.is_empty()

func _make_chip(id: String, amount: int) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text = "%s ×%d" % [_production.get_item_name(id), amount]
	if _production.get_stock(id) < amount:
		label.add_theme_color_override("font_color", COLOR_WARN)
	var remove := Button.new()
	remove.text = "×"
	remove.tooltip_text = "移除一份"
	remove.custom_minimum_size = Vector2(24, 20)
	remove.pressed.connect(func() -> void: remove_material(id))
	row.add_child(label)
	row.add_child(remove)
	return row

func _refresh_preview() -> void:
	if not is_instance_valid(_production):
		_preview.text = ""
		_craft.disabled = true
		_clear.disabled = true
		return
	var preview := _production.preview_craft(_selected)
	match str(preview.code):
		"ok":
			_preview.text = "→ %s%s" % [preview.product_name, "（计入当前订单）" if preview.advances_order else ""]
			_preview.add_theme_color_override("font_color", COLOR_OK)
		"empty":
			_preview.text = "从左侧点选原料，或在成品上重做"
			_preview.remove_theme_color_override("font_color")
		_:
			_preview.text = str(preview.message)
			_preview.add_theme_color_override("font_color", COLOR_WARN)
	_craft.disabled = _selected.is_empty()

func _sync_selected_product() -> void:
	if _selected_product_id.is_empty() or not is_instance_valid(_production):
		return
	var recipe := _production.get_recipe_by_product(_selected_product_id)
	if recipe == null or not _is_product_available(_selected_product_id):
		_detail.text = "%s · %d 杯\n暂无已知配方" % [_production.get_item_name(_selected_product_id), _production.get_stock(_selected_product_id)]
		_redo.disabled = true
		return
	_detail.text = "%s · %d 杯\n配方：%s" % [
		_production.get_item_name(_selected_product_id), _production.get_stock(_selected_product_id),
		" + ".join(_production.get_recipe_names(recipe.materials))]
	_redo.disabled = false

func _selected_count(id: String) -> int:
	var count := 0
	for selected: String in _selected:
		if selected == id:
			count += 1
	return count

func _counts(materials: Array) -> Dictionary:
	var counts: Dictionary = {}
	for id: Variant in materials:
		if id is String:
			counts[id] = int(counts.get(id, 0)) + 1
	return counts

func _collect_available(recipes: Array[TeaRecipe]) -> void:
	_available_materials.clear()
	_available_products.clear()
	for recipe: TeaRecipe in recipes:
		_available_products[recipe.product_id] = true
		for id: String in recipe.materials:
			_available_materials[id] = true

func _is_product_available(product_id: String) -> bool:
	for recipe: TeaRecipe in _production.get_available_recipes():
		if recipe.product_id == product_id:
			return true
	return false

func _compare_ingredients(a: Dictionary, b: Dictionary) -> bool:
	var order_a: int = CATEGORY_ORDER.get(a.category, 9)
	var order_b: int = CATEGORY_ORDER.get(b.category, 9)
	if order_a != order_b:
		return order_a < order_b
	return str(a.id) < str(b.id)
