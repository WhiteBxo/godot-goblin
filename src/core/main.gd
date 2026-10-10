class_name CaveGame
extends Node2D

@onready var cave_map: CaveMap = $CaveMap
@onready var player: CavePlayer = $Player
@onready var hud: CaveHud = $Hud

func _ready() -> void:
	if cave_map.load_error != OK:
		get_tree().quit(1)
		return
	player.configure(cave_map.can_stand_at)
	player.global_position = cave_map.get_spawn_position()
	player.follow_player()
	hud.set_hint("WASD / 方向键移动")
