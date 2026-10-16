extends SceneTree
## Explicit offline authoring only. Runtime never rebuilds or overwrites the map.

const DIR := "res://src/levels/settlement/"
const ART := "res://assets/map/settlement/"
var _data: Dictionary

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if FileAccess.file_exists(DIR + "settlement_map.tscn") and "--rebuild" not in OS.get_cmdline_user_args():
		push_error("Saved map already exists. Pass -- --rebuild only for an intentional offline rebuild.")
		quit(2)
		return
	_data = JSON.parse_string(FileAccess.get_file_as_string(DIR + "settlement_layout.json"))
	DirAccess.make_dir_recursive_absolute(DIR + "districts")
	for zone: Dictionary in _data.zones:
		if not ResourceLoader.exists(zone.asset):
			push_error("Missing generated asset: " + str(zone.asset))
			quit(1)
			return
		_save_district(zone)
	var map := Node2D.new()
	map.name = "SettlementMap"
	map.y_sort_enabled = true
	map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map.set_script(load(DIR + "settlement_map.gd"))
	_build_ground(map)
	_build_river(map)
	_build_boundary(map)
	_build_streets(map)
	var districts := _node(map, "Districts")
	districts.y_sort_enabled = true
	for zone: Dictionary in _data.zones:
		var district: Node2D = load(DIR + "districts/" + str(zone.id) + ".tscn").instantiate()
		district.position = _v(zone.position)
		districts.add_child(district)
		district.owner = map
	_build_props(map)
	var spawn := Marker2D.new()
	spawn.name = "Spawn"
	spawn.position = _v(_data.spawn)
	map.add_child(spawn)
	var points := _node(map, "InteractionPoints")
	var anchors := _node(map, "StoryAnchors")
	for zone: Dictionary in _data.zones:
		var point: InteractionPoint = load("res://src/gameplay/interaction/interaction_point.tscn").instantiate()
		point.name = str(zone.id)
		point.position = _v(zone.position) + _v(zone.entry)
		point.interaction_id = str(zone.id)
		point.display_name = str(zone.name)
		point.description = str(zone.observation)
		points.add_child(point)
		_anchor(anchors, str(zone.id) + "_entrance", point.position)
	for service: Dictionary in _data.get("service_points", []):
		var point: InteractionPoint = load("res://src/gameplay/interaction/interaction_point.tscn").instantiate()
		point.name = str(service.id)
		point.position = _v(service.position)
		point.interaction_id = str(service.id)
		point.display_name = str(service.name)
		point.description = str(service.description)
		points.add_child(point)
		_anchor(anchors, str(service.id), point.position)
	for anchor: Dictionary in _data.get("story_anchors", []):
		_anchor(anchors, str(anchor.id), _v(anchor.position))
	_own(map, map)
	_save(map, DIR + "settlement_map.tscn")
	print("Saved 16 independent districts, continuous ground, bridges, collision and story anchors.")
	map.free()
	quit()

func _save_district(zone: Dictionary) -> void:
	var district := Node2D.new()
	district.name = str(zone.id).get_slice("_", 1).to_pascal_case()
	district.y_sort_enabled = true
	district.set_meta("zone_id", zone.id)
	district.set_meta("display_name", zone.name)
	district.set_meta("footprint", Rect2(80, 70, 1380, 870))
	var texture: Texture2D = load(zone.asset)
	var background := Sprite2D.new()
	background.name = "PaintedInterior"
	background.centered = false
	background.texture = texture
	background.z_index = -20
	district.add_child(background)
	var walls := _node(district, "Walls")
	var foreground := _node(district, "Foreground")
	foreground.y_sort_enabled = true
	var wall_specs: Array = zone.get("walls", [])
	for index in range(wall_specs.size()):
		var wall: Dictionary = wall_specs[index]
		_collider(walls, "Wall%d" % index, _rect(wall.collision))
		if wall.has("visual"):
			_occluder(foreground, texture, "Wall%d" % index, _rect(wall.visual), float(wall.get("sort_y", wall.visual[1] + wall.visual[3])))
	var furniture := _node(district, "Furniture")
	for index in range(zone.obstacles.size()):
		var obstacle: Dictionary = zone.obstacles[index]
		_collider(furniture, str(obstacle.get("name", "Furniture%d" % index)), _rect(obstacle.collision))
		if obstacle.has("visual"):
			_occluder(foreground, texture, "Furniture%d" % index, _rect(obstacle.visual), float(obstacle.get("sort_y", obstacle.collision[1] + obstacle.collision[3])))
	var entry := Marker2D.new()
	entry.name = "Entrance"
	entry.position = _v(zone.entry)
	district.add_child(entry)
	_own(district, district)
	_save(district, DIR + "districts/" + str(zone.id) + ".tscn")
	district.free()

