extends Node
## Standalone listening harness; never loaded by the production scene.

@onready var _audio: AudioManager = $AudioManager
var _adapter: StoryAudioAdapter
var _status: Label


func _ready() -> void:
	AudioDemoTones.populate(_audio)
	preload("res://src/resources/audio/sound_library.tres").register_all(_audio)
	_adapter = StoryAudioAdapter.new(_audio)
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.size = Vector2(608, 328)
	var theme := Theme.new()
	theme.default_font = preload("res://assets/fonts/fusion_pixel/fusion-pixel-12px-monospaced-zh_hans.otf.woff2")
	theme.default_font_size = 12
	panel.theme = theme
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var title := Label.new()
	title.text = "AudioManager · 独立听音测试\n先播放 A，再切换 B：旧曲淡出 0.6 秒，新曲淡入 0.6 秒。"
	column.add_child(title)
	var music := HBoxContainer.new()
	column.add_child(music)
	_button(music, "BGM A", func() -> void: _audio.play_bgm("demo.music_a", 0.6))
	_button(music, "切换 BGM B", func() -> void: _audio.play_bgm("demo.music_b", 0.6))
	_button(music, "压低 BGM", func() -> void: _audio.fade_bgm(-24.0, 0.8))
	_button(music, "恢复 BGM", func() -> void: _audio.fade_bgm(0.0, 0.8))
	_button(music, "淡出停止", func() -> void: _audio.stop_bgm(1.0))
	var daily := HBoxContainer.new()
	column.add_child(daily)
	_button(daily, "奶茶日常 BGM（从头试听）", func() -> void: _audio.play_bgm("music.daily_milk_tea", 0.0, -6.0, true))
	var loop_note := Label.new()
	loop_note.text = "末尾 → 1:08.279 循环 · 上方淡出停止"
	daily.add_child(loop_note)
	var sounds := HBoxContainer.new()
	column.add_child(sounds)
	_button(sounds, "叠加低音 + 高音", func() -> void:
		_audio.play_sfx("demo.low")
		_audio.play_sfx("demo.high"))
	_button(sounds, "UI 提示音", func() -> void: _audio.play_ui("demo.ui"))
	_button(sounds, "缺失 ID（安全跳过）", func() -> void: _audio.play_sfx("demo.missing"))
	var owned := HBoxContainer.new()
	column.add_child(owned)
	_button(owned, "演出长音效（4 秒）", func() -> void: _adapter.play_sfx({"id": "demo.story"}))
	_button(owned, "取消所属音效", _adapter.stop_owned)
	_button(owned, "独立音效淡出", func() -> void:
		var handle := _audio.play_sfx("demo.story")
		_audio.stop_sound(handle, 1.5))
	var instructions := Label.new()
	instructions.text = "取消演出音效时，BGM 应持续；淡出按钮应使音量平滑降低。\n奶茶日常为用户提供音频，其余为程序合成占位音。"
	column.add_child(instructions)
	_status = Label.new()
	column.add_child(_status)


func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)


func _process(_delta: float) -> void:
	if _status == null:
		return
	var state := _audio.get_bgm_state()
	_status.text = "BGM：%s · %.1f dB\n音效池：%d / %d\n诊断：%s" % [
		state["id"] if state["playing"] else "停止", state["volume_db"],
		_audio.get_active_sound_count(), _audio.pool_size, _audio.last_error]
