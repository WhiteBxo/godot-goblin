extends SceneTree
## Generates res://src/resources/ui/game_theme.tres from UITokens.
## Run: godot --headless --path . --script res://tools/ui/build_theme.gd

const THEME_PATH := "res://src/resources/ui/game_theme.tres"
const FONT_PATH := "res://assets/fonts/fusion_pixel/fusion-pixel-12px-monospaced-zh_hans.otf.woff2"
const T := preload("res://src/resources/ui/ui_tokens.gd")


func _initialize() -> void:
	var theme: Theme = ResourceLoader.load(THEME_PATH) as Theme
	if theme == null:
		theme = Theme.new()
	theme.clear()
	theme.default_font = load(FONT_PATH) as Font
	theme.default_font_size = T.FONT_BODY
	_build_containers(theme)
	_build_labels(theme)
	_build_buttons(theme)
	_build_item_list(theme)
	_build_tabs(theme)
	_build_inputs(theme)
	_build_scrollbars(theme)
	_build_popups(theme)
	_build_misc(theme)
	var error := ResourceSaver.save(theme, THEME_PATH)
	print("THEME: save=%d types=%d" % [error, theme.get_type_list().size()])
	quit(0 if error == OK else 1)


func _flat(bg: Color, border: Color = Color.TRANSPARENT, width: int = 0, radius: int = 0,
		ml: float = 0.0, mt: float = 0.0, mr: float = 0.0, mb: float = 0.0,
		shadow: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	if width > 0:
		style.set_border_width_all(width)
		style.border_color = border
	if radius > 0:
		style.set_corner_radius_all(radius)
	style.content_margin_left = ml
	style.content_margin_top = mt
	style.content_margin_right = mr
	style.content_margin_bottom = mb
	if shadow:
		style.shadow_color = T.SHADOW
		style.shadow_size = 2
		style.shadow_offset = Vector2(0, 2)
	return style


func _line(color: Color, thickness: int = 1, vertical: bool = false) -> StyleBoxLine:
	var style := StyleBoxLine.new()
	style.color = color
	style.thickness = thickness
	style.vertical = vertical
	return style


func _empty(mt: float = 0.0) -> StyleBoxEmpty:
	var style := StyleBoxEmpty.new()
	style.content_margin_top = mt
	return style


func _build_containers(theme: Theme) -> void:
	var panel := _flat(T.PANEL, T.BORDER, T.BORDER_PANEL, T.RADIUS_PANEL, 0, 0, 0, 0, true)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_type_variation("InsetPanel", "PanelContainer")
	theme.set_stylebox("panel", "InsetPanel",
		_flat(T.PANEL, T.BORDER, T.BORDER_PANEL, T.RADIUS_PANEL, T.SPACE_3, T.SPACE_3, T.SPACE_3, T.SPACE_3, true))
	theme.set_type_variation("CardPanel", "PanelContainer")
	theme.set_stylebox("panel", "CardPanel",
		_flat(T.RAISED, T.BORDER_SOFT, 1, T.RADIUS_BUTTON, T.SPACE_2, T.SPACE_2, T.SPACE_2, T.SPACE_2))
	theme.set_type_variation("SunkenPanel", "PanelContainer")
	theme.set_stylebox("panel", "SunkenPanel",
		_flat(T.SUNKEN, T.BORDER_SOFT, 1, T.RADIUS_BUTTON, 6, 6, 6, 6))

	theme.set_constant("margin_left", "MarginContainer", T.SPACE_3)
	theme.set_constant("margin_top", "MarginContainer", T.SPACE_2)
	theme.set_constant("margin_right", "MarginContainer", T.SPACE_3)
	theme.set_constant("margin_bottom", "MarginContainer", T.SPACE_2)
	theme.set_constant("separation", "VBoxContainer", T.SPACE_2)
	theme.set_constant("separation", "HBoxContainer", T.SPACE_2)
	theme.set_constant("h_separation", "GridContainer", T.SPACE_2)
	theme.set_constant("v_separation", "GridContainer", T.SPACE_2)
	theme.set_stylebox("panel", "ScrollContainer", _empty())
	theme.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())


