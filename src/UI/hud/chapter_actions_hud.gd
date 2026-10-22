class_name ChapterActionsHUD
extends UIScreen
## On-demand game menu. The host routes navigation and real chapter actions.
signal action_requested(id: String)
signal navigation_requested(id: StringName)

var _page: Control
var _navigation: Dictionary = {}
## Same count the corner chip shows, repeated on the entry that owns the news.
var _badges: Dictionary = {}
## Last known availability per menu entry. A false → true flip is the moment a
## new option appears, and the only moment worth nudging.
var _access: Dictionary = {}
var _access_known := false

func _ready() -> void:
	_page = $ModalShell.get_content()
	# A page, not a slab: the sheet keeps a wide margin so the room stays visible.
	var margin: MarginContainer = $ModalShell.get_node("Margin")
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_right", 96)
	$ModalShell.close_requested.connect(close_requested.emit)
	if MobileSupport.is_touch_ui():
		$ModalShell.set_hint("点按选项 · 右上角返回游戏")
	var titles := {ScreenIds.ORDER_HISTORY: "奶茶订单", ScreenIds.TASKS: "任务日志 [J]", ScreenIds.CHRONICLE: "异世界见闻录", ScreenIds.DRINKS: "哥布林饮品图鉴", ScreenIds.CHARACTERS: "人物记录", ScreenIds.INVENTORY: "原料图鉴 [B]", ScreenIds.MAP: "地图 [M]", ScreenIds.SETTINGS: "设置"}
	for id: StringName in titles:
		var button := Button.new()
		button.text = titles[id]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: navigation_requested.emit(id))
		_page.get_node("Navigation").add_child(button)
		_navigation[id] = button
		var badge := Label.new()
		badge.name = "Unread"
		badge.theme_type_variation = &"UnreadBadge"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.visible = false
		button.add_child(badge)
		badge.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.offset_left = -28.0
		badge.offset_right = -6.0
		badge.offset_top = -7.0
		badge.offset_bottom = 7.0
		_badges[id] = badge

func set_navigation_access(access: Dictionary, unread: Dictionary = {}) -> void:
	for id: StringName in _navigation:
		var available: bool = access.get(id, false)
		_navigation[id].disabled = not available
		var count := int(unread.get(id, 0))
		var badge: Label = _badges.get(id)
		if badge != null:
			badge.visible = available and count > 0
			badge.text = "%d+" % count if count > 9 else str(maxi(1, count))
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
