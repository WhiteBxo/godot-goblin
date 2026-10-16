extends MainGame
## F6: the real game host plus debug-only UI launch buttons.

func _ready() -> void:
	super._ready()
	if not OS.has_feature("debug"):
		return
	var menu := HBoxContainer.new()
	menu.position = Vector2(16, 40)
	menu.theme = preload("res://src/resources/ui/game_theme.tres")
	$DebugLayer.add_child(menu)
	_add_button(menu, "店铺弹窗", func() -> void:
		if not get_ui_manager().has_modal():
			_shop_ui.open(_shop_level.get_interaction_points()[0]))
	_add_button(menu, "对白", func() -> void: get_dialogue_manager().start_dialogue("demo.greeting"))
	_add_button(menu, "暂停", func() -> void: get_ui_manager().set_paused(true))

func _add_button(menu: HBoxContainer, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	menu.add_child(button)