func _build_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", T.TEXT)
	theme.set_constant("line_spacing", "Label", T.LINE_SEPARATION)
	theme.set_constant("outline_size", "Label", 0)

	_label_variation(theme, "Title", T.ACCENT, T.FONT_TITLE)
	_label_variation(theme, "HeroTitle", T.ACCENT, T.FONT_HERO)
	_label_variation(theme, "H2", T.ACCENT, T.FONT_BODY)
	_label_variation(theme, "Speaker", T.ACCENT, T.FONT_BODY)
	_label_variation(theme, "Hint", T.TEXT_MUTED, T.FONT_BODY)
	_label_variation(theme, "Muted", T.TEXT_MUTED, T.FONT_BODY)
	_label_variation(theme, "Subtitle", T.TEXT_DIM, T.FONT_BODY)
	_label_variation(theme, "Value", T.TEXT_DIM, T.FONT_BODY)
	_label_variation(theme, "Success", T.SUCCESS, T.FONT_BODY)
	_label_variation(theme, "Warning", T.WARNING, T.FONT_BODY)
	_label_variation(theme, "Danger", T.DANGER, T.FONT_BODY)
	_label_variation(theme, "UnreadDot", T.ACCENT, T.FONT_BODY)

	var badge := _flat(T.RAISED, T.BORDER_SOFT, 1, 3, T.SPACE_1, 1, T.SPACE_1, 1)
	_label_variation(theme, "Badge", T.TEXT_DIM, T.FONT_BODY)
	theme.set_stylebox("normal", "Badge", badge)
	_label_variation(theme, "BadgeMain", T.ACCENT, T.FONT_BODY)
	theme.set_stylebox("normal", "BadgeMain", _flat(T.RAISED, T.ACCENT, 1, 3, T.SPACE_1, 1, T.SPACE_1, 1))
	_label_variation(theme, "BadgeDone", T.SUCCESS, T.FONT_BODY)
	theme.set_stylebox("normal", "BadgeDone", _flat(T.RAISED, T.SUCCESS, 1, 3, T.SPACE_1, 1, T.SPACE_1, 1))
	_label_variation(theme, "BadgeMuted", T.TEXT_MUTED, T.FONT_BODY)
	theme.set_stylebox("normal", "BadgeMuted", _flat(T.SUNKEN, T.LINE, 1, 3, T.SPACE_1, 1, T.SPACE_1, 1))

	_label_variation(theme, "Keycap", T.ACCENT, T.FONT_BODY)
	theme.set_stylebox("normal", "Keycap",
		_flat(T.RAISED, T.BORDER_SOFT, 1, 3, T.SPACE_1, 0, T.SPACE_1, 0))


func _label_variation(theme: Theme, name: StringName, color: Color, size: int) -> void:
	theme.set_type_variation(name, &"Label")
	theme.set_color("font_color", name, color)
	theme.set_font_size("font_size", name, size)


