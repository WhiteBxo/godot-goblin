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

## Injected by GatheringService. Without it the point fails closed.
var _harvest_gate: Callable


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
