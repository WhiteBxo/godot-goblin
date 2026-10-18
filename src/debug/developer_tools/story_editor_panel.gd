class_name StoryEditorPanel
extends VBoxContainer
## The view edits the same StoryProject document as the CLI and Codex.

signal close_requested

const DEFAULT_PROJECT := "res://docs/story_authoring/day1_stages_01_02_project.json"
const TEMPLATES := {
	"wait": {"command": "wait", "seconds": 0.5},
	"actor_move": {"command": "actor_move", "actor": "player", "target": "day1_counter", "speed": 120, "timeout": 15, "wait": true},
	"actor_face": {"command": "actor_face", "actor": "player", "direction": "down", "wait": true},
	"actor_emote": {"command": "actor_emote", "actor": "player", "symbol": "!", "duration": 0.8, "wait": true},
	"actor_show": {"command": "actor_show", "actor": "player", "wait": true},
	"actor_hide": {"command": "actor_hide", "actor": "player", "wait": true},
	"camera_focus": {"command": "camera_focus", "actor": "player", "duration": 0.8, "wait": true},
	"camera_move": {"command": "camera_move", "target": "day1_counter", "duration": 0.8, "wait": true},
	"camera_zoom": {"command": "camera_zoom", "value": 1.0, "duration": 0.5, "wait": true},
	"camera_shake": {"command": "camera_shake", "intensity": 2, "duration": 0.3, "decay": 1.5, "wait": true},
	"camera_reset": {"command": "camera_reset", "wait": true},
	"play_sfx": {"command": "play_sfx", "id": "shop.door_bell", "wait": false},
	"play_bgm": {"command": "play_bgm", "id": "music.daily_milk_tea", "fade": 0.5, "volume_db": -12, "wait": true},
	"stop_bgm": {"command": "stop_bgm", "fade": 0.5, "wait": true},
	"fade_bgm": {"command": "fade_bgm", "volume_db": -12, "fade": 0.5, "wait": true},
	"dialogue": {"command": "dialogue", "id": "day1.shop_opening"},
	"set_flag": {"command": "set_flag", "key": "day1.example", "value": true},
	"set_stage": {"command": "set_stage", "value": "day1.example"},
}

var project := StoryProject.new()
var _path_field: LineEdit
var _beat_selector: OptionButton
var _steps: ItemList
var _command: OptionButton
var _fields: GridContainer
var _field_controls: Dictionary = {}
var _raw_step: TextEdit
var _raw_project: TextEdit
var _dialogues: OptionButton
var _lines: OptionButton
var _speaker: LineEdit
var _text: TextEdit
var _portrait: LineEdit
var _details: TabContainer
var _message: Label
var _dirty_label: Label
var _beat_id := ""
var _step_index := -1
var _rendering := false
var _pending := false
var _pending_tab := 0
var _dialogue_id := ""
var _line_id := ""
var _preview_pid := -1
var _preview_files: Array[String] = []
var _discard_armed := false