func _build_buttons(theme: Theme) -> void:
	var normal := _flat(T.RAISED, T.BORDER_SOFT, 1, T.RADIUS_BUTTON, T.SPACE_3, T.SPACE_1, T.SPACE_3, T.SPACE_1)
	var hover := _flat(T.RAISED_HOVER, T.BORDER, 1, T.RADIUS_BUTTON, T.SPACE_3, T.SPACE_1, T.SPACE_3, T.SPACE_1)
	var pressed := _flat(T.PRESSED, T.BORDER_SOFT, 1, T.RADIUS_BUTTON, T.SPACE_3, T.SPACE_1, T.SPACE_3, T.SPACE_1)
	var disabled := _flat(T.SUNKEN, T.LINE, 1, T.RADIUS_BUTTON, T.SPACE_3, T.SPACE_1, T.SPACE_3, T.SPACE_1)
	var focus := _flat(Color.TRANSPARENT, T.ACCENT, 1, T.RADIUS_BUTTON, 0, 0, 0, 0)
	focus.expand_margin_left = T.FOCUS_EXPAND
	focus.expand_margin_top = T.FOCUS_EXPAND
	focus.expand_margin_right = T.FOCUS_EXPAND
	focus.expand_margin_bottom = T.FOCUS_EXPAND
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_color("font_color", "Button", T.TEXT)
	theme.set_color("font_hover_color", "Button", T.ACCENT_STRONG)
	theme.set_color("font_pressed_color", "Button", T.ACCENT)
	theme.set_color("font_hover_pressed_color", "Button", T.ACCENT_STRONG)
	theme.set_color("font_focus_color", "Button", T.TEXT)
	theme.set_color("font_disabled_color", "Button", T.TEXT_MUTED)
	theme.set_constant("h_separation", "Button", 6)
	theme.set_constant("icon_max_width", "Button", T.ICON_SMALL)

	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton",
		_flat(T.ACCENT, T.ACCENT_STRONG, 1, T.RADIUS_BUTTON, T.SPACE_3, T.SPACE_1, T.SPACE_3, T.SPACE_1))
	theme.set_stylebox("hover", "PrimaryButton",
		_flat(T.ACCENT_STRONG, T.ACCENT_STRONG, 1, T.RADIUS_BUTTON, T.SPACE_3, T.SPACE_1, T.SPACE_3, T.SPACE_1))
	theme.set_stylebox("pressed", "PrimaryButton",
		_flat(Color("e0b25f"), T.BORDER, 1, T.RADIUS_BUTTON, T.SPACE_3, T.SPACE_1, T.SPACE_3, T.SPACE_1))
	theme.set_stylebox("disabled", "PrimaryButton",
		_flat(T.SUNKEN, T.LINE, 1, T.RADIUS_BUTTON, T.SPACE_3, T.SPACE_1, T.SPACE_3, T.SPACE_1))
	theme.set_stylebox("focus", "PrimaryButton", focus)
	theme.set_color("font_color", "PrimaryButton", T.PRIMARY_TEXT)
	theme.set_color("font_hover_color", "PrimaryButton", T.PRIMARY_TEXT)
	theme.set_color("font_pressed_color", "PrimaryButton", T.PRIMARY_TEXT)
	theme.set_color("font_hover_pressed_color", "PrimaryButton", T.PRIMARY_TEXT)
	theme.set_color("font_focus_color", "PrimaryButton", T.PRIMARY_TEXT)
	theme.set_color("font_disabled_color", "PrimaryButton", T.TEXT_MUTED)

	theme.set_type_variation("GhostButton", "Button")
	theme.set_stylebox("normal", "GhostButton",
		_flat(Color.TRANSPARENT, T.BORDER_SOFT, 1, T.RADIUS_BUTTON, T.SPACE_3, T.SPACE_1, T.SPACE_3, T.SPACE_1))
	theme.set_stylebox("hover", "GhostButton",
		_flat(T.RAISED, T.BORDER_SOFT, 1, T.RADIUS_BUTTON, T.SPACE_3, T.SPACE_1, T.SPACE_3, T.SPACE_1))
	theme.set_stylebox("pressed", "GhostButton",
		_flat(T.SUNKEN, T.BORDER_SOFT, 1, T.RADIUS_BUTTON, T.SPACE_3, T.SPACE_1, T.SPACE_3, T.SPACE_1))
	theme.set_stylebox("disabled", "GhostButton",
		_flat(Color.TRANSPARENT, T.LINE, 1, T.RADIUS_BUTTON, T.SPACE_3, T.SPACE_1, T.SPACE_3, T.SPACE_1))
	theme.set_stylebox("focus", "GhostButton", focus)
	theme.set_color("font_color", "GhostButton", T.TEXT_DIM)
	theme.set_color("font_hover_color", "GhostButton", T.ACCENT_STRONG)
	theme.set_color("font_pressed_color", "GhostButton", T.ACCENT)
	theme.set_color("font_hover_pressed_color", "GhostButton", T.ACCENT_STRONG)
	theme.set_color("font_focus_color", "GhostButton", T.TEXT_DIM)
	theme.set_color("font_disabled_color", "GhostButton", T.TEXT_MUTED)

	theme.set_type_variation("DangerButton", "Button")
	theme.set_stylebox("normal", "DangerButton",
		_flat(T.SUNKEN, T.DANGER, 1, T.RADIUS_BUTTON, T.SPACE_3, T.SPACE_1, T.SPACE_3, T.SPACE_1))
	theme.set_stylebox("hover", "DangerButton",
		_flat(Color(T.DANGER, 0.16), T.DANGER, 1, T.RADIUS_BUTTON, T.SPACE_3, T.SPACE_1, T.SPACE_3, T.SPACE_1))
	theme.set_stylebox("pressed", "DangerButton",
		_flat(Color(T.DANGER, 0.26), T.DANGER, 1, T.RADIUS_BUTTON, T.SPACE_3, T.SPACE_1, T.SPACE_3, T.SPACE_1))
	theme.set_stylebox("disabled", "DangerButton",
		_flat(T.SUNKEN, T.LINE, 1, T.RADIUS_BUTTON, T.SPACE_3, T.SPACE_1, T.SPACE_3, T.SPACE_1))
	theme.set_stylebox("focus", "DangerButton", focus)
	theme.set_color("font_color", "DangerButton", T.DANGER)
	theme.set_color("font_hover_color", "DangerButton", T.DANGER)
	theme.set_color("font_pressed_color", "DangerButton", T.DANGER)
	theme.set_color("font_hover_pressed_color", "DangerButton", T.DANGER)
	theme.set_color("font_focus_color", "DangerButton", T.DANGER)
	theme.set_color("font_disabled_color", "DangerButton", T.TEXT_MUTED)

	theme.set_type_variation("IconButton", "Button")
	var icon_normal := _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, T.RADIUS_BUTTON, T.SPACE_1, T.SPACE_1, T.SPACE_1, T.SPACE_1)
	var icon_hover := _flat(T.RAISED, T.BORDER_SOFT, 1, T.RADIUS_BUTTON, T.SPACE_1, T.SPACE_1, T.SPACE_1, T.SPACE_1)
	var icon_pressed := _flat(T.PRESSED, T.BORDER_SOFT, 1, T.RADIUS_BUTTON, T.SPACE_1, T.SPACE_1, T.SPACE_1, T.SPACE_1)
	theme.set_stylebox("normal", "IconButton", icon_normal)
	theme.set_stylebox("hover", "IconButton", icon_hover)
	theme.set_stylebox("pressed", "IconButton", icon_pressed)
	theme.set_stylebox("disabled", "IconButton", icon_normal)
	theme.set_stylebox("focus", "IconButton", focus)
	theme.set_color("font_color", "IconButton", T.TEXT_DIM)
	theme.set_color("font_hover_color", "IconButton", T.ACCENT_STRONG)
	theme.set_color("font_pressed_color", "IconButton", T.ACCENT)
	theme.set_color("font_focus_color", "IconButton", T.TEXT_DIM)
	theme.set_color("font_disabled_color", "IconButton", T.TEXT_MUTED)


