extends Node
## Composition fixture only; all event order and completion conditions are data.
@export var autoplay := true
@onready var game: MainGame = $MainGame

func _ready() -> void:
	if not OS.has_feature("debug"):
		return
	var error := game.get_dialogue_manager().load_dialogues("res://src/resources/dialogue/order_bridge_demo.json")
	if error == OK:
		error = game.get_story_director().load_events("res://src/resources/story/order_bridge_demo.json")
	if error == OK:
		error = game.get_gameplay_bridge().load_phases("res://src/resources/story/order_bridge_demo_phases.json")
	if error != OK:
		push_error("Order Bridge fixture load failed: %d" % error)
		return
	if autoplay:
		game.get_story_director().request_event("order_demo.intro")
