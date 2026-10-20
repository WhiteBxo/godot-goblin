extends TileMapLayer
## Rendering-only overrides for scene-authored furniture. The atlas, animation,
## saved cells and passage metadata remain owned by the original TileMapLayer.

var _depth_rules: Array = []

func configure_depth_rules(rules: Array) -> void:
	_depth_rules = rules.duplicate(true)
	y_sort_enabled = true
	notify_runtime_tile_data_update()

func _use_tile_data_runtime_update(coords: Vector2i) -> bool:
	for rule: Dictionary in _depth_rules:
		if rule.rect.has_point(coords):
			return true
	return false

func _tile_data_runtime_update(coords: Vector2i, tile_data: TileData) -> void:
	for rule: Dictionary in _depth_rules:
		if not rule.rect.has_point(coords):
			continue
		# TileData.z_index is relative to this layer. Furniture defaults to actor
		# Z=0; flat floor decor can explicitly stay behind actors at Z=-1.
		tile_data.z_index = int(rule.get("z_index", 0)) - z_index
		tile_data.y_sort_origin = roundi(float(rule.sort_y) - map_to_local(coords).y) - y_sort_origin
		return