func _build_item_list(theme: Theme) -> void:
	theme.set_stylebox("panel", "ItemList",
		_flat(T.SUNKEN, T.BORDER_SOFT, 1, T.RADIUS_BUTTON, 6, 6, 6, 6))
	theme.set_stylebox("focus", "ItemList",
		_flat(Color.TRANSPARENT, Color(T.ACCENT, 0.55), 1, T.RADIUS_BUTTON, 0, 0, 0, 0))
	theme.set_stylebox("hovered", "ItemList",
		_flat(Color(T.RAISED, 0.45), Color.TRANSPARENT, 0, 2, 6, 3, 6, 3))
	var selected := _flat(T.RAISED_HOVER, T.ACCENT_STRONG, 1, 2, 6, 3, 6, 3)
	selected.border_width_left = 2
	selected.border_width_top = 0
	selected.border_width_right = 0
	selected.border_width_bottom = 0
	theme.set_stylebox("selected", "ItemList", selected)
	var selected_focus := _flat(T.RAISED_HOVER, T.ACCENT_STRONG, 1, 2, 6, 3, 6, 3)
	selected_focus.border_width_left = 2
	selected_focus.border_width_top = 0
	selected_focus.border_width_right = 0
	selected_focus.border_width_bottom = 0
	theme.set_stylebox("selected_focus", "ItemList", selected_focus)
	theme.set_stylebox("hovered_selected", "ItemList", selected)
	theme.set_stylebox("hovered_selected_focus", "ItemList", selected_focus)
	theme.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	theme.set_color("font_color", "ItemList", T.TEXT)
	theme.set_color("font_hovered_color", "ItemList", T.ACCENT_STRONG)
	theme.set_color("font_hovered_selected_color", "ItemList", T.ACCENT_STRONG)
	theme.set_color("font_selected_color", "ItemList", T.ACCENT_STRONG)
	theme.set_color("font_outline_color", "ItemList", Color.BLACK)
	theme.set_color("guide_color", "ItemList", T.LINE)
	theme.set_constant("h_separation", "ItemList", T.SPACE_2)
	theme.set_constant("v_separation", "ItemList", 6)
	theme.set_constant("icon_margin", "ItemList", 6)
	theme.set_constant("line_separation", "ItemList", 2)
	theme.set_constant("outline_size", "ItemList", 0)
	theme.set_font_size("font_size", "ItemList", T.FONT_BODY)


