extends Node2D
## Isolated F6 fixture. The extra torch and scenery do not bind the formal level.

var inventory: WarehouseInventory
var setup: Day1StealthSetup
var service: Day1StealthService
var player: ShopPlayer
var hud: Day1StealthHUD
var actors := {}
var external_lock := false
var sample_ids: Array[String] = []

func _ready() -> void:
	if not OS.has_feature("debug"):
		return
	get_window().content_scale_size = Vector2i(1280, 720)
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	var state := get_node("/root/GameState")
	state.start_new_game()
	state.select_business_profile("day1")
	state.set_story_stage("day1.s05.throw_fixture")
	state.set_flag("day1.s04.commission_accepted")
	DayPhase.enter_night(state)
	var menu := WarehouseInventory.CATALOG.duplicate(true) as TeaMenu
	var torch := IngredientDefinition.new()
	torch.id = "fixture_torch"
	torch.display_name = "试玩火把"
	menu.ingredients.append(torch)
	inventory = WarehouseInventory.new(menu)
	add_child(inventory)
	for ingredient: IngredientDefinition in menu.ingredients:
		inventory.add_ingredient(ingredient.id, 20)
	for extras: Array in [["mint_syrup", "mint_syrup"], ["scorch_tongue_pepper", "cocoa_powder"], ["rainbow_cube", "apple_jam"], ["strawberry_jam", "brown_sugar_boba"], ["red_mottled_wood", "cocoa_powder"], ["firefly_cap", "phantom_gold_mushroom"], ["mint_syrup", "honey_amber_crystal"], ["mint_syrup", "phantom_gold_mushroom"]]:
		var result := inventory.try_make_formula(["goblin_firebrew", extras[0], extras[1]], 5)
		sample_ids.append(result.id)
	player = load("res://src/gameplay/player/shop_player.tscn").instantiate()
	player.position = Vector2(480, 400)
	add_child(player)
	player.configure_camera(Rect2(0, 0, 1500, 1000))
	setup = Day1StealthSetup.new()
	add_child(setup)
	setup.torch_item_id = "fixture_torch"
	setup.escape_rules_reference = "isolated debug fixture; does not settle formal P08/P09"
	setup.checkpoint = Marker2D.new()
	setup.checkpoint.position = player.position
	add_child(setup.checkpoint)
	setup.escape_zone = Area2D.new()
	setup.escape_zone.collision_layer = 0
	setup.escape_zone.position = Vector2(300, 700)
	add_child(setup.escape_zone)
	add_shape(setup.escape_zone, Vector2(80, 80))
	# This fixture reproduces the four authored posts only; PATROL is used by the
	# chapter street scene and would need its own label and slot here.
	var roles := [Day1GuardResponse.Role.ENTRANCE, Day1GuardResponse.Role.MANSION_LURE, Day1GuardResponse.Role.MANSION_GATE, Day1GuardResponse.Role.DRUNKEN]
	var positions := [Vector2(680, 400), Vector2(1100, 350), Vector2(1180, 350), Vector2(1200, 730)]
	for slot in range(roles.size()):
		var role: int = roles[slot]
		var actor: SettlementCharacter = load("res://src/gameplay/characters/guard.tscn").instantiate()
		actor.actor_id = StringName("fixture_guard_%d" % role)
		actor.display_name = ["入口守卫", "宅邸诱饵卫", "宅邸第二卫", "醉酒守卫"][slot]
		actor.initial_facing = PlayerController.Facing.RIGHT
		actor.position = positions[slot]
		add_child(actor)
		actors[actor.actor_id] = actor
		var guard := Day1GuardResponse.new()
		guard.actor = actor
		guard.role = role
		guard.sight_range = 150.0
		guard.discovery_seconds = 2.0
		if role in [Day1GuardResponse.Role.MANSION_GATE, Day1GuardResponse.Role.DRUNKEN]:
			guard.clearance_flag = StringName("fixture.guard_%d.cleared" % role)
		if role == Day1GuardResponse.Role.DRUNKEN:
			guard.encounter_event_id = "fixture.drunken"
		add_child(guard)
		setup.guards.append(guard)
	var fire := Day1FlammableTarget.new()
	fire.target_id = &"fixture_fire"
	fire.design_reference = "debug fixture only"
	fire.position = Vector2(700, 560)
	add_child(fire)
	add_shape(fire, Vector2(40, 40))
	setup.flammable_targets.append(fire)
	var wood := Day1DestructibleTarget.new()
	wood.target_id = &"fixture_wood"
	wood.design_reference = "debug fixture wooden crate"
	wood.position = Vector2(820, 400)
	wood.blocker = add_wall(wood.position, Vector2(40, 100))
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([Vector2(-20, -50), Vector2(20, -50), Vector2(20, 50), Vector2(-20, 50)])
	visual.color = Color.SADDLE_BROWN
	wood.blocker.add_child(visual)
	wood.visual = visual
	add_child(wood)
	add_shape(wood, Vector2(44, 104))
	setup.destructible_targets.append(wood)
	add_wall(Vector2(920, 440), Vector2(24, 260))
	service = Day1StealthService.new()
	add_child(service)
	service.configure(state, inventory, player, self, setup,
		func(id: StringName) -> PlayerController: return actors.get(id),
		func() -> bool: return not external_lock)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = load("res://src/UI/hud/day1_stealth_hud.tscn").instantiate()
	layer.add_child(hud)
	hud.configure(service)
	var hint := Label.new()
	hint.position = Vector2(24, 20)
	hint.text = "投掷试玩（独立夹具） · WASD 移动 · 选择饮品后鼠标指向落点，按 F 投掷\n入口守卫在中间；棕色箱子可腐蚀；右侧灰墙用于验证阻挡。重试不返还已投出的杯。"
	hint.theme = preload("res://src/resources/ui/game_theme.tres")
	hint.theme_type_variation = &"Hint"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hint)

func add_shape(parent: CollisionObject2D, size: Vector2) -> void:
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	parent.add_child(shape)

func add_wall(at: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.position = at
	add_child(wall)
	add_shape(wall, size)
	return wall

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1500, 1000), Color(0.12, 0.15, 0.18))
	draw_rect(Rect2(908, 310, 24, 260), Color.SLATE_GRAY)
	draw_circle(Vector2(700, 560), 20.0, Color.DARK_ORANGE)