func _build_ground(map: Node2D) -> void:
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(256, 256)
	var source := TileSetAtlasSource.new()
	source.texture = load(ART + "ground.png")
	source.texture_region_size = Vector2i(256, 256)
	source.use_texture_padding = false
	for y in range(4):
		for x in range(4):
			source.create_tile(Vector2i(x, y))
	tiles.add_source(source, 0)
	ResourceSaver.save(tiles, DIR + "settlement_ground.tres")
	var floor_layer := TileMapLayer.new()
	floor_layer.name = "Ground"
	floor_layer.tile_set = load(DIR + "settlement_ground.tres")
	floor_layer.z_index = -50
	var outline := PackedVector2Array()
	for point: Array in _data.floor_outline:
		outline.append(_v(point))
	for y in range(36):
		for x in range(32):
			var center := Vector2(x, y) * 256 + Vector2(128, 128)
			var inside := Geometry2D.is_point_in_polygon(center, outline)
			if not inside:
				for i in range(outline.size()):
					if center.distance_to(Geometry2D.get_closest_point_to_segment(center, outline[i], outline[(i + 1) % outline.size()])) < 180:
						inside = true
						break
			if inside:
				floor_layer.set_cell(Vector2i(x, y), 0, Vector2i((x * 3 + y) % 4, (x + y * 3) % 4))
	map.add_child(floor_layer)

func _build_river(map: Node2D) -> void:
	var river_rect := _rect(_data.river)
	var outline := PackedVector2Array()
	for point: Array in _data.river_outline:
		outline.append(_v(point))
	var river := Polygon2D.new()
	river.name = "River"
	river.texture = load(ART + "river.png")
	river.polygon = outline
	river.uv = outline
	river.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	river.z_index = -40
	map.add_child(river)
	var banks := _node(map, "RiverBanks")
	banks.z_index = -35
	var bank_line := Line2D.new()
	bank_line.name = "BankContour"
	bank_line.width = 12
	bank_line.default_color = Color("353534")
	bank_line.points = outline
	banks.add_child(bank_line)
	var collision := _node(map, "RiverCollision")
	var previous := river_rect.position.y
	for y: float in _data.bridges:
		_river_collider(collision, outline, previous, y - 92)
		previous = y + 92
		var bridge := Sprite2D.new()
		bridge.name = "Bridge%d" % int(y)
		bridge.texture = load(ART + "bridge.png")
		bridge.centered = false
		bridge.position = Vector2(2336 - bridge.texture.get_width() * 0.5, y - 512)
		bridge.z_index = -30
		map.add_child(bridge)
	_river_collider(collision, outline, previous, river_rect.end.y)

func _river_collider(parent: Node2D, river: PackedVector2Array, top: float, bottom: float) -> void:
	var band := PackedVector2Array([Vector2(0, top), Vector2(8192, top), Vector2(8192, bottom), Vector2(0, bottom)])
	for polygon: PackedVector2Array in Geometry2D.intersect_polygons(river, band):
		var body := StaticBody2D.new()
		body.name = "Water%d" % int(top)
		body.collision_mask = 2
		var shape := CollisionPolygon2D.new()
		shape.polygon = polygon
		body.add_child(shape)
		parent.add_child(body)