func _build_tabs(theme: Theme) -> void:
	var selected := _flat(Color.TRANSPARENT, T.ACCENT, 1, 0, 10, 6, 10, 6)
	selected.border_width_top = 0
	selected.border_width_left = 0
	selected.border_width_right = 0
	selected.border_width_bottom = 2
	var hovered := _flat(Color(T.RAISED, 0.55), T.BORDER_SOFT, 1, 0, 10, 6, 10, 6)
	hovered.border_width_top = 0
	hovered.border_width_left = 0
	hovered.border_width_right = 0
	hovered.border_width_bottom = 2
	var unselected := _flat(Color.TRANSPARENT, T.LINE, 1, 0, 10, 6, 10, 6)
	unselected.border_width_top = 0
	unselected.border_width_left = 0
	unselected.border_width_right = 0
	unselected.border_width_bottom = 1
	var disabled := _flat(Color.TRANSPARENT, T.LINE, 1, 0, 10, 6, 10, 6)
	disabled.border_width_top = 0
	disabled.border_width_left = 0
	disabled.border_width_right = 0
	disabled.border_width_bottom = 1
	var focus := _flat(Color.TRANSPARENT, T.ACCENT, 1, 4, 0, 0, 0, 0)
	for type: StringName in [&"TabContainer", &"TabBar"]:
		theme.set_stylebox("tab_selected", type, selected)
		theme.set_stylebox("tab_hovered", type, hovered)
		theme.set_stylebox("tab_unselected", type, unselected)
		theme.set_stylebox("tab_disabled", type, disabled)
		theme.set_stylebox("tab_focus", type, focus)
		theme.set_color("font_selected_color", type, T.ACCENT_STRONG)
		theme.set_color("font_hovered_color", type, T.ACCENT)
		theme.set_color("font_unselected_color", type, T.TEXT_MUTED)
		theme.set_color("font_disabled_color", type, T.TEXT_MUTED)
		theme.set_color("font_outline_color", type, Color.BLACK)
		theme.set_color("drop_mark_color", type, T.ACCENT)
		theme.set_font_size("font_size", type, T.FONT_BODY)
	theme.set_stylebox("panel", "TabContainer", _empty(T.SPACE_3))
	theme.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	theme.set_constant("side_margin", "TabContainer", 0)
	theme.set_constant("icon_separation", "TabContainer", T.SPACE_1)
	theme.set_constant("icon_max_width", "TabContainer", T.ICON_SMALL)
	theme.set_constant("outline_size", "TabContainer", 0)
	theme.set_constant("h_separation", "TabBar", 0)


