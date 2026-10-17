extends Control

const ACTORS := ["goblin", "guard", "captain", "chef"]
const ACTOR_LABELS := ["普通哥布林", "守卫", "守卫长", "厨师"]
const ACTION_LABELS := {
	"attack_down": "攻击 · 正面", "attack_side": "攻击 · 侧面", "attack_up": "攻击 · 背面",
	"walk_down": "走路 · 正面", "walk_side": "走路 · 侧面", "walk_up": "走路 · 背面",
}

var _sprite: AnimatedSprite2D
var _actors: OptionButton
var _actions: OptionButton
var _status: Label
var _play_button: Button
var _mirror: CheckButton

func _ready() -> void:
	var preview_theme := Theme.new()
	preview_theme.default_font = preload("res://assets/fonts/fusion_pixel/fusion-pixel-12px-monospaced-zh_hans.otf.woff2")
	preview_theme.default_font_size = 16
	theme = preview_theme
	var background := ColorRect.new()
	background.color = Color("39434e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var title := Label.new()
	title.text = "哥布林动作预览 · 原图切帧 / 攻击单次 / 走路循环"
	title.position = Vector2(16, 8)
	add_child(title)
	var selectors := HBoxContainer.new()
	selectors.position = Vector2(16, 38)
	selectors.add_theme_constant_override("separation", 12)
	add_child(selectors)
	_actors = OptionButton.new()
	for actor in ACTOR_LABELS:
		_actors.add_item(actor)
	_actors.item_selected.connect(_select_actor)
	selectors.add_child(_actors)
	_actions = OptionButton.new()
	_actions.item_selected.connect(_select_action)
	selectors.add_child(_actions)
	_mirror = CheckButton.new()
	_mirror.text = "侧身镜像"
	_mirror.toggled.connect(func(enabled: bool) -> void: _sprite.flip_h = enabled)
	selectors.add_child(_mirror)
	var ground := ColorRect.new()
	ground.color = Color("71808c")
	ground.position = Vector2(190, 270)
	ground.size = Vector2(260, 1)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)
	_sprite = AnimatedSprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.position = Vector2(320, 175)
	add_child(_sprite)
	_status = Label.new()
	_status.position = Vector2(16, 278)
	add_child(_status)
	var controls := HBoxContainer.new()
	controls.position = Vector2(16, 310)
	controls.add_theme_constant_override("separation", 10)
	add_child(controls)
	_button(controls, "上一帧", _step.bind(-1))
	_play_button = _button(controls, "暂停", _toggle_play)
	_button(controls, "下一帧", _step.bind(1))
	_button(controls, "重播", _replay)
	var speed := OptionButton.new()
	for choice in ["0.25x", "0.5x", "1x", "2x"]:
		speed.add_item(choice)
	speed.select(2)
	speed.item_selected.connect(func(index: int) -> void: _sprite.speed_scale = [0.25, 0.5, 1.0, 2.0][index])
	controls.add_child(speed)
	_select_actor(0)

func _process(_delta: float) -> void:
	if _sprite == null:
		return
	var frames := _sprite.sprite_frames
	_status.text = "%s   %d / %d 帧   12 FPS   %s" % [ACTION_LABELS[String(_sprite.animation)], _sprite.frame + 1, frames.get_frame_count(_sprite.animation), "循环" if frames.get_animation_loop(_sprite.animation) else "单次"]
	_play_button.text = "暂停" if _sprite.is_playing() else "播放"

func _button(parent: HBoxContainer, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _select_actor(index: int) -> void:
	_actors.select(index)
	_sprite.stop()
	_sprite.sprite_frames = load("res://src/gameplay/goblin_actions/%s_frames.tres" % ACTORS[index]) as SpriteFrames
	# Uniform preview zoom only; stored texture regions retain their original size.
	_sprite.scale = Vector2.ONE * (0.75 if ACTORS[index] == "captain" else 3.0)
	_actions.clear()
	for animation in _sprite.sprite_frames.get_animation_names():
		_actions.add_item(ACTION_LABELS[String(animation)])
		_actions.set_item_metadata(_actions.item_count - 1, animation)
	_select_action(0)

func _select_action(index: int) -> void:
	_actions.select(index)
	var animation: StringName = _actions.get_item_metadata(index)
	_mirror.set_pressed_no_signal(false)
	_mirror.disabled = not String(animation).ends_with("_side")
	_sprite.flip_h = false
	_sprite.stop()
	_sprite.play(animation)

func _toggle_play() -> void:
	if _sprite.is_playing():
		_sprite.pause()
	elif _sprite.frame == _sprite.sprite_frames.get_frame_count(_sprite.animation) - 1 and _sprite.frame_progress >= 1.0:
		_replay()
	else:
		_sprite.play()

func _replay() -> void:
	_sprite.stop()
	_sprite.play()

func _step(offset: int) -> void:
	_sprite.pause()
	_sprite.set_frame_and_progress(posmod(_sprite.frame + offset, _sprite.sprite_frames.get_frame_count(_sprite.animation)), 0.0)
