extends SceneTree
## Explicit authoring operation. Rebuild requires an opt-in; runtime never imports JSON.
const LEVEL := "res://src/levels/night_infiltration/"
const ART := "res://assets/map/night_infiltration/"
var map: Node2D
var architecture: Node2D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if FileAccess.file_exists(LEVEL + "night_infiltration_map.tscn") and "--rebuild" not in OS.get_cmdline_user_args():
		push_error("Saved editor map exists. Explicit -- --rebuild required.")
		quit(2)
		return
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ART + "catalog.json"))
	map = Node2D.new()
	map.name = "NightInfiltration"
	map.y_sort_enabled = true
	map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map.set_script(load(LEVEL + "night_infiltration_map.gd"))
	_ground()
	var objects := Node2D.new()
	objects.name = "Objects"
	objects.y_sort_enabled = true
	map.add_child(objects)
	architecture = Node2D.new()
	architecture.name = "Architecture"
	map.add_child(architecture)
	for entry: Dictionary in catalog.assets:
		var module: Node2D = load(entry.scene).instantiate()
		module.name = str(entry.id).to_pascal_case()
		module.position = Vector2(entry.position[0], entry.position[1])
		if entry.kind == "room":
			module.z_index = -10
		elif entry.kind == "rock":
			module.z_index = 2
		objects.add_child(module)
		for index in range(entry.blocks.size()):
			var rect: Array = entry.blocks[index]
			_solid("Footprint%d" % index, Rect2(rect[0], rect[1], rect[2], rect[3]), module)
	_room_solids()
	_boundary()
	_anchors()
	_points()
	_own(map)
	var scene := PackedScene.new()
	assert(scene.pack(map) == OK)
	assert(ResourceSaver.save(scene, LEVEL + "night_infiltration_map.tscn") == OK)
	map.free()
	print("NIGHT_BAKE_OK: original coordinates, 38 independent modules, 405 saved floor cells")
	quit()

func _ground() -> void:
	var source := TileSetAtlasSource.new()
	source.texture = load(ART + "ground_atlas.png")
	source.texture_region_size = Vector2i(64, 64)
	source.use_texture_padding = false
	for y in range(15):
		for x in range(27):
			source.create_tile(Vector2i(x, y))
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(64, 64)
	tiles.add_source(source, 0)
	assert(ResourceSaver.save(tiles, LEVEL + "night_ground.tres") == OK)
	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.z_index = -20
	ground.tile_set = load(LEVEL + "night_ground.tres")
	for y in range(15):
		for x in range(27):
			ground.set_cell(Vector2i(x, y), 0, Vector2i(x, y))
	map.add_child(ground)

func _solid(label: String, rect: Rect2, module: Node2D = null) -> void:
	var body := StaticBody2D.new()
	body.name = label
	body.collision_mask = 2
	if module != null:
		module.add_child(body)
		rect.position -= module.position
	else:
		architecture.add_child(body)
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var rectangle := RectangleShape2D.new()
	rectangle.size = rect.size
	shape.shape = rectangle
	shape.position = rect.get_center()
	body.add_child(shape)

func _room_solids() -> void:
	var blocks := {
		"ElderNorth": Rect2(970, 35, 638, 70),
		"ElderWest": Rect2(970, 100, 38, 253),
		"ElderEast": Rect2(1567, 80, 41, 270),
		"ElderFrontLeft": Rect2(970, 353, 210, 102),
		"ElderFrontRight": Rect2(1340, 353, 267, 102),
		"ElderDesk": Rect2(1085, 215, 153, 70),
		"ElderBed": Rect2(1305, 162, 132, 123),
		"ElderBooks": Rect2(1010, 93, 88, 112),
		"ElderBooksMiddle": Rect2(1244, 97, 51, 117),
		"ElderCabinet": Rect2(1478, 92, 89, 168),
		"ElderLeftChest": Rect2(1008, 260, 44, 65),
		"ElderRightCrate": Rect2(1510, 301, 54, 26),
		"ElderDoor": Rect2(1180, 439, 160, 15),
		"CargoRock": Rect2(1209, 618, 96, 76),
		"ClosedSoutheast": Rect2(1220, 782, 170, 155)
	}
	for label: String in blocks:
		_solid(label, blocks[label])

