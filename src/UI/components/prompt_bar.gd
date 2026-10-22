class_name PromptBar
extends CenterContainer
## Bottom-centre interaction prompt with a themed keycap.

@export_range(0.0, 0.5, 0.01) var appear_seconds := 0.08

@onready var _key: Label = %Key
@onready var _text: Label = %Text
@onready var _panel: PanelContainer = $Panel
var _fade: Tween
var _pop: Tween
var _key_pop: Tween

func _ready() -> void:
	_panel.resized.connect(_center_pivot)
	# Keycaps name a key the player cannot press; the touch pad is the key.
	_key.visible = not MobileSupport.is_touch_ui()

func show_prompt(text: String, key: String = "E") -> void:
	var changed := _text.text != text or _key.text != key
	_key.text = key
	_text.text = text
	if text.is_empty():
		clear()
		return
	if not visible:
		visible = true
		modulate.a = 0.0
		_pop_in()
		_start_fade(1.0)
	elif changed:
		# Only the text changed: keep the prompt stable and avoid a second fade.
		modulate.a = 1.0
		_pulse_key()

## 世界胶囊已经说了这件事：底部只保留文字数据（测试与宿主读），不再显示，
## 免得同一句话在物体上和屏幕底部各说一遍。
func show_silent(text: String, key: String = "E") -> void:
	if visible:
		clear()
	_key.text = key
	_text.text = text

func clear() -> void:
	_text.text = ""
	if _fade != null:
		_fade.kill()
		_fade = null
	if _pop != null:
		_pop.kill()
		_pop = null
	if _key_pop != null:
		_key_pop.kill()
		_key_pop = null
	_panel.scale = Vector2.ONE
	_panel.modulate.a = 1.0
	_key.scale = Vector2.ONE
	modulate.a = 1.0
	visible = false

func _center_pivot() -> void:
	_panel.pivot_offset = _panel.size * 0.5

## The bar rises into place instead of simply appearing.
func _pop_in() -> void:
	_center_pivot()
	if _pop != null:
		_pop.kill()
	_panel.scale = Vector2(0.9, 0.9)
	_panel.modulate.a = 0.0
	_pop = create_tween().set_parallel(true)
	_pop.tween_property(_panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop.tween_property(_panel, "modulate:a", 1.0, 0.10)

func _pulse_key() -> void:
	if _key_pop != null:
		_key_pop.kill()
	_key.pivot_offset = _key.size * 0.5
	_key.scale = Vector2.ONE
	_key_pop = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_key_pop.tween_property(_key, "scale", Vector2(1.18, 1.18), 0.08)
	_key_pop.tween_property(_key, "scale", Vector2.ONE, 0.14)

func _start_fade(target: float) -> void:
	if _fade != null:
		_fade.kill()
	if appear_seconds <= 0.0:
		modulate.a = target
		return
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", target, appear_seconds)

func get_text() -> String:
	return _text.text

func get_key_text() -> String:
	return _key.text

func get_text_label() -> Label:
	return _text
