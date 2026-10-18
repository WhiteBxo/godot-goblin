class_name OrderTicket
extends PanelContainer
## A presentation-only slip shared by the order board and order crafting.

signal primary_pressed

@onready var _icon: TextureRect = %ProductIcon
@onready var _title: Label = %ProductTitle
@onready var _target: Label = %Target
@onready var _status: Label = %Status
@onready var _requirements: Label = %Requirements
@onready var _hint: Label = %NextStep
@onready var _primary: Button = %Primary
@onready var _feedback: Label = %CraftFeedback
var _completion_tween: Tween

func _ready() -> void:
	_primary.pressed.connect(func() -> void: primary_pressed.emit())

func present(entry: Dictionary, action: String = "", enabled: bool = false) -> void:
	_clear_result()
	_icon.texture = entry.get("icon")
	_title.text = entry.get("title", "今天暂时没有订单")
	_target.text = "交给：" + str(entry.target_name) if not entry.is_empty() else "新的订单会在这里出现"
	_status.text = entry.get("status_text", "稍作休息")
	_status.theme_type_variation = &"TicketWarning" if entry.get("stage") in ["missing_materials", "recipe_locked"] else &"TicketStamp"
	var lines := PackedStringArray()
	if not entry.is_empty():
		lines.append("报酬：" + entry.rewards)
		for item: Dictionary in entry.items:
			lines.append("%s  %d / %d" % ["已有成品" if not entry.product_id.is_empty() else item.name, item.owned, item.needed])
		if not entry.missing_text.is_empty() and entry.status != "completed":
			lines.append("还缺：" + entry.missing_text)
	_requirements.text = "\n".join(lines)
	_hint.text = "下一步：" + str(entry.get("hint", "可以返回店铺，等待新的客人。"))
	_primary.text = action
	_primary.visible = not action.is_empty()
	_primary.disabled = not enabled

## Only a committed crafting result can trigger the cup presentation.
func show_result(result: Dictionary) -> void:
	_clear_result()
	_feedback.text = result.get("message", "")
	_feedback.visible = not _feedback.text.is_empty()
	_feedback.theme_type_variation = &"TicketStamp" if result.get("ok", false) else &"TicketWarning"
	if not result.get("ok", false):
		return
	_status.text = "制作完成 · 已入库"
	_icon.pivot_offset = _icon.size * 0.5
	_icon.scale = Vector2(0.8, 0.8)
	_completion_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_completion_tween.tween_property(_icon, "scale", Vector2(1.15, 1.15), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_completion_tween.tween_property(_icon, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _clear_result() -> void:
	if _completion_tween != null:
		_completion_tween.kill()
		_completion_tween = null
	_icon.scale = Vector2.ONE
	_feedback.hide()

func get_primary_button() -> Button:
	return _primary

func get_title_text() -> String:
	return _title.text

func get_hint_text() -> String:
	return _hint.text