func _ready() -> void:
	var open_row := HBoxContainer.new()
	add_child(open_row)
	_path_field = LineEdit.new()
	_path_field.text = DEFAULT_PROJECT
	_path_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_row.add_child(_path_field)
	_button(open_row, "打开工程", _open)
	_button(open_row, "放弃并重读", _discard)
	_dirty_label = Label.new()
	_dirty_label.theme_type_variation = &"Hint"
	add_child(_dirty_label)
	var workspace := HSplitContainer.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.split_offset = 260
	add_child(workspace)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 245
	workspace.add_child(content)
	_beat_selector = OptionButton.new()
	_beat_selector.fit_to_longest_item = false
	_beat_selector.clip_text = true
	content.add_child(_beat_selector)
	_beat_selector.item_selected.connect(_select_beat)
	_watch_popup(_beat_selector)
	_steps = ItemList.new()
	_steps.custom_minimum_size.y = 64
	_steps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_steps)
	_steps.item_selected.connect(_select_step)
	var order := VBoxContainer.new()
	content.add_child(order)
	for group: Array in [
		[["添加停顿", _insert_wait], ["复制", _duplicate_step], ["删除", _remove_step]],
		[["上移", _move_step.bind(-1)], ["下移", _move_step.bind(1)], ["撤销", _undo], ["重做", _redo]]]:
		var row := HBoxContainer.new()
		order.add_child(row)
		for entry: Array in group:
			_button(row, entry[0], entry[1])
	_details = TabContainer.new()
	_details.custom_minimum_size.y = 118
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_details)
	var form := ScrollContainer.new()
	form.name = "步骤表单"
	_details.add_child(form)
	var form_body := VBoxContainer.new()
	form_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(form_body)
	_command = OptionButton.new()
	for command: String in TEMPLATES:
		_command.add_item(command)
	form_body.add_child(_command)
	_command.item_selected.connect(_change_command)
	_watch_popup(_command)
	_fields = GridContainer.new()
	_fields.columns = 2
	form_body.add_child(_fields)
	_raw_step = _text_editor("步骤 JSON")
	_raw_step.text_changed.connect(_changed)
	var dialogue_page := VBoxContainer.new()
	dialogue_page.name = "对白"
	_details.add_child(dialogue_page)
	var selectors := HBoxContainer.new()
	dialogue_page.add_child(selectors)
	_dialogues = OptionButton.new()
	_dialogues.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialogues.fit_to_longest_item = false
	selectors.add_child(_dialogues)
	_lines = OptionButton.new()
	selectors.add_child(_lines)
	_speaker = LineEdit.new()
	_speaker.placeholder_text = "说话人"
	dialogue_page.add_child(_speaker)
	_speaker.text_changed.connect(func(_value: String) -> void: _changed())
	_text = TextEdit.new()
	_text.custom_minimum_size.y = 42
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	dialogue_page.add_child(_text)
	_text.text_changed.connect(_changed)
	_portrait = LineEdit.new()
	_portrait.placeholder_text = "立绘 res:// 路径（空为默认立绘）"
	dialogue_page.add_child(_portrait)
	_portrait.text_changed.connect(func(_value: String) -> void: _changed())
	_dialogues.item_selected.connect(_select_dialogue)
	_lines.item_selected.connect(_select_line)
	_watch_popup(_dialogues)
	_watch_popup(_lines)
	_raw_project = _text_editor("工程 JSON")
	_raw_project.text_changed.connect(_changed)
	_details.tab_changed.connect(_select_detail)
	var actions := HBoxContainer.new()
	add_child(actions)
	move_child(actions, 1)
	for entry: Array in [["应用修改", apply_current], ["校验", _validate], ["保存工程和产物", _save], ["预览整段", preview_event], ["停止预览", stop_preview]]:
		_button(actions, entry[0], entry[1])
	_message = Label.new()
	_message.theme_type_variation = &"Hint"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_message)
	_message.text = "打开工程后选择 Beat；预览运行在独立窗口。保存不会回写 MD。"

func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)

func _text_editor(title: String) -> TextEdit:
	var editor := TextEdit.new()
	editor.name = title
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_details.add_child(editor)
	return editor

func _changed() -> void:
	if not _rendering:
		_discard_armed = false
		if not _pending:
			_pending_tab = _details.current_tab
		_pending = true
		_dirty_label.text = "有未应用的输入；切换前请应用修改。"

func _open() -> void:
	if _pending or project.dirty:
		_message.text = "当前有未保存修改，请先保存；需要放弃时可关闭本次宿主后重新打开。"
		return
	if not DebugRuntime.is_enabled():
		return
	var error := project.open_project(_path_field.text.strip_edges())
	if error != OK:
		_message.text = project.last_error
		return
	_beat_id = ""
	_step_index = 0
	_refresh()
	_message.text = "已打开；表单与 JSON 编辑同一份内容。"

func _discard() -> void:
	if (_pending or project.dirty) and not _discard_armed:
		_discard_armed = true
		_message.text = "再次点击「放弃并重读」丢弃未保存草稿，并打开磁盘上的工程。"
		return
	_discard_armed = false
	_pending = false
	project = StoryProject.new()
	_open()

