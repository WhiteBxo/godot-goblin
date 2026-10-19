extends InteractionPoint
## Both mouse and E enter the host's ordinary interaction route.

@export_multiline var directions := "↑ 北：洞窟深处、长老居所\n↓ 南：奶茶店\n← 西：酒馆、赌场\n→ 东：集市"
@export var interactive := false

func _ready() -> void:
	interaction_id = StringName("wayfinding_" + String(get_parent().name) + "_" + String(name))
	display_name = "路牌 · 查看方向"
	description = directions
	if interactive:
		add_to_group("wayfinding")
	super._ready()
	hide_development_markers()
	if interactive:
		$Panel/Text.text = "路牌"
		$Panel/Text.pressed.connect(interact)
	else:
		$Panel/Text.mouse_filter = Control.MOUSE_FILTER_IGNORE
