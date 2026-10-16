class_name ShopPopup
extends Control

signal close_requested
signal make_requested(recipe: Array[String])

var _production: TeaProduction
var _production_panel: TeaProductionPanel

func _ready() -> void:
	$Center/Panel/Margin/Content/Close.pressed.connect(func() -> void: close_requested.emit())

func present(point: InteractionPoint) -> void:
	$Center/Panel/Margin/Content/Title.text = point.display_name
	$Center/Panel/Margin/Content/DescriptionScroll/Description.text = point.description
	$Center/Panel/Margin/Content/DescriptionScroll.scroll_vertical = 0
	if _production != null:
		var crafting := point.interaction_id == &"tea_station"
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