func _watch_popup(choice: OptionButton) -> void:
	choice.get_popup().window_input.connect(func(event: InputEvent) -> void:
		if DebugRuntime.is_enabled() and event.is_action_pressed(DeveloperTools.TOGGLE_ACTION) and not event.is_echo():
			close_requested.emit())

func close_popups(node: Node = self) -> void:
	for child: Node in node.get_children():
		if child is OptionButton:
			child.get_popup().hide()
		close_popups(child)

func _beat() -> Dictionary:
	for beat: Dictionary in project.snapshot().get("beats", []):
		if beat.id == _beat_id:
			return beat
	return {}

func _refresh() -> void:
	_rendering = true
	_pending = false
	var document := project.snapshot()
	_beat_selector.clear()
	var selected := 0
	for beat: Dictionary in document.get("beats", []):
		if beat.id == _beat_id:
			selected = _beat_selector.item_count
		_beat_selector.add_item("%s · %s" % [beat.id, beat.get("event", "玩家操作")])
		_beat_selector.set_item_metadata(_beat_selector.item_count - 1, beat.id)
	if _beat_selector.item_count > 0:
		_beat_selector.select(selected)
		_beat_id = _beat_selector.get_selected_metadata()
	_steps.clear()
	var beat := _beat()
	for entry: Dictionary in beat.get("steps", []):
		var data: Dictionary = entry.data
		_steps.add_item("%s  %s  %s" % [entry.id, data.command, data.get("actor", data.get("id", data.get("value", "")))])
	_step_index = mini(_step_index, _steps.item_count - 1)
	if _step_index >= 0:
		_steps.select(_step_index)
		_render_step(beat.steps[_step_index].data)
	else:
		_render_step({})
	var dialogue_id := _dialogues.get_item_text(_dialogues.selected) if _dialogues.selected >= 0 else ""
	_dialogues.clear()
	for id: String in document.get("dialogues", {}):
		_dialogues.add_item(id)
		if id == dialogue_id:
			_dialogues.select(_dialogues.item_count - 1)
	_render_dialogue()
	_raw_project.text = JSON.stringify(document, "\t", false)
	_dirty_label.text = "工程有修改，尚未保存" if project.dirty else "已与磁盘同步"
	_rendering = false

func _render_step(data: Dictionary) -> void:
	_raw_step.text = JSON.stringify(data, "\t", false)
	for child: Node in _fields.get_children():
		child.free()
	_field_controls.clear()
	if data.is_empty():
		return
	var command: String = data.command
	var known := false
	for index in range(_command.item_count):
		if _command.get_item_text(index) == command:
			_command.select(index)
			known = true
	if not known:
		_command.add_item(command)
		_command.select(_command.item_count - 1)
	var fields: Dictionary = TEMPLATES.get(command, {}).duplicate(true)
	fields.merge(data, true)
	# Preserve the mutually exclusive camera actor/target and audio id/path forms.
	if data.has("target") and command == "camera_focus":
		fields.erase("actor")
	if data.has("path") and command == "play_sfx":
		fields.erase("id")
	for key: String in fields:
		if key == "command":
			continue
		var label := Label.new()
		label.text = key
		_fields.add_child(label)
		var value: Variant = fields[key]
		var options: Array = []
		var document := project.snapshot()
		if value is String:
			match key:
				"actor": options = document.manifest.get("actors", {}).keys()
				"target": options = document.manifest.get("markers", {}).get("ids", []).duplicate()
				"direction": options = ["up", "down", "left", "right"]
				"id":
					options = document.dialogues.keys() if command == "dialogue" else document.manifest.get("audio", {}).get("ids", []).duplicate()
		var field: Control
		if not options.is_empty():
			var choice := OptionButton.new()
			choice.fit_to_longest_item = false
			if value not in options:
				options.append(value)
			for option: String in options:
				choice.add_item(option)
				if option == value:
					choice.select(choice.item_count - 1)
			choice.item_selected.connect(func(_index: int) -> void: _changed())
			_watch_popup(choice)
			field = choice
		else:
			var input := LineEdit.new()
			input.text = str(value) if value is String else JSON.stringify(value)
			input.text_changed.connect(func(_value: String) -> void: _changed())
			field = input
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_fields.add_child(field)
		_field_controls[key] = {"control": field, "type": typeof(value)}

