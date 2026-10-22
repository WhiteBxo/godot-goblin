class_name InteractionPoint
extends Area2D

signal availability_changed(point: InteractionPoint, available: bool)
signal interacted(point: InteractionPoint)

@export var interaction_id: StringName
@export var display_name := "交互地点"
## 动作胶囊里的动词（"打开""进入""交谈"…）。留空时按交互点类型推断。
@export var action_verb := ""
## 运行期条件（宿主注入）：返回一句话说明为什么现在按不动，空串表示可用。
## 子类可以覆写 get_blocked_reason() 用自己已有的字段（门看通行条件）。
var blocked_reason_resolver: Callable
## 胶囊底边相对交互点的高度：默认浮在物体上方，不压住美术。
@export var prompt_anchor := Vector2(0, -30)
@export_multiline var description := ""
## Local artwork bounds, independent of the reach/collision shape.
@export var feedback_rect := Rect2(-18, -18, 36, 36)
@export var success_sound: String = ""
@export_enum("UI", "SFX") var sound_bus: String = "UI"
## Scene-authored links stay valid when the host reparents actors.
@export var required_actors: Array[Node2D] = []
## Related overlapping targets may use business priority after spatial selection.
@export var selection_group: StringName
@export var mouse_interaction_enabled := false
@export var interaction_enabled := true:
	set(value):
		interaction_enabled = value
		if is_inside_tree():
			availability_changed.emit(self, is_available())
var _bodies: Array[Node2D] = []

func _ready() -> void:
	$Label.text = display_name
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if mouse_interaction_enabled:
		# Picking needs a nonzero layer. Layer 8 does not collide with world/player/NPC.
		set_collision_layer_value(8, true)
		input_pickable = true

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if mouse_interaction_enabled and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and is_available():
		interact()
		get_viewport().set_input_as_handled()

func hide_development_markers() -> void:
	$Marker.hide()
	$Label.hide()

## 目标物体上方的一枚胶囊："E · 打开订单板"。只在该点被选中时出现，
## 平时不给世界加任何字，避免每个家具都在喊自己的名字。
## 画在屏幕空间（`WorldPrompt`）：世界里的字会跟着相机缩放，商店这种
## 缩放到 0.4 的镜头下会小到看不清。
func get_action_text() -> String:
	var verb := _action_verb()
	if verb.is_empty():
		return display_name
	return "%s%s" % [verb, display_name]

## 世界胶囊与底部提示条只保留一个，宿主据此让底部闭嘴。
func shows_world_prompt() -> bool:
	return true

## 为什么现在按不动。空串 = 可用。宁可显示"还不能用 + 原因"，也不要让玩家
## 站在门口按 E 之后什么都不发生。
func get_blocked_reason() -> String:
	if blocked_reason_resolver.is_valid():
		return str(blocked_reason_resolver.call(self))
	return ""

## 动词按交互点类型推断；场景里写了 action_verb 就以它为准。
func _action_verb() -> String:
	if not action_verb.is_empty():
		return action_verb
	if "destination_scene" in self:
		return "进入"
	if "entry_id" in self:
		# StoryInteractionPoint：kind 0 拾取、1 文档。
		return "阅读" if int(get("kind")) == 1 else "拿走"
	if "refresh_mode" in self:
		return "采集"
	match String(interaction_id):
		"orders", "storage", "stock", "warehouse", "notice":
			return "打开"
		"tea_station", "casino_table":
			return "使用"
		"coins":
			return "拿走"
	return ""

func is_available() -> bool:
	_bodies = _bodies.filter(func(body: Node2D) -> bool:
		return is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion())
	return (interaction_enabled and is_visible_in_tree() and is_inside_tree()
		and not is_queued_for_deletion() and not _bodies.is_empty()
		and required_actors.all(func(actor: Node2D) -> bool:
			return is_instance_valid(actor) and actor.is_visible_in_tree() and not actor.is_queued_for_deletion()))

func interact() -> void:
	if is_available():
		interacted.emit(self)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body not in _bodies:
		_bodies.append(body)
		availability_changed.emit(self, is_available())

func _on_body_exited(body: Node2D) -> void:
	_bodies.erase(body)
	if _bodies.is_empty():
		availability_changed.emit(self, false)
