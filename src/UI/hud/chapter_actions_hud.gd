class_name ChapterActionsHUD
extends UIScreen
## On-demand game menu. The host routes navigation and real chapter actions.
signal action_requested(id: String)
signal navigation_requested(id: StringName)

var _page: Control
var _navigation: Dictionary = {}
## Last known availability per menu entry. A false → true flip is the moment a
## new option appears, and the only moment worth nudging.
var _access: Dictionary = {}
var _access_known := false

func _ready() -> void:
	_page = $ModalShell.get_content()
	$ModalShell.close_requested.connect(close_requested.emit)
	var titles := {ScreenIds.ORDER_HISTORY: "奶茶订单", ScreenIds.TASKS: "任务日志 [J]", ScreenIds.CHRONICLE: "异世界见闻录", ScreenIds.DRINKS: "哥布林饮品图鉴", ScreenIds.CHARACTERS: "人物记录", ScreenIds.INVENTORY: "背包 [B]", ScreenIds.MAP: "地图 [M]", ScreenIds.SETTINGS: "设置"}
	for id: StringName in titles:
		var button := Button.new()
		button.text = titles[id]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: navigation_requested.emit(id))
		_page.get_node("Navigation").add_child(button)
		_navigation[id] = button

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
	_page.get_node("Scroll/Content/Notice").text = notice
	_page.get_node("Scroll/Content/Notice").visible = not notice.is_empty()
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
