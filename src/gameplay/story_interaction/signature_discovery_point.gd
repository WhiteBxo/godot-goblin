class_name SignatureDiscoveryPoint
extends StoryInteractionPoint
## A source-authored encounter/letter read through the existing investigation UI.
## MainGame already resolves documents after closing their content. No parallel
## input route, guessed dialogue or writes from a UI callback are introduced.

@export var signature_id := ""

func _ready() -> void:
	kind = Kind.DOCUMENT
	entry_id = StringName("signature_" + signature_id)
	_state = get_node_or_null("/root/GameState")
	if is_instance_valid(_state):
		var signature: Dictionary = _state.get_warehouse_inventory().get_recipe_rules().get_signature(signature_id)
		description = str(signature.get("discovery_note", ""))
		_state.state_changed.connect(_refresh_availability)
	super._ready()

func _refresh_availability() -> void:
	availability_changed.emit(self, is_available())
	_refresh_world_marker()

func conditions_met() -> bool:
	return super.conditions_met() and _state.can_discover_signature(signature_id)

func is_resolved() -> bool:
	return is_instance_valid(_state) and _state.get_transactions().is_signature_discovered(signature_id)

func resolve() -> Dictionary:
	if _resolving or not conditions_met():
		return _failure("尚未满足这款爆品的发现条件。")
	_resolving = true
	var result: Dictionary = _state.discover_signature(signature_id)
	if result.get("ok", false):
		resolved.emit(entry_id)
	_resolving = false
	availability_changed.emit(self, is_available())
	return result
