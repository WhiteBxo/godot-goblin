extends Node2D
## F6: compare both common-goblin appearances in front/back idle poses.

const GOBLIN := preload("res://src/gameplay/characters/common_goblin.gd")
const SCENE := preload("res://src/gameplay/characters/common_goblin.tscn")
const THEME := preload("res://src/resources/ui/game_theme.tres")
var _actors: Array[PlayerController] = []
var _walking := false

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("292a35"))
	_label("普通哥布林 · 正面 / 背面待机", Vector2(140, 28))
	for index in 4:
		var actor := SCENE.instantiate()
		actor.appearance = GOBLIN.Appearance.WITH_BACKPACK if index < 2 else GOBLIN.Appearance.WITHOUT_BACKPACK
		actor.position = Vector2(95 + index * 150, 216)
		actor.speed_multiplier = 0.35
		add_child(actor)
		actor.face_direction(PlayerController.Facing.DOWN if index % 2 == 0 else PlayerController.Facing.UP)
		_actors.append(actor)
		_label(("背包版" if index < 2 else "无背包版") + (" · 正面" if index % 2 == 0 else " · 背面"), Vector2(35 + index * 150, 264))
	var button := Button.new()
	button.theme = THEME
	button.text = "走两步，再回到待机"
	button.position = Vector2(228, 300)
	button.pressed.connect(_walk_then_idle)
	add_child(button)
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png("res://artifacts/common_goblin_idle_preview.png")
		get_tree().quit(error)

func _label(text: String, position_value: Vector2) -> void:
	var label := Label.new()
	label.theme = THEME
	label.text = text
	label.position = position_value
	add_child(label)

func _walk_then_idle() -> void:
	if _walking:
		return
	_walking = true
	var elapsed := 0.0
	while elapsed < 0.5:
		await get_tree().physics_frame
		var delta := get_physics_process_delta_time()
		elapsed += delta
		for actor in _actors:
			actor.move_direction(actor.get_facing_vector(), delta)
	for actor in _actors:
		actor.stop_performance_motion()
	await get_tree().create_timer(1.5).timeout
	for index in _actors.size():
		_actors[index].teleport_to(Vector2(95 + index * 150, 216))
	_walking = false
