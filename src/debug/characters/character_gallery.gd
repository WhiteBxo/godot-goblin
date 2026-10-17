extends Node2D
## F6: all characters independently exercise the real ActorDirector movement API.

const IDS := ["fat_goblin", "common_goblin", "guard", "guard_captain", "elder", "chef", "tavern", "casino", "human_customer", "human_customer_female"]
var _actors := ActorDirector.new()

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("292a35"))
	var camera := Camera2D.new()
	camera.position = Vector2(640, 360)
	camera.zoom = Vector2(0.5, 0.5)
	add_child(camera)
	var entities := Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	add_child(_actors)
	_actors.configure(entities)
	var title := Label.new()
	title.theme = preload("res://src/resources/ui/game_theme.tres")
	title.text = "角色动作预览 · 自动循环四向行走与待机（胖哥布林移动使用静帧）"
	title.position = Vector2(50, 25)
	add_child(title)
	for index in IDS.size():
		var id: String = IDS[index]
		var actor: SettlementCharacter = load("res://src/gameplay/characters/%s.tscn" % id).instantiate()
		actor.position = Vector2(120 + index % 5 * 250, 270 + index / 5 * 310)
		entities.add_child(actor)
		_actors.actor_register(StringName(id), actor)
		var label := Label.new()
		label.theme = title.theme
		label.text = actor.display_name
		label.position = actor.position + Vector2(-40, 16)
		add_child(label)
		_preview(actor)

func _preview(actor: SettlementCharacter) -> void:
	var origin := actor.position
	while is_inside_tree():
		for direction: Vector2 in [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]:
			var action := _actors.actor_move(actor.actor_id, actor.position + direction * 65, 65.0)
			await action.wait()
			if not is_inside_tree():
				return
			await get_tree().create_timer(0.8).timeout
		actor.teleport_to(origin)
