class_name ShopPopup
extends Control

signal close_requested

func _ready() -> void:
	$Center/Panel/Margin/Content/Close.pressed.connect(func() -> void: close_requested.emit())

func present(point: InteractionPoint) -> void:
	$Center/Panel/Margin/Content/Title.text = point.display_name
	$Center/Panel/Margin/Content/DescriptionScroll/Description.text = point.description
	$Center/Panel/Margin/Content/DescriptionScroll.scroll_vertical = 0

func get_default_focus() -> Control:
	return $Center/Panel/Margin/Content/Close