func _build_boundary(map: Node2D) -> void:
	var points := PackedVector2Array()
	for point: Array in _data.floor_outline:
		points.append(_v(point))
	var root_node := _node(map, "OuterCavernBoundary")
	var outside := Polygon2D.new()
	outside.name = "OutsideCavernMask"
	outside.polygon = points
	outside.invert_enabled = true
	outside.invert_border = 12000
	outside.color = Color("171b20")
	outside.z_index = -25
	root_node.add_child(outside)
	var dark := Line2D.new()
	dark.name = "SingleOuterWall"
	dark.points = points
	dark.closed = true
	dark.width = 150
	dark.default_color = Color("25272c")
	dark.joint_mode = Line2D.LINE_JOINT_ROUND
	dark.z_index = -15
	root_node.add_child(dark)
	var props: Texture2D = load(ART + "props.png")
	for index in range(points.size()):
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		var body := StaticBody2D.new()
		body.name = "Boundary%d" % index
		body.position = (a + b) * 0.5
		body.rotation = (b - a).angle()
		body.collision_mask = 2
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(a.distance_to(b) + 30, 40)
		shape.shape = rectangle
		body.add_child(shape)
		root_node.add_child(body)
		var count := ceili(a.distance_to(b) / 190)
		var tangent := (b - a).normalized()
		var outward := Vector2(tangent.y, -tangent.x)
		for row in range(3):
			for step in range(count):
				var sprite := Sprite2D.new()
				sprite.name = "OuterRock%d_%d_%d" % [index, row, step]
				sprite.texture = props
				sprite.region_enabled = true
				sprite.region_rect = Rect2(((step + row * 2) % 6) * 256, 0, 256, 256)
				sprite.position = a.lerp(b, (step + row * 0.3) / count) + outward * row * 125
				sprite.z_index = -10 - row
				sprite.modulate = Color.WHITE.darkened(row * 0.16)
				root_node.add_child(sprite)

func _build_streets(map: Node2D) -> void:
	var streets := _node(map, "Streets")
	streets.z_index = -45
	for path: Array in _data.get("streets", []):
		var line := Line2D.new()
		line.name = "Street%d" % streets.get_child_count()
		line.width = 180
		line.default_color = Color(0.38, 0.30, 0.21, 0.48)
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		for point: Array in path:
			line.add_point(_v(point))
		streets.add_child(line)

func _build_props(map: Node2D) -> void:
	var props := _node(map, "StreetProps")
	props.y_sort_enabled = true
	var atlas: Texture2D = load(ART + "props.png")
	for item: Dictionary in _data.get("street_props", []):
		var prop := Node2D.new()
		prop.name = str(item.id)
		prop.position = _v(item.position)
		var sprite := Sprite2D.new()
		sprite.texture = atlas
		sprite.region_enabled = true
		sprite.region_rect = Rect2(_v(item.cell) * 256, Vector2(256, 256))
		sprite.position.y = -84
		prop.add_child(sprite)
		if item.get("solid", false):
			_collider(prop, "Feet", Rect2(-38, -16, 76, 32))
		props.add_child(prop)

func _occluder(parent: Node2D, texture: Texture2D, label: String, area: Rect2, sort_y: float) -> void:
	var anchor := Node2D.new()
	anchor.name = label
	anchor.position = Vector2(0, sort_y)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = area
	sprite.position = area.position - anchor.position
	anchor.add_child(sprite)
	parent.add_child(anchor)

func _collider(parent: Node2D, label: String, area: Rect2) -> void:
	var body := StaticBody2D.new()
	body.name = label
	body.collision_mask = 2
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = area.size
	shape.shape = rectangle
	shape.position = area.get_center()
	body.add_child(shape)
	parent.add_child(body)

func _anchor(parent: Node2D, label: String, at: Vector2) -> void:
	var marker := Marker2D.new()
	marker.name = label
	marker.position = at
	parent.add_child(marker)

func _node(parent: Node, label: String) -> Node2D:
	var node := Node2D.new()
	node.name = label
	parent.add_child(node)
	return node

func _own(node: Node, scene_root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = scene_root
		if child.scene_file_path.is_empty():
			_own(child, scene_root)

func _save(node: Node, path: String) -> void:
	var packed := PackedScene.new()
	var error := packed.pack(node)
	if error == OK:
		error = ResourceSaver.save(packed, path)
	assert(error == OK, "Failed to save " + path)

func _rect(value: Array) -> Rect2:
	return Rect2(value[0], value[1], value[2], value[3])

func _v(value: Array) -> Vector2:
	return Vector2(value[0], value[1])
