extends Control
## F6 preview. Uses the existing service, including ownership and UI/SFX routing.

const LIBRARY: SoundLibrary = preload("res://src/resources/audio/sound_library.tres")
const CATEGORIES := ["全部", "ui", "shop", "player", "story", "ambience", "music"]

@onready var audio: AudioManager = $AudioManager
var _owner := RefCounted.new()
var _rows: Array[Dictionary] = []
var _visible_rows: Array[int] = []
var _list: ItemList
var _details: Label
var _status: Label
var _volume_label: Label
var _volume: HSlider
var _sequence_timer: Timer
var _continuous := false
var _sequence_index := 0
var _current_handle := 0
var _last_id := ""


func _ready() -> void:
	if not OS.has_feature("debug"):
		return
	var errors := LIBRARY.register_all(audio)
	_build_ui()
	for entry in LIBRARY.entries:
		var streams: Array = entry["streams"]
		for index in range(streams.size()):
			_rows.append({"id": SoundLibrary.variant_id(entry["id"], index, streams.size()),
				"label": entry["label"], "stream": streams[index], "loop": entry["loop"],
				"loop_offset": entry.get("loop_offset", 0.0)})
	_filter(0)
	audio.sound_finished.connect(_on_finished)
	_status.text = "就绪 · %d 个音效 · 点击列表查看，双击播放" % _rows.size() if errors.is_empty() else "\n".join(errors)


func _build_ui() -> void:
	var theme_resource := Theme.new()
	theme_resource.default_font = preload("res://assets/fonts/fusion_pixel/fusion-pixel-12px-monospaced-zh_hans.otf.woff2")
	theme_resource.default_font_size = 12
	theme = theme_resource
	var background := ColorRect.new()
	background.color = Color("18212b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title := Label.new()
	title.text = "GOBLIN / SOUND LIBRARY 01    ·    音效与音乐试听"
	column.add_child(title)
	var toolbar := HBoxContainer.new()
	column.add_child(toolbar)
	var category := OptionButton.new()
	for item in CATEGORIES:
		category.add_item(item)
	category.item_selected.connect(_filter)
	toolbar.add_child(category)
	_button(toolbar, "播放", play_selected)
	_button(toolbar, "连续试听", start_sequence)
	_button(toolbar, "停止", stop_preview)
	_button(toolbar, "缺失资源测试", _missing_probe)
	var volume_row := HBoxContainer.new()
	column.add_child(volume_row)
	_volume_label = Label.new()
	_volume_label.custom_minimum_size.x = 135
	volume_row.add_child(_volume_label)
	_volume = HSlider.new()
	_volume.min_value = -48
	_volume.max_value = 0
	_volume.step = 1
	_volume.value = -6
	_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume.value_changed.connect(_set_volume)
	volume_row.add_child(_volume)
	_set_volume(_volume.value)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_select)
	_list.item_activated.connect(func(_index: int) -> void: play_selected())
	column.add_child(_list)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.custom_minimum_size.y = 48
	column.add_child(_details)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_sequence_timer = Timer.new()
	_sequence_timer.one_shot = true
	_sequence_timer.timeout.connect(_next)
	add_child(_sequence_timer)


func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)


func _filter(category: int) -> void:
	stop_preview()
	_list.clear()
	_visible_rows.clear()
	for index in range(_rows.size()):
		var row: Dictionary = _rows[index]
		if category != 0 and not str(row["id"]).begins_with(CATEGORIES[category] + "."):
			continue
		_visible_rows.append(index)
		var stream := row["stream"] as AudioStream
		_list.add_item("%s · %s  %.3fs%s" % [row["id"], row["label"],
			stream.get_length() if stream else 0.0, " [循环]" if row["loop"] else ""])
	if not _visible_rows.is_empty():
		_list.select(0)
		_select(0)


func _select(index: int) -> void:
	var row: Dictionary = _rows[_visible_rows[index]]
	var stream := row["stream"] as AudioStream
	_details.text = "%s · %s\n%s\n%.3f 秒%s" % [row["id"], row["label"],
		stream.resource_path if stream else "缺失 AudioStream",
		stream.get_length() if stream else 0.0, " · 末尾回到 %.3f 秒（连续试听仅 6 秒）" % row["loop_offset"] if row["loop"] else ""]


func play_selected() -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return
	stop_preview()
	_play(selected[0])


func _play(index: int) -> void:
	var row: Dictionary = _rows[_visible_rows[index]]
	_list.select(index)
	_list.ensure_current_is_visible()
	_select(index)
	_last_id = row["id"]
	_current_handle = audio.play_ui(_last_id, _owner, _volume.value) if _last_id.begins_with("ui.") else audio.play_sfx(_last_id, _owner, _volume.value)
	_status.text = "播放：" + _last_id if _current_handle != 0 else audio.last_error
	if _continuous:
		if row["loop"]:
			_sequence_timer.start(6.0)
		elif _current_handle == 0:
			_sequence_timer.start(.25)


func start_sequence() -> void:
	stop_preview()
	if _visible_rows.is_empty():
		return
	_continuous = true
	_sequence_index = 0
	_play(0)


func _next() -> void:
	if not _continuous:
		return
	var previous := _current_handle
	_current_handle = 0
	audio.stop_sound(previous)
	_sequence_index += 1
	if _sequence_index >= _visible_rows.size():
		stop_preview()
		_status.text = "连续试听完成"
		return
	_play(_sequence_index)


func _on_finished(handle: int, cancelled: bool) -> void:
	if handle != _current_handle:
		return
	_current_handle = 0
	if _continuous and not cancelled:
		_sequence_timer.start(.22)
	else:
		_status.text = "播放结束：" + _last_id


func stop_preview() -> void:
	_continuous = false
	_current_handle = 0
	if _sequence_timer != null:
		_sequence_timer.stop()
	if is_instance_valid(audio):
		audio.stop_owned(_owner)
	if _status != null:
		_status.text = "已停止"


func _set_volume(value: float) -> void:
	_volume_label.text = "试听音量：%.0f dB" % value
	# Service gain is per request. Restart the selected preview at the new gain.
	# This uses only its public API and never touches global bus or pool internals.
	if _current_handle != 0:
		play_selected()


func _missing_probe() -> void:
	var handle := audio.play_sfx_path("res://assets/audio/missing_preview.wav", _owner)
	_status.text = "安全跳过：" + audio.last_error if handle == 0 else "异常：缺失文件被播放"


func _exit_tree() -> void:
	stop_preview()
