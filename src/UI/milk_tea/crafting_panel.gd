class_name CraftingPanel
extends VBoxContainer
## Inventory on the left; available recipes and a batch mixing tray on the right.
## Read-only towards services; every commit goes through craft_requested().

signal craft_requested(materials: Array[String], quantity: int)

const CATEGORY_ORDER: Dictionary = {"tea": 0, "milk": 1, "syrup": 2, "topping": 3, "material": 4}

var _production: TeaProduction
var _selected: Array[String] = []
var _selected_product_id: String = ""
var _last_result: Dictionary = {}
var _refreshing := false
## Chip rows by material, so a newly added one can pop in without a rebuild.
var _chip_rows: Dictionary = {}
## Derived from the recipes this session may offer; locked recipes never reach the lists.
var _available_materials: Dictionary = {}
var _available_products: Dictionary = {}
## Recipe rows stay mounted between refreshes so the clicked row keeps focus.
var _recipe_buttons: Dictionary[String, Button] = {}
var _recipe_signature := ""

@onready var _list: ItemList = $Body/Left/MaterialList
@onready var _detail: Label = $Body/Left/ProductDetail
@onready var _redo: Button = $Body/Left/RedoButton
@onready var _recipe_list: ScrollContainer = $Body/Right/RecipeList
@onready var _recipe_rows: GridContainer = $Body/Right/RecipeList/Rows
@onready var _capacity: Label = $Body/Right/Batch/Capacity
@onready var _quantity: SpinBox = $Body/Right/Batch/Quantity
@onready var _maximum: Button = $Body/Right/Batch/Maximum
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
	_quantity.value_changed.connect(func(_value: float) -> void:
		_rebuild_chips()
		_refresh_preview())
	_maximum.pressed.connect(func() -> void: set_batch_quantity(_production.get_max_craftable(_selected)))
	_redo.pressed.connect(redo_selected_product)
	_clear.pressed.connect(func() -> void: clear_selection())
	_craft.pressed.connect(func() -> void: submit())
	_result.visible = false
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
	_collect_available(_production.get_known_recipes())
	_prune_selection()
	_rebuild_list()
	_rebuild_recipes()
	_order_line.text = _production.get_order_text()
	if clear_result:
		_result.text = ""
		_result.theme_type_variation = &""
		_result.visible = false
	_rebuild_chips()
	_refresh_preview()
	_sync_selected_product()
	_refreshing = false
	_list.get_v_scroll_bar().set_deferred("value", scroll)

func batch_quantity() -> int:
	return int(_quantity.value)

func set_batch_quantity(quantity: int) -> void:
	_quantity.value = clampi(quantity, 1, maxi(1, _production.get_max_craftable(_selected)))

## Replaces the tray in full, even if stock is insufficient, so shortages are visible.
func select_recipe(product_id: String) -> bool:
	if not is_instance_valid(_production) or not _is_product_available(product_id):
		return false
	var recipe := _production.get_recipe_by_product(product_id)
	if recipe == null:
		return false
	_selected.assign(recipe.materials)
	_quantity.set_value_no_signal(1)
	_after_selection_change(true)
	UIFlourish.settle(_preview, 0.96)
	return true

func _on_recipe_pressed(product_id: String) -> void:
	if not _refreshing:
		select_recipe(product_id)

func _rebuild_recipes() -> void:
	var selected_key := TeaRecipe.key_for(_selected)
	var recipes: Array[TeaRecipe] = _production.get_known_recipes()
	var signature_parts: Array[String] = [selected_key]
	for recipe: TeaRecipe in recipes:
		signature_parts.append("%s:%d" % [recipe.product_id, _production.get_max_craftable(recipe.materials)])
	var signature := "|".join(signature_parts)
	if signature == _recipe_signature and _recipe_buttons.size() == recipes.size():
		return
	var scroll := _recipe_list.get_v_scroll_bar().value
	var focused := _focused_recipe()
	for child in _recipe_rows.get_children():
		_recipe_rows.remove_child(child)
		child.queue_free()
	_recipe_buttons.clear()
	for recipe: TeaRecipe in recipes:
		var maximum := _production.get_max_craftable(recipe.materials)
		var row := _make_recipe_row(recipe, maximum, TeaRecipe.key_for(recipe.materials) == selected_key)
		_recipe_rows.add_child(row)
		_recipe_buttons[recipe.product_id] = row
	_sync_recipe_neighbors()
	if not focused.is_empty() and _recipe_buttons.has(focused):
		_recipe_buttons[focused].grab_focus()
	_recipe_signature = signature
	_recipe_list.get_v_scroll_bar().set_deferred("value", scroll)

