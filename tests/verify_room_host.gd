extends SceneTree
## Verifies the capability-based arrival contract and the minimal room host.
## Runs headless: /path/to/Godot --headless --path . --script res://tests/verify_room_host.gd

const PLAYER_SCENE: PackedScene = preload("res://src/gameplay/player/shop_player.tscn")
const AUDIO_SCENE: PackedScene = preload("res://src/core/audio/audio_manager.tscn")
const SHOP_SCENE: PackedScene = preload("res://src/levels/milkTea/milk_tea_shop.tscn")
const POINT_SCENE: PackedScene = preload("res://src/gameplay/interaction/interaction_point.tscn")
const EXIT_SCRIPT: Script = preload("res://src/core/navigation/scene_exit.gd")

var _checks := 0
var _failures: Array[String] = []

## A map that answers every question the arrival path asks, but is neither
## MilkTeaShop nor SettlementMap.
class FakeRoom extends Node2D:
	func get_scene_entrance(id: StringName) -> SceneEntrance:
		for child in get_children():
			if child is SceneEntrance and child.entrance_id == id:
				return child
		return null

	func get_scene_exits() -> Array[SceneExit]:
		return []

	func get_spawn_position() -> Vector2:
		return Vector2(32, 48)

	func get_camera_bounds() -> Rect2:
		return Rect2(Vector2.ZERO, Vector2(640, 360))

	func get_interaction_points() -> Array[InteractionPoint]:
		return []

## Missing get_camera_bounds: the arrival path cannot frame the player here.
class FakeRoomWithoutCamera extends Node2D:
	func get_scene_entrance(_id: StringName) -> SceneEntrance:
		return null

	func get_scene_exits() -> Array[SceneExit]:
		return []

	func get_spawn_position() -> Vector2:
		return Vector2.ZERO

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)

func _build_skeleton(game: MainGame) -> void:
	var systems := Node.new()
	systems.name = "Systems"
	game.add_child(systems)
	var audio: AudioManager = AUDIO_SCENE.instantiate()
	audio.name = "AudioManager"
	systems.add_child(audio)
	var world := Node2D.new()
	world.name = "World"
	game.add_child(world)
	var level_root := Node2D.new()
	level_root.name = "LevelRoot"
	world.add_child(level_root)
	var entity_root := Node2D.new()
	entity_root.name = "EntityRoot"
	world.add_child(entity_root)
	var effect_root := Node2D.new()
	effect_root.name = "EffectRoot"
	world.add_child(effect_root)
	for layer_name: String in ["HudLayer", "PopupLayer", "PauseLayer", "TransitionLayer", "DebugLayer"]:
		var layer := CanvasLayer.new()
		layer.name = layer_name
		game.add_child(layer)

func _detached_host(map: Node) -> MainGame:
	var game := MainGame.new()
	game.name = "MainGame"
	game.day1_story_enabled = false
	_build_skeleton(game)
	game.get_node("World/LevelRoot").add_child(map)
	var player: ShopPlayer = PLAYER_SCENE.instantiate()
	player.name = "Player"
	game.get_node("World/EntityRoot").add_child(player)
	return game

func _verify_contract() -> void:
	var room := FakeRoom.new()
	room.name = "FakeRoom"
	var entrance := SceneEntrance.new()
	entrance.name = "Door"
	entrance.entrance_id = &"door"
	room.add_child(entrance)
	var host := _detached_host(room)
	_check(host.prepare_scene_arrival(&"door") == OK, "Capability map passes arrival preflight without a type whitelist")
	_check(host.prepare_scene_arrival(&"missing") == ERR_DOES_NOT_EXIST, "Unknown entrance id still fails closed")
	_check(host.prepare_scene_arrival(&"") == ERR_INVALID_PARAMETER, "Empty entrance id is invalid")
	host.free()

	var bare_host := _detached_host(FakeRoomWithoutCamera.new())
	_check(bare_host.prepare_scene_arrival(&"door") == ERR_UNCONFIGURED, "Map missing camera bounds is refused")
	bare_host.free()

	var plain := Node2D.new()
	plain.name = "Plain"
	var plain_host := _detached_host(plain)
	_check(plain_host.prepare_scene_arrival(&"door") == ERR_UNCONFIGURED, "Map without the contract is refused")
	plain_host.free()

	var shop: MilkTeaShop = SHOP_SCENE.instantiate()
	var shop_host := _detached_host(shop)
	_check(shop_host.prepare_scene_arrival(&"street_door") == OK, "Existing shop scene keeps its arrival behaviour")
	_check(shop_host.prepare_scene_arrival(&"nope") == ERR_DOES_NOT_EXIST, "Existing shop still validates entrance ids")
	shop_host.free()

func _verify_live_host() -> void:
	var room := FakeRoom.new()
	room.name = "FakeRoom"
	var entrance := SceneEntrance.new()
	entrance.name = "SpawnDoor"
	entrance.entrance_id = &"door"
	room.add_child(entrance)
	var exit_node: Node = POINT_SCENE.instantiate()
	exit_node.set_script(EXIT_SCRIPT)
	var exit := exit_node as SceneExit
	exit.name = "Back"
	exit.interaction_id = &"back"
	exit.destination_scene = "res://src/core/main.tscn"
	exit.destination_entrance = &"street_door"
	room.add_child(exit)

	var game := _detached_host(room)
	root.add_child(game)
	await process_frame
	await process_frame

	_check(game.get_active_level() == room, "Room map becomes the active level")
	_check(game.get_player() != null and game.get_player().global_position == Vector2(32, 48), "Player uses the room spawn position")
	_check(game.get_scene_travel() != null and not game.get_scene_travel().is_busy(), "Scene travel is assembled idle")
	_check(game.get_node_or_null("Systems/RoomInteraction") != null, "Room interaction is assembled")
	_check(game.get_node("TransitionLayer").get_child_count() > 0, "Transition visual is attached to the shared layer")
	_check(game.get_player().movement_enabled, "Arrival keeps player movement enabled")
	_check(exit.are_conditions_met(null), "Room exit without flags stays passable")

func _run() -> void:
	_verify_contract()
	await _verify_live_host()
	print("ROOM_HOST: %d checks, %d failures" % [_checks, _failures.size()])
	for failure: String in _failures:
		print("FAILED: " + failure)
	quit(0 if _failures.is_empty() else 1)
