class_name WorldPrompt
extends Control
## The one action capsule in the game.
##
## It follows whichever interaction point the selector currently holds and sits
## just above it — but in screen space, because world-space text is at the mercy
## of the camera zoom (the shop renders at roughly 0.4x, where a 12px label is
## unreadable). One instance, one capsule: nothing else in the world labels
## itself, so the room stays clean until something is actually reachable.

const GAP := 18.0
const MARGIN := 4.0

var _target: InteractionPoint
var _bar: PanelContainer
var _key: Label
var _text: Label
var _reason: Label
var _pop: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar = $Bar
	_key = $Bar/Content/Row/Key
	_text = $Bar/Content/Row/Text
	_reason = $Bar/Content/Reason
	_bar.visible = false
	# 触屏没有 E 键：只说“做什么”。
	_key.visible = not MobileSupport.is_touch_ui()
	set_process(false)

func bind(interaction: ShopInteraction) -> void:
	if not is_instance_valid(interaction):
		return
	if not interaction.target_changed.is_connected(_on_target_changed):
		interaction.target_changed.connect(_on_target_changed)
	_on_target_changed(interaction.get_target())

func clear() -> void:
	_target = null
	_bar.visible = false
	set_process(false)

func get_action_text() -> String:
	return _text.text

## 空串 = 这个目标现在按得动；非空就是它给出的原因。
func get_blocked_reason() -> String:
	return _reason.text if _reason.visible else ""

func get_text_label() -> Label:
	return _text

func get_key_label() -> Label:
	return _key

func is_prompt_visible() -> bool:
	return _bar.visible

func _on_target_changed(point: InteractionPoint) -> void:
	if not is_instance_valid(point):
		clear()
		return
	_target = point
	_apply(point)
	_place()
	_show_bar()
	set_process(true)

## 同一个目标的条件会变（旗标刚置上、材料刚凑齐），站着不动也要跟着改。
func _apply(point: InteractionPoint) -> void:
	var blocked := _reason_for(point)
	_text.text = point.get_action_text()
	# 不带键帽 + 一行红色原因：玩家看得见"这是什么、为什么还不行"。
	_key.visible = not MobileSupport.is_touch_ui() and blocked.is_empty()
	_reason.text = blocked
	_reason.visible = not blocked.is_empty()

func _reason_for(point: InteractionPoint) -> String:
	return point.get_blocked_reason() if point.has_method("get_blocked_reason") else ""

## 跟随相机：目标点每帧重新投影到屏幕坐标，胶囊始终贴在物体上沿。
func _process(_delta: float) -> void:
	if not is_instance_valid(_target) or not _target.is_available():
		clear()
		return
	_place()
	if _reason_for(_target) != get_blocked_reason():
		_apply(_target)
		_place()

func _place() -> void:
	var size := _bar.get_combined_minimum_size()
	_bar.size = size
	var screen := get_viewport().get_canvas_transform() * _target.global_position
	var limit := get_viewport_rect().size
	var position := screen - Vector2(size.x * 0.5, size.y + GAP)
	position.x = clampf(position.x, MARGIN, maxf(MARGIN, limit.x - size.x - MARGIN))
	position.y = clampf(position.y, MARGIN, maxf(MARGIN, limit.y - size.y - MARGIN))
	_bar.position = position.round()

## 0.12s 从下方浮起，和四角高亮同一节奏。
func _show_bar() -> void:
	_bar.visible = true
	if _pop != null:
		_pop.kill()
	_bar.pivot_offset = Vector2(_bar.size.x * 0.5, _bar.size.y)
	_bar.scale = Vector2(0.94, 0.94)
	_bar.modulate.a = 0.0
	_pop = create_tween().set_parallel(true)
	_pop.tween_property(_bar, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop.tween_property(_bar, "modulate:a", 1.0, 0.10)