## A recipe is a line on the menu card: the drink on the left, the number of
## cups it still yields on the right, both on the same paper row.
func _make_recipe_row(recipe: TeaRecipe, maximum: int, selected: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 34)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.theme_type_variation = &"RecipeRowSelected" if selected else &"RecipeRow"
	button.tooltip_text = " + ".join(_production.get_recipe_names(recipe.materials))
	button.pressed.connect(func() -> void: _on_recipe_pressed(recipe.product_id))
	button.focus_entered.connect(_reveal_row.bind(button))
	var content := HBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 6)
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 7
	content.offset_right = -9
	# The cup itself, at its native 32px so the pixel art stays on the grid.
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _product_icon(recipe.product_id)
	content.add_child(icon)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.text = _display_name(recipe.product_id)
	content.add_child(name_label)
	var count := Label.new()
	count.name = "Count"
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.theme_type_variation = &"Value" if maximum > 0 else &"Warning"
	count.text = "%d 杯" % maximum if maximum > 0 else "缺料"
	content.add_child(count)
	return button

## The list is already "what I can make", so the data's "（成品）" suffix only
## eats a third of the row width.
func _display_name(product_id: String) -> String:
	return _production.get_item_name(product_id).replace("（成品）", "")

func _reveal_row(button: Button) -> void:
	if is_instance_valid(button):
		_recipe_list.ensure_control_visible(button)

## Two columns, so six drinks fit a 360px-tall screen without a scroll bar.
func _sync_recipe_neighbors() -> void:
	if not is_instance_valid(_production):
		return
	var rows: Array[Button] = []
	for recipe: TeaRecipe in _production.get_known_recipes():
		rows.append(_recipe_buttons.get(recipe.product_id))
	var columns := maxi(1, _recipe_rows.columns)
	var last := rows.size() - 1
	for index in range(rows.size()):
		var row := rows[index]
		if row == null:
			continue
		var up: Button = rows[maxi(0, index - columns)]
		var down: Button = rows[mini(last, index + columns)]
		var left: Button = rows[maxi(0, index - 1)]
		var right: Button = rows[mini(last, index + 1)]
		row.focus_neighbor_top = row.get_path_to(up)
		row.focus_neighbor_bottom = row.get_path_to(down)
		row.focus_neighbor_left = row.get_path_to(left)
		row.focus_neighbor_right = row.get_path_to(right)

func _focused_recipe() -> String:
	# Inventory signals also fire while a session is being replaced, which can
	# catch this panel outside the tree; there is no focus to read then.
	var viewport := get_viewport()
	if viewport == null:
		return ""
	var owner := viewport.gui_get_focus_owner()
	if owner == null:
		return ""
	for product_id: String in _recipe_buttons:
		if _recipe_buttons[product_id] == owner:
			return product_id
	return ""

func add_material(id: String) -> bool:
	if not is_instance_valid(_production) or id.is_empty():
		return false
	if _production.get_stock(id) <= _selected_count(id):
		return false
	_selected.append(id)
	_after_selection_change(false)
	_pop_chip(id)
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
		_last_result = {"ok": false, "code": "busy", "message": "暂时无法制作，请稍后再试。"}
		return _last_result
	craft_requested.emit(selected_materials(), batch_quantity())
	if _last_result.is_empty():
		_last_result = {"ok": false, "code": "busy", "message": "制作没有成功，请再试一次。"}
	return _last_result

