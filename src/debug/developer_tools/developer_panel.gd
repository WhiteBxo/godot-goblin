class_name DeveloperPanel
extends Control

signal speed_multiplier_selected(multiplier: float)
signal close_requested
signal respawn_requested
signal restart_requested
signal clear_log_requested

@onready var speed_selector: OptionButton = %SpeedSelector
@onready var status_text: TextEdit = %StatusText
@onready var story_text: TextEdit = %StoryText
@onready var log_text: TextEdit = %LogText
@onready var _respawn: Button = %Respawn
@onready var _restart: Button = %Restart
@onready var _confirmation: VBoxContainer = %Confirmation

func _ready() -> void:
	var details: TabContainer = $Panel/Margin/Tools/Tabs/剧情/Details
	details.set_tab_title(0, "状态数据")
	details.set_tab_title(1, "事件日志")
	speed_selector.item_selected.connect(_on_speed_selected)
	# Embedded popup windows receive input before the main viewport.
	speed_selector.get_popup().window_input.connect(_on_popup_input)
	%Close.pressed.connect(func() -> void: close_requested.emit())
	_respawn.pressed.connect(func() -> void: respawn_requested.emit())
	_restart.pressed.connect(func() -> void: _confirmation.show())
	%ConfirmRestart.pressed.connect(func() -> void:
		_confirmation.hide()
		restart_requested.emit())
	%CancelRestart.pressed.connect(cancel_restart)
	%ClearLog.pressed.connect(func() -> void: clear_log_requested.emit())
	hide()

func uses_native_gui_input() -> bool:
	return true

func get_default_focus() -> Control:
	return %Close

func on_ui_closed() -> void:
	cancel_restart()

func cancel_restart() -> void:
	_confirmation.hide()
	speed_selector.get_popup().hide()

func configure_choices(multipliers: PackedInt32Array) -> void:
	speed_selector.clear()
	for multiplier: int in multipliers:
		speed_selector.add_item("玩家移速 %d×" % multiplier, multiplier)

func set_speed_multiplier(multiplier: float) -> void:
	speed_selector.select(speed_selector.get_item_index(int(multiplier)))

func set_capabilities(speed_available: bool, respawn_available: bool, restart_available: bool) -> void:
	speed_selector.disabled = not speed_available
	_respawn.disabled = not respawn_available
	_restart.disabled = not restart_available
	%ConfirmRestart.disabled = not restart_available
	%CharacterHint.text = "不可用的能力已禁用；剧情演出期间禁用角色操作。"

func set_status(data: Dictionary, state: Dictionary) -> void:
	var text := "场景：%s\n关卡：%s\n玩家坐标：%s\nFPS：%s\n当前天数：%s\n剧情阶段：%s" % [
		data.get("scene", "不可用"), data.get("level", "不可用"), data.get("position", "不可用"),
		data.get("fps", "不可用"), state.get("current_day", "GameState 不可用"),
		state.get("story_stage", "GameState 不可用") if not str(state.get("story_stage", "")).is_empty() else "未设置"]
	_replace_text(status_text, text)

func set_story(state: Dictionary, runtime: Dictionary) -> void:
	var description := "StoryDirector 不可用"
	if not runtime.is_empty():
		description = "未加载剧情事件" if not runtime.loaded else "已加载 %d 个事件 · 空闲" % runtime.event_count
		if not str(runtime.event_id).is_empty():
			description += "\n执行中：%s / 步骤 %d（从 0 开始）" % [runtime.event_id, runtime.step_index]
		if not str(runtime.last_error).is_empty():
			description += "\n最近错误：" + str(runtime.last_error)
	var text := description + "\n\nGameState 不可用"
	if not state.is_empty():
		text = description + "\n\nflags（只读）\n" + JSON.stringify(state.flags, "  ")
		text += "\n\nvariables（只读）\n" + JSON.stringify(state.variables, "  ")
		text += "\n\n已完成事件（只读）\n" + JSON.stringify(state.completed_events, "  ")
	_replace_text(story_text, text)

func set_log(lines: Array[String]) -> void:
	_replace_text(log_text, "暂无事件信号记录" if lines.is_empty() else "\n".join(lines))

func _replace_text(view: TextEdit, text: String) -> void:
	if view.text == text:
		return
	var scroll := view.scroll_vertical
	view.text = text
	view.scroll_vertical = scroll

func _on_speed_selected(index: int) -> void:
	speed_multiplier_selected.emit(float(speed_selector.get_item_id(index)))

func _on_popup_input(event: InputEvent) -> void:
	if DebugRuntime.is_enabled() and event.is_action_pressed(DeveloperTools.TOGGLE_ACTION) and not event.is_echo():
		close_requested.emit()
