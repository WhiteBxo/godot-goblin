class_name HandbookHUD
extends Button

@onready var _dot: Label = $Unread

func _ready() -> void:
	# Keep the small menu button within its authored HUD bounds.
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style: StyleBox = get_theme_stylebox(state).duplicate()
		for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			style.set_content_margin(side, 4.0)
		add_theme_stylebox_override(state, style)

func refresh_access(available: bool, unread: int, characters_unread: int = 0) -> void:
	visible = available
	focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE
	var total := unread + characters_unread
	var was_hidden := not _dot.visible
	_dot.visible = available and total > 0
	_dot.text = "%d+" % total if total > 9 else str(maxi(1, total))
	if _dot.visible and was_hidden:
		_pop_badge()
	tooltip_text = "菜单 · J 查看任务日志" + (" · 异世界见闻录 %d 条未读" % unread if unread > 0 else "")
	if characters_unread > 0:
		tooltip_text += " · 人物记录 %d 位未读" % characters_unread

## A new entry should be noticed from the corner of the eye, not by reading a
## tooltip: the badge drops in once and settles.
func _pop_badge() -> void:
	_dot.pivot_offset = _dot.size * 0.5
	_dot.scale = Vector2(0.4, 0.4)
	var tween := _dot.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_dot, "scale", Vector2.ONE, 0.22)