func _build_inputs(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit",
		_flat(T.SUNKEN, T.LINE, 1, T.RADIUS_BUTTON, T.SPACE_2, T.SPACE_1, T.SPACE_2, T.SPACE_1))
	theme.set_stylebox("focus", "LineEdit",
		_flat(T.SUNKEN, T.ACCENT, 1, T.RADIUS_BUTTON, T.SPACE_2, T.SPACE_1, T.SPACE_2, T.SPACE_1))
	theme.set_stylebox("read_only", "LineEdit",
		_flat(T.PANEL, T.LINE, 1, T.RADIUS_BUTTON, T.SPACE_2, T.SPACE_1, T.SPACE_2, T.SPACE_1))
	theme.set_color("font_color", "LineEdit", T.TEXT)
	theme.set_color("font_selected_color", "LineEdit", T.ACCENT_STRONG)
	theme.set_color("font_uneditable_color", "LineEdit", T.TEXT_MUTED)
	theme.set_color("font_placeholder_color", "LineEdit", T.TEXT_MUTED)
	theme.set_color("caret_color", "LineEdit", T.ACCENT)
	theme.set_color("selection_color", "LineEdit", Color(T.ACCENT, 0.28))
	theme.set_constant("caret_width", "LineEdit", 1)
	theme.set_constant("minimum_character_width", "LineEdit", 4)
	theme.set_font_size("font_size", "LineEdit", T.FONT_BODY)

	var up_normal := _flat(T.RAISED, T.BORDER_SOFT, 1, 3, 0, 0, 0, 0)
	var up_hover := _flat(T.RAISED_HOVER, T.BORDER, 1, 3, 0, 0, 0, 0)
	var up_pressed := _flat(T.PRESSED, T.BORDER_SOFT, 1, 3, 0, 0, 0, 0)
	var up_disabled := _flat(T.SUNKEN, T.LINE, 1, 3, 0, 0, 0, 0)
	theme.set_stylebox("up_background", "SpinBox", up_normal)
	theme.set_stylebox("up_background_hovered", "SpinBox", up_hover)
	theme.set_stylebox("up_background_pressed", "SpinBox", up_pressed)
	theme.set_stylebox("up_background_disabled", "SpinBox", up_disabled)
	theme.set_stylebox("down_background", "SpinBox", up_normal)
	theme.set_stylebox("down_background_hovered", "SpinBox", up_hover)
	theme.set_stylebox("down_background_pressed", "SpinBox", up_pressed)
	theme.set_stylebox("down_background_disabled", "SpinBox", up_disabled)
	theme.set_stylebox("field_and_buttons_separator", "SpinBox", _line(T.LINE, 1, true))
	theme.set_stylebox("up_down_buttons_separator", "SpinBox", _line(T.LINE, 1, false))
	theme.set_color("up_icon_modulate", "SpinBox", T.TEXT)
	theme.set_color("up_hover_icon_modulate", "SpinBox", T.ACCENT_STRONG)
	theme.set_color("up_pressed_icon_modulate", "SpinBox", T.ACCENT)
	theme.set_color("up_disabled_icon_modulate", "SpinBox", T.TEXT_MUTED)
	theme.set_color("down_icon_modulate", "SpinBox", T.TEXT)
	theme.set_color("down_hover_icon_modulate", "SpinBox", T.ACCENT_STRONG)
	theme.set_color("down_pressed_icon_modulate", "SpinBox", T.ACCENT)
	theme.set_color("down_disabled_icon_modulate", "SpinBox", T.TEXT_MUTED)
	theme.set_constant("buttons_width", "SpinBox", 18)
	theme.set_constant("field_and_buttons_separation", "SpinBox", 1)
	theme.set_constant("buttons_vertical_separation", "SpinBox", 1)
	theme.set_constant("set_min_buttons_width_from_icons", "SpinBox", 0)


func _build_scrollbars(theme: Theme) -> void:
	var track := _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 2, 2, 2, 2, 2)
	var grabber := _flat(T.LINE, Color.TRANSPARENT, 0, 2, 1, 1, 1, 1)
	var highlight := _flat(T.BORDER, Color.TRANSPARENT, 0, 2, 1, 1, 1, 1)
	var pressed := _flat(T.ACCENT, Color.TRANSPARENT, 0, 2, 1, 1, 1, 1)
	for type: StringName in [&"VScrollBar", &"HScrollBar"]:
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("scroll_focus", type, track)
		theme.set_stylebox("grabber", type, grabber)
		theme.set_stylebox("grabber_highlight", type, highlight)
		theme.set_stylebox("grabber_pressed", type, pressed)


func _build_popups(theme: Theme) -> void:
	theme.set_stylebox("panel", "PopupMenu",
		_flat(T.PANEL, T.BORDER, 1, T.RADIUS_BUTTON, 6, 6, 6, 6, true))
	var hover := _flat(T.RAISED, T.ACCENT, 1, 2, 6, 3, 6, 3)
	hover.border_width_left = 2
	hover.border_width_top = 0
	hover.border_width_right = 0
	hover.border_width_bottom = 0
	theme.set_stylebox("hover", "PopupMenu", hover)
	theme.set_stylebox("separator", "PopupMenu", _line(T.LINE, 1))
	theme.set_color("font_color", "PopupMenu", T.TEXT)
	theme.set_color("font_hover_color", "PopupMenu", T.ACCENT_STRONG)
	theme.set_color("font_disabled_color", "PopupMenu", T.TEXT_MUTED)
	theme.set_color("font_separator_color", "PopupMenu", T.TEXT_MUTED)
	theme.set_color("font_accelerator_color", "PopupMenu", T.TEXT_MUTED)
	theme.set_constant("h_separation", "PopupMenu", T.SPACE_2)
	theme.set_constant("v_separation", "PopupMenu", 6)
	theme.set_font_size("font_size", "PopupMenu", T.FONT_BODY)

	theme.set_stylebox("panel", "TooltipPanel",
		_flat(T.SUNKEN, T.BORDER, 1, T.RADIUS_BUTTON, T.SPACE_2, T.SPACE_1, T.SPACE_2, T.SPACE_1, true))
	theme.set_color("font_color", "TooltipLabel", T.TEXT)
	theme.set_font_size("font_size", "TooltipLabel", T.FONT_BODY)


