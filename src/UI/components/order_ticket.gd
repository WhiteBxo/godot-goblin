class_name OrderTicket
extends PanelContainer
## A presentation-only slip shared by the order board and order crafting.

signal primary_pressed
## Optional second action: an accepted order that may be given up.
signal secondary_pressed

@onready var _icon: TextureRect = %ProductIcon
@onready var _title: Label = %ProductTitle
@onready var _target: Label = %Target
@onready var _status: Label = %Status
@onready var _requirements: Label = %Requirements
@onready var _hint: Label = %NextStep
@onready var _primary: Button = %Primary
@onready var _secondary: Button = %Secondary
@onready var _feedback: Label = %CraftFeedback
var _completion_tween: Tween
var _flash_tween: Tween
var _slip_tween: Tween
## Only a genuinely different customer's order replaces the slip; a stock
## refresh of the same order keeps it still.
var _shown_id := ""
var _shown_status := ""

func _ready() -> void:
	_primary.pressed.connect(func() -> void: primary_pressed.emit())
	_secondary.pressed.connect(func() -> void: secondary_pressed.emit())

func present(entry: Dictionary, action: String = "", enabled: bool = false, secondary: String = "") -> void:
	_clear_result()
	var order_id := str(entry.get("order_id", ""))
	var replaced := order_id != _shown_id
	_shown_id = order_id
	var status := str(entry.get("status_text", "稍作休息"))
	var status_changed := not replaced and status != _shown_status
	_shown_status = status
	_icon.texture = entry.get("icon")
	_title.text = entry.get("title", "今天暂时没有订单")
	_target.text = "交给：" + str(entry.target_name) if not entry.is_empty() else "新的订单会在这里出现"
	_status.text = status
	_status.theme_type_variation = &"TicketWarning" if entry.get("stage") in ["missing_materials", "recipe_locked", "experiment"] else &"TicketStamp"
	var lines := PackedStringArray()
	if not entry.is_empty():
		if not str(entry.get("description", "")).is_empty():
			lines.append("订单要求：" + str(entry.description))
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
	_secondary.text = secondary
	_secondary.visible = not secondary.is_empty()
	if replaced:
		_play_slip_change()
	elif status_changed:
		# The order moved (accepted, covered by stock, ready): the stamp lands.
		UIFlourish.stamp(_status)

## Another customer's slip arrives instead of the text jumping under the eye.
func _play_slip_change() -> void:
	if _slip_tween != null:
		_slip_tween.kill()
	modulate.a = 0.0
	_slip_tween = create_tween()
	_slip_tween.tween_property(self, "modulate:a", 1.0, 0.14)

## Only a committed crafting result can trigger the cup presentation.
func show_result(result: Dictionary) -> void:
	_clear_result()
	_feedback.text = result.get("message", "")
	_feedback.visible = not _feedback.text.is_empty()
	_feedback.theme_type_variation = &"TicketStamp" if result.get("ok", false) else &"TicketWarning"
	if not result.get("ok", false):
		return
	_status.text = "制作完成 · 已入库"
	UIFlourish.stamp(_status)
	_status.modulate = Color(1.0, 0.94, 0.68)
	if _flash_tween != null:
		_flash_tween.kill()
	_flash_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_flash_tween.tween_property(_status, "modulate", Color.WHITE, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	UIFlourish.cups(_primary, _icon.texture, int(result.get("quantity", 1)), Vector2(0.06, 0.5))
	_icon.pivot_offset = _icon.size * 0.5
	_icon.scale = Vector2(0.8, 0.8)
	_completion_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_completion_tween.tween_property(_icon, "scale", Vector2(1.15, 1.15), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_completion_tween.tween_property(_icon, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _clear_result() -> void:
	if _completion_tween != null:
		_completion_tween.kill()
		_completion_tween = null
	if _flash_tween != null:
		_flash_tween.kill()
		_flash_tween = null
	_status.modulate = Color.WHITE
	_status.scale = Vector2.ONE
	_status.rotation = 0.0
	_icon.scale = Vector2.ONE
	_feedback.hide()

func get_primary_button() -> Button:
	return _primary

func get_title_text() -> String:
	return _title.text

func get_hint_text() -> String:
	return _hint.text
