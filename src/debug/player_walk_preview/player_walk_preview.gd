extends Control

const DIRECTIONS: Array[String] = ["down", "left", "right", "up"]
const FRAMES := preload("res://src/gameplay/player/player_run_frames.tres")
const MATERIAL := preload("res://src/gameplay/player/player_sprite_material.tres")

var _sprites: Array[AnimatedSprite2D] = []
var _labels: Array[Label] = []
var _playing := true
var _play_button: Button

func _ready() -> void:
	var preview_theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	preview_theme.default_font = font
	theme = preview_theme
	var background := ColorRect.new()
	background.color = Color("39434e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var title := Label.new()
	title.text = "四方向跑步检查：16 帧原始序列"
	title.position = Vector2(20, 15)
	add_child(title)
	for index in range(4):
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = FRAMES
		sprite.material = MATERIAL
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(80 + index * 160, 245)
		sprite.scale = Vector2.ONE * 0.7
		sprite.offset = Vector2(0, -144)
		sprite.speed_scale = 0.5
		sprite.play("run_" + DIRECTIONS[index])
		add_child(sprite)
		_sprites.append(sprite)
		var label := Label.new()
		label.position = Vector2(30 + index * 160, 265)
		add_child(label)
		_labels.append(label)
	var buttons := HBoxContainer.new()
	buttons.position = Vector2(20, 310)
	buttons.add_theme_constant_override("separation", 12)
	add_child(buttons)
	_add_button(buttons, "上一帧", _step.bind(-1))
	_play_button = _add_button(buttons, "暂停", _toggle_play)
	_add_button(buttons, "下一帧", _step.bind(1))
	var speed := OptionButton.new()
	for choice in ["0.25x", "0.5x", "1.0x"]:
		speed.add_item(choice)
	speed.select(1)
	speed.item_selected.connect(func(index: int) -> void:
		for sprite in _sprites:
			sprite.speed_scale = [0.25, 0.5, 1.0][index])
	buttons.add_child(speed)

func _process(_delta: float) -> void:
	for index in range(_sprites.size()):
		var frame := _sprites[index].frame
		_labels[index].text = "%s  %d / 16\n%s" % [["下", "左", "右", "上"][index], frame + 1, "跑步"]

func _add_button(parent: HBoxContainer, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _toggle_play() -> void:
	_playing = not _playing
	_play_button.text = "暂停" if _playing else "播放"
	for sprite in _sprites:
		if _playing:
			sprite.play()
		else:
			sprite.pause()

func _step(offset: int) -> void:
	_playing = false
	_play_button.text = "播放"
	for sprite in _sprites:
		sprite.pause()
		sprite.set_frame_and_progress(posmod(sprite.frame + offset, 16), 0.0)