func _build_misc(theme: Theme) -> void:
	var check_normal := _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, T.RADIUS_BUTTON, T.SPACE_2, T.SPACE_1, T.SPACE_2, T.SPACE_1)
	var check_hover := _flat(Color(T.RAISED, 0.55), T.BORDER_SOFT, 1, T.RADIUS_BUTTON, T.SPACE_2, T.SPACE_1, T.SPACE_2, T.SPACE_1)
	var check_pressed := _flat(T.SUNKEN, T.BORDER_SOFT, 1, T.RADIUS_BUTTON, T.SPACE_2, T.SPACE_1, T.SPACE_2, T.SPACE_1)
	var check_focus := _flat(Color.TRANSPARENT, T.ACCENT, 1, T.RADIUS_BUTTON, 0, 0, 0, 0)
	theme.set_stylebox("normal", "CheckBox", check_normal)
	theme.set_stylebox("hover", "CheckBox", check_hover)
	theme.set_stylebox("pressed", "CheckBox", check_pressed)
	theme.set_stylebox("hover_pressed", "CheckBox", check_pressed)
	theme.set_stylebox("disabled", "CheckBox", check_normal)
	theme.set_stylebox("focus", "CheckBox", check_focus)
	theme.set_color("font_color", "CheckBox", T.TEXT)
	theme.set_color("font_hover_color", "CheckBox", T.ACCENT_STRONG)
	theme.set_color("font_pressed_color", "CheckBox", T.ACCENT)
	theme.set_color("font_disabled_color", "CheckBox", T.TEXT_MUTED)
	theme.set_color("checkbox_checked_color", "CheckBox", T.ACCENT)
	theme.set_color("checkbox_unchecked_color", "CheckBox", T.BORDER_SOFT)

	theme.set_stylebox("background", "ProgressBar",
		_flat(T.SUNKEN, T.LINE, 1, 2, 0, 0, 0, 0))
	theme.set_stylebox("fill", "ProgressBar", _flat(T.ACCENT, Color.TRANSPARENT, 0, 2, 0, 0, 0, 0))
	theme.set_color("font_color", "ProgressBar", T.TEXT)
	theme.set_type_variation("SuccessBar", "ProgressBar")
	theme.set_stylebox("fill", "SuccessBar", _flat(T.SUCCESS, Color.TRANSPARENT, 0, 2, 0, 0, 0, 0))

	theme.set_stylebox("separator", "HSeparator", _line(T.LINE, 1, false))
	theme.set_stylebox("separator", "VSeparator", _line(T.LINE, 1, true))
	theme.set_constant("separation", "HSeparator", T.SPACE_2)
	theme.set_constant("separation", "VSeparator", T.SPACE_2)

	theme.set_color("default_color", "RichTextLabel", T.TEXT)
	theme.set_color("font_selected_color", "RichTextLabel", T.ACCENT_STRONG)
	theme.set_color("selection_color", "RichTextLabel", Color(T.ACCENT, 0.24))
	theme.set_constant("line_separation", "RichTextLabel", T.LINE_SEPARATION)
	theme.set_constant("paragraph_separation", "RichTextLabel", T.LINE_SEPARATION)
	theme.set_font_size("normal_font_size", "RichTextLabel", T.FONT_BODY)
	theme.set_font_size("bold_font_size", "RichTextLabel", T.FONT_BODY)
	theme.set_font_size("italics_font_size", "RichTextLabel", T.FONT_BODY)
	theme.set_font_size("bold_italics_font_size", "RichTextLabel", T.FONT_BODY)
	theme.set_font_size("mono_font_size", "RichTextLabel", T.FONT_BODY)