func _render_dialogue() -> void:
	var line_id := _lines.get_item_text(_lines.selected) if _lines.selected >= 0 else ""
	_lines.clear()
	if _dialogues.selected < 0:
		return
	var dialogue: Dictionary = project.snapshot().dialogues[_dialogues.get_item_text(_dialogues.selected)]
	_dialogue_id = _dialogues.get_item_text(_dialogues.selected)
	for id: String in dialogue.lines:
		_lines.add_item(id)
		if id == line_id:
			_lines.select(_lines.item_count - 1)
	_render_line()

func _render_line() -> void:
	if _dialogues.selected < 0 or _lines.selected < 0:
		return
	var line: Dictionary = project.snapshot().dialogues[_dialogues.get_item_text(_dialogues.selected)].lines[_lines.get_item_text(_lines.selected)]
	_line_id = _lines.get_item_text(_lines.selected)
	_speaker.text = line.speaker
	_text.text = line.text
	_portrait.text = line.get("portrait", "")

func _select_beat(index: int) -> void:
	if _pending:
		_message.text = "请先应用修改，再切换 Beat。"
		_refresh_selector()
		return
	_beat_id = _beat_selector.get_item_metadata(index)
	_step_index = 0
	_refresh()

func _refresh_selector() -> void:
	for index in range(_beat_selector.item_count):
		if _beat_selector.get_item_metadata(index) == _beat_id:
			_beat_selector.select(index)

func _select_step(index: int) -> void:
	if _pending:
		if _step_index >= 0:
			_steps.select(_step_index)
		_message.text = "请先应用修改，再切换步骤。"
		return
	_step_index = index
	_rendering = true
	_render_step(_beat().steps[index].data)
	_rendering = false

func _select_dialogue(_index: int) -> void:
	if _pending:
		for index in range(_dialogues.item_count):
			if _dialogues.get_item_text(index) == _dialogue_id:
				_dialogues.select(index)
		_message.text = "对白切换前请先应用修改。"
		return
	_rendering = true
	_render_dialogue()
	_rendering = false

func _select_line(_index: int) -> void:
	if _pending:
		for index in range(_lines.item_count):
			if _lines.get_item_text(index) == _line_id:
				_lines.select(index)
		_message.text = "行切换前请先应用修改。"
		return
	_rendering = true
	_render_line()
	_rendering = false

func _select_detail(_index: int) -> void:
	if _pending and _details.current_tab != _pending_tab:
		_details.current_tab = _pending_tab
		_message.text = "请先应用修改，再切换编辑视图。"

func _change_command(index: int) -> void:
	var command := _command.get_item_text(index)
	if not TEMPLATES.has(command):
		return
	_rendering = true
	_render_step(TEMPLATES[command].duplicate(true))
	_rendering = false
	_changed()

func apply_current() -> bool:
	if not _pending:
		return not project.snapshot().is_empty()
	var error := ERR_INVALID_DATA
	match _details.current_tab:
		0:
			var data := {"command": _command.get_item_text(_command.selected)}
			for key: String in _field_controls:
				var field: Dictionary = _field_controls[key]
				var text: String = field.control.text
				if field.type == TYPE_STRING:
					data[key] = text
				else:
					var parser := JSON.new()
					if parser.parse(text) != OK:
						_message.text = "参数 %s 需要有效 JSON 值" % key
						return false
					data[key] = parser.data
			error = project.set_step(_beat_id, _step_index, data)
		1, 3:
			var parser := JSON.new()
			if parser.parse(_raw_step.text if _details.current_tab == 1 else _raw_project.text) != OK or not parser.data is Dictionary:
				_message.text = "JSON 无效：" + parser.get_error_message()
				return false
			error = project.set_step(_beat_id, _step_index, parser.data) if _details.current_tab == 1 else project.replace_document(parser.data)
		2:
			if _dialogues.selected < 0 or _lines.selected < 0:
				return false
			var candidate := project.snapshot()
			var line: Dictionary = candidate.dialogues[_dialogues.get_item_text(_dialogues.selected)].lines[_lines.get_item_text(_lines.selected)]
			line.speaker = _speaker.text
			line.text = _text.text
			line["portrait"] = _portrait.text
			error = project.replace_document(candidate)
	if error != OK:
		_message.text = project.last_error
		return false
	_refresh()
	_message.text = "修改已应用到草稿；保存后生成运行时文件。"
	return true