func _boundary() -> void:
	# Segments follow the actual continuous floor perimeter. Only southwest leads out.
	var outline := PackedVector2Array([
		Vector2(129,937),Vector2(127,861),Vector2(105,801),Vector2(90,778),Vector2(95,649),Vector2(57,573),Vector2(83,503),Vector2(47,454),Vector2(59,341),Vector2(119,283),Vector2(187,251),Vector2(239,194),Vector2(280,139),Vector2(330,109),Vector2(460,119),Vector2(504,88),Vector2(621,105),Vector2(669,88),Vector2(710,53),Vector2(778,70),Vector2(824,51),Vector2(870,80),Vector2(930,116),Vector2(960,80),Vector2(982,35),Vector2(1614,35),Vector2(1624,103),Vector2(1638,178),Vector2(1614,259),Vector2(1642,329),Vector2(1619,389),Vector2(1646,447),Vector2(1678,431),Vector2(1678,576),Vector2(1610,603),Vector2(1580,628),Vector2(1510,655),Vector2(1490,686),Vector2(1400,691),Vector2(1370,759),Vector2(1337,794),Vector2(1215,800),Vector2(1195,811),Vector2(1150,782),Vector2(1080,792),Vector2(1020,807),Vector2(974,815),Vector2(932,774),Vector2(902,746),Vector2(883,756),Vector2(859,723),Vector2(818,735),Vector2(778,750),Vector2(750,779),Vector2(720,771),Vector2(700,799),Vector2(657,762),Vector2(628,778),Vector2(600,768),Vector2(540,782),Vector2(485,768),Vector2(450,756),Vector2(420,780),Vector2(381,772),Vector2(347,801),Vector2(346,862),Vector2(326,937)
	])
	var body := StaticBody2D.new()
	body.name = "CaveBoundary"
	body.collision_mask = 2
	architecture.add_child(body)
	for index in range(outline.size()):
		var segment := SegmentShape2D.new()
		segment.a = outline[index]
		segment.b = outline[(index + 1) % outline.size()]
		var shape := CollisionShape2D.new()
		shape.shape = segment
		body.add_child(shape)

func _anchors() -> void:
	var root := Node2D.new()
	root.name = "StoryAnchors"
	map.add_child(root)
	var anchors := {
		"ArrivalFromPublicStreet": Vector2(235, 855),
		"ExitToPublicStreet": Vector2(235, 900),
		"EntranceGuard": Vector2(241, 750),
		"CoinLanding": Vector2(525, 690),
		"EntrancePassed": Vector2(242, 571),
		"DrunkGuard": Vector2(870, 509),
		"DayTwoDelivery": Vector2(905, 541),
		"ElderDoor": Vector2(1260, 490),
		"DoorGuardLeft": Vector2(1217, 481),
		"DoorGuardRight": Vector2(1333, 482),
		"Manuscript": Vector2(1155, 307),
		"GriffinBlood": Vector2(1470, 291),
		"PickupTorch": Vector2(107, 529),
		"Combustibles": Vector2(214, 527),
		"ReturnObstruction": Vector2(245, 792),
		"EscapeSafe": Vector2(235, 855)
	}
	for label: String in anchors:
		var marker := Marker2D.new()
		marker.name = label
		marker.position = anchors[label]
		root.add_child(marker)
	var exit: Marker2D = root.get_node("ExitToPublicStreet")
	exit.set_meta("external_port", true)
	exit.set_meta("destination", "public_street")
	exit.set_meta("arrival", "from_elder_district")

func _points() -> void:
	var root := Node2D.new()
	root.name = "InteractionPoints"
	map.add_child(root)
	var entries := [
		["public_street", "返回公共街道", "ExitToPublicStreet", "这条路通往奶茶店外的公共街道。酒馆和赌场位于公共街道的另一条岔路。"],
		["coin_landing", "观察入口侧方", "CoinLanding", "木箱旁留着一小块空地，和入口通道隔开。"],
		["drunk_guard", "醉酒守卫", "DayTwoDelivery", "守卫拎着酒壶，停在货物旁。"],
		["elder_door", "打开宅邸正门", "ElderDoor", "厚重的木门通向长老的房间。"],
		["manuscript", "查看残缺文书", "Manuscript", "书桌上有一份纸页泛黄、边缘撕裂的古老文书。"],
		["griffin_blood", "查看格里芬之血", "GriffinBlood", "红色的密封瓶保管在柜子里。"],
		["torch", "观察火把与货棚", "PickupTorch", "火把旁的木棚堆着干草和木料。"]
	]
	for entry: Array in entries:
		var point := Area2D.new()
		point.set_script(load("res://src/gameplay/interaction/interaction_point.gd"))
		point.collision_layer = 0
		point.collision_mask = 2
		var reach := CollisionShape2D.new()
		reach.name = "CollisionShape2D"
		var circle := CircleShape2D.new()
		circle.radius = 56.0
		reach.shape = circle
		point.add_child(reach)
		var label := Label.new()
		label.name = "Label"
		label.hide()
		point.add_child(label)
		var marker := Polygon2D.new()
		marker.name = "Marker"
		marker.hide()
		point.add_child(marker)
		point.name = str(entry[0]).to_pascal_case()
		point.set("interaction_id", entry[0])
		point.set("display_name", entry[1])
		point.set("description", entry[3])
		point.position = map.get_node("StoryAnchors/" + entry[2]).position
		root.add_child(point)

func _own(node: Node) -> void:
	for child: Node in node.get_children():
		# Packed module descendants retain their instance ownership. Re-owning them
		# serializes duplicate inherited children, which become orphans on load.
		if child.owner == null:
			child.owner = map
			_own(child)
