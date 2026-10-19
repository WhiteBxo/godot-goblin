extends UIScreen
## One settings view for the standalone title and UIManager's paused modal stack.
signal dismissed

var _manager: UIManager
var _id: StringName
var _music: OptionButton
var _sound: OptionButton
var _speed: OptionButton
var _auto: OptionButton
var _message: Label

func _ready() -> void:
	var page: Control = $ModalShell.get_content()
	_music = page.get_node("Music/Value")
	_sound = page.get_node("Sound/Value")
	_speed = page.get_node("Speed/Value")
	_auto = page.get_node("Auto/Value")
	_message = page.get_node("Message")
	for option: OptionButton in [_music, _sound]:
		for percent in [0, 25, 50, 75, 100]:
			option.add_item("%d%%" % percent)
	for title: String in ["慢", "标准", "快", "立即显示"]:
		_speed.add_item(title)
	for title: String in ["关闭", "1.5 秒", "3 秒", "5 秒"]:
		_auto.add_item(title)
	page.get_node("Apply").pressed.connect(apply)
	$ModalShell.close_requested.connect(_close)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh())
	refresh()

func bind_ui(manager: UIManager, id: StringName) -> void:
	_manager = manager
	_id = id

func refresh() -> void:
	if not is_node_ready():
		return
	var values := PlayerPreferences.get_values()
	_music.select(roundi(values.music * 4.0))
	_sound.select(roundi(values.sound * 4.0))
	_speed.select(PlayerPreferences.SPEEDS.find(values.dialogue_speed))
	_auto.select(PlayerPreferences.AUTO_DELAYS.find(values.dialogue_auto))
	_message.text = "应用后立即生效；关闭可放弃尚未应用的调整。"

func apply() -> void:
	var error := PlayerPreferences.save_values({"music": _music.selected / 4.0, "sound": _sound.selected / 4.0, "dialogue_speed": PlayerPreferences.SPEEDS[_speed.selected], "dialogue_auto": PlayerPreferences.AUTO_DELAYS[_auto.selected]})
	_message.text = "设置已保存。" if error == OK else "设置未能保存，请重试；原设置已保留。"

func get_default_focus() -> Control:
	return _music

func uses_native_gui_input() -> bool:
	return true

func on_ui_closed() -> void:
	dismissed.emit()

func _close() -> void:
	if is_instance_valid(_manager):
		_manager.close_screen(_id)
	else:
		hide()
		dismissed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_instance_valid(_manager) and is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