func _edit_result(error: Error) -> void:
	if error == OK:
		_refresh()
		_message.text = "步骤已更新，可撤销；保存后生效。"
	else:
		_message.text = project.last_error

func _insert_wait() -> void:
	if apply_current():
		_edit_result(project.insert_step(_beat_id, _step_index + 1, TEMPLATES.wait))

func _duplicate_step() -> void:
	if apply_current() and _step_index >= 0:
		_edit_result(project.insert_step(_beat_id, _step_index + 1, _beat().steps[_step_index].data))

func _remove_step() -> void:
	if apply_current():
		_edit_result(project.remove_step(_beat_id, _step_index))

func _move_step(offset: int) -> void:
	if not apply_current():
		return
	var error := project.move_step(_beat_id, _step_index, offset)
	if error == OK:
		_step_index += offset
	_edit_result(error)

func _undo() -> void:
	if _pending:
		_pending = false
		_refresh()
	elif project.undo():
		_refresh()

func _redo() -> void:
	if not _pending and project.redo():
		_refresh()

func _validate() -> void:
	if apply_current():
		_message.text = "结构、逐步映射和对白引用通过；实景路径与表现请预览确认。" if not project.compile().is_empty() else project.last_error

func _save() -> void:
	if not apply_current():
		return
	if project.save() != OK:
		_message.text = project.last_error
		return
	_refresh()
	_message.text = "已保存工程、演出、对白、phase 和映射。演出/对白可在事件页重载；phase 改动需重启宿主。"

func preview_event() -> void:
	if not DebugRuntime.is_enabled() or not OS.has_feature("editor") or not apply_current():
		return
	var beat := _beat()
	var document := project.snapshot()
	if not beat.has("event") or not document.previews.has(beat.event):
		_message.text = "该段没有明确的预览现场；请在工程 previews 中配置事件起点。玩家操作 Beat 通过正式试玩验证。"
		return
	stop_preview()
	var request := project.compile()
	if request.is_empty():
		_message.text = project.last_error
		return
	request["scene"] = document.manifest.scene
	request["event"] = beat.event
	request["fixture"] = document.previews[beat.event]
	var directory := "user://story_editor"
	DirAccess.make_dir_recursive_absolute(directory)
	var file := "%s/preview_%d_%d.json" % [directory, OS.get_process_id(), Time.get_ticks_usec()]
	var handle := FileAccess.open(file, FileAccess.WRITE)
	if handle == null:
		_message.text = "不能写入预览请求"
		return
	handle.store_string(JSON.stringify(request))
	handle.close()
	_preview_files.append(file)
	_preview_pid = OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--path", ProjectSettings.globalize_path("res://"), "--windowed",
		"--script", "res://src/debug/developer_tools/story_preview_runner.gd", "--", ProjectSettings.globalize_path(file)]))
	if _preview_pid > 0:
		for kind: String in ["story", "dialogue"]:
			_preview_files.append("user://story_editor/runner_%d_%s.json" % [_preview_pid, kind])
	_message.text = "已启动独立预览：%s。窗口内 R 重演，Esc 取消对白。" % beat.event if _preview_pid > 0 else "预览进程启动失败"

func stop_preview() -> void:
	if _preview_pid > 0 and OS.is_process_running(_preview_pid):
		OS.kill(_preview_pid)
	_preview_pid = -1
	for file: String in _preview_files:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	_preview_files.clear()

func _exit_tree() -> void:
	stop_preview()