func show_result(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	var succeeded: bool = bool(result.get("ok", false))
	_result.text = str(result.get("message", ""))
	_result.visible = not _result.text.is_empty()
	_result.theme_type_variation = &"Success" if succeeded else &"Warning"
	if succeeded:
		_selected.clear()
		_selected_product_id = ""
		_detail.text = "选中成品可查看详情并重做"
		_redo.disabled = true
		_rebuild_chips()
		refresh(false)
		_present_batch(result)
	else:
		_refresh_preview()
		if _result.visible:
			# A refusal is felt as a recoil, not only read as red text.
			UIFlourish.refuse(_result)

## The cups leave the counter before the sentence is read, beside the button's
## label rather than on top of it.
func _present_batch(result: Dictionary) -> void:
	UIFlourish.cups(_craft, _product_icon(str(result.get("product_id", ""))), int(result.get("quantity", 0)), Vector2(0.05, 0.5))
	if _result.visible:
		UIFlourish.settle(_result, 0.94)

func _product_icon(product_id: String) -> Texture2D:
	if product_id.is_empty() or not is_instance_valid(_production):
		return null
	var inventory := _production.get_inventory()
	if not is_instance_valid(inventory):
		return null
	# Read the definition directly: get_ingredient_view() hides undiscovered
	# products, and a recipe the player can already make must still show its cup.
	var definition := inventory.get_definition(product_id)
	return definition.icon if definition != null else null

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
	if not is_inside_tree():
		return
	var first := recipe_row(0)
	if first != null:
		first.grab_focus()
	else:
		_recipe_list.grab_focus()

func get_default_focus() -> Control:
	return recipe_row(0)

## Rows are plain buttons over the same paper; tests and hosts address them by
## position instead of by ItemList index.
func recipe_count() -> int:
	return _recipe_rows.get_child_count()

func recipe_row(index: int) -> Button:
	if index < 0 or index >= _recipe_rows.get_child_count():
		return null
	return _recipe_rows.get_child(index) as Button

func uses_native_gui_input() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return is_instance_valid(focus) and (focus == _list or focus == _recipe_list or _recipe_list.is_ancestor_of(focus) or focus == _quantity or _quantity.is_ancestor_of(focus))

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
	_rebuild_recipes()
	if clear_result:
		_result.text = ""
		_result.theme_type_variation = &""
		_result.visible = false
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
	_chip_rows.clear()
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
		var row := _make_chip(id, counts[id])
		_chip_rows[id] = row
		_chips.add_child(row)
	_clear.disabled = _selected.is_empty()

## Only the row that just gained a portion pops; the rest of the tray stays put.
func _pop_chip(id: String) -> void:
	var row: Control = _chip_rows.get(id, null)
	if is_instance_valid(row):
		UIFlourish.settle(row, 0.76)

func _make_chip(id: String, amount: int) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text = "%s ×%d / %d" % [_production.get_item_name(id), amount * int(_quantity.value), _production.get_stock(id)]
	if _production.get_stock(id) < amount:
		label.theme_type_variation = &"Warning"
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
	var maximum := _production.get_max_craftable(_selected)
	_quantity.max_value = maxi(1, maximum)
	_quantity.editable = maximum > 0
	_maximum.disabled = maximum < 1
	_capacity.text = "最多 %d 杯" % maximum if maximum > 0 else ("原料不足" if not _selected.is_empty() else "先选一个配方")
	_capacity.theme_type_variation = &"Warning" if maximum <= 0 and not _selected.is_empty() else &"Hint"
	var preview := _production.preview_craft(_selected, int(_quantity.value))
	match str(preview.code):
		"ok":
			_preview.text = "→ %s ×%d%s" % [str(preview.product_name).replace("（成品）", ""), int(_quantity.value), "（计入当前订单）" if preview.advances_order else ""]
			_preview.theme_type_variation = &"Success"
		"empty":
			_preview.text = "选择配方和杯数，即可制作入库"
			_preview.theme_type_variation = &""
		_:
			_preview.text = str(preview.message)
			_preview.theme_type_variation = &"Warning"
	_craft.disabled = preview.code != "ok"
	var label := "制作 %d 杯并入库" % int(_quantity.value)
	if label != _craft.text:
		_craft.text = label
		if not _craft.disabled:
			# The batch size is the thing being chosen, so the action answers it.
			UIFlourish.settle(_craft, 0.96)

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
	for recipe: TeaRecipe in _production.get_known_recipes():
		if recipe.product_id == product_id:
			return true
	return false

func _compare_ingredients(a: Dictionary, b: Dictionary) -> bool:
	var order_a: int = CATEGORY_ORDER.get(a.category, 9)
	var order_b: int = CATEGORY_ORDER.get(b.category, 9)
	if order_a != order_b:
		return order_a < order_b
	return str(a.id) < str(b.id)
