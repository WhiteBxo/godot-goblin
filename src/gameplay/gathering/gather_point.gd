class_name GatherPoint
extends InteractionPoint
## Static configuration only. Harvest facts live in GameState; rules live in GatheringService.

## Catalog item produced here. Must exist in the shared menu and must not be a product.
@export var item_id: String = ""
@export_range(1, 2147483647, 1) var amount: int = 1
## once: never refills. daily: refills when GameState.current_day advances.
@export_enum("once", "daily") var refresh_mode: String = "daily"
## Empty means always available. Night points use world.phase.night.
@export var required_flag: String = ""
## Authored acquisition text, displayed only after the inventory commit succeeds.
@export_multiline var success_description := ""
## Non-empty turns the point into scenery the player can never harvest: the text
## says why (an ingredient only the locals know how to reach). Marker and artwork
## stay hidden so a locked patch never reads as a target.
@export_multiline var blocked_reason := ""
## Only configured RPG points show a distant clue and their harvestable artwork.
@export var show_world_marker := false

func update_presentation(harvestable: bool) -> void:
	if not show_world_marker:
		return
	$Marker.visible = harvestable
	var visual := get_node_or_null("HarvestVisual") as CanvasItem
	if visual != null:
		visual.visible = harvestable

## Injected by GatheringService. Without it the point fails closed.
var _harvest_gate: Callable


func _ready() -> void:
	super()
	# 章节地图上的采集点在迁移时漏配了 success_sound（旧聚落地图是逐个配的 24 处），
	# 采集成功因此没有任何确认音，与制作/交付的手感不一致。空值时补上交互默认音，
	# 场景里显式配置过的仍然优先。
	if success_sound.is_empty():
		success_sound = "ui.confirm"


func bind_gathering(gate: Callable) -> void:
	if _harvest_gate == gate:
		return
	_harvest_gate = gate
	if is_inside_tree():
		availability_changed.emit(self, is_available())


## Availability is always derived, never cached, so a spent point stops being a target
## on the very next query from ShopInteraction.
func is_available() -> bool:
	return super.is_available() and _harvest_gate.is_valid() and bool(_harvest_gate.call(self))
