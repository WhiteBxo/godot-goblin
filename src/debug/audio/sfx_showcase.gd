extends Control
## F6 preview for the 2026-10-20 sound additions. Plays the shipped variants only:
## no synthesis, no gameplay state, so what you hear is exactly what the game plays.

const LIBRARY: SoundLibrary = preload("res://src/resources/audio/sound_library.tres")
const GROUPS := [
	{
		"title": "投币落地 · story.coin_drop",
		"note": "潜入里扔金币命中后播放。以前借的是石块撞击声，现在是金属币落地弹跳。",
		"ids": ["story.coin_drop"],
	},
	{
		"title": "采集材质 · gather.*",
		"note": "按采集物分派：苔藓/菌菇/块茎用植物声，晶簇用晶体声，取血用玻璃瓶开合。",
		"ids": ["gather.plant", "gather.crystal", "gather.vial"],
	},
	{
		"title": "穿门 · shop.door_bell",
		"note": "跨场景到达时播放，进店和出宅都算；以前这个音效只有调试场景在用。",
		"ids": ["shop.door_bell"],
	},
]

@onready var audio: AudioManager = $AudioManager

var _owner := RefCounted.new()
var _previous := {}
var _status: Label
var _now_playing := ""

func _ready() -> void:
	if not OS.has_feature("debug"):
		return
	var errors := LIBRARY.register_all(audio)
	_build()
	audio.sound_finished.connect(_on_finished)
	_status.text = "就绪 · 点击任意按钮试听" if errors.is_empty() else "\n".join(errors)

func _build() -> void:
	theme = preload("res://src/resources/ui/game_theme.tres")
	var background := ColorRect.new()
	background.color = Color("18212b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "新增音效预览 · 2026-10-20"
	title.theme_type_variation = &"Title"
	column.add_child(title)
	for group: Dictionary in GROUPS:
		column.add_child(_section(group))
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(filler)
	_status = Label.new()
	_status.theme_type_variation = &"Hint"
	column.add_child(_status)

func _section(group: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var heading := Label.new()
	heading.text = group["title"]
	heading.theme_type_variation = &"BadgeMain"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	heading.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(heading)
	var note := Label.new()
	note.text = group["note"]
	note.theme_type_variation = &"Hint"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	for id: String in group["ids"]:
		row.add_child(_button(id))
	box.add_child(row)
	return box

func _button(id: String) -> Button:
	var button := Button.new()
	var streams := _streams(id)
	button.text = id
	button.tooltip_text = "%d 个变体 · %.2f 秒" % [streams.size(), streams[0].get_length() if not streams.is_empty() else 0.0]
	button.theme_type_variation = &"GhostButton"
	button.pressed.connect(func() -> void: _play(id))
	return button

func _streams(id: String) -> Array:
	for entry: Dictionary in LIBRARY.entries:
		if entry["id"] == id:
			return entry["streams"]
	return []

func _play(id: String) -> void:
	var variant := LIBRARY.choose_variant(id, _previous.get(id, ""))
	if variant.is_empty():
		variant = id
	if audio.play_sfx(variant, _owner, -6.0) == AudioManager.INVALID_HANDLE:
		_status.text = "没有可播放的变体：" + id
		return
	_previous[id] = variant
	_now_playing = variant
	_status.text = "▶ " + variant

func _on_finished(_handle: int, _cancelled: bool) -> void:
	if not _now_playing.is_empty():
		_status.text = "✓ " + _now_playing
		_now_playing = ""
