extends SceneTree
## Explicit authoring operation. Never called by the playable scene.

const LEVEL := "res://src/levels/disappeared_street/"
const ART := "res://assets/map/disappeared_street/"
var _catalog: Dictionary

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if FileAccess.file_exists(LEVEL + "disappeared_street_map.tscn") and "--rebuild" not in OS.get_cmdline_user_args():
		push_error("Saved map exists. Explicit -- --rebuild is required to overwrite editor changes.")
		quit(2)
		return
	_catalog = JSON.parse_string(FileAccess.get_file_as_string(ART + "catalog.json"))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEVEL + "street_layout.json"))
	var map := Node2D.new()
	map.name = "DisappearedStreet"
	map.y_sort_enabled = true
	map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map.set_script(load(LEVEL + "disappeared_street_map.gd"))
	map.set("world_size", Vector2(data.world_size[0], data.world_size[1]))
	_ground(map, data)
	var objects := Node2D.new()
	objects.name = "Objects"
	objects.y_sort_enabled = true
	map.add_child(objects)
	for entry: Dictionary in data.objects:
		var object: Node2D = load(LEVEL + "modules/" + str(entry.asset) + ".tscn").instantiate()
		object.name = entry.id
		object.position = Vector2(entry.position[0], entry.position[1])
		objects.add_child(object)
	_rocks(map)
	_boundaries(map, Vector2(data.world_size[0], data.world_size[1]))
	var dark := Polygon2D.new()
	dark.name = "DarkExitShade"
	dark.z_index = -10
	dark.polygon = PackedVector2Array([Vector2(1280, 0), Vector2(1536, 0), Vector2(1536, 440), Vector2(1280, 440)])
	dark.vertex_colors = PackedColorArray([Color(0.025, 0.03, 0.06, 0.95), Color(0.025, 0.03, 0.06, 0.95), Color(0.025, 0.03, 0.06, 0.0), Color(0.025, 0.03, 0.06, 0.0)])
	map.add_child(dark)
	var spawn := Marker2D.new()
	spawn.name = "Spawn"
	spawn.position = Vector2(data.spawn[0], data.spawn[1])
	map.add_child(spawn)
	var points := Node2D.new()
	points.name = "InteractionPoints"
	map.add_child(points)
	for entry: Dictionary in data.points:
		var point: InteractionPoint = load("res://src/gameplay/interaction/interaction_point.tscn").instantiate()
		point.name = str(entry.id).to_pascal_case()
		point.interaction_id = entry.id
		point.display_name = entry.name
		point.description = entry.description
		point.position = Vector2(entry.position[0], entry.position[1])
		point.get_node("Label").hide()
		point.get_node("Marker").hide()
		points.add_child(point)
	_own(map, map)
	_save(map, LEVEL + "disappeared_street_map.tscn")
	map.free()
	print("STREET_BAKE: saved native-size modules, 120 floor cells, collision and interaction points")
	quit()

func _ground(map: Node2D, data: Dictionary) -> void:
	var source := TileSetAtlasSource.new()
	source.texture = load(ART + "ground.png")
	source.texture_region_size = Vector2i(128, 128)
	source.use_texture_padding = false
	for y in range(8):
		for x in range(12):
			source.create_tile(Vector2i(x, y))
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(128, 128)
	tiles.add_source(source, 0)
	assert(ResourceSaver.save(tiles, LEVEL + "street_ground.tres") == OK)
	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.z_index = -20
	ground.tile_set = load(LEVEL + "street_ground.tres")
	for y in range(int(data.world_size[1]) / 128):
		for x in range(int(data.world_size[0]) / 128):
			ground.set_cell(Vector2i(x, y), 0, Vector2i(x % 12, y % 8))
	map.add_child(ground)

func _rocks(map: Node2D) -> void:
	var rim := Node2D.new()
	rim.name = "CaveRim"
	rim.y_sort_enabled = true
	map.add_child(rim)
	for asset: Dictionary in _catalog.assets:
		if asset.kind != "rock":
			continue
		# Turn each native alpha silhouette into real reusable static geometry.
		var module: Node2D = load(asset.scene).instantiate()
		var bitmap := BitMap.new()
		var image: Image = load(asset.texture).get_image()
		bitmap.create_from_image_alpha(image)
		var body := StaticBody2D.new()
		body.name = "RockCollision"
		body.collision_mask = 2
		module.add_child(body)
		var visual: Sprite2D = module.get_node("Visual")
		for polygon: PackedVector2Array in bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, image.get_size()), 3.0):
			if polygon.size() < 3:
				continue
			var shape := CollisionPolygon2D.new()
			shape.name = "Silhouette%d" % body.get_child_count()
			shape.position = visual.position
			shape.polygon = polygon
			body.add_child(shape)
		_own(module, module)
		_save(module, asset.scene)
		module.free()
		var at := Vector2(asset.map_top_left[0] + asset.native_size[0] / 2, asset.map_top_left[1] + asset.native_size[1])
		if asset.map_top_left[1] > 760:
			at.y += 256
		_place_rock(rim, asset, at)
		if asset.map_top_left[1] > 500 and asset.map_top_left[1] < 760:
			_place_rock(rim, asset, at + Vector2(0, 256))

func _place_rock(parent: Node2D, asset: Dictionary, at: Vector2) -> void:
	var object: Node2D = load(asset.scene).instantiate()
	object.name = str(asset.id).to_pascal_case() + "At%d" % roundi(at.y)
	object.position = at
	object.z_index = 2 if at.y > 1050 else -5
	parent.add_child(object)

func _boundaries(map: Node2D, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.name = "OuterBoundary"
	body.collision_mask = 2
	map.add_child(body)
	for rect: Rect2 in [Rect2(-32, -32, size.x + 64, 32), Rect2(-32, size.y, size.x + 64, 32), Rect2(-32, 0, 32, size.y), Rect2(size.x, 0, 32, size.y)]:
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = rect.size
		shape.shape = rectangle
		shape.position = rect.get_center()
		body.add_child(shape)
	# Story stage 3 permits approach to the dark exit, but no travel deeper yet.
	var gate := CollisionShape2D.new()
	gate.name = "UnexploredExit"
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(210, 18)
	gate.shape = rectangle
	gate.position = Vector2(1400, 230)
	body.add_child(gate)

func _own(node: Node, scene_root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = scene_root
		if child.scene_file_path.is_empty():
			_own(child, scene_root)

func _save(node: Node, path: String) -> void:
	var packed := PackedScene.new()
	assert(packed.pack(node) == OK)
	assert(ResourceSaver.save(packed, path) == OK)
