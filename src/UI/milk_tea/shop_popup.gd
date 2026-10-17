class_name ShopPopup
extends Control

signal close_requested
signal make_requested(recipe: Array[String])

var _production: TeaProduction
var _production_panel: TeaProductionPanel

var _tea: TeaMaking
var _station := false

func _ready() -> void:
	$Center/Panel/Margin/Content/Close.pressed.connect(func() -> void: close_requested.emit())

func bind_tea_making(tea: TeaMaking) -> void:
	_tea = tea
	_tea.changed.connect(_refresh_recipe)
	for ingredient: String in TeaMaking.LABELS:
		var button := Button.new()
		button.text = "加入" + TeaMaking.LABELS[ingredient]
		button.pressed.connect(func() -> void:
			if _tea.add_ingredient(ingredient) == ERR_INVALID_DATA:
				$Center/Panel/Margin/Content/RecipeStatus.text = "顺序错误，请从红茶重新开始。"
			)
		$Center/Panel/Margin/Content/Ingredients.add_child(button)
	_refresh_recipe()

func is_making_station() -> bool:
	return _station

func _refresh_recipe() -> void:
	var demo_recipe := is_instance_valid(_tea) and _tea.has_session()
	$Center/Panel/Margin/Content/Ingredients.visible = _station and demo_recipe
	$Center/Panel/Margin/Content/RecipeStatus.visible = _station and demo_recipe
	if is_instance_valid(_production_panel):
		_production_panel.visible = _station and not demo_recipe
		$Center/Panel/Margin/Content/DescriptionScroll.visible = not _station or demo_recipe
	$Center/Panel/Margin/Content/RecipeStatus.text = _tea.get_instruction() if is_instance_valid(_tea) else "当前没有制作目标。"
	for button: Button in $Center/Panel/Margin/Content/Ingredients.get_children():
		button.disabled = not is_instance_valid(_tea) or not _tea.is_active()

func present(point: InteractionPoint) -> void:
	_station = point.interaction_id == &"tea_station"
	_refresh_recipe()
	$Center/Panel/Margin/Content/Title.text = point.display_name
	$Center/Panel/Margin/Content/DescriptionScroll/Description.text = (
		"固定配方：珍珠奶茶一杯\n按红茶 → 牛奶 → 珍珠依次投料。\n顺序错误会清空本杯进度；关窗可保留进度。\n仅当前玩法目标可制作，不消耗库存。"
		if _station and is_instance_valid(_tea) else point.description
	)
	$Center/Panel/Margin/Content/DescriptionScroll.scroll_vertical = 0
	if _production != null:
		var crafting := _station and not (is_instance_valid(_tea) and _tea.has_session())
		_production_panel.visible = crafting
		$Center/Panel/Margin/Content/DescriptionScroll.visible = not crafting
		if crafting:
			_production_panel.refresh(true)
		elif point.interaction_id == &"orders":
			$Center/Panel/Margin/Content/DescriptionScroll/Description.text = _production.get_order_text() + "\n\n到制作台选择对应原料，完成后自动交付。"
		elif point.interaction_id == &"storage":
			var lines := PackedStringArray(["店铺原有食材 · 库存（份）"])
			for ingredient in _production.get_ingredients():
				lines.append("%s  %d" % [ingredient.name, _production.get_stock(ingredient.id)])
			$Center/Panel/Margin/Content/DescriptionScroll/Description.text = "\n".join(lines)

func configure_production(production: TeaProduction) -> void:
	_production = production
	_production_panel = TeaProductionPanel.new()
	_production_panel.name = "ProductionPanel"
	var content := $Center/Panel/Margin/Content
	content.add_child(_production_panel)
	content.move_child(_production_panel, $Center/Panel/Margin/Content/Close.get_index())
	_production_panel.configure(production)
	_production_panel.make_requested.connect(func(recipe: Array[String]) -> void: make_requested.emit(recipe))
	_production_panel.hide()

func show_production_result(result: Dictionary) -> void:
	_production_panel.show_result(result)

func get_default_focus() -> Control:
	return $Center/Panel/Margin/Content/Close
