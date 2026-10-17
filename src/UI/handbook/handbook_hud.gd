class_name HandbookHUD
extends Button

@onready var _dot: Label = $Unread

func _ready() -> void:
	# Text-button padding would squeeze a 24px icon inside this 36px button.
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style: StyleBox = get_theme_stylebox(state).duplicate()
		for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			style.set_content_margin(side, 4.0)
		add_theme_stylebox_override(state, style)

func refresh_access(available: bool, unread: int) -> void:
	visible = available
	focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE
	_dot.visible = available and unread > 0
	tooltip_text = "手册（J）" + (" · 异闻录 %d 条未读" % unread if unread > 0 else "")
