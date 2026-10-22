class_name ChapterActionsHUD
extends UIScreen
## On-demand game menu. The host routes navigation and real chapter actions.
signal action_requested(id: String)
signal navigation_requested(id: StringName)

const INK := Color(0.227, 0.165, 0.102, 1)
const INK_SOFT := Color(0.478, 0.392, 0.286, 1)
const PAPER := Color(0.961, 0.91, 0.812, 1)

var _page: Control
var _navigation: Dictionary = {}
## Last known availability per menu entry. A false → true flip is the moment a
## new option appears, and the only moment worth nudging.
var _access: Dictionary = {}
var _access_known := false

func _ready() -> void:
	_page = $ModalShell.get_content()
	_apply_paper_skin()
	$ModalShell.close_requested.connect(close_requested.emit)
	if MobileSupport.is_touch_ui():
		$ModalShell.set_hint("点按选项 · 右上角返回游戏")
	var titles := {ScreenIds.ORDER_HISTORY: "奶茶订单", ScreenIds.TASKS: "任务日志 [J]", ScreenIds.CHRONICLE: "异世界见闻录", ScreenIds.DRINKS: "哥布林饮品图鉴", ScreenIds.CHARACTERS: "人物记录", ScreenIds.INVENTORY: "原料图鉴 [B]", ScreenIds.MAP: "地图 [M]", ScreenIds.SETTINGS: "设置"}
	for id: StringName in titles:
		var button := Button.new()
		button.text = titles[id]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_paper_button(button)
		button.pressed.connect(func() -> void: navigation_requested.emit(id))
		_page.get_node("Navigation").add_child(button)
		_navigation[id] = button

## The menu is a page of the same paper the HUD is printed on: cream sheet, ink
## rules, ink text. The modal shell itself stays untouched so order boards and
## handbooks keep their own treatment for now.
func _apply_paper_skin() -> void:
	var margin: MarginContainer = $ModalShell.get_node("Margin")
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_right", 96)
	var panel: PanelContainer = $ModalShell.get_node("Margin/Panel")
	panel.add_theme_stylebox_override("panel", _paper_box(PAPER))
	for path: String in ["Status", "Scroll/Content/ObjectiveTitle", "Scroll/Content/Objective", "Scroll/Content/Notice"]:
		var label := _page.get_node_or_null(path)
		if label is Label:
			label.add_theme_color_override("font_color", INK if path != "Status" else INK_SOFT)
	var title: Label = $ModalShell.get_node("Margin/Panel/Content/Header/Title")
	title.add_theme_color_override("font_color", INK)
	var close: Button = $ModalShell.get_node_or_null("Margin/Panel/Content/Header/Close")
	if close != null:
		_style_paper_button(close)
		close.add_theme_font_size_override("font_size", 11)
	var footer: Label = $ModalShell.get_node_or_null("Margin/Panel/Content/Footer")
	if footer != null:
		footer.add_theme_color_override("font_color", INK_SOFT)

func _paper_box(fill: Color, border_bottom: int = 2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = Color(0.29, 0.216, 0.133, 1)
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = border_bottom
	box.border_width_bottom = border_bottom
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 6
	box.corner_radius_bottom_right = 4
	box.corner_radius_bottom_left = 6
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	box.shadow_color = Color(0.227, 0.165, 0.102, 0.3)
	box.shadow_size = 0
	box.shadow_offset = Vector2(3, 3)
	return box

## Ink text on cream paper; hover warms the border instead of filling the row.
func _style_paper_button(button: Button) -> void:
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color(0.71, 0.275, 0.184, 1))
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_disabled_color", Color(0.478, 0.392, 0.286, 0.55))
	button.add_theme_stylebox_override("normal", _paper_box(Color(0, 0, 0, 0), 1))
	# Locked entries stay light: the theme's disabled box is a dark slab that
	# swallows ink text.
	button.add_theme_stylebox_override("disabled", _paper_box(Color(0.902, 0.812, 0.639, 0.4), 1))
	button.add_theme_stylebox_override("hover", _paper_box(Color(0.902, 0.812, 0.639, 0.55), 1))
	button.add_theme_stylebox_override("pressed", _paper_box(Color(0.851, 0.741, 0.541, 0.7), 1))
	button.add_theme_stylebox_override("focus", _paper_box(Color(0.902, 0.812, 0.639, 0.4), 1))

func set_navigation_access(access: Dictionary) -> void:
	for id: StringName in _navigation:
		var available: bool = access.get(id, false)
		_navigation[id].disabled = not available
		# An entry that just became available gets one nudge: the new option is
		# noticed instead of merely being no longer grey.
		if _access_known and available and not bool(_access.get(id, false)):
			UIFlourish.settle(_navigation[id], 0.92)
		_access[id] = available
	_access_known = true

func set_overview(title: String, objective: String, balance: String, saved: String) -> void:
	_page.get_node("Status").text = "钱包 " + balance + "  ·  " + saved
	_page.get_node("Scroll/Content/ObjectiveTitle").text = title if not title.is_empty() else "当前行程"
	var objective_label: Control = _page.get_node("Scroll/Content/Objective")
	var text := objective if not objective.is_empty() else "暂时没有待办目标，可以自由探索。"
	var changed: bool = objective_label.text != text
	objective_label.text = text
	# A changed objective lands instead of being swapped in place.
	if changed:
		UIFlourish.settle(objective_label, 0.97)

func show_actions(actions: Array[Dictionary], notice: String, enabled: bool) -> void:
	var notice_label: Control = _page.get_node("Scroll/Content/Notice")
	notice_label.text = notice
	notice_label.visible = not notice.is_empty()
	# The rule keeps a notice from reading as the tail of the current objective.
	var notice_rule: Control = _page.get_node("Scroll/Content/NoticeRule")
	notice_rule.visible = not notice.is_empty()
	var buttons: VBoxContainer = _page.get_node("Scroll/Content/Actions")
	for child: Node in buttons.get_children():
		buttons.remove_child(child)
		child.queue_free()
	for action: Dictionary in actions:
		var button := Button.new()
		button.text = action.text
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_style_paper_button(button)
		button.disabled = not enabled
		button.set_meta("action_id", action.id)
		button.pressed.connect(func() -> void: action_requested.emit(action.id))
		buttons.add_child(button)

func get_action_button(id: String) -> Button:
	for button: Button in _page.get_node("Scroll/Content/Actions").get_children():
		if button.get_meta("action_id") == id:
			return button
	return null

func get_navigation_button(id: StringName) -> Button:
	return _navigation.get(id)

func get_default_focus() -> Control:
	return $ModalShell.get_close_button()

func uses_native_gui_input() -> bool:
	return true
