extends Node2D
## F6: compare portraits and real four-direction movement, followed by idle.

const IDS := ["market_mother", "prayer_woman", "goblin_girl"]
var _director := ActorDirector.new()

func _ready() -> void:
	if not OS.has_feature("debug"):
		return
	RenderingServer.set_default_clear_color(Color("343c46"))
	var entities := Node2D.new()
	add_child(entities)
	add_child(_director)
	_director.configure(entities)
	_label("妇女与女孩 · 四向行走 / 待机自动循环", Vector2(20, 6))
	for index in IDS.size():
		var id: String = IDS[index]
		var x := 108.0 + index * 212.0
		var portrait := Sprite2D.new()
		portrait.texture = load("res://assets/characters/npc/%s/portrait.png" % id)
		portrait.scale = Vector2.ONE * (140.0 / portrait.texture.get_height())
		portrait.position = Vector2(x, 110)
		add_child(portrait)
		var actor: SettlementCharacter = load("res://src/gameplay/characters/%s.tscn" % id).instantiate()
		actor.position = Vector2(x, 304)
		entities.add_child(actor)
		_director.actor_register(actor.actor_id, actor)
		_label(actor.display_name, Vector2(x - 50, 318))
		_preview(actor)
	_label("祭坛同伴无正面走路图，down 移动沿用本人待机", Vector2(20, 340))

func _label(text: String, at: Vector2) -> void:
	var label := Label.new()
	label.theme = preload("res://src/resources/ui/game_theme.tres")
	label.add_theme_font_size_override("font_size", 12)
	label.text = text
	label.position = at
	add_child(label)

func _preview(actor: SettlementCharacter) -> void:
	var origin := actor.position
	while is_inside_tree():
		for direction: Vector2 in [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]:
			var action := _director.actor_move(actor.actor_id, actor.position + direction * 24, 24.0)
			await action.wait()
			if not is_inside_tree():
				return
			await get_tree().create_timer(1.5).timeout
		actor.teleport_to(origin)
